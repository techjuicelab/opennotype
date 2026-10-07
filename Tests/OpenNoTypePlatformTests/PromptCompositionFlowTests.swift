import AppKit
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class PromptCompositionFlowTests: KoreanPresentationTestCase {
    func testPromptHistoryReprocessingAlwaysUsesTwoGenerationsAndTwoReviewsWithoutTyping() async throws {
        let fixture = try fixture()
        await fixture.model.refreshData()
        await reprocessAndWait(fixture)

        XCTAssertEqual(fixture.http.bodies.count, 2)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.map(\.transcript), [fixture.entry.originalText, fixture.entry.originalText])
        XCTAssertEqual(calls.map(\.prompt), [PromptFlowHTTP.draft, PromptFlowHTTP.final])
        XCTAssertEqual(fixture.model.promptComposition?.output, PromptFlowHTTP.final)
        XCTAssertEqual(fixture.model.historyReprocessing?.result, PromptFlowHTTP.final)
        XCTAssertEqual(fixture.model.historyReprocessing?.reviewTarget?.purpose, .promptComposition)
        XCTAssertNil(fixture.model.historyReprocessing?.error)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertEqual(fixture.boundaries.captures, 0)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
        let first = try userInput(fixture.http.bodies[0]), second = try userInput(fixture.http.bodies[1])
        XCTAssertEqual(first["mode"] as? String, "prompt")
        XCTAssertEqual(first["spoken_text"] as? String, fixture.entry.originalText)
        XCTAssertNil(first["prompt_draft"])
        XCTAssertNil(first["writing_profile"])
        XCTAssertNil(first["target_language"])
        XCTAssertEqual(second["prompt_draft"] as? String, PromptFlowHTTP.draft)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
        XCTAssertEqual(saved.first?.mode, .prompt)
    }

    func testUncertainFinalReviewHoldsPromptAndNeverPublishesHistoryPreviewResult() async throws {
        let fixture = try fixture(uncertainFinal: true)
        await fixture.model.refreshData()
        await reprocessAndWait(fixture)

        XCTAssertEqual(fixture.http.bodies.count, 2)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(fixture.model.promptComposition?.held == true)
        XCTAssertEqual(fixture.model.promptComposition?.draft, PromptFlowHTTP.draft)
        XCTAssertNil(fixture.model.promptComposition?.output)
        XCTAssertNil(fixture.model.historyReprocessing?.result)
        XCTAssertNotNil(fixture.model.historyReprocessing?.error)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertFalse(fixture.model.isBusy)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
    }

    func testMissingReviewKeyBlocksHistoryReprocessingBeforePaidGeneration() async throws {
        let fixture = try fixture(hasKey: false)
        try await fixture.store.saveHistory([fixture.entry])
        await fixture.model.refreshData()
        XCTAssertNotNil(fixture.model.promptCompositionIssue)
        XCTAssertNotNil(fixture.model.historyReprocessingUnavailableReason(for: fixture.entry))
        fixture.model.reprocessHistory(fixture.entry)

        XCTAssertTrue(fixture.http.bodies.isEmpty)
        let calls = await fixture.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(fixture.model.historyReprocessing)
        XCTAssertNil(fixture.model.promptComposition)
        XCTAssertFalse(fixture.model.isBusy)
    }

    func testPromptRecordingStartsInOwnAppWithoutAccessibilityOrInputTargetCapture() async throws {
        let fixture = try fixture()
        XCTAssertFalse(fixture.model.accessibilityAllowed)
        await fixture.model.toggle(.prompt)

        XCTAssertTrue(fixture.model.phase == .recording)
        XCTAssertEqual(fixture.model.mode, .prompt)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 1)
        XCTAssertEqual(fixture.boundaries.captures, 0)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertTrue(fixture.http.bodies.isEmpty)
        fixture.model.cancel()
        XCTAssertFalse(fixture.model.isBusy)
    }

    func testPromptHistorySettingsChangeBeforeItsFirstSuspensionCancelsBeforePaidGeneration() async throws {
        for changeProvider in [false, true] {
            let fixture = try fixture()
            try await fixture.store.saveHistory([fixture.entry])
            await fixture.model.refreshData()
            XCTAssertEqual(fixture.model.mode, .dictation, "The last recording mode does not identify a history job")
            fixture.model.reprocessHistory(fixture.entry)
            XCTAssertNil(fixture.model.promptComposition, "The task has not yet reached composePrompt")
            if changeProvider { fixture.model.preferences.textProvider = .groq }
            else { fixture.model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/changed-prompt" }

            XCTAssertFalse(fixture.model.isBusy)
            XCTAssertNil(fixture.model.historyReprocessing)
            let latePhase = expectation(description: "Cancelled prompt history must not resume")
            latePhase.isInverted = true
            fixture.model.onPhaseChange = { latePhase.fulfill() }
            await fulfillment(of: [latePhase], timeout: 0.1)
            fixture.model.onPhaseChange = nil
            XCTAssertTrue(fixture.http.bodies.isEmpty)
            let calls = await fixture.reviewer.calls
            XCTAssertTrue(calls.isEmpty)
            XCTAssertNil(fixture.model.promptComposition)
        }
    }

    func testOrdinaryHistoryKeepsCapturedSettingsAfterTheLastRecordingWasPromptMode() async throws {
        let fixture = try fixture()
        var entry = fixture.entry
        entry.mode = .dictation
        try await fixture.store.saveHistory([entry])
        await fixture.model.refreshData()
        fixture.model.mode = .prompt
        fixture.model.preferences.dictationOutputLanguage = .original
        let finished = expectation(description: "Ordinary history retains its captured provider model")
        var delivered = false
        fixture.model.onPhaseChange = { [weak model = fixture.model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        fixture.model.reprocessHistory(entry)
        fixture.model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/changed-after-capture"
        await fulfillment(of: [finished], timeout: 5)
        fixture.model.onPhaseChange = nil

        XCTAssertEqual(fixture.http.bodies.count, 1)
        let body = try XCTUnwrap(fixture.http.bodies.first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "test/prompt-flow")
        XCTAssertEqual(fixture.model.historyReprocessing?.result, PromptFlowHTTP.draft)
        XCTAssertNil(fixture.model.historyReprocessing?.error)
        XCTAssertNil(fixture.model.promptComposition)
        let calls = await fixture.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
    }

    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let entry: HistoryEntry
        let http: PromptFlowHTTP
        let reviewer: PromptFlowReviewer
        let boundaries: PromptFlowBoundaries
    }

    private func fixture(hasKey: Bool = true, uncertainFinal: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-PromptFlow-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("vault"), backend: PromptFlowSecrets())
        let entry = HistoryEntry(mode: .prompt,
            originalText: "OpenNoType에서 말한 아이디어를 Codex용 짧은 작업 요청으로 정리해 줘. 코드나 설계는 넣지 마.",
            resultText: "이전에 보관한 프롬프트", provider: .groq)
        let http = PromptFlowHTTP()
        let reviewer = PromptFlowReviewer(uncertainFinal: uncertainFinal)
        let boundaries = PromptFlowBoundaries()
        var runtime = AppRuntime()
        runtime.frontmostApplication = { .current }
        runtime.capture = { _ in boundaries.captures += 1; XCTFail("Prompt composition must not capture another app"); return nil }
        runtime.accessibilityPermitted = { false }
        runtime.secureInputActive = { true }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("Unexpected microphone permission request"); return false }
        runtime.readKey = { _ in hasKey ? "synthetic-prompt-flow-key" : nil }
        runtime.readDecisionKey = { _ in XCTFail("OpenRouter review must use its existing connection"); return nil }
        runtime.startRecording = { _ in boundaries.recordingStarts += 1 }
        runtime.stopRecording = { nil }
        runtime.recordingElapsed = { 1 }
        runtime.recordingPeakDB = { -12 }
        runtime.insertText = { _, _, _, _ in boundaries.insertions += 1; XCTFail("Prompt composition must not type into another app"); return .confirmed(.paste) }
        var preferences = Preferences.koreanForTesting
        preferences.provider = .openRouter
        preferences.useLocalTranscription = false
        preferences.speakerFilterEnabled = false
        preferences.usageTrackingEnabled = false
        preferences.automaticLearningEnabled = false
        preferences.decisionProvider = .openRouter
        preferences.decisionReviewMode = .off
        preferences.dictationOutputLanguage = .japanese
        preferences.dictationExpression = .init(style: .creative, strength: 100)
        preferences.textModels[AIProvider.openRouter.rawValue] = "test/prompt-flow"
        let model = AppModel(store: store, runtime: runtime, client: http.client, decisionClient: reviewer,
                             startServices: false, preferences: preferences)
        addTeardownBlock { @MainActor in
            model.cancel(); http.close()
            try? FileManager.default.removeItem(at: root)
        }
        return .init(model: model, store: store, entry: entry, http: http, reviewer: reviewer, boundaries: boundaries)
    }

    private func reprocessAndWait(_ fixture: Fixture) async {
        do { try await fixture.store.saveHistory([fixture.entry]); await fixture.model.refreshData() }
        catch { XCTFail("Synthetic history setup failed: \(error)"); return }
        let finished = expectation(description: "Prompt history pipeline completes")
        var delivered = false
        fixture.model.onPhaseChange = { [weak model = fixture.model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        fixture.model.reprocessHistory(fixture.entry)
        await fulfillment(of: [finished], timeout: 5)
        fixture.model.onPhaseChange = nil
    }

    private func userInput(_ data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
        let content = try XCTUnwrap(messages.first(where: { $0["role"] == "user" })?["content"])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
    }
}

@MainActor private final class PromptFlowBoundaries {
    var captures = 0
    var insertions = 0
    var recordingStarts = 0
}

private actor PromptFlowReviewer: DecisionEvaluating {
    let uncertainFinal: Bool
    private(set) var calls: [PromptCompositionReviewRequest] = []
    init(uncertainFinal: Bool) { self.uncertainFinal = uncertainFinal }
    func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        throw DecisionError.invalidInput
    }
    func reviewPromptComposition(_ input: PromptCompositionReviewRequest, configuration: DecisionConfiguration,
                                 onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> PromptCompositionReviewResult {
        calls.append(input)
        let choice: PromptCompositionReviewChoice = uncertainFinal && calls.count == 2 ? .uncertain : .pass
        var probabilities: [PromptCompositionReviewChoice: Double] = [.pass: 0.03, .fail: 0.03, .uncertain: 0.03]
        probabilities[choice] = 0.94
        let assessment = PromptCompositionReviewAssessment(choice: choice, probabilities: probabilities, confidence: 0.9)
        return .init(assessments: Dictionary(uniqueKeysWithValues: PromptCompositionIssue.allCases.map { ($0, assessment) }))
    }
}

private final class PromptFlowSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = nil }
}

