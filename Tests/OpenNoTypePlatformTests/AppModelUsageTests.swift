import AppKit
import AVFoundation
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class AppModelUsageTests: XCTestCase {
    func testDisabledTextHistoryStillPersistsBothUsageStagesThroughRecovery() async throws {
        let fixture = try makeFixture()
        let failure = try await addFailure(to: fixture.store)
        var preferences = cloudPreferences()
        preferences.historyEnabled = false
        let http = UsageAppHTTP()
        let model = makeModel(fixture, preferences: preferences, http: http)
        await retryAndWait(model, failure: failure)

        XCTAssertNil(model.error)
        XCTAssertEqual(model.result, UsageAppHTTP.resultText)
        let history = try await fixture.store.history()
        XCTAssertTrue(history.isEmpty)
        let records = try await fixture.store.usageRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.event.stage)), [.transcription, .textProcessing])
        XCTAssertTrue(records.allSatisfy(\.isRecovery))
        XCTAssertEqual(Set(records.map(\.jobID)).count, 1)
        XCTAssertEqual(records.first { $0.event.stage == .transcription }?.event.audioSeconds, 1)
        XCTAssertEqual(model.usageRecords.count, 2)
        XCTAssertNil(model.usageStorageError)
    }

    func testDisabledUsageTrackingDoesNotPreventRecoveryOrStoreAccounting() async throws {
        let fixture = try makeFixture()
        let failure = try await addFailure(to: fixture.store)
        var preferences = cloudPreferences()
        preferences.usageTrackingEnabled = false
        let http = UsageAppHTTP()
        let model = makeModel(fixture, preferences: preferences, http: http)
        await retryAndWait(model, failure: failure)

        XCTAssertNil(model.error)
        XCTAssertEqual(model.result, UsageAppHTTP.resultText)
        XCTAssertEqual(http.requests.count, 2)
        let records = try await fixture.store.usageRecords()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(model.usageRecords.isEmpty)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.count, 1)
        let failures = try await fixture.store.failures()
        XCTAssertTrue(failures.isEmpty)
    }

    func testSuccessfulTranscriptionRemainsAccountedWhenTextProcessingFails() async throws {
        let fixture = try makeFixture()
        let failure = try await addFailure(to: fixture.store)
        let http = UsageAppHTTP { request, _ in
            if request.path.hasSuffix("/chat/completions") {
                return .json(["error": ["message": "synthetic provider failure"]], status: 500)
            }
            return UsageAppHTTP.success(for: request)
        }
        let model = makeModel(fixture, preferences: cloudPreferences(), http: http)
        await retryAndWait(model, failure: failure)

        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.result, "")
        let records = try await fixture.store.usageRecords()
        XCTAssertEqual(records.count, 2)
        let transcription = try XCTUnwrap(records.first { $0.event.stage == .transcription })
        XCTAssertEqual(transcription.event.outcome, .responseReceived)
        XCTAssertEqual(transcription.cost.kind, .providerReported)
        XCTAssertEqual(transcription.cost.usd, 0.000075)
        let processing = try XCTUnwrap(records.first { $0.event.stage == .textProcessing })
        XCTAssertEqual(processing.event.outcome, .failed)
        XCTAssertEqual(processing.event.httpStatus, 500)
        XCTAssertEqual(processing.cost.kind, .unavailable)
        XCTAssertNil(processing.cost.usd)
        let failures = try await fixture.store.failures()
        XCTAssertEqual(failures.map(\.id), [failure.id])
        let history = try await fixture.store.history()
        XCTAssertTrue(history.isEmpty)
    }

    func testReportedModelsAndCostsSurviveEncryptedStorageAndANewAppModel() async throws {
        let fixture = try makeFixture()
        let failure = try await addFailure(to: fixture.store)
        var preferences = cloudPreferences()
        preferences.historyEnabled = false
        let http = UsageAppHTTP()
        let model = makeModel(fixture, preferences: preferences, http: http)
        await retryAndWait(model, failure: failure)
        let saved = try await fixture.store.usageRecords()
        XCTAssertEqual(saved.count, 2)
        let text = try XCTUnwrap(saved.first { $0.event.stage == .textProcessing })
        XCTAssertEqual(text.event.model, "test/requested-text")
        XCTAssertEqual(text.event.reportedModel, "test/resolved-text")
        XCTAssertEqual(text.event.inputTokens, 40)
        XCTAssertEqual(text.event.outputTokens, 15)
        XCTAssertEqual(text.cost.kind, .providerReported)
        XCTAssertEqual(try XCTUnwrap(text.cost.usd), 0.00015, accuracy: 1e-12)
        let encoded = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        XCTAssertFalse(encoded.contains(UsageAppHTTP.transcriptText))
        XCTAssertFalse(encoded.contains(UsageAppHTTP.resultText))
        XCTAssertFalse(encoded.contains("synthetic-usage-app-key"))
        let encrypted = try Data(contentsOf: fixture.directory.appendingPathComponent("vault-v1.enc"))
        XCTAssertNil(encrypted.range(of: Data("test/resolved-text".utf8)))
        XCTAssertNil(encrypted.range(of: Data("inputTokens".utf8)))

        let reopenedStore = try SecureStore(directory: fixture.directory, backend: fixture.backend)
        let reopenedModel = AppModel(store: reopenedStore, runtime: offlineRuntime(root: fixture.root),
                                     client: http.client, startServices: false, preferences: preferences)
        await reopenedModel.refreshData()
        XCTAssertEqual(reopenedModel.usageRecords, saved)
        XCTAssertNotNil(reopenedModel.usageTrackingStartedAt)
        XCTAssertNil(reopenedModel.usageStorageError)
        XCTAssertEqual(http.requests.count, 2, "Opening usage history must not make provider requests")
    }

    func testProviderRetryAttemptsPersistIndividuallyInsideOneAppJob() async throws {
        let fixture = try makeFixture()
        let failure = try await addFailure(to: fixture.store)
        let http = UsageAppHTTP { request, sequence in
            if sequence == 1 {
                return .json(["error": ["message": "temporary"]], status: 503, headers: ["Retry-After": "0"])
            }
            return UsageAppHTTP.success(for: request)
        }
        let model = makeModel(fixture, preferences: cloudPreferences(), http: http)
        await retryAndWait(model, failure: failure)

        XCTAssertNil(model.error)
        XCTAssertEqual(http.requests.count, 3)
        let records = try await fixture.store.usageRecords()
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(Set(records.map(\.jobID)).count, 1)
        let transcriptions = records.filter { $0.event.stage == .transcription }.sorted { $0.event.attempt < $1.event.attempt }
        XCTAssertEqual(transcriptions.map(\.event.attempt), [1, 2])
        XCTAssertEqual(transcriptions.map(\.event.outcome), [.failed, .responseReceived])
        XCTAssertEqual(transcriptions.map(\.event.httpStatus), [503, 200])
        XCTAssertEqual(transcriptions.map(\.cost.kind), [.unavailable, .providerReported])
        XCTAssertEqual(records.filter { $0.event.stage == .textProcessing }.map(\.event.attempt), [1])
    }

    func testPaidResponseWithMalformedOutputIsNotLostWhenAppRejectsResult() async throws {
        let fixture = try makeFixture()
        let failure = try await addFailure(to: fixture.store)
        let http = UsageAppHTTP { request, _ in
            if request.path.hasSuffix("/chat/completions") {
                return .json(["model": "test/resolved-text", "usage": ["prompt_tokens": 40, "completion_tokens": 15, "cost": 0.00015],
                              "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": "invalid structured output"]]]])
            }
            return UsageAppHTTP.success(for: request)
        }
        let model = makeModel(fixture, preferences: cloudPreferences(), http: http)
        await retryAndWait(model, failure: failure)

        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.result, "")
        let records = try await fixture.store.usageRecords()
        XCTAssertEqual(records.count, 2)
        let text = try XCTUnwrap(records.first { $0.event.stage == .textProcessing })
        XCTAssertEqual(text.event.outcome, .responseReceived)
        XCTAssertEqual(text.event.reportedModel, "test/resolved-text")
        XCTAssertEqual(text.cost.kind, .providerReported)
        XCTAssertEqual(try XCTUnwrap(text.cost.usd), 0.00015, accuracy: 1e-12)
        let failures = try await fixture.store.failures()
        XCTAssertEqual(failures.map(\.id), [failure.id])
    }

    func testOneFailedUsageCommitKeepsAnIncompleteWarningAcrossLaterSuccessAndRelaunch() async throws {
        let fault = UsageAppCommitFault()
        let fixture = try makeFixture(beforeVaultCommit: { try fault.failIfArmed() })
        let failure = try await addFailure(to: fixture.store)
        let http = UsageAppHTTP { request, _ in
            if request.path.hasSuffix("/audio/transcriptions") { fault.arm() }
            return UsageAppHTTP.success(for: request)
        }
        let model = makeModel(fixture, preferences: cloudPreferences(), http: http)
        await retryAndWait(model, failure: failure)

        XCTAssertEqual(fault.failureCount, 1, "Only the first accounting commit is rejected")
        XCTAssertNil(model.error, "An accounting write failure must not discard the completed result")
        XCTAssertEqual(model.result, UsageAppHTTP.resultText)
        let records = try await fixture.store.usageRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.event.stage, .textProcessing, "The later usage commit still succeeds")
        let history = try await fixture.store.history()
        XCTAssertEqual(history.count, 1)
        let failures = try await fixture.store.failures()
        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(model.preferences.usageAccountingIncomplete)
        XCTAssertNotNil(model.usageStorageError, "A later successful write must not erase the missing-accounting warning")

        // Round-trip the same persisted preferences schema without touching the user's defaults.
        let restoredPreferences = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(model.preferences))
        let reopenedStore = try SecureStore(directory: fixture.directory, backend: fixture.backend)
        let reopenedModel = AppModel(store: reopenedStore, runtime: offlineRuntime(root: fixture.root),
                                     client: http.client, startServices: false, preferences: restoredPreferences)
        await reopenedModel.refreshData()
        XCTAssertTrue(reopenedModel.preferences.usageAccountingIncomplete)
        XCTAssertNotNil(reopenedModel.usageStorageError)
        XCTAssertEqual(reopenedModel.usageRecords, records)
        await reopenedModel.clearUsage()
        XCTAssertFalse(reopenedModel.preferences.usageAccountingIncomplete)
        XCTAssertNil(reopenedModel.usageStorageError)
        XCTAssertTrue(reopenedModel.usageRecords.isEmpty)
        let remainingHistory = try await reopenedStore.history()
        XCTAssertEqual(remainingHistory.map(\.id), history.map(\.id), "Clearing accounting must preserve text history")
    }

    func testDisablingTrackingBeforeTheNextResponseKeepsSavedUsageAndDropsLaterAccounting() async throws {
        let fixture = try makeFixture()
        let failure = try await addFailure(to: fixture.store)
        let waitingForTextResponse = expectation(description: "Text request waits before its HTTP response")
        let gate = UsageAppResponseGate()
        let http = UsageAppHTTP { request, _ in
            var response = UsageAppHTTP.success(for: request)
            if request.path.hasSuffix("/chat/completions") {
                response.gate = gate
                waitingForTextResponse.fulfill()
            }
            return response
        }
        let model = makeModel(fixture, preferences: cloudPreferences(), http: http)
        let finished = expectation(description: "Recovery completes with accounting disabled during its request")
        var delivered = false
        model.onPhaseChange = { [weak model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        defer { gate.release(); model.onPhaseChange = nil; model.cancel() }
        model.retry(failure)
        await fulfillment(of: [waitingForTextResponse], timeout: 6)
        let before = try await fixture.store.usageRecords()
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(before.first?.event.stage, .transcription)
        model.preferences.usageTrackingEnabled = false
        gate.release()
        await fulfillment(of: [finished], timeout: 6)

        XCTAssertNil(model.error)
        XCTAssertEqual(model.result, UsageAppHTTP.resultText)
        XCTAssertEqual(http.requests.count, 2)
        let after = try await fixture.store.usageRecords()
        XCTAssertEqual(after, before, "Disabling collection preserves accepted records and skips the later callback")
        XCTAssertEqual(model.usageRecords, before)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.count, 1, "Accounting settings must not cancel the user's processing request")
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let backend: UsageAppMemorySecrets
        let store: SecureStore
    }
    private func makeFixture(beforeVaultCommit: (@Sendable () throws -> Void)? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-AppUsage-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("vault", isDirectory: true)
        let backend = UsageAppMemorySecrets()
        let store = try SecureStore(directory: directory, backend: backend, beforeVaultCommit: beforeVaultCommit)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(root: root, directory: directory, backend: backend, store: store)
    }
    private func offlineRuntime(root: URL) -> AppRuntime {
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }
        runtime.capture = { _ in XCTFail("Recovery must not capture or modify another app"); return nil }
        runtime.accessibilityPermitted = { true }
        runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("No microphone permission request"); return false }
        runtime.readKey = { _ in "synthetic-usage-app-key" }
        runtime.startRecording = { _ in XCTFail("No microphone recording") }
        let audioSession = TemporaryAudioSession(rootDirectory: root.appendingPathComponent("temporary-audio", isDirectory: true))
        runtime.makeTemporaryAudioURL = { try audioSession.makeURL() }
        return runtime
    }
    private func cloudPreferences() -> Preferences {
        var preferences = Preferences()
        preferences.provider = .openRouter
        preferences.useLocalTranscription = false
        preferences.speakerFilterEnabled = false
        preferences.usageTrackingEnabled = true
        preferences.transcriptionModels[AIProvider.openRouter.rawValue] = "test/requested-stt"
        preferences.textModels[AIProvider.openRouter.rawValue] = "test/requested-text"
        return preferences
    }
    private func makeModel(_ fixture: Fixture, preferences: Preferences, http: UsageAppHTTP) -> AppModel {
        AppModel(store: fixture.store, runtime: offlineRuntime(root: fixture.root), client: http.client,
                 startServices: false, preferences: preferences)
    }
    private func addFailure(to store: SecureStore) async throws -> FailedRecording {
        let failure = FailedRecording(mode: .dictation, provider: .openRouter, targetLanguage: "English (United States)",
                                      transcriptionModel: "test/requested-stt", textModel: "test/requested-text",
                                      usedLocalTranscription: false, usedSpeakerFilter: false)
        try await store.saveFailure(failure, audio: Self.syntheticWAV())
        return failure
    }
    private func retryAndWait(_ model: AppModel, failure: FailedRecording) async {
        let finished = expectation(description: "Recovery returns to idle after accounting")
        var delivered = false
        model.onPhaseChange = { [weak model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        model.retry(failure)
        await fulfillment(of: [finished], timeout: 6)
        model.onPhaseChange = nil
        if model.isBusy { model.cancel() }
    }
    private static func syntheticWAV() -> Data {
        // One second of 16 kHz mono PCM; no microphone or model cache is involved.
        let bytes: UInt32 = 32_000
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(bytes + 36); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(16_000))
        append(UInt32(32_000)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(bytes); data.append(Data(repeating: 0, count: Int(bytes)))
        return data
    }
}

private final class UsageAppMemorySecrets: SecretBackend, @unchecked Sendable {
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
private struct UsageAppRequest {
    let path: String
    let model: String
}
private struct UsageAppResponse {
    var status = 200
    var headers: [String: String] = [:]
    let object: [String: Any]
    var gate: UsageAppResponseGate? = nil
    static func json(_ object: [String: Any], status: Int = 200, headers: [String: String] = [:]) -> Self {
        .init(status: status, headers: headers, object: object)
    }
}
private final class UsageAppHTTP: @unchecked Sendable {
    static let transcriptText = "합성 음성 사용량 테스트 전사문"
    static let resultText = "합성 음성 사용량 테스트 결과"
    let id = UUID().uuidString
    let session: URLSession
    let client: ProviderClient
    var requests: [UsageAppRequest] { UsageAppURLProtocol.requests(for: id) }
    init(handler: @escaping (UsageAppRequest, Int) -> UsageAppResponse = { request, _ in UsageAppHTTP.success(for: request) }) {
        UsageAppURLProtocol.register(id, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageAppURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-OpenNoType-AppUsage": id]
        session = URLSession(configuration: configuration)
        client = ProviderClient(session: session)
    }
    deinit { session.invalidateAndCancel(); UsageAppURLProtocol.remove(id) }
    static func success(for request: UsageAppRequest) -> UsageAppResponse {
        if request.path.hasSuffix("/audio/transcriptions") {
            return .json(["text": transcriptText, "model": "test/resolved-stt", "usage": ["type": "duration", "seconds": 1, "cost": 0.000075]])
        }
        return .json(["model": "test/resolved-text", "usage": ["prompt_tokens": 40, "completion_tokens": 15, "cost": 0.00015],
                      "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": "{\"text\":\"\(resultText)\"}"]]]])
    }
}
/// Intercepts every URL, including unsupported endpoints; requests can never reach a live provider.
private final class UsageAppURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var logs: [String: [UsageAppRequest]] = [:]
    private static var handlers: [String: (UsageAppRequest, Int) -> UsageAppResponse] = [:]
    static func register(_ id: String, handler: @escaping (UsageAppRequest, Int) -> UsageAppResponse) {
        lock.lock(); defer { lock.unlock() }; logs[id] = []; handlers[id] = handler
    }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; logs[id] = nil; handlers[id] = nil }
    static func requests(for id: String) -> [UsageAppRequest] { lock.lock(); defer { lock.unlock() }; return logs[id] ?? [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let id = request.value(forHTTPHeaderField: "X-OpenNoType-AppUsage") ?? ""
            let body = try Self.body(request)
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let model = object["model"] as? String, let url = request.url,
                  ["/api/v1/audio/transcriptions", "/api/v1/chat/completions"].contains(url.path) else {
                throw URLError(.badServerResponse)
            }
            let received = UsageAppRequest(path: url.path, model: model)
            Self.lock.lock()
            let handler = Self.handlers[id]
            if handler != nil { Self.logs[id]?.append(received) }
            let count = Self.logs[id]?.count ?? 0
            Self.lock.unlock()
            guard let handler else { throw URLError(.unsupportedURL) }
            let stub = handler(received, count)
            let data = try JSONSerialization.data(withJSONObject: stub.object)
            let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            let deliver = { [self] in
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            if let gate = stub.gate { gate.whenReleased(deliver) } else { deliver() }
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

private final class UsageAppCommitFault: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private var failures = 0
    var failureCount: Int { lock.lock(); defer { lock.unlock() }; return failures }
    func arm() { lock.lock(); defer { lock.unlock() }; armed = true }
    func failIfArmed() throws {
        lock.lock(); defer { lock.unlock() }
        guard armed else { return }
        armed = false; failures += 1
        throw SecureStoreError.fileSystem(28)
    }
}
private final class UsageAppResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var pending: (() -> Void)?
    func whenReleased(_ action: @escaping () -> Void) {
        lock.lock()
        if released { lock.unlock(); action() }
        else { pending = action; lock.unlock() }
    }
    func release() {
        lock.lock()
        released = true
        let action = pending
        pending = nil
        lock.unlock()
        action?()
    }
}
