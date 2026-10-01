import AppKit
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class DecisionReviewFlowTests: XCTestCase {
    func testPreferencesDefaultAndUnknownModesNeverOptIn() throws {
        for json in ["{}", #"{"decisionReviewMode":"unknown","retentionDays":7}"#,
                     #"{"decisionReviewMode":true,"retentionDays":7}"#] {
            let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
            XCTAssertEqual(preferences.decisionReviewMode, .off)
        }
        for mode in DecisionReviewMode.allCases {
            var preferences = Preferences(); preferences.decisionReviewMode = mode
            let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(decoded.decisionReviewMode, mode)
        }
    }

    func testOffPreservesTheExistingPipelineWithoutADecisionRequest() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.99)
        let fixture = try fixture(mode: .off, evaluator: evaluator)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertNil(fixture.model.decisionReviewSummary)
    }

    func testProtectHoldsInputButKeepsOriginalAndResultForReview() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.95)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await recordAndWait(fixture)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertEqual(fixture.model.decisionOriginalText, DecisionAppURLProtocol.transcript)
        XCTAssertTrue(fixture.model.notice?.contains("자동 입력을 보류") == true)
        XCTAssertEqual(fixture.model.page, .home)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.last?.originalText, DecisionAppURLProtocol.transcript)
        XCTAssertEqual(history.last?.resultText, DecisionAppURLProtocol.output)
        let usage = try await fixture.store.usageRecords()
        XCTAssertEqual(usage.filter { $0.event.stage == .decisionReview }.count, 1)
        XCTAssertTrue(fixture.model.lastProcessingTimings?.contains("Jev 검토") == true)
    }

    func testLowRiskInsertsAndOnlyProposesKnownSpellingsWithoutLearning() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.1, proposeTerm: true)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertEqual(fixture.model.decisionTermSuggestions, ["오픈 라우터 → OpenRouter"])
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertTrue(fixture.model.dictionary.isEmpty)
        let stored = try await fixture.store.dictionary()
        XCTAssertTrue(stored.isEmpty)
        let calls = await evaluator.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.key, "synthetic-openRouter-key")
        XCTAssertEqual(call.request.transcript, DecisionAppURLProtocol.transcript)
        XCTAssertFalse(String(describing: call.request).contains("private surrounding context"))
    }

    func testUnavailableReviewFailsOpenWithoutReportingSuccess() async throws {
        for failure in [DecisionError.timedOut, .invalidResponse, .missingAPIKey] {
            let fixture = try fixture(mode: .protect, evaluator: DecisionAppEvaluator(failure: failure))
            await recordAndWait(fixture)
            XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
            XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("완료하지 못했습니다") == true)
            XCTAssertNil(fixture.model.decisionOriginalText)
            XCTAssertNil(fixture.model.error)
        }
    }

    func testObserveStartsAfterInputAndDoesNotKeepTheAppBusy() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Background review started"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .observe, evaluator: evaluator)
        await recordAndWait(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        await gate.release()
        await waitForReview(fixture.model)
        XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("문장 정리 결과는 변경하지 않았습니다") == true)
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertNil(fixture.model.decisionOriginalText)
        XCTAssertEqual(fixture.insertions.texts.count, 1)
    }

    func testObserveDiscardsLateResultsAfterCancelDisableHistoryOrDeletion() async throws {
        for action in 0..<4 {
            let gate = DecisionAppGate(entered: expectation(description: "Review started for action \(action)"))
            let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
            let fixture = try fixture(mode: .observe, evaluator: evaluator)
            await recordAndWait(fixture)
            await fulfillment(of: [gate.entered], timeout: 3)
            switch action {
            case 0: fixture.model.cancel()
            case 1: fixture.model.preferences.decisionReviewMode = .off
            case 2: fixture.model.preferences.historyEnabled = false
            default: await fixture.model.deleteHistory()
            }
            await gate.release()
            for _ in 0..<10 { await Task.yield() }
            XCTAssertNil(fixture.model.decisionReviewSummary)
            XCTAssertTrue(fixture.model.decisionTermSuggestions.isEmpty)
            XCTAssertEqual(fixture.insertions.texts.count, 1)
        }
    }

    func testProtectCancellationCannotHoldOrInsertAStaleResult() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Protection waits"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await startAndStop(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.cancel()
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertNil(fixture.model.decisionReviewSummary)
        XCTAssertNil(fixture.model.decisionOriginalText)
        XCTAssertFalse(fixture.model.isBusy)
    }

    func testRevokingReviewWhileProtectingContinuesNormalInput() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Protection can be revoked"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        let completed = watchCompletion(fixture.model)
        await startAndStop(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.preferences.decisionReviewMode = .off
        await gate.release()
        await fulfillment(of: [completed], timeout: 3)
        fixture.model.onPhaseChange = nil
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertNil(fixture.model.decisionReviewSummary)
        XCTAssertNil(fixture.model.decisionOriginalText)
    }

    func testRecordedReviewModeAndProviderRemainFrozen() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.95)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .recording)
        fixture.model.preferences.decisionReviewMode = .observe
        fixture.model.preferences.textProvider = .groq
        let completed = watchCompletion(fixture.model)
        fixture.model.elapsed = 1; fixture.model.stop()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        XCTAssertTrue(fixture.insertions.texts.isEmpty, "The recorded protection mode still applies")
        let calls = await evaluator.calls
        XCTAssertEqual(calls.map(\.key), ["synthetic-openRouter-key"])
    }

    func testReenablingReviewDoesNotResendARecordingWhoseConsentWasRevoked() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.99)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await fixture.model.toggle(.dictation)
        fixture.model.preferences.decisionReviewMode = .off
        fixture.model.preferences.decisionReviewMode = .protect
        let completed = watchCompletion(fixture.model)
        fixture.model.elapsed = 1; fixture.model.stop()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testANewRecordingDiscardsThePreviousBackgroundReview() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Previous background review started"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .observe, evaluator: evaluator)
        await recordAndWait(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .recording)
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(fixture.model.decisionReviewSummary)
        XCTAssertTrue(fixture.model.decisionTermSuggestions.isEmpty)
        XCTAssertTrue(fixture.model.phase == .recording, "Old completion must not stop the new recording")
    }

    func testUnsupportedModesAndProvidersDoNotSendExtraText() async throws {
        for input in [InputMode.translation, .rewrite] {
            let evaluator = DecisionAppEvaluator()
            let fixture = try fixture(mode: .protect, evaluator: evaluator)
            await recordAndWait(fixture, mode: input)
            let calls = await evaluator.calls
            XCTAssertTrue(calls.isEmpty)
        }
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, provider: .groq)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testExplicitReviewOptInDoesNotRequireTextHistory() async throws {
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, history: false)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        let history = try await fixture.store.history()
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testTermCandidatesAreBoundedRelevantAndFavorThePersonalDictionary() {
        let dictionary = [DictionaryEntry(spoken: "오픈 라우터", written: "PersonalSpelling"),
                          .init(spoken: "없는 단어", written: "UnusedTerm"),
                          .init(spoken: "일반 단어", written: "일반 표기")]
        let terms = AppModel.decisionTermCandidates(transcript: "오픈 라우터와 원 패스워드, 그록, 깃허브, 노션의 에이피아이", dictionary: dictionary)
        XCTAssertEqual(terms.count, 4)
        XCTAssertEqual(terms.first?.candidate, "PersonalSpelling")
        XCTAssertFalse(terms.contains { $0.candidate == "UnusedTerm" || $0.candidate == "일반 표기" })
        XCTAssertEqual(Set(terms.map(\.id)).count, terms.count)
    }

    func testSpellingSuggestionsCanPreserveHangulButNeverReverseSpokenLatin() {
        let terms = [DecisionTermCandidate(id: "term", original: "오픈 라우터", candidate: "OpenRouter")]
        let review = DecisionResult(meaningChanged: 0.1, contentAdded: 0.1, contentOmitted: 0.1,
            terms: [.init(id: "term", choice: .keepOriginal,
                          probabilities: [.keepOriginal: 0.9, .useCandidate: 0.05, .uncertain: 0.05], confidence: 0.9)])
        XCTAssertEqual(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: "'오픈 라우터'라고 적어", output: "'OpenRouter'라고 적어"), ["OpenRouter → 오픈 라우터 · 원문 표기 유지"])
        XCTAssertTrue(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: "오픈 라우터의 영문 표기는 OpenRouter", output: "OpenRouter의 영문 표기는 OpenRouter").isEmpty)
    }

    func testSpellingSuggestionsIgnoreTermsDiscardedBySelfCorrection() {
        let terms = [DecisionTermCandidate(id: "notes", original: "노션", candidate: "Notion"),
                     DecisionTermCandidate(id: "repo", original: "깃허브", candidate: "GitHub")]
        let review = DecisionResult(meaningChanged: 0.1, contentAdded: 0.1, contentOmitted: 0.1,
            terms: terms.map { .init(id: $0.id, choice: .useCandidate,
                                    probabilities: [.useCandidate: 0.9, .keepOriginal: 0.05, .uncertain: 0.05], confidence: 0.9) })
        let transcript = "노션에 아니 깃허브 이슈에 남겨 주세요"
        XCTAssertTrue(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: transcript, output: "GitHub 이슈에 남겨 주세요.").isEmpty)
        XCTAssertEqual(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: transcript, output: "깃허브 이슈에 남겨 주세요."), ["깃허브 → GitHub"])
    }

    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let insertions: DecisionAppInsertions
    }
    private func fixture(mode: DecisionReviewMode, evaluator: DecisionAppEvaluator,
                         provider: AIProvider = .openRouter, history: Bool = true) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-DecisionApp-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("store"), backend: DecisionAppSecrets())
        let audio = root.appendingPathComponent("synthetic.wav")
        try Data([82, 73, 70, 70, 1, 2, 3]).write(to: audio)
        let target = InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
                                originalValue: nil, range: nil, selectedText: "selected synthetic source", context: "private surrounding context")
        let insertions = DecisionAppInsertions()
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }; runtime.capture = { _ in target }
        runtime.accessibilityPermitted = { true }; runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("Unexpected microphone access"); return false }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.readKey = { "synthetic-\($0.rawValue)-key" }
        runtime.startRecording = { _ in }; runtime.stopRecording = { audio }; runtime.recordingPeakDB = { -12 }
        runtime.insertText = { text, _, _, cancelled in
            XCTAssertFalse(cancelled()); insertions.texts.append(text); return .confirmed(.paste)
        }
        var preferences = Preferences()
        preferences.provider = .groq; preferences.textProvider = provider
        preferences.decisionReviewMode = mode; preferences.automaticLearningEnabled = false
        preferences.historyEnabled = history
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DecisionAppURLProtocol.self]
        let session = URLSession(configuration: config)
        let model = AppModel(store: store, runtime: runtime, client: ProviderClient(session: session),
                             decisionClient: evaluator, startServices: false, preferences: preferences)
        addTeardownBlock { @MainActor in model.cancel(); session.invalidateAndCancel(); try? FileManager.default.removeItem(at: root) }
        return .init(model: model, store: store, insertions: insertions)
    }
    private func watchCompletion(_ model: AppModel) -> XCTestExpectation {
        let completed = expectation(description: "Dictation completes")
        var delivered = false
        model.onPhaseChange = { [weak model] in
            if model?.phase == .idle, !delivered { delivered = true; completed.fulfill() }
        }
        return completed
    }
    private func startAndStop(_ fixture: Fixture, mode: InputMode = .dictation) async {
        await fixture.model.toggle(mode)
        XCTAssertTrue(fixture.model.phase == .recording)
        fixture.model.elapsed = 1; fixture.model.stop()
    }
    private func recordAndWait(_ fixture: Fixture, mode: InputMode = .dictation) async {
        let completed = watchCompletion(fixture.model)
        await startAndStop(fixture, mode: mode)
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
    }
    private func waitForReview(_ model: AppModel) async {
        for _ in 0..<100 {
            if model.decisionReviewSummary?.contains("검토하고 있어요") == false { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The synthetic decision did not finish")
    }
}

@MainActor private final class DecisionAppInsertions { var texts: [String] = [] }
private actor DecisionAppGate {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(entered: XCTestExpectation) { self.entered = entered }
    func wait() async {
        entered.fulfill()
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
private actor DecisionAppEvaluator: DecisionEvaluating {
    struct Call { let request: DecisionRequest; let key: String }
    private(set) var calls: [Call] = []
    let risk: Double
    let proposeTerm: Bool
    let failure: DecisionError?
    let gate: DecisionAppGate?
    init(risk: Double = 0.1, proposeTerm: Bool = false, failure: DecisionError? = nil, gate: DecisionAppGate? = nil) {
        self.risk = risk; self.proposeTerm = proposeTerm; self.failure = failure; self.gate = gate
    }
    func evaluate(_ input: DecisionRequest, apiKey: String,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        calls.append(.init(request: input, key: apiKey))
        if let gate { await gate.wait() }
        try Task.checkCancellation()
        if let failure { throw failure }
        let usage = ProviderUsage(provider: .openRouter, model: DecisionClient.model, stage: .decisionReview)
        await onUsage?(usage)
        let terms: [DecisionTermResult] = proposeTerm ? input.termCandidates.map {
            .init(id: $0.id, choice: .useCandidate, probabilities: [.useCandidate: 0.8, .keepOriginal: 0.1, .uncertain: 0.1], confidence: 0.8)
        } : []
        return .init(meaningChanged: risk, contentAdded: 0.05, contentOmitted: 0.05, terms: terms)
    }
}
private final class DecisionAppSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = nil }
}
/// Intercepts every URL; these app tests cannot reach a live service.
private final class DecisionAppURLProtocol: URLProtocol {
    static let transcript = "오픈 라우터 연결을 확인해 주세요"
    static let output = "오픈 라우터 연결을 확인해 주세요."
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            let object: [String: Any]
            if url.path.hasSuffix("/audio/transcriptions") { object = ["text": Self.transcript] }
            else if url.path.hasSuffix("/chat/completions") {
                let encoded = try JSONSerialization.data(withJSONObject: ["text": Self.output])
                object = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": String(decoding: encoded, as: UTF8.self)]]]]
            } else { throw URLError(.unsupportedURL) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
