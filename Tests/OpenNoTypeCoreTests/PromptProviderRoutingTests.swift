import XCTest
@testable import OpenNoTypeCore

final class PromptProviderRoutingTests: XCTestCase {
    func testPromptAllowsSameModelProviderRecoveryWithinOneStrictRequest() async throws {
        for model in ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "openai/gpt-6-luna", "custom/future-model"] {
            for draft in [nil, "음성으로 기록을 정리하는 기능을 개선해 주세요."] as [String?] {
                let harness = RoutingHarness { request, _ in
                    let body = try request.routingJSONBody()
                    let routing = try XCTUnwrap(body["provider"] as? [String: Any])
                    XCTAssertEqual(Set(routing.keys), Set(["allow_fallbacks", "require_parameters", "sort"]))
                    XCTAssertEqual(routing["allow_fallbacks"] as? Bool, true)
                    XCTAssertEqual(routing["require_parameters"] as? Bool, true)
                    XCTAssertEqual(routing["sort"] as? String, "throughput")
                    XCTAssertEqual(body["model"] as? String, model)
                    XCTAssertNil(body["models"], "Recovery must stay on the selected model")
                    XCTAssertEqual(body["stream"] as? Bool, false)
                    XCTAssertEqual(body["max_tokens"] as? Int, 4_096)
                    XCTAssertEqual(request.timeoutInterval, 30)
                    if ["openai/gpt-oss-120b", "openai/gpt-oss-20b"].contains(model) {
                        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
                        XCTAssertEqual(reasoning["effort"] as? String, "medium")
                        XCTAssertEqual(reasoning["exclude"] as? Bool, true)
                    }
                    let format = try XCTUnwrap(body["response_format"] as? [String: Any])
                    XCTAssertEqual(format["type"] as? String, "json_schema")
                    let schema = try XCTUnwrap(format["json_schema"] as? [String: Any])
                    XCTAssertEqual(schema["strict"] as? Bool, true)
                    let resultSchema = try XCTUnwrap(schema["schema"] as? [String: Any])
                    XCTAssertEqual(resultSchema["required"] as? [String], ["text"])
                    XCTAssertEqual(resultSchema["additionalProperties"] as? Bool, false)
                    // Model a router whose first upstream is rate limited. The client sends one
                    // request; only an explicit provider recovery policy lets that router succeed.
                    guard routing["allow_fallbacks"] as? Bool == true else { return .rateLimited }
                    return .text("음성으로 기록을 정리하는 기능을 개선해 주세요.")
                }
                do {
                    let output = try await harness.client.process(.init(mode: .prompt,
                        transcript: "음성으로 기록을 정리하는 기능을 개선해 주세요.", promptDraft: draft),
                        configuration: configuration(.openRouter, model: model))
                    XCTAssertEqual(output, "음성으로 기록을 정리하는 기능을 개선해 주세요.")
                } catch { XCTFail("Eligible same-model provider recovery must be allowed: \(error)") }
                XCTAssertEqual(harness.count, 1, "Provider recovery must not add a client request")
            }
        }
    }

    func testExhaustedProviderRecoveryDoesNotEnableClientRetriesOrExposeBodies() async throws {
        for draft in [nil, "음성 기록 기능을 개선해 주세요."] as [String?] {
            for status in [429, 503] {
                let ledger = RoutingUsageLedger()
                let harness = RoutingHarness { request, attempt in
                    let body = try request.routingJSONBody()
                    let routing = try XCTUnwrap(body["provider"] as? [String: Any])
                    XCTAssertEqual(Set(routing.keys), Set(["allow_fallbacks", "require_parameters", "sort"]))
                    XCTAssertEqual(routing["allow_fallbacks"] as? Bool, true)
                    XCTAssertEqual(routing["require_parameters"] as? Bool, true)
                    XCTAssertEqual(routing["sort"] as? String, "throughput")
                    if attempt > 1 { return .text("재호출되어서는 안 되는 결과입니다.") }
                    return RoutingResponse(status: status, headers: ["Retry-After": "0"],
                        data: Data("private-source-key-provider-body-sentinel".utf8))
                }
                do {
                    _ = try await harness.client.process(.init(mode: .prompt,
                        transcript: "음성 기록 기능을 개선해 주세요.", promptDraft: draft),
                        configuration: configuration(.openRouter, model: "openai/gpt-oss-120b"),
                        allowRetry: true, onUsage: { await ledger.append($0) })
                    XCTFail("An exhausted router response must remain an HTTP failure")
                } catch {
                    XCTAssertEqual(error as? ProviderError, .httpStatus(status))
                    XCTAssertFalse(error.localizedDescription.contains("sentinel"))
                }
                XCTAssertEqual(harness.count, 1)
                let events = await ledger.values()
                XCTAssertEqual(events.count, 1)
                XCTAssertEqual(events.first?.attempt, 1)
                XCTAssertEqual(events.first?.outcome, .failed)
                XCTAssertEqual(events.first?.httpStatus, status)
            }
        }
    }

    func testOtherProcessingModesAndDirectProvidersKeepTheirRoutingPolicy() async throws {
        let requests: [ProcessingRequest] = [
            .init(mode: .dictation, transcript: "내용을 정리해 주세요."),
            .init(mode: .dictation, transcript: "내용을 정리해 주세요.", outputLanguage: .english),
            .init(mode: .rewrite, transcript: "짧게 다듬어 주세요.", selectedText: "원래 문장입니다.")
        ]
        for processing in requests {
            let harness = RoutingHarness { request, _ in
                let body = try request.routingJSONBody()
                XCTAssertEqual(body["provider"] as? [String: Bool],
                    ["allow_fallbacks": false, "require_parameters": true])
                XCTAssertEqual(body["max_tokens"] as? Int, 16_384)
                XCTAssertEqual(request.timeoutInterval, 120)
                return .text("정리한 문장입니다.")
            }
            _ = try await harness.client.process(processing,
                configuration: configuration(.openRouter, model: "openai/gpt-oss-120b"))
            XCTAssertEqual(harness.count, 1)
        }
        let direct = RoutingHarness { request, _ in
            let body = try request.routingJSONBody()
            XCTAssertEqual(request.url?.host, "api.groq.com")
            XCTAssertNil(body["provider"])
            XCTAssertNil(body["models"])
            XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-120b")
            return .text("음성 기록 기능을 개선해 주세요.")
        }
        _ = try await direct.client.process(.init(mode: .prompt, transcript: "음성 기록 기능을 개선해 주세요."),
            configuration: configuration(.groq, model: "openai/gpt-oss-120b"))
        XCTAssertEqual(direct.count, 1)
    }

    private func configuration(_ provider: AIProvider, model: String) -> ProviderConfiguration {
        .init(provider: provider, apiKey: "test-key", transcriptionModel: "test-stt", textModel: model)
    }
}

