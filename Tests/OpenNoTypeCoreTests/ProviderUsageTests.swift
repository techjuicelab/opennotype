import XCTest
@testable import OpenNoTypeCore

final class ProviderUsageTests: XCTestCase {
    func testResponsesUsageSurvivesMalformedGeneratedResult() async throws {
        let ledger = UsageLedger()
        let harness = UsageHarness { _, _ in
            .json(["model": "gpt-5-mini-2025-08-07", "status": "completed", "output": [
                ["type": "message", "role": "assistant", "status": "completed", "content": [
                    ["type": "output_text", "text": "not the required JSON result"]]]],
                "usage": ["input_tokens": 500, "output_tokens": 90,
                    "input_tokens_details": ["cached_tokens": 300, "cache_write_tokens": 25],
                    "output_tokens_details": ["reasoning_tokens": 70]]])
        }
        do {
            _ = try await harness.client.process(request, configuration: config(.openAI), onUsage: { await ledger.append($0) })
            XCTFail("Invalid generated JSON must still fail")
        } catch { XCTAssertEqual(error as? ProviderError, .invalidResponse) }
        let entries = await ledger.entries
        XCTAssertEqual(entries.count, 1)
        let usage = try XCTUnwrap(entries.first)
        XCTAssertEqual(usage.model, "requested-model")
        XCTAssertEqual(usage.reportedModel, "gpt-5-mini-2025-08-07")
        XCTAssertEqual(usage.outcome, .responseReceived)
        XCTAssertEqual(usage.stage, .textProcessing)
        XCTAssertEqual(usage.httpStatus, 200)
        XCTAssertEqual(usage.inputTokens, 500)
        XCTAssertEqual(usage.cachedInputTokens, 300)
        XCTAssertEqual(usage.cacheWriteTokens, 25)
        XCTAssertEqual(usage.outputTokens, 90)
        XCTAssertEqual(usage.reasoningTokens, 70)
    }

