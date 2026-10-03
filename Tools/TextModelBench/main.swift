import Foundation

// Capture/replay the real ProviderClient. No question, request builder, or parser copies.
private final class ReplayState: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var status = 200
    private var captured: [(URL, Data)] = []

    func configure(data: Data, status: Int) {
        lock.lock(); defer { lock.unlock() }
        self.data = data; self.status = status; captured = []
    }
    func receive(_ request: URLRequest, body: Data) -> (Data, Int) {
        lock.lock(); defer { lock.unlock() }
        captured.append((request.url!, body))
        return (data, status)
    }
    func snapshot() -> [(URL, Data)] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
}

private final class ReplayProtocol: URLProtocol, @unchecked Sendable {
    static let state = ReplayState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0, body.count + count <= 1_000_000 else {
                    client?.urlProtocol(self, didFailWithError: ProviderError.invalidInput); return
                }
                if count == 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let (data, status) = Self.state.receive(request, body: body)
        // Prevent the production parser's replay from fabricating a second paid attempt.
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json", "Retry-After": "120"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor UsageCollector {
    var values: [ProviderUsage] = []
    func append(_ value: ProviderUsage) { values.append(value) }
    func snapshot() -> [ProviderUsage] { values }
}

private func processingRequest(_ fixture: [String: Any]) throws -> ProcessingRequest {
    guard fixture["mode"] as? String == "dictation", let transcript = fixture["stt_input"] as? String,
          let profile = fixture["writing_profile"] as? [String: Any],
          let kind = WritingProfileKind(rawValue: profile["kind"] as? String ?? ""),
          let tone = WritingTone(rawValue: profile["tone"] as? String ?? "") else { throw ProviderError.invalidInput }
    let expression: DictationExpression
    if let supplied = profile["expression"], !(supplied is NSNull) {
        // Benchmarks must not silently evaluate faithful dictation when a fixture intended a new style.
        guard let settings = supplied as? [String: Any],
              let style = DictationExpressionStyle(rawValue: settings["style"] as? String ?? ""),
              let number = settings["strength"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let strength = settings["strength"] as? Int, (0...100).contains(strength) else {
            throw ProviderError.invalidInput
        }
        expression = .init(style: style, strength: strength)
    } else { expression = .init() }
    let entries = (fixture["dictionary"] as? [[String: String]] ?? []).compactMap { item -> DictionaryEntry? in
        guard let spoken = item["spoken"], let written = item["written"] else { return nil }
        return .init(spoken: spoken, written: written)
    }
    return .init(mode: .dictation, transcript: transcript, context: fixture["cursor_context"] as? String,
                 dictionary: entries, writingProfile: .init(kind: kind, tone: tone, expression: expression))
}

private func errorCode(_ error: Error) -> String {
    guard let error = error as? ProviderError else { return "harness_error" }
    switch error {
    case .missingAPIKey: return "missing_api_key"
    case .missingModel: return "missing_model"
    case .localTranscriptionRequired: return "local_transcription_required"
    case .invalidInput: return "invalid_input"
    case .unsupportedAudioFormat: return "unsupported_audio_format"
    case .audioTooLarge: return "audio_too_large"
    case .unreadableAudio: return "unreadable_audio"
    case .httpStatus: return "http_status"
    case .connectionFailed: return "connection_failed"
    case .timedOut: return "timed_out"
    case .responseTooLarge: return "response_too_large"
    case .invalidResponse: return "invalid_response"
    case .emptyOutput: return "empty_output"
    case .incompleteOutput: return "incomplete_output"
    case .refused: return "refused"
    }
}

private func usageObject(_ value: ProviderUsage) -> [String: Any] {
    ["input_tokens": value.inputTokens as Any? ?? NSNull(),
     "output_tokens": value.outputTokens as Any? ?? NSNull(),
     "reasoning_tokens": value.reasoningTokens as Any? ?? NSNull(),
     "cached_input_tokens": value.cachedInputTokens as Any? ?? NSNull(),
     "provider_reported_cost_usd": value.providerCostUSD as Any? ?? NSNull(),
     "reported_model": value.reportedModel as Any? ?? NSNull()]
}

@main
private enum TextModelBench {
    static func run() async throws -> Any {
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        guard inputData.count <= 2_000_000,
              let input = try JSONSerialization.jsonObject(with: inputData) as? [String: Any],
              CommandLine.arguments.count == 2 else { throw ProviderError.invalidInput }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplayProtocol.self]
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = ProviderClient(session: session)
        if CommandLine.arguments[1] == "export" {
            guard let fixtures = input["fixtures"] as? [[String: Any]], let models = input["models"] as? [String],
                  fixtures.count <= 20, models.count <= 32 else { throw ProviderError.invalidInput }
            var result: [[String: Any]] = []
            for fixture in fixtures {
                guard let id = fixture["id"] as? String else { throw ProviderError.invalidInput }
                for model in models {
                    let synthetic: [String: Any] = ["choices": [["finish_reason": "stop", "message":
                        ["role": "assistant", "content": "{\"text\":\"synthetic-ok\"}"]]]]
                    ReplayProtocol.state.configure(data: try JSONSerialization.data(withJSONObject: synthetic), status: 200)
                    _ = try await client.process(processingRequest(fixture), configuration: .init(provider: .openRouter,
                        apiKey: "synthetic-benchmark-key", transcriptionModel: "", textModel: model))
                    let captured = ReplayProtocol.state.snapshot()
                    guard captured.count == 1 else { throw ProviderError.invalidResponse }
                    let (endpoint, body) = captured[0]
                    result.append(["id": id, "model": model, "endpoint": endpoint.absoluteString,
                                   "body_base64": body.base64EncodedString()])
                }
            }
            return result
        }
        if CommandLine.arguments[1] == "parse" {
            guard let fixture = input["fixture"] as? [String: Any], let model = input["model"] as? String,
                  let status = input["http_status"] as? Int else { throw ProviderError.invalidInput }
            let response = try JSONSerialization.data(withJSONObject: input["response"] ?? NSNull(), options: [.fragmentsAllowed])
            ReplayProtocol.state.configure(data: response, status: status)
            let collector = UsageCollector()
            var output: [String: Any]
            do {
                let text = try await client.process(processingRequest(fixture), configuration: .init(provider: .openRouter,
                    apiKey: "synthetic-benchmark-key", transcriptionModel: "", textModel: model),
                    onUsage: { await collector.append($0) })
                output = ["ok": true, "text": text]
            } catch { output = ["ok": false, "error": errorCode(error)] }
            let usage = await collector.snapshot()
            output["usage"] = usage.last.map(usageObject) ?? [:]
            output["replayed_attempts"] = ReplayProtocol.state.snapshot().count
            return output
        }
        throw ProviderError.invalidInput
    }
    static func main() async {
        do {
            let output = try JSONSerialization.data(withJSONObject: await run(), options: [.sortedKeys, .withoutEscapingSlashes])
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data((errorCode(error) + "\n").utf8)); exit(1)
        }
    }
}