private struct RoutingResponse {
    var status = 200
    var headers: [String: String] = [:]
    var data: Data
    static var rateLimited: Self { .init(status: 429, data: Data("upstream rate limit".utf8)) }
    static func text(_ text: String) -> Self {
        let result = String(decoding: try! JSONSerialization.data(withJSONObject: ["text": text]), as: UTF8.self)
        let envelope: [String: Any] = ["choices": [["finish_reason": "stop", "message": [
            "role": "assistant", "content": result]]]]
        return .init(headers: ["Content-Type": "application/json"],
                     data: try! JSONSerialization.data(withJSONObject: envelope))
    }
}

private actor RoutingUsageLedger {
    private var events: [ProviderUsage] = []
    func append(_ event: ProviderUsage) { events.append(event) }
    func values() -> [ProviderUsage] { events }
}

private final class RoutingHarness {
    let id = UUID().uuidString
    let session: URLSession
    let client: ProviderClient
    var count: Int { RoutingProtocol.count(id) }
    init(handler: @escaping (URLRequest, Int) throws -> RoutingResponse) {
        RoutingProtocol.register(id, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoutingProtocol.self]
        configuration.httpAdditionalHeaders = ["X-OpenNoType-Routing-Test": id]
        session = URLSession(configuration: configuration)
        client = ProviderClient(session: session)
    }
    deinit { session.invalidateAndCancel(); RoutingProtocol.remove(id) }
}

private final class RoutingProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest, Int) throws -> RoutingResponse] = [:]
    private static var counts: [String: Int] = [:]
    static func register(_ id: String, handler: @escaping (URLRequest, Int) throws -> RoutingResponse) {
        lock.lock(); defer { lock.unlock() }; handlers[id] = handler; counts[id] = 0
    }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; handlers[id] = nil; counts[id] = nil }
    static func count(_ id: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[id] ?? 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-OpenNoType-Routing-Test") ?? ""
        Self.lock.lock()
        let handler = Self.handlers[id]
        Self.counts[id, default: 0] += 1
        let count = Self.counts[id] ?? 0
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let stub = try handler(request, count)
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status,
                httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private extension URLRequest {
    func routingJSONBody() throws -> [String: Any] {
        let data: Data
        if let httpBody { data = httpBody }
        else {
            guard let stream = httpBodyStream else { throw ProviderError.invalidInput }
            stream.open(); defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw ProviderError.invalidInput }
                if count == 0 { break }
                bytes.append(buffer, count: count)
            }
            data = bytes
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