    func testHTTPResultWithInvalidBodyStillReportsAnAttemptWithoutInventingUsage() async throws {
        for body in [Data("not-json".utf8), Data("{\"usage\":null}".utf8)] {
            let ledger = UsageLedger()
            let harness = UsageHarness { _, _ in .init(data: body) }
            do {
                _ = try await harness.client.process(request, configuration: config(.openAI), onUsage: { await ledger.append($0) })
                XCTFail("Expected invalid response")
            } catch { XCTAssertTrue(error is ProviderError) }
            let entries = await ledger.entries
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first?.outcome, .responseReceived)
            XCTAssertNil(entries.first?.inputTokens)
            XCTAssertNil(entries.first?.outputTokens)
            XCTAssertNil(entries.first?.providerCostUSD, "Missing usage is not a zero-dollar charge")
        }
    }

    func testRetryReportsEachActualAttemptAndProviderCost() async throws {
        let ledger = UsageLedger()
        let harness = UsageHarness { _, attempt in
            if attempt == 1 {
                return .json(["error": ["message": "temporary"], "usage": ["cost": 0.001]], status: 503,
                             headers: ["Retry-After": "0"])
            }
            return .json(Self.chat(usage: ["prompt_tokens": 120, "completion_tokens": 20, "cost": 0.0025,
                "prompt_tokens_details": ["cached_tokens": 40, "cache_write_tokens": 10, "audio_tokens": 3],
                "completion_tokens_details": ["reasoning_tokens": 7]]))
        }
        let result = try await harness.client.process(request, configuration: config(.openRouter), onUsage: { await ledger.append($0) })
        XCTAssertEqual(result, "완료")
        let entries = await ledger.entries
        XCTAssertEqual(entries.map(\.attempt), [1, 2])
        XCTAssertEqual(entries.map(\.httpStatus), [503, 200])
        XCTAssertEqual(entries.map(\.outcome), [.failed, .responseReceived])
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        XCTAssertEqual(entries[0].providerCostUSD, 0.001)
        XCTAssertEqual(entries[1].providerCostUSD, 0.0025)
        XCTAssertEqual(entries[1].cachedInputTokens, 40)
        XCTAssertEqual(entries[1].cacheWriteTokens, 10)
        XCTAssertEqual(entries[1].audioInputTokens, 3)
        XCTAssertEqual(entries[1].reasoningTokens, 7)
        XCTAssertEqual(harness.count, 2)
    }

    func testTransportFailureReportsUnknownUsageWithoutRetrying() async throws {
        let ledger = UsageLedger()
        let harness = UsageHarness { _, _ in throw URLError(.networkConnectionLost) }
        do {
            _ = try await harness.client.process(request, configuration: config(.groq), onUsage: { await ledger.append($0) })
            XCTFail("Expected transport failure")
        } catch { XCTAssertEqual(error as? ProviderError, .connectionFailed) }
        let entries = await ledger.entries
        XCTAssertEqual(harness.count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .failed)
        XCTAssertNil(entries.first?.httpStatus)
        XCTAssertNil(entries.first?.providerCostUSD)
    }

    func testCancellationInFlightReportsCancelledAttemptBeforeReturning() async throws {
        let started = expectation(description: "Request started")
        let ledger = UsageLedger()
        let harness = UsageHarness { _, _ in started.fulfill(); return .init(data: nil) }
        let task = Task {
            try await harness.client.process(request, configuration: config(.openAI), onUsage: { await ledger.append($0) })
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let entries = await ledger.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .cancelled)
        XCTAssertNil(entries.first?.inputTokens)
        XCTAssertEqual(harness.count, 1)
    }

    func testCancellationDuringAccountingKeepsKnownUsageAndAwaitsUncancelledCallback() async throws {
        let entered = expectation(description: "Accounting entered")
        let gate = UsageGate()
        let ledger = UsageLedger()
        let harness = UsageHarness { _, _ in .json(Self.chat(usage: ["prompt_tokens": 40, "completion_tokens": 6, "cost": 0.02])) }
        let task = Task {
            try await harness.client.process(request, configuration: config(.openRouter), onUsage: {
                let usage = $0
                entered.fulfill()
                await gate.wait()
                XCTAssertFalse(Task.isCancelled, "Accounting must survive the request's cancellation")
                await ledger.append(usage)
            })
        }
        await fulfillment(of: [entered], timeout: 3)
        task.cancel()
        await gate.release()
        do { _ = try await task.value; XCTFail("Expected cancellation after accounting") }
        catch { XCTAssertTrue(error is CancellationError) }
        let entries = await ledger.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .responseReceived)
        XCTAssertEqual(entries.first?.providerCostUSD, 0.02)
        XCTAssertEqual(entries.first?.inputTokens, 40)
    }

    func testCancellationAfterRetriableResponseDoesNotInventASecondAttempt() async throws {
        let entered = expectation(description: "Failed attempt accounted")
        let gate = UsageGate()
        let ledger = UsageLedger()
        let harness = UsageHarness { _, _ in .json([:], status: 429, headers: ["Retry-After": "2"]) }
        let task = Task {
            try await harness.client.process(request, configuration: config(.openAI), onUsage: {
                await ledger.append($0)
                entered.fulfill()
                await gate.wait()
            })
        }
        await fulfillment(of: [entered], timeout: 3)
        task.cancel()
        await gate.release()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let entries = await ledger.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .failed)
        XCTAssertEqual(entries.first?.httpStatus, 429)
        XCTAssertEqual(harness.count, 1)
    }

    func testAudioTokenBreakdownAndServerDuration() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID()).wav")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        for usageObject: [String: Any] in [
            ["type": "tokens", "input_tokens": 230, "output_tokens": 12,
             "input_token_details": ["audio_tokens": 220, "text_tokens": 10]],
            ["type": "duration", "seconds": 12.75]
        ] {
            let ledger = UsageLedger()
            let harness = UsageHarness { _, _ in .json(["text": "음성 인식", "usage": usageObject]) }
            _ = try await harness.client.transcribe(audioURL: url, configuration: config(.openAI), dictionary: [],
                                                    audioSeconds: 12.2, onUsage: { await ledger.append($0) })
            let entries = await ledger.entries
            let usage = try XCTUnwrap(entries.first)
            XCTAssertEqual(usage.stage, .transcription)
            XCTAssertEqual(usage.audioSeconds, usageObject["type"] as? String == "tokens" ? 12.2 : 12.75)
            if usageObject["type"] as? String == "tokens" {
                XCTAssertEqual(usage.inputTokens, 230)
                XCTAssertEqual(usage.audioInputTokens, 220)
                XCTAssertEqual(usage.outputTokens, 12)
            } else {
                XCTAssertNil(usage.inputTokens)
                XCTAssertNil(usage.audioInputTokens)
            }
        }
    }

    func testAnthropicCacheCountersKeepNoncachedInputSeparate() async throws {
        let ledger = UsageLedger()
        let harness = UsageHarness { _, _ in
            .json(["type": "message", "role": "assistant", "model": "claude-sonnet-4-6", "stop_reason": "end_turn",
                   "content": [["type": "text", "text": "{\"text\":\"완료\"}"]],
                   "usage": ["input_tokens": 50, "output_tokens": 12,
                             "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 500]])
        }
        _ = try await harness.client.process(request, configuration: config(.anthropic), onUsage: { await ledger.append($0) })
        let entries = await ledger.entries
        XCTAssertEqual(entries.first?.inputTokens, 50)
        XCTAssertEqual(entries.first?.cachedInputTokens, 1000)
        XCTAssertEqual(entries.first?.cacheWriteTokens, 500)
        XCTAssertEqual(entries.first?.outputTokens, 12)
    }

    func testGroqSupportsStandardAndNestedUsageWithoutCountingComputeTimeAsAudio() async throws {
        for nested in [false, true] {
            let ledger = UsageLedger()
            let harness = UsageHarness { _, _ in
                let usage: [String: Any] = ["prompt_tokens": 18, "completion_tokens": 556, "total_time": 0.46,
                    "prompt_tokens_details": ["cached_tokens": 3], "completion_tokens_details": ["reasoning_tokens": 8]]
                var response = Self.chat(usage: usage)
                if nested { response.removeValue(forKey: "usage"); response["x_groq"] = ["usage": usage] }
                return .json(response)
            }
            _ = try await harness.client.process(request, configuration: config(.groq), onUsage: { await ledger.append($0) })
            let entries = await ledger.entries
            XCTAssertEqual(entries.first?.inputTokens, 18)
            XCTAssertEqual(entries.first?.outputTokens, 556)
            XCTAssertEqual(entries.first?.cachedInputTokens, 3)
            XCTAssertEqual(entries.first?.reasoningTokens, 8)
            XCTAssertNil(entries.first?.audioSeconds)
        }
    }

    func testUntrustedCountersRejectBooleansNegativeFractionalNonfiniteAndNull() {
        for invalid: Any in [true, false, -1, 1.25, Double.nan, Double.infinity, NSNull(), "23"] {
            let usage = ProviderClient.usage(object: ["usage": ["input_tokens": invalid, "output_tokens": invalid,
                "prompt_tokens_details": ["cached_tokens": invalid, "cache_write_tokens": invalid, "audio_tokens": invalid],
                "completion_tokens_details": ["reasoning_tokens": invalid]]], provider: .openRouter,
                model: "model", stage: .textProcessing, outcome: .responseReceived, attempt: 1, httpStatus: 200, audioSeconds: nil)
            XCTAssertNil(usage.inputTokens)
            XCTAssertNil(usage.outputTokens)
            XCTAssertNil(usage.cachedInputTokens)
            XCTAssertNil(usage.cacheWriteTokens)
            XCTAssertNil(usage.audioInputTokens)
            XCTAssertNil(usage.reasoningTokens)
        }
        for invalid: Any in [true, false, -1, Double.nan, Double.infinity, NSNull(), "0.3"] {
            let usage = ProviderClient.usage(object: ["usage": ["cost": invalid, "seconds": invalid]], provider: .openRouter,
                model: "model", stage: .transcription, outcome: .responseReceived, attempt: 1, httpStatus: 200, audioSeconds: nil)
            XCTAssertNil(usage.providerCostUSD)
            XCTAssertNil(usage.audioSeconds)
        }
        let zero = ProviderClient.usage(object: ["usage": ["cost": 0, "input_tokens": 0, "seconds": 0]], provider: .openRouter,
            model: "model", stage: .transcription, outcome: .responseReceived, attempt: 1, httpStatus: 200, audioSeconds: nil)
        XCTAssertEqual(zero.providerCostUSD, 0)
        XCTAssertEqual(zero.inputTokens, 0)
        XCTAssertEqual(zero.audioSeconds, 0)
    }

    func testValidationBeforeNetworkDoesNotRecordAnAttempt() async throws {
        let ledger = UsageLedger()
        let harness = UsageHarness { _, _ in XCTFail("Must not make a request"); return .json([:]) }
        do {
            _ = try await harness.client.process(.init(mode: .dictation, transcript: " "), configuration: config(.openAI),
                                                  onUsage: { await ledger.append($0) })
            XCTFail("Invalid local input")
        } catch { XCTAssertEqual(error as? ProviderError, .invalidInput) }
        let entries = await ledger.entries
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(harness.count, 0)
    }

    private var request: ProcessingRequest { .init(mode: .dictation, transcript: "원문") }
    private func config(_ provider: AIProvider) -> ProviderConfiguration {
        .init(provider: provider, apiKey: "mock-key", transcriptionModel: "requested-model", textModel: "requested-model")
    }
    private static func chat(usage: [String: Any]) -> [String: Any] {
        ["model": "reported-model", "usage": usage,
         "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": "{\"text\":\"완료\"}"]]]]
    }
}

