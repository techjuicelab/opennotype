import AppKit
import AVFoundation
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class AppModelFlowTests: XCTestCase {
    @MainActor private final class CaptureGate {
        let entered: XCTestExpectation
        var count = 0
        private var continuations: [CheckedContinuation<InputTarget?, Never>] = []
        private var released = false
        private var result: InputTarget?

        init(entered: XCTestExpectation) { self.entered = entered }
        func capture() async -> InputTarget? {
            count += 1
            if count == 1 { entered.fulfill() }
            if released { return result }
            return await withCheckedContinuation { continuations.append($0) }
        }
        func release(_ target: InputTarget?) {
            released = true; result = target
            let waiting = continuations; continuations.removeAll()
            waiting.forEach { $0.resume(returning: target) }
        }
    }

    private func isolatedStore() throws -> SecureStore {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-AppFlow-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try SecureStore(directory: directory, backend: FlowMemorySecrets())
    }

    private func offlineRuntime() -> AppRuntime {
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }
        runtime.capture = { _ in XCTFail("Unexpected target capture"); return nil }
        runtime.accessibilityPermitted = { true }
        runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("No permission prompt is allowed in an app flow test"); return false }
        runtime.readKey = { _ in "synthetic-app-flow-key" }
        runtime.startRecording = { _ in XCTFail("No microphone start is allowed without a test override") }
        let audioDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-AppFlow-Audio-\(UUID().uuidString)", isDirectory: true)
        let audioSession = TemporaryAudioSession(rootDirectory: audioDirectory)
        runtime.makeTemporaryAudioURL = { try audioSession.makeURL() }
        addTeardownBlock { try? FileManager.default.removeItem(at: audioDirectory) }
        return runtime
    }

    private var syntheticTarget: InputTarget {
        InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
                    originalValue: nil, range: nil, selectedText: nil, context: nil)
    }

    func testRecordingStartAnnouncesHotkeyOverlapOnceAndKeepsTheNotice() async throws {
        let store = try isolatedStore()
        let warning = "notype 앱도 ⌥Space 단축키를 사용합니다. 이 단축키를 누르면 두 앱이 함께 녹음을 시작합니다. notype을 종료해 주세요."
        var runtime = offlineRuntime()
        runtime.capture = { [target = syntheticTarget] _ in target }
        runtime.startRecording = { _ in }
        runtime.hotkeyConflictWarnings = { _ in [warning] }
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: runtime, client: http.client, startServices: false, preferences: Preferences())
        defer { model.cancel() }
        XCTAssertTrue(model.hotkeyConflicts.isEmpty, "startServices: false never scans other apps")

        await model.toggle(.dictation)
        XCTAssertTrue(model.phase == .recording)
        XCTAssertEqual(model.hotkeyConflicts, [warning])
        XCTAssertEqual(model.notice, warning)
        XCTAssertEqual(model.transientMessage, "notype 앱도 ⌥Space 단축키를 사용합니다. 설정 › 입력·단축키를 확인해 주세요.")

        model.cancel(); model.transientMessage = nil
        await model.toggle(.dictation)
        XCTAssertTrue(model.phase == .recording)
        XCTAssertEqual(model.notice, warning, "the main window keeps explaining the overlap")
        XCTAssertNil(model.transientMessage, "each overlap is flashed once per session")
        XCTAssertEqual(http.requests.count, 0)
    }

    func testRecordingStartWithoutOverlapLeavesNoticeAndBarUntouched() async throws {
        let store = try isolatedStore()
        var runtime = offlineRuntime()
        runtime.capture = { [target = syntheticTarget] _ in target }
        runtime.startRecording = { _ in }
        runtime.hotkeyConflictWarnings = { _ in [] }
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: runtime, client: http.client, startServices: false, preferences: Preferences())
        defer { model.cancel() }
        await model.toggle(.dictation)
        XCTAssertTrue(model.phase == .recording)
        XCTAssertNil(model.notice)
        XCTAssertNil(model.transientMessage)
        XCTAssertTrue(model.hotkeyConflicts.isEmpty)
    }

    func testSuspendedCaptureOwnsStartBeforeASecondShortcutArrives() async throws {
        let store = try isolatedStore()
        let gate = CaptureGate(entered: expectation(description: "First capture suspended"))
        var starts = 0
        var runtime = offlineRuntime()
        runtime.capture = { _ in await gate.capture() }
        runtime.startRecording = { _ in starts += 1 }
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: runtime, client: http.client, startServices: false, preferences: Preferences())
        defer { model.cancel() }

        let first = Task { await model.toggle(.dictation) }
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertTrue(model.phase == .starting)
        let secondReturned = expectation(description: "Second shortcut is rejected while starting")
        let second = Task { await model.toggle(.translation); secondReturned.fulfill() }
        await fulfillment(of: [secondReturned], timeout: 3)
        XCTAssertEqual(gate.count, 1)
        XCTAssertEqual(starts, 0)
        gate.release(syntheticTarget)
        await first.value; await second.value

        XCTAssertEqual(starts, 1)
        XCTAssertTrue(model.phase == .recording)
        XCTAssertEqual(model.mode, .dictation)
        XCTAssertEqual(http.requests.count, 0)
    }

    func testCancelledStartIgnoresCaptureThatReturnsLater() async throws {
        let gate = CaptureGate(entered: expectation(description: "Capture suspended"))
        var starts = 0
        var runtime = offlineRuntime()
        runtime.capture = { _ in await gate.capture() }
        runtime.startRecording = { _ in starts += 1 }
        let http = FlowHTTP()
        let model = AppModel(store: try isolatedStore(), runtime: runtime, client: http.client,
                             startServices: false, preferences: Preferences())
        let starting = Task { await model.toggle(.dictation) }
        await fulfillment(of: [gate.entered], timeout: 3)
        model.cancel()
        gate.release(syntheticTarget)
        await starting.value

        XCTAssertEqual(starts, 0)
        XCTAssertTrue(model.phase == .idle)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(http.requests.count, 0)
    }

    func testPreferencesChangedDuringCaptureDoNotChangeTheStartedRecordingSnapshot() async throws {
        let store = try isolatedStore()
        let gate = CaptureGate(entered: expectation(description: "Capture suspended before preferences change"))
        var starts = 0
        var runtime = offlineRuntime()
        let audioURL = try runtime.makeTemporaryAudioURL()
        try Data([82, 73, 70, 70, 1, 2, 3]).write(to: audioURL)
        var capturedAllowance: Set<String> = []
        runtime.capture = { allowed in capturedAllowance = allowed; return await gate.capture() }
        runtime.startRecording = { _ in starts += 1 }
        runtime.stopRecording = { audioURL }
        runtime.recordingPeakDB = { -20 }
        var preferences = Preferences()
        preferences.provider = .openRouter
        preferences.transcriptionModels[AIProvider.openRouter.rawValue] = "test/start-stt"
        preferences.textModels[AIProvider.openRouter.rawValue] = "test/start-text"
        preferences.targetLanguage = "English (United States)"
        preferences.allowedContextApps = ["test.editor"]
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: runtime, client: http.client, startServices: false, preferences: preferences)
        defer { model.cancel() }
        model.dictionary = [.init(spoken: "시작 단어", written: "BeforeCapture")]
        // Prevent a regression from touching model caches: the altered filter would fail for its
        // missing profile before inference, while the original cloud snapshot needs neither model.
        model.localState = .ready; model.speakerState = .ready; model.hasSpeakerProfile = false
        let starting = Task { await model.toggle(.translation) }
        await fulfillment(of: [gate.entered], timeout: 3)
        model.preferences.provider = .anthropic
        model.preferences.transcriptionModels[AIProvider.openRouter.rawValue] = "test/changed-stt"
        model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/changed-text"
        model.preferences.targetLanguage = "Korean"
        model.preferences.useLocalTranscription = true
        model.preferences.speakerFilterEnabled = true
        model.preferences.allowedContextApps = []
        model.dictionary = [.init(spoken: "나중 단어", written: "AfterCapture")]
        // The own-process sentinel is rejected before TextInsertion performs any AX/clipboard work.
        gate.release(InputTarget(pid: ProcessInfo.processInfo.processIdentifier, bundleID: "test.editor", element: nil,
                                 originalValue: nil, range: nil, selectedText: nil, context: nil))
        await starting.value
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(model.phase == .recording)
        XCTAssertEqual(capturedAllowance, ["test.editor"])

        let finished = expectation(description: "Original snapshot reaches the provider and storage")
        var delivered = false
        model.onPhaseChange = { [weak model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        model.elapsed = 1
        model.stop()
        await fulfillment(of: [finished], timeout: 5)
        model.onPhaseChange = nil

        XCTAssertEqual(model.result, "합성 결과")
        XCTAssertEqual(http.requests.map(\.model), ["test/start-stt", "test/start-text"])
        let textRequest = try XCTUnwrap(http.requests.last)
        let body = String(decoding: textRequest.body, as: UTF8.self)
        XCTAssertTrue(body.contains("BeforeCapture"))
        XCTAssertFalse(body.contains("AfterCapture"))
        XCTAssertTrue(body.contains("English (United States)"))
        let history = try await store.history()
        XCTAssertEqual(history.last?.provider, .openRouter)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testCancellingArmedInputTestDuringCaptureCannotReviveProcessing() async throws {
        let gate = CaptureGate(entered: expectation(description: "Input test capture suspended"))
        var starts = 0
        var runtime = offlineRuntime()
        runtime.capture = { _ in await gate.capture() }
        runtime.startRecording = { _ in starts += 1 }
        let http = FlowHTTP()
        let model = AppModel(store: try isolatedStore(), runtime: runtime, client: http.client,
                             startServices: false, preferences: Preferences())
        model.armInputTest()
        let testing = Task { await model.toggle(.dictation) }
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertTrue(model.phase == .starting)
        XCTAssertFalse(model.inputTestArmed)
        model.cancel()
        gate.release(syntheticTarget)
        await testing.value

        XCTAssertTrue(model.phase == .idle)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(model.inputDiagnostics, "", "A cancelled capture must stop before any live AX diagnostics or paste")
        XCTAssertEqual(http.requests.count, 0)
    }

    func testRetryUsesRecordedModelsOrExplicitlySelectedCurrentModels() async throws {
        for useCurrentSettings in [false, true] {
            let store = try isolatedStore()
            let failure = FailedRecording(mode: .dictation, provider: .openRouter, targetLanguage: "English (United States)",
                                          transcriptionModel: "test/recorded-stt", textModel: "test/recorded-text",
                                          usedLocalTranscription: false, usedSpeakerFilter: false)
            try await store.saveFailure(failure, audio: Data([82, 73, 70, 70, 1, 2, 3]))
            var preferences = Preferences()
            preferences.provider = .openRouter
            preferences.transcriptionModels[AIProvider.openRouter.rawValue] = "test/current-stt"
            preferences.textModels[AIProvider.openRouter.rawValue] = "test/current-text"
            let http = FlowHTTP()
            let model = AppModel(store: store, runtime: offlineRuntime(), client: http.client,
                                 startServices: false, preferences: preferences)
            await retryAndWait(model, failure: failure, useCurrentSettings: useCurrentSettings)

            XCTAssertNil(model.error)
            XCTAssertEqual(model.result, "합성 결과")
            let requests = http.requests
            XCTAssertEqual(requests.map(\.model), useCurrentSettings
                           ? ["test/current-stt", "test/current-text"]
                           : ["test/recorded-stt", "test/recorded-text"])
            XCTAssertEqual(requests.map(\.path), ["/api/v1/audio/transcriptions", "/api/v1/chat/completions"])
            let remaining = try await store.failures()
            XCTAssertFalse(remaining.contains { $0.id == failure.id })
        }
    }

    func testCurrentSettingsCanRecoverAnOldSpeakerFilterFailureWithoutTheFilter() async throws {
        let store = try isolatedStore()
        let failure = FailedRecording(mode: .dictation, provider: .openRouter, targetLanguage: "English (United States)",
                                      transcriptionModel: "test/recorded-stt", textModel: "test/recorded-text",
                                      usedLocalTranscription: false, usedSpeakerFilter: true)
        try await store.saveFailure(failure, audio: Data([82, 73, 70, 70, 1, 2, 3]))
        var preferences = Preferences()
        preferences.provider = .openRouter
        preferences.speakerFilterEnabled = false
        preferences.useLocalTranscription = false
        preferences.transcriptionModels[AIProvider.openRouter.rawValue] = "test/current-stt"
        preferences.textModels[AIProvider.openRouter.rawValue] = "test/current-text"
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: offlineRuntime(), client: http.client,
                             startServices: false, preferences: preferences)
        // A missing profile is sufficient to reject the old filter path. This state avoids loading
        // a real model or inspecting the user's model cache during the regression test.
        model.speakerState = .ready
        model.hasSpeakerProfile = false

        await retryAndWait(model, failure: failure, useCurrentSettings: false)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(http.requests.count, 0, "The recorded filter setting requires a prepared speaker profile")
        let retained = try await store.failures()
        XCTAssertTrue(retained.contains { $0.id == failure.id })

        await retryAndWait(model, failure: failure, useCurrentSettings: true)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.result, "합성 결과")
        XCTAssertEqual(http.requests.map(\.model), ["test/current-stt", "test/current-text"])
        let recovered = try await store.failures()
        XCTAssertFalse(recovered.contains { $0.id == failure.id })
    }

    func testClearedCurrentModelFieldsUseTheSameDefaultsShownInSettings() async throws {
        let store = try isolatedStore()
        let failure = FailedRecording(mode: .dictation, provider: .openRouter, targetLanguage: "English (United States)",
                                      transcriptionModel: "test/recorded-stt", textModel: "test/recorded-text",
                                      usedLocalTranscription: false, usedSpeakerFilter: false)
        try await store.saveFailure(failure, audio: Data([82, 73, 70, 70, 1, 2, 3]))
        var preferences = Preferences()
        preferences.provider = .openRouter
        preferences.transcriptionModels[AIProvider.openRouter.rawValue] = ""
        preferences.textModels[AIProvider.openRouter.rawValue] = " \t\n "
        let defaults = ProviderDefaults.forProvider(.openRouter)
        XCTAssertEqual(preferences.transcriptionModel, defaults.transcriptionModel)
        XCTAssertEqual(preferences.textModel, defaults.textModel)
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: offlineRuntime(), client: http.client,
                             startServices: false, preferences: preferences)

        await retryAndWait(model, failure: failure, useCurrentSettings: true)

        XCTAssertNil(model.error)
        XCTAssertEqual(model.result, "합성 결과")
        XCTAssertEqual(http.requests.map(\.model), [defaults.transcriptionModel, defaults.textModel],
                       "The configuration sent to the provider must match the defaults shown after clearing custom IDs")
        let remaining = try await store.failures()
        XCTAssertFalse(remaining.contains { $0.id == failure.id })
    }

    func testUndoLearningRestoresThePreviousSpellingThroughTheAppFlow() async throws {
        let store = try isolatedStore()
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: offlineRuntime(), client: http.client,
                             startServices: false, preferences: Preferences())
        let saved = await model.saveDictionaryEntry(spoken: "오픈", written: "BeforeLearning")
        XCTAssertTrue(saved)
        let previous = try XCTUnwrap(model.dictionary.first)
        let learned = DictionaryEntry(spoken: "오픈", written: "AfterLearning", learned: true)
        let applied = await model.applyLearnedEntry(learned)
        XCTAssertTrue(applied)
        XCTAssertTrue(model.canUndoLastLearning)
        XCTAssertEqual(model.dictionary.map(\.written), ["AfterLearning"])

        await model.undoLastLearning()
        XCTAssertEqual(model.dictionary, [previous])
        XCTAssertFalse(model.canUndoLastLearning)
        let stored = try await store.dictionary()
        XCTAssertEqual(stored, [previous])
        XCTAssertEqual(http.requests.count, 0)
    }

    func testUndoLearningPreservesALaterManualEdit() async throws {
        let store = try isolatedStore()
        let http = FlowHTTP()
        let model = AppModel(store: store, runtime: offlineRuntime(), client: http.client,
                             startServices: false, preferences: Preferences())
        let applied = await model.applyLearnedEntry(.init(spoken: "오픈", written: "Learned", learned: true))
        XCTAssertTrue(applied)
        let learned = try XCTUnwrap(model.dictionary.first)
        let edited = await model.updateDictionaryEntry(learned, spoken: "오픈", written: "ManuallyChosen")
        XCTAssertTrue(edited)
        await model.undoLastLearning()

        XCTAssertEqual(model.dictionary.map(\.written), ["ManuallyChosen"])
        XCTAssertFalse(model.canUndoLastLearning)
        let stored = try await store.dictionary()
        XCTAssertEqual(stored.map(\.written), ["ManuallyChosen"])
        XCTAssertEqual(http.requests.count, 0)
    }

    private func retryAndWait(_ model: AppModel, failure: FailedRecording, useCurrentSettings: Bool) async {
        let finished = expectation(description: "Retry returns to idle")
        var delivered = false
        model.onPhaseChange = { [weak model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        model.retry(failure, useCurrentSettings: useCurrentSettings)
        await fulfillment(of: [finished], timeout: 5)
        model.onPhaseChange = nil
        if model.isBusy { model.cancel() }
    }
}

private final class FlowMemorySecrets: SecretBackend, @unchecked Sendable {
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

private struct FlowRequest {
    let path: String
    let model: String
    let body: Data
}

private final class FlowHTTP: @unchecked Sendable {
    let id = UUID().uuidString
    let session: URLSession
    let client: ProviderClient
    var requests: [FlowRequest] { FlowURLProtocol.requests(for: id) }

    init() {
        FlowURLProtocol.register(id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlowURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-OpenNoType-AppFlow": id]
        session = URLSession(configuration: configuration)
        client = ProviderClient(session: session)
    }
    deinit { session.invalidateAndCancel(); FlowURLProtocol.remove(id) }
}

/// Every request is intercepted, including unexpected URLs. Nothing can fall through to HTTP.
private final class FlowURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var logs: [String: [FlowRequest]] = [:]
    static func register(_ id: String) { lock.lock(); defer { lock.unlock() }; logs[id] = [] }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; logs[id] = nil }
    static func requests(for id: String) -> [FlowRequest] { lock.lock(); defer { lock.unlock() }; return logs[id] ?? [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let id = request.value(forHTTPHeaderField: "X-OpenNoType-AppFlow") ?? ""
            let body = try Self.body(request)
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let model = object["model"] as? String, let url = request.url else { throw URLError(.badServerResponse) }
            Self.lock.lock()
            let registered = Self.logs[id] != nil
            if registered { Self.logs[id]?.append(.init(path: url.path, model: model, body: body)) }
            Self.lock.unlock()
            guard registered else { throw URLError(.unsupportedURL) }
            let response: [String: Any]
            switch url.path {
            case "/api/v1/audio/transcriptions": response = ["text": "합성 전사문"]
            case "/api/v1/chat/completions":
                response = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": "{\"text\":\"합성 결과\"}"]]]]
            default: throw URLError(.unsupportedURL)
            }
            let data = try JSONSerialization.data(withJSONObject: response)
            let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    private static func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open(); defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { return data }
            data.append(bytes, count: count)
        }
    }
}
