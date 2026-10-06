import AppKit
import AVFoundation
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class TranslationProtectionFlowTests: KoreanPresentationTestCase {
    func testOptOutAndOtherReviewModesKeepTranslationAtTwoProviderRequests() async throws {
        for (enabled, mode) in [(false, DecisionReviewMode.protect), (true, .off), (true, .observe), (true, .repair)] {
            let f = try fixture(enabled: enabled, mode: mode)
            await record(f)
            XCTAssertEqual(f.http.requestCount, 2)
            let calls = await f.reviewer.calls
            XCTAssertTrue(calls.isEmpty)
            XCTAssertEqual(f.insertions.texts, [f.http.output])
        }
    }

    func testNativeAndExplicitTranslationReviewCapturedLanguageAndToneBeforeTyping() async throws {
        for (mode, output, language) in [(InputMode.dictation, DictationOutputLanguage.english, "English (United States)"),
                                        (.dictation, .japanese, "Japanese"), (.dictation, .korean, "Korean"),
                                        (.translation, .original, "Japanese")] {
            let f = try fixture(output: output, tone: .formal, detailed: true)
            await record(f, mode: mode)
            let calls = await f.reviewer.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.purpose, .translation(targetLanguage: language))
            XCTAssertEqual(calls.first?.translationTone, .formal)
            XCTAssertTrue(calls.first?.termCandidates.isEmpty == true)
            XCTAssertEqual(Set(calls.first?.detailAxes ?? []), Set(DecisionDetailAxis.allCases))
            XCTAssertEqual(f.insertions.texts, [f.http.output])
            XCTAssertEqual(f.http.requestCount, 2, "Review cannot trigger regeneration or another STT request")
            let history = try await f.store.history()
            XCTAssertEqual(history.last?.targetLanguage, language)
            let usage = try await f.store.usageRecords()
            XCTAssertEqual(usage.filter { $0.event.stage == .decisionReview }.count, 1)
        }
    }

    func testInconclusiveHighRiskAndMalformedReviewsNeverInsert() async throws {
        for risk in [0.1001, 0.5, 0.9, Double.nan, -0.1, 1.1] {
            let f = try fixture(risk: risk)
            await record(f)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertEqual(f.model.result, f.http.output)
            XCTAssertEqual(f.http.requestCount, 2)
            let calls = await f.reviewer.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertTrue(f.model.notice?.contains("보류") == true)
        }
    }

    func testUnavailableReviewAndMissingConnectionHoldWithoutFallbackOrRegeneration() async throws {
        let failed = try fixture(failure: .timedOut)
        await record(failed)
        XCTAssertTrue(failed.insertions.texts.isEmpty)
        XCTAssertEqual(failed.model.result, failed.http.output)
        XCTAssertEqual(failed.http.requestCount, 2)
        let missing = try fixture(decisionProvider: .typeSafe)
        await record(missing)
        XCTAssertTrue(missing.insertions.texts.isEmpty)
        XCTAssertEqual(missing.http.requestCount, 2)
        let calls = await missing.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testOversizedTranslationReviewHoldsBeforeCallingReviewer() async throws {
        let f = try fixture(transcript: String(repeating: "한", count: 8_001))
        await record(f)
        let calls = await f.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(f.insertions.texts.isEmpty)
        XCTAssertEqual(f.http.requestCount, 2)
        XCTAssertEqual(f.model.result, f.http.output)
    }

    func testRecordingKeepsCapturedTargetAndToneWhenSettingsChange() async throws {
        let f = try fixture(tone: .formal)
        await f.model.toggle(.dictation)
        XCTAssertEqual(f.model.phase, .recording)
        f.model.preferences.dictationOutputLanguage = .english
        f.model.preferences.writingProfiles["test.translation.editor"] = .init(tone: .casual)
        f.model.stop()
        await waitForIdle(f.model)
        let calls = await f.reviewer.calls
        XCTAssertEqual(calls.first?.purpose, .translation(targetLanguage: "Japanese"))
        XCTAssertEqual(calls.first?.translationTone, .formal)
        XCTAssertEqual(f.insertions.texts, [f.http.output])
    }

    func testEnablingProtectionAfterRecordingStartsDoesNotAddReviewToCapturedOptOut() async throws {
        let f = try fixture(enabled: false)
        await f.model.toggle(.dictation)
        f.model.preferences.translationProtectionEnabled = true
        f.model.stop()
        await waitForIdle(f.model)
        let calls = await f.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(f.http.requestCount, 2)
        XCTAssertEqual(f.insertions.texts, [f.http.output])
    }

    func testProtectionRevocationOrCancellationDiscardsLateReviewBeforeTyping() async throws {
        for cancel in [false, true] {
            let gate = TranslationProtectionGate(entered: expectation(description: "Translation review waits"))
            let f = try fixture(gate: gate)
            await f.model.toggle(.dictation)
            f.model.stop()
            await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            if cancel { f.model.cancel() }
            else { f.model.preferences.translationProtectionEnabled = false }
            await gate.release()
            await waitForIdle(f.model)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertEqual(f.http.requestCount, 2)
        }
    }

    func testTranslationToggleDoesNotRevokeSameLanguageDictationReview() async throws {
        let gate = TranslationProtectionGate(entered: expectation(description: "Same-language review waits"))
        let f = try fixture(output: .original, gate: gate)
        await f.model.toggle(.dictation)
        f.model.stop()
        await fulfillment(of: [gate.entered], timeout: 3)
        f.model.preferences.translationProtectionEnabled = false
        await gate.release()
        await waitForIdle(f.model)
        let calls = await f.reviewer.calls
        XCTAssertEqual(calls.first?.purpose, .dictation)
        XCTAssertEqual(f.insertions.texts, [f.http.output])
        XCTAssertEqual(f.http.requestCount, 2)
    }

    func testHistoryReprocessingCapturesProtectionAndLanguageWithoutInsertionOrHistoryReplacement() async throws {
        for enabled in [false, true] {
            let f = try fixture(enabled: enabled, tone: .polite)
            let entry = HistoryEntry(mode: .dictation, originalText: f.http.transcript, resultText: "saved result",
                sourceBundleID: "test.translation.editor", provider: .openRouter)
            _ = try await f.store.appendHistory(entry)
            await f.model.refreshData()
            f.model.reprocessHistory(entry)
            f.model.preferences.dictationOutputLanguage = .english
            f.model.preferences.writingProfiles["test.translation.editor"] = .init(tone: .casual)
            if !enabled { f.model.preferences.translationProtectionEnabled = true }
            await waitForIdle(f.model)
            let calls = await f.reviewer.calls
            XCTAssertEqual(calls.count, enabled ? 1 : 0)
            if enabled {
                XCTAssertEqual(calls.first?.purpose, .translation(targetLanguage: "Japanese"))
                XCTAssertEqual(calls.first?.translationTone, .polite)
            }
            XCTAssertEqual(f.model.historyReprocessing?.reviewTarget?.purpose, .translation(targetLanguage: "Japanese"))
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertEqual(f.http.requestCount, 1)
            let history = try await f.store.history()
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(history.first?.resultText, "saved result")
        }
    }

    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let reviewer: TranslationProtectionReviewer
        let http: TranslationProtectionHTTP
        let insertions: TranslationProtectionInsertions
    }

    private func fixture(enabled: Bool = true, mode: DecisionReviewMode = .protect,
                         output: DictationOutputLanguage = .japanese, tone: WritingTone = .preserve,
                         detailed: Bool = false, risk: Double = 0.01, failure: DecisionError? = nil,
                         gate: TranslationProtectionGate? = nil, decisionProvider: DecisionProvider = .openRouter,
                         transcript: String = "急ぎではありません。資料を確認していただけますか。") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-TranslationProtection-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("store"), backend: TranslationProtectionSecrets())
        let audio = root.appendingPathComponent("synthetic.wav")
        let target = InputTarget(pid: 41009, bundleID: "test.translation.editor", element: nil,
                                 originalValue: nil, range: nil, selectedText: nil, context: nil)
        let insertions = TranslationProtectionInsertions()
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }; runtime.capture = { _ in target }
        runtime.accessibilityPermitted = { true }; runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("Unexpected microphone request"); return false }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.readKey = { _ in "synthetic-provider-key" }; runtime.readStartupKey = { _ in "synthetic-provider-key" }
        runtime.readDecisionKey = { _ in nil }
        runtime.startRecording = { _ in try Data([82, 73, 70, 70, 1, 2, 3]).write(to: audio) }
        runtime.stopRecording = { audio }; runtime.recordingElapsed = { 1 }; runtime.recordingPeakDB = { -20 }
        runtime.insertText = { text, _, _, isCancelled in
            XCTAssertFalse(isCancelled()); insertions.texts.append(text); return .confirmed(.paste)
        }
        var preferences = Preferences.koreanForTesting
        preferences.provider = .groq; preferences.textProvider = .openRouter
        preferences.decisionReviewMode = mode; preferences.translationProtectionEnabled = enabled
        preferences.dictationOutputLanguage = output; preferences.targetLanguage = "Japanese"
        preferences.writingProfiles["test.translation.editor"] = .init(tone: tone)
        preferences.automaticLearningEnabled = false; preferences.jevDetailedReviewEnabled = detailed
        preferences.decisionProvider = decisionProvider
        let translated: String
        switch output {
        case .english: translated = "Could you review the materials? It is not urgent."
        case .korean: translated = "급한 건 아니에요. 자료를 확인해 주실 수 있나요?"
        default: translated = "急ぎではありません。資料を確認していただけますか。"
        }
        let http = TranslationProtectionHTTP(transcript: transcript, output: translated)
        let reviewer = TranslationProtectionReviewer(risk: risk, failure: failure, gate: gate)
        let model = AppModel(store: store, runtime: runtime, client: http.client, decisionClient: reviewer,
                             startServices: false, preferences: preferences)
        addTeardownBlock { @MainActor in model.cancel(); http.close(); try? FileManager.default.removeItem(at: root) }
        return .init(model: model, store: store, reviewer: reviewer, http: http, insertions: insertions)
    }

    private func record(_ f: Fixture, mode: InputMode = .dictation) async {
        await f.model.toggle(mode)
        XCTAssertEqual(f.model.phase, .recording)
        f.model.stop()
        await waitForIdle(f.model)
    }
    private func waitForIdle(_ model: AppModel) async {
        for _ in 0..<400 {
            if model.phase == .idle { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Synthetic translation protection did not finish")
    }
}

@MainActor private final class TranslationProtectionInsertions { var texts: [String] = [] }
private actor TranslationProtectionGate {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(entered: XCTestExpectation) { self.entered = entered }
    func wait() async {
        entered.fulfill()
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
private actor TranslationProtectionReviewer: DecisionEvaluating {
    private(set) var calls: [DecisionRequest] = []
    let risk: Double
    let failure: DecisionError?
    let gate: TranslationProtectionGate?
    init(risk: Double, failure: DecisionError?, gate: TranslationProtectionGate?) {
        self.risk = risk; self.failure = failure; self.gate = gate
    }
    func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        calls.append(input)
        if let gate { await gate.wait() }
        try Task.checkCancellation()
        if let failure { throw failure }
        let usage = ProviderUsage(provider: .openRouter, decisionProvider: configuration.provider,
            model: configuration.provider.model, stage: .decisionReview, inputTokens: 100, outputTokens: 10)
        await onUsage?(usage)
        return .init(meaningChanged: risk, contentAdded: 0.01, contentOmitted: 0.01,
            detailRisks: Dictionary(uniqueKeysWithValues: input.detailAxes.map { ($0, 0.01) }))
    }
}
private final class TranslationProtectionSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = nil }
}
private final class TranslationProtectionHTTP: @unchecked Sendable {
    static let registryLock = NSLock()
    static var registry: [String: TranslationProtectionHTTP] = [:]
    let id = UUID().uuidString
    let transcript: String
    let output: String
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    private(set) var session: URLSession!
    lazy var client = ProviderClient(session: session)
    init(transcript: String, output: String) {
        self.transcript = transcript; self.output = output
        Self.registryLock.lock(); Self.registry[id] = self; Self.registryLock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationProtectionURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Synthetic-Translation-Test": id]
        session = URLSession(configuration: config)
    }
    func close() {
        session.invalidateAndCancel()
        Self.registryLock.lock(); Self.registry[id] = nil; Self.registryLock.unlock()
    }
    func response(for request: URLRequest) throws -> Data {
        lock.lock(); count += 1; lock.unlock()
        let object: [String: Any]
        if request.url?.path.hasSuffix("/audio/transcriptions") == true { object = ["text": transcript] }
        else {
            let text = try JSONSerialization.data(withJSONObject: ["text": output])
            object = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": String(decoding: text, as: UTF8.self)]]],
                      "usage": ["prompt_tokens": 100, "completion_tokens": 20]]
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
/// Handles every network request locally; no synthetic regression can contact a live provider.
private final class TranslationProtectionURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let id = request.value(forHTTPHeaderField: "X-Synthetic-Translation-Test"), let url = request.url else { throw URLError(.badURL) }
            TranslationProtectionHTTP.registryLock.lock()
            let state = TranslationProtectionHTTP.registry[id]
            TranslationProtectionHTTP.registryLock.unlock()
            guard let state else { throw URLError(.resourceUnavailable) }
            let bytes = try state.response(for: request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                               headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