private actor UsageLedger {
    var entries: [ProviderUsage] = []
    func append(_ usage: ProviderUsage) { entries.append(usage) }
}
private actor UsageGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
private struct UsageStubResponse {
    var status = 200
    var headers: [String: String] = [:]
    var data: Data?
    static func json(_ object: [String: Any], status: Int = 200, headers: [String: String] = [:]) -> Self {
        .init(status: status, headers: headers, data: try! JSONSerialization.data(withJSONObject: object))
    }
}
private final class UsageHarness {
    let id = UUID().uuidString
    let session: URLSession
    let client: ProviderClient
    var count: Int { UsageProtocol.count(id) }
    init(handler: @escaping (URLRequest, Int) throws -> UsageStubResponse) {
        UsageProtocol.register(id, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageProtocol.self]
        configuration.httpAdditionalHeaders = ["X-OpenNoType-Usage-Test": id]
        session = URLSession(configuration: configuration)
        client = ProviderClient(session: session)
    }
    deinit { session.invalidateAndCancel(); UsageProtocol.remove(id) }
}
private final class UsageProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest, Int) throws -> UsageStubResponse] = [:]
    private static var counts: [String: Int] = [:]
    static func register(_ id: String, handler: @escaping (URLRequest, Int) throws -> UsageStubResponse) {
        lock.lock(); defer { lock.unlock() }; handlers[id] = handler; counts[id] = 0
    }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; handlers[id] = nil; counts[id] = nil }
    static func count(_ id: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[id] ?? 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-OpenNoType-Usage-Test") ?? ""
        Self.lock.lock()
        let handler = Self.handlers[id]
        Self.counts[id, default: 0] += 1
        let count = Self.counts[id] ?? 0
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let stub = try handler(request, count)
            guard let data = stub.data else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