private final class PromptFlowHTTP: @unchecked Sendable {
    static let draft = "OpenNoType의 아이디어를 Codex용 짧은 작업 요청으로 정리해 주세요."
    static let final = "OpenNoType의 아이디어를 Codex용 짧은 작업 요청으로 정리해 주세요. 코드와 직접 설계는 포함하지 마세요."
    let id = UUID().uuidString
    let session: URLSession
    let client: ProviderClient
    var bodies: [Data] { PromptFlowURLProtocol.bodies(for: id) }
    init() {
        PromptFlowURLProtocol.register(id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PromptFlowURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-OpenNoType-PromptFlow": id]
        session = URLSession(configuration: configuration)
        client = ProviderClient(session: session)
    }
    func close() { session.invalidateAndCancel(); PromptFlowURLProtocol.remove(id) }
}

/// Every URL is intercepted; no live service, microphone or real credential is used.
private final class PromptFlowURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var logs: [String: [Data]] = [:]
    static func register(_ id: String) { lock.lock(); defer { lock.unlock() }; logs[id] = [] }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; logs[id] = nil }
    static func bodies(for id: String) -> [Data] { lock.lock(); defer { lock.unlock() }; return logs[id] ?? [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url, url.path.hasSuffix("/chat/completions"),
                  let id = request.value(forHTTPHeaderField: "X-OpenNoType-PromptFlow") else { throw URLError(.unsupportedURL) }
            let body = try Self.body(request)
            Self.lock.lock()
            guard let count = Self.logs[id]?.count else { Self.lock.unlock(); throw URLError(.resourceUnavailable) }
            Self.logs[id]?.append(body)
            Self.lock.unlock()
            let output = count == 0 ? PromptFlowHTTP.draft : PromptFlowHTTP.final
            let content = String(decoding: try JSONSerialization.data(withJSONObject: ["text": output]), as: UTF8.self)
            let object: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": content]]]]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    private static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
