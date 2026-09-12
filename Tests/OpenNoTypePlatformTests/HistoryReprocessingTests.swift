import AppKit
import AVFoundation
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class HistoryReprocessingTests: XCTestCase {
    func testReprocessingUsesOriginalTextAndCurrentSettingsWithoutChangingHistoryOrDelivery() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry()
        try await fixture.store.saveHistory([entry])
        let http = HistoryPreviewHTTP()
        var preferences = currentPreferences()
        preferences.writingProfiles["test.editor"] = .init(kind: .development, tone: .polite)
        let model = makeModel(fixture, http: http, preferences: preferences)
        await model.refreshData()
        model.dictionary = [.init(spoken: "합성", written: "Synthetic")]
        model.result = "현재 입력 결과 유지"
        var managerOpens = 0
        model.showManager = { managerOpens += 1 }

        await reprocessAndWait(model, entry: entry)

        XCTAssertEqual(model.historyReprocessing?.result, HistoryPreviewHTTP.resultText)
        XCTAssertNil(model.historyReprocessing?.error)
        XCTAssertEqual(model.result, "현재 입력 결과 유지")
        XCTAssertEqual(managerOpens, 0)
        XCTAssertEqual(http.requests.count, 1, "Only one text request; no STT or automatic verification request")
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.path, "/api/v1/chat/completions")
        XCTAssertEqual(request.model, "test/current-text")
        let input = try userInput(request)
        XCTAssertEqual(input["spoken_text"] as? String, entry.originalText)
        XCTAssertNil(input["cursor_context"])
        XCTAssertNil(input["original_text"])
        let profile = try XCTUnwrap(input["writing_profile"] as? [String: String])
        XCTAssertEqual(profile, ["kind": "development", "tone": "polite"])
        XCTAssertTrue(String(decoding: request.body, as: UTF8.self).contains("Synthetic"))
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.map(\.id), [entry.id])
        XCTAssertEqual(saved.first?.originalText, entry.originalText)
        XCTAssertEqual(saved.first?.resultText, entry.resultText)
        XCTAssertEqual(saved.first?.provider, .groq)
        let usage = try await fixture.store.usageRecords()
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage.first?.event.stage, .textProcessing)
        XCTAssertEqual(usage.first?.event.inputTokens, 40)
        XCTAssertEqual(usage.first?.event.outputTokens, 15)
        XCTAssertEqual(usage.first?.event.model, "test/current-text")
        XCTAssertFalse(try XCTUnwrap(usage.first).isRecovery)
        let failures = try await fixture.store.failures()
        XCTAssertTrue(failures.isEmpty)
    }

    func testTranslationSnapshotsCurrentLanguageAndProfileAndExplainsThoseSettings() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry(mode: .translation)
        try await fixture.store.saveHistory([entry])
        let http = HistoryPreviewHTTP()
        var preferences = currentPreferences()
        preferences.targetLanguage = "Japanese"
        preferences.writingProfiles["test.editor"] = .init(kind: .email, tone: .formal)
        let model = makeModel(fixture, http: http, preferences: preferences)
        await model.refreshData()
        XCTAssertTrue(model.historyReprocessingSettings(for: entry).contains("Japanese"))
        XCTAssertTrue(model.historyReprocessingSettings(for: entry).contains("격식 있는 존댓말"))
        let finished = idleExpectation(model)
        model.reprocessHistory(entry)
        model.preferences.targetLanguage = "English (United States)"
        model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/changed-text"
        model.preferences.writingProfiles["test.editor"] = .init(kind: .notes, tone: .casual)
        await fulfillment(of: [finished], timeout: 5)
        model.onPhaseChange = nil

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.model, "test/current-text")
        let input = try userInput(request)
        XCTAssertEqual(input["target_language"] as? String, "Japanese")
        XCTAssertEqual(input["writing_profile"] as? [String: String], ["kind": "email", "tone": "formal"])
        XCTAssertTrue(try XCTUnwrap(model.historyReprocessing).settingsDescription.contains("Japanese"))
        XCTAssertFalse(try XCTUnwrap(model.historyReprocessing).settingsDescription.contains("changed-text"))
    }

    func testRewriteAndMissingOrEmptyHistoryDoNotSendRequests() async throws {
        let fixture = try makeFixture()
        let rewrite = historyEntry(mode: .rewrite)
        let empty = HistoryEntry(mode: .dictation, originalText: " \n", resultText: "이전 결과", provider: .groq)
        try await fixture.store.saveHistory([rewrite, empty])
        let http = HistoryPreviewHTTP()
        let model = makeModel(fixture, http: http)
        await model.refreshData()
        XCTAssertTrue(try XCTUnwrap(model.historyReprocessingUnavailableReason(for: rewrite)).contains("당시 선택한 문장"))
        model.reprocessHistory(rewrite)
        XCTAssertNil(model.historyReprocessing)
        model.reprocessHistory(empty)
        XCTAssertNil(model.historyReprocessing)
        model.reprocessHistory(historyEntry())
        XCTAssertNil(model.historyReprocessing)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(http.requests.count, 0)
    }

    func testCancelStopsPreviewAndLateCompletionCannotRestoreIt() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry()
        try await fixture.store.saveHistory([entry])
        let requested = expectation(description: "Text request is suspended")
        let stopped = expectation(description: "Cancelled transport stops")
        let gate = HistoryPreviewGate()
        let http = HistoryPreviewHTTP(gate: gate, requested: requested, stopped: stopped)
        let model = makeModel(fixture, http: http)
        await model.refreshData()
        model.result = "기존 결과"
        model.reprocessHistory(entry)
        await fulfillment(of: [requested], timeout: 5)
        model.cancel()
        gate.release()
        await fulfillment(of: [stopped], timeout: 5)
        await assertNoLatePhaseChange(model)

        XCTAssertNil(model.historyReprocessing)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.result, "기존 결과")
        XCTAssertEqual(http.requests.count, 1)
        let saved = try await fixture.store.history()
        XCTAssertTrue(saved.contains(where: { $0.id == entry.id }))
    }

    func testNewRecordingCancelsHistoryRequestWithoutBeingEndedByItsCompletion() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry()
        try await fixture.store.saveHistory([entry])
        let requested = expectation(description: "History request is suspended")
        let stopped = expectation(description: "History transport stops")
        let gate = HistoryPreviewGate()
        let http = HistoryPreviewHTTP(gate: gate, requested: requested, stopped: stopped)
        var runtime = offlineRuntime(root: fixture.root)
        var starts = 0
        runtime.capture = { _ in
            InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
                        originalValue: nil, range: nil, selectedText: nil, context: nil)
        }
        runtime.startRecording = { _ in starts += 1 }
        let model = AppModel(store: fixture.store, runtime: runtime, client: http.client,
                             startServices: false, preferences: currentPreferences())
        defer { model.cancel() }
        await model.refreshData()
        model.reprocessHistory(entry)
        await fulfillment(of: [requested], timeout: 5)
        await model.toggle(.translation)
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(model.phase == .recording)
        gate.release()
        await fulfillment(of: [stopped], timeout: 5)
        await assertNoLatePhaseChange(model)

        XCTAssertNil(model.historyReprocessing)
        XCTAssertTrue(model.phase == .recording)
        XCTAssertEqual(model.mode, .translation)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testRejectedRecordingPreservesCompletedPreviewUntilRecordingActuallyStarts() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry()
        try await fixture.store.saveHistory([entry])
        let http = HistoryPreviewHTTP()
        var frontIsSelf = true
        var hasTarget = false
        var starts = 0
        var runtime = offlineRuntime(root: fixture.root)
        runtime.frontmostApplication = { frontIsSelf ? .current : nil }
        runtime.capture = { _ in
            guard hasTarget else { return nil }
            return InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
                               originalValue: nil, range: nil, selectedText: nil, context: nil)
        }
        runtime.startRecording = { _ in starts += 1 }
        let model = AppModel(store: fixture.store, runtime: runtime, client: http.client,
                             startServices: false, preferences: currentPreferences())
        defer { model.cancel() }
        await model.refreshData()
        await reprocessAndWait(model, entry: entry)
        let previewID = try XCTUnwrap(model.historyReprocessing).id

        await model.toggle(.dictation)
        XCTAssertEqual(model.historyReprocessing?.id, previewID)
        XCTAssertEqual(model.historyReprocessing?.result, HistoryPreviewHTTP.resultText)
        XCTAssertEqual(starts, 0)

        frontIsSelf = false
        await model.toggle(.dictation)
        XCTAssertEqual(model.historyReprocessing?.id, previewID, "A failed target capture must also keep the paid preview")
        XCTAssertEqual(model.historyReprocessing?.result, HistoryPreviewHTTP.resultText)
        XCTAssertEqual(starts, 0)

        hasTarget = true
        await model.toggle(.dictation)
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(model.phase == .recording)
        XCTAssertNil(model.historyReprocessing)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testDeletingSourceCancelsPendingPreviewAndCannotResurrectDeletedRecord() async throws {
        for deleteAll in [false, true] {
            let fixture = try makeFixture()
            let entry = historyEntry()
            try await fixture.store.saveHistory([entry])
            let requested = expectation(description: "History request is suspended before deletion")
            let stopped = expectation(description: "Deleted source transport stops")
            let gate = HistoryPreviewGate()
            let http = HistoryPreviewHTTP(gate: gate, requested: requested, stopped: stopped)
            let model = makeModel(fixture, http: http)
            await model.refreshData()
            model.reprocessHistory(entry)
            await fulfillment(of: [requested], timeout: 5)
            await model.deleteHistory(deleteAll ? nil : entry)
            gate.release()
            await fulfillment(of: [stopped], timeout: 5)
            await assertNoLatePhaseChange(model)

            XCTAssertNil(model.historyReprocessing)
            XCTAssertFalse(model.isBusy)
            XCTAssertTrue(model.history.isEmpty)
            let saved = try await fixture.store.history()
            XCTAssertTrue(saved.isEmpty)
            model.reprocessHistory(entry)
            XCTAssertEqual(http.requests.count, 1)
        }
    }

    func testStorageRefreshRemovesCompletedPreviewWhenItsSourceDisappears() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry()
        try await fixture.store.saveHistory([entry])
        let http = HistoryPreviewHTTP()
        let model = makeModel(fixture, http: http)
        await model.refreshData()
        await reprocessAndWait(model, entry: entry)
        XCTAssertNotNil(model.historyReprocessing?.result)
        _ = try await fixture.store.deleteHistory(id: entry.id)
        await model.refreshData()

        XCTAssertNil(model.historyReprocessing)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testMalformedOutputHasPreviewErrorAndStillRecordsReceivedUsage() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry()
        try await fixture.store.saveHistory([entry])
        let http = HistoryPreviewHTTP(content: "malformed synthetic JSON")
        let model = makeModel(fixture, http: http)
        await model.refreshData()
        await reprocessAndWait(model, entry: entry)

        XCTAssertNotNil(model.historyReprocessing?.error)
        XCTAssertNil(model.historyReprocessing?.result)
        XCTAssertFalse(model.isBusy)
        let usage = try await fixture.store.usageRecords()
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage.first?.event.outcome, .responseReceived)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.first?.resultText, entry.resultText)
    }

    func testDisabledUsageTrackingStillAllowsPreviewWithoutAccounting() async throws {
        let fixture = try makeFixture()
        let entry = historyEntry()
        try await fixture.store.saveHistory([entry])
        let http = HistoryPreviewHTTP()
        var preferences = currentPreferences()
        preferences.usageTrackingEnabled = false
        let model = makeModel(fixture, http: http, preferences: preferences)
        await model.refreshData()
        await reprocessAndWait(model, entry: entry)

        XCTAssertEqual(model.historyReprocessing?.result, HistoryPreviewHTTP.resultText)
        let usage = try await fixture.store.usageRecords()
        XCTAssertTrue(usage.isEmpty)
        XCTAssertEqual(http.requests.count, 1)
    }

    private struct Fixture { let root: URL; let store: SecureStore }
    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-HistoryPreview-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("vault"), backend: HistoryPreviewSecrets())
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(root: root, store: store)
    }
    private func historyEntry(mode: InputMode = .dictation) -> HistoryEntry {
        .init(mode: mode, originalText: "합성 원문, 어 합성 원문을 다시 정리해 줘.",
              resultText: "이전에 보관한 결과", sourceBundleID: "test.editor", provider: .groq)
    }
    private func currentPreferences() -> Preferences {
        var preferences = Preferences()
        preferences.provider = .openRouter
        preferences.useLocalTranscription = false
        preferences.speakerFilterEnabled = false
        preferences.usageTrackingEnabled = true
        preferences.textModels[AIProvider.openRouter.rawValue] = "test/current-text"
        return preferences
    }
    private func offlineRuntime(root: URL) -> AppRuntime {
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }
        runtime.capture = { _ in XCTFail("History preview must not capture a target app"); return nil }
        runtime.accessibilityPermitted = { true }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("No microphone permission prompt"); return false }
        runtime.readKey = { _ in "synthetic-history-preview-key" }
        runtime.startRecording = { _ in XCTFail("History preview must not start recording") }
        let audioSession = TemporaryAudioSession(rootDirectory: root.appendingPathComponent("audio"))
        runtime.makeTemporaryAudioURL = { try audioSession.makeURL() }
        return runtime
    }
    private func makeModel(_ fixture: Fixture, http: HistoryPreviewHTTP, preferences: Preferences? = nil) -> AppModel {
        AppModel(store: fixture.store, runtime: offlineRuntime(root: fixture.root), client: http.client,
                 startServices: false, preferences: preferences ?? currentPreferences())
    }
    private func idleExpectation(_ model: AppModel) -> XCTestExpectation {
        let finished = expectation(description: "History preview completes")
        var fulfilled = false
        model.onPhaseChange = { [weak model] in
            if model?.phase == .idle, !fulfilled { fulfilled = true; finished.fulfill() }
        }
        return finished
    }
    private func reprocessAndWait(_ model: AppModel, entry: HistoryEntry) async {
        let finished = idleExpectation(model)
        model.reprocessHistory(entry)
        await fulfillment(of: [finished], timeout: 5)
        model.onPhaseChange = nil
        if model.isBusy { model.cancel() }
    }
    private func assertNoLatePhaseChange(_ model: AppModel) async {
        let changed = expectation(description: "Stale history completion must not change phase")
        changed.isInverted = true
        model.onPhaseChange = { changed.fulfill() }
        await fulfillment(of: [changed], timeout: 0.15)
        model.onPhaseChange = nil
    }
    private func userInput(_ request: HistoryPreviewRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        let text = try XCTUnwrap(messages.first(where: { $0["role"] == "user" })?["content"])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

private final class HistoryPreviewSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[service + ":" + account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + ":" + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + ":" + account] = nil
    }
}
private struct HistoryPreviewRequest { let path: String; let model: String; let body: Data }
private final class HistoryPreviewGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (() -> Void)?
    private var released = false
    func wait(_ action: @escaping () -> Void) {
        lock.lock()
        if released { lock.unlock(); action() }
        else { pending = action; lock.unlock() }
    }
    func release() {
        lock.lock(); released = true; let action = pending; pending = nil; lock.unlock()
        action?()
    }
}
private final class HistoryPreviewHTTP: @unchecked Sendable {
    static let resultText = "다시 처리한 합성 결과"
    let id = UUID().uuidString
    let session: URLSession
    let client: ProviderClient
    var requests: [HistoryPreviewRequest] { HistoryPreviewURLProtocol.requests(for: id) }
    init(content: String = "{\"text\":\"다시 처리한 합성 결과\"}", gate: HistoryPreviewGate? = nil,
         requested: XCTestExpectation? = nil, stopped: XCTestExpectation? = nil) {
        HistoryPreviewURLProtocol.register(id, stub: .init(content: content, gate: gate, requested: requested, stopped: stopped))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HistoryPreviewURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-OpenNoType-HistoryPreview": id]
        session = URLSession(configuration: configuration)
        client = ProviderClient(session: session)
    }
    deinit { session.invalidateAndCancel(); HistoryPreviewURLProtocol.remove(id) }
}
/// Every URL is intercepted. These tests cannot contact an API, capture an input target, or use a real key.
private final class HistoryPreviewURLProtocol: URLProtocol {
    struct Stub {
        let content: String
        let gate: HistoryPreviewGate?
        let requested: XCTestExpectation?
        let stopped: XCTestExpectation?
    }
    private static let lock = NSLock()
    private static var logs: [String: [HistoryPreviewRequest]] = [:]
    private static var stubs: [String: Stub] = [:]
    private let stateLock = NSLock()
    private var cancelled = false
    private var stoppedExpectation: XCTestExpectation?
    static func register(_ id: String, stub: Stub) {
        lock.lock(); defer { lock.unlock() }; logs[id] = []; stubs[id] = stub
    }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; logs[id] = nil; stubs[id] = nil }
    static func requests(for id: String) -> [HistoryPreviewRequest] { lock.lock(); defer { lock.unlock() }; return logs[id] ?? [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let id = request.value(forHTTPHeaderField: "X-OpenNoType-HistoryPreview") ?? ""
            let body = try Self.body(request)
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let model = object["model"] as? String, let url = request.url else { throw URLError(.badServerResponse) }
            Self.lock.lock()
            let stub = Self.stubs[id]
            if stub != nil { Self.logs[id]?.append(.init(path: url.path, model: model, body: body)) }
            Self.lock.unlock()
            guard let stub, url.path == "/api/v1/chat/completions" else { throw URLError(.unsupportedURL) }
            stateLock.lock(); stoppedExpectation = stub.stopped; stateLock.unlock()
            let data = try JSONSerialization.data(withJSONObject: [
                "model": "test/resolved-text", "usage": ["prompt_tokens": 40, "completion_tokens": 15, "cost": 0.00015],
                "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": stub.content]]]
            ])
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            let deliver = { [self] in
                stateLock.lock(); let stopped = cancelled; stateLock.unlock()
                guard !stopped else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            if let gate = stub.gate { gate.wait(deliver) } else { deliver() }
            stub.requested?.fulfill()
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {
        stateLock.lock(); cancelled = true; let stopped = stoppedExpectation; stoppedExpectation = nil; stateLock.unlock()
        stopped?.fulfill()
    }
    private static func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open(); defer { stream.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { return data }
            data.append(bytes, count: count)
        }
    }
}
