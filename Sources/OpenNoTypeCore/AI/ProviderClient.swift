import Foundation
import CoreFoundation

/// Direct HTTPS transport. No keys, audio, prompts, or provider bodies are logged.
public final class ProviderClient: @unchecked Sendable {
    private let session: URLSession
    private let redirectPolicy = RejectRedirects()
    private static let maximumAudioBytes = 25_000_000
    private static let maximumResponseBytes = 8_000_000

    public init(session: URLSession = .shared) { self.session = session }

    public func transcribe(audioURL: URL, configuration: ProviderConfiguration,
                           dictionary: [DictionaryEntry], writingProfile: WritingProfile = .init(),
                           audioSeconds: Double? = nil,
                           onUsage: (@Sendable (ProviderUsage) async -> Void)? = nil) async throws -> String {
        try Task.checkCancellation()
        guard configuration.provider != .anthropic else { throw ProviderError.localTranscriptionRequired }
        let model = try validate(configuration, model: configuration.transcriptionModel)
        guard audioURL.isFileURL else { throw ProviderError.unreadableAudio }
        let format = audioURL.pathExtension.lowercased()
        let mimeTypes = ["wav": "audio/wav", "mp3": "audio/mpeg", "mp4": "audio/mp4",
                         "m4a": "audio/mp4", "mpeg": "audio/mpeg", "mpga": "audio/mpeg",
                         "webm": "audio/webm", "flac": "audio/flac", "ogg": "audio/ogg"]
        guard let mimeType = mimeTypes[format] else { throw ProviderError.unsupportedAudioFormat }
        let audio: Data
        do {
            let values = try audioURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw ProviderError.unreadableAudio }
            guard (values.fileSize ?? 0) <= Self.maximumAudioBytes else { throw ProviderError.audioTooLarge }
            audio = try Data(contentsOf: audioURL)
        } catch let error as ProviderError { throw error }
        catch { throw ProviderError.unreadableAudio }
        guard !audio.isEmpty else { throw ProviderError.unreadableAudio }
        guard audio.count <= Self.maximumAudioBytes else { throw ProviderError.audioTooLarge }
        try Task.checkCancellation()

        var request: URLRequest
        switch configuration.provider {
        case .openAI, .groq:
            let endpoint = configuration.provider == .groq
                ? "https://api.groq.com/openai/v1/audio/transcriptions"
                : "https://api.openai.com/v1/audio/transcriptions"
            request = try baseRequest(endpoint, configuration: configuration)
            let boundary = "OpenNoType-" + UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            appendField("model", value: model, boundary: boundary, to: &body)
            appendField("response_format", value: "json", boundary: boundary, to: &body)
            if configuration.provider == .openAI, TranscriptionHints.supportsContextPrompt(model: model) {
                let hints = TranscriptionHints.make(dictionary: dictionary, profile: writingProfile)
                appendField("prompt", value: hints.prompt, boundary: boundary, to: &body)
                if model == "gpt-transcribe" {
                    // Other transcription models do not share the keywords[] contract.
                    for term in hints.keywords {
                        appendField("keywords[]", value: term, boundary: boundary, to: &body)
                    }
                }
            } else if model != "gpt-4o-transcribe-diarize",
                      let prompt = try whisperTranscriptionPrompt(dictionary: dictionary, profile: writingProfile) {
                // Groq Whisper, OpenAI whisper-1 and unknown models: transcript-style vocabulary within 224 tokens.
                appendField("prompt", value: prompt, boundary: boundary, to: &body)
            }
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.\(format)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
            body.append(audio)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            request.httpBody = body
        case .openRouter:
            request = try baseRequest("https://openrouter.ai/api/v1/audio/transcriptions", configuration: configuration)
            // STT provider routing controls are not supported by OpenRouter. Do not send
            // chat-only allow_fallbacks/only/data_collection options as a false guarantee.
            request.httpBody = try encodeJSON([
                "model": model,
                "input_audio": ["data": audio.base64EncodedString(), "format": format]
            ])
        case .anthropic: throw ProviderError.localTranscriptionRequired
        }
        let object = try responseObject(await send(request, provider: configuration.provider, model: model,
                                                   stage: .transcription, audioSeconds: audioSeconds, onUsage: onUsage))
        if let status = object["status"] as? String, status != "completed" { throw ProviderError.incompleteOutput }
        if let reason = object["finish_reason"] as? String, reason != "stop" { throw ProviderError.incompleteOutput }
        guard let text = object["text"] as? String else { throw ProviderError.invalidResponse }
        return try validatedText(text)
    }

    public func process(_ request: ProcessingRequest, configuration: ProviderConfiguration,
                        onUsage: (@Sendable (ProviderUsage) async -> Void)? = nil) async throws -> String {
        try Task.checkCancellation()
        let model = try validate(configuration, model: configuration.textModel)
        let prompt = try ProcessingPrompt.build(request)
        var networkRequest: URLRequest
        switch configuration.provider {
        case .openAI:
            networkRequest = try baseRequest("https://api.openai.com/v1/responses", configuration: configuration)
            networkRequest.httpBody = try encodeJSON([
                "model": model, "store": false,
                "instructions": prompt.instructions, "input": prompt.input,
                "max_output_tokens": 16_384,
                "text": ["format": ["type": "json_schema", "name": "dictation_result",
                                      "strict": true, "schema": Self.resultSchema]]
            ])
        case .openRouter:
            networkRequest = try baseRequest("https://openrouter.ai/api/v1/chat/completions", configuration: configuration)
            networkRequest.httpBody = try encodeJSON([
                "model": model, "stream": false, "max_tokens": 16_384,
                "provider": ["allow_fallbacks": false, "require_parameters": true],
                "messages": [["role": "system", "content": prompt.instructions],
                             ["role": "user", "content": prompt.input]],
                "response_format": ["type": "json_schema", "json_schema": [
                    "name": "dictation_result", "strict": true, "schema": Self.resultSchema]]
            ])
        case .groq:
            networkRequest = try baseRequest("https://api.groq.com/openai/v1/chat/completions", configuration: configuration)
            var body: [String: Any] = [
                "model": model, "stream": false, "max_completion_tokens": 16_384,
                "messages": [["role": "system", "content": prompt.instructions],
                             ["role": "user", "content": prompt.input]]
            ]
            if ["openai/gpt-oss-120b", "openai/gpt-oss-20b"].contains(model) {
                // GPT-OSS supports strict schema output and include_reasoning, not reasoning_format.
                body["response_format"] = ["type": "json_schema", "json_schema": [
                    "name": "dictation_result", "strict": true, "schema": Self.resultSchema]]
                body["include_reasoning"] = false
                body["reasoning_effort"] = "low"
            } else {
                // Models such as Llama 3.3 support JSON mode without strict schema decoding.
                // The shared parser still rejects malformed, extra-field, or incomplete output.
                body["response_format"] = ["type": "json_object"]
            }
            networkRequest.httpBody = try encodeJSON(body)
        case .anthropic:
            networkRequest = try baseRequest("https://api.anthropic.com/v1/messages", configuration: configuration)
            networkRequest.httpBody = try encodeJSON([
                "model": model, "max_tokens": 16_384,
                "system": prompt.instructions,
                "messages": [["role": "user", "content": prompt.input]]
            ])
        }
        let response = try responseObject(await send(networkRequest, provider: configuration.provider, model: model,
                                                     stage: .textProcessing, audioSeconds: nil, onUsage: onUsage))
        let text: String
        switch configuration.provider {
        case .openAI: text = try parseResponses(response)
        case .openRouter, .groq: text = try parseChat(response)
        case .anthropic: text = try parseMessages(response)
        }
        try Task.checkCancellation()
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["text"]), let result = object["text"] as? String else {
            throw ProviderError.invalidResponse
        }
        return try validatedText(result)
    }

    private static var resultSchema: [String: Any] {
        ["type": "object", "properties": ["text": ["type": "string"]],
         "required": ["text"], "additionalProperties": false]
    }

    /// Returns the model identifier as it will be sent: surrounding whitespace from a pasted id is dropped.
    @discardableResult
    private func validate(_ configuration: ProviderConfiguration, model: String) throws -> String {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\r"), !key.contains("\n") else { throw ProviderError.missingAPIKey }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200, !trimmed.contains("\r"), !trimmed.contains("\n") else {
            throw ProviderError.missingModel
        }
        return trimmed
    }

    private func baseRequest(_ endpoint: String, configuration: ProviderConfiguration) throws -> URLRequest {
        guard let url = URL(string: endpoint), url.scheme == "https" else { throw ProviderError.invalidInput }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuration.provider == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send(_ request: URLRequest, provider: AIProvider, model: String,
                      stage: UsageStage, audioSeconds: Double?,
                      onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> Data {
        // Retry only explicit temporary HTTP failures, once. Ambiguous transport failures are not replayed.
        for attempt in 1...2 {
            try Task.checkCancellation()
            let createdAt = Date()
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request, delegate: redirectPolicy) }
            catch {
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                await reportUsage(Self.usage(object: nil, provider: provider, model: model, stage: stage,
                    outcome: cancelled ? .cancelled : .failed, attempt: attempt, createdAt: createdAt,
                    httpStatus: nil, audioSeconds: audioSeconds), to: onUsage)
                if cancelled { throw CancellationError() }
                throw ProviderError.connectionFailed
            }
            let http = response as? HTTPURLResponse
            // Accounting precedes cancellation and output validation. A paid response may arrive just
            // before cancellation, or contain usable usage even when its generated text is malformed.
            let object = data.count <= Self.maximumResponseBytes
                ? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] : nil
            let received = http.map { (200...299).contains($0.statusCode) } ?? false
            await reportUsage(Self.usage(object: object, provider: provider, model: model, stage: stage,
                outcome: received ? .responseReceived : .failed, attempt: attempt, createdAt: createdAt,
                httpStatus: http?.statusCode, audioSeconds: audioSeconds), to: onUsage)
            try Task.checkCancellation()
            guard let http else { throw ProviderError.invalidResponse }
            if !received {
                if attempt == 1, [429, 502, 503, 504].contains(http.statusCode), let delay = retryDelay(http) {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                // Never surface the raw provider body: it can echo keys or private input.
                throw ProviderError.httpStatus(http.statusCode)
            }
            guard data.count <= Self.maximumResponseBytes else { throw ProviderError.invalidResponse }
            return data
        }
        throw ProviderError.connectionFailed
    }

    private func reportUsage(_ usage: ProviderUsage,
                             to callback: (@Sendable (ProviderUsage) async -> Void)?) async {
        guard let callback else { return }
        // A cancelled request must still finish persisting already known accounting. This task
        // intentionally does not inherit cancellation; the caller awaits its completion.
        await Task.detached { await callback(usage) }.value
    }

    /// Provider metadata only: never retain prompts, output text, request IDs, keys, or raw bodies.
    static func usage(object: [String: Any]?, provider: AIProvider, model: String, stage: UsageStage,
                      outcome: UsageOutcome, attempt: Int, createdAt: Date = Date(), httpStatus: Int?,
                      audioSeconds: Double?) -> ProviderUsage {
        let groq = provider == .groq ? object?["x_groq"] as? [String: Any] : nil
        let usage = (object?["usage"] as? [String: Any]) ?? (groq?["usage"] as? [String: Any]) ?? [:]
        let input = (usage["input_tokens_details"] as? [String: Any])
            ?? (usage["input_token_details"] as? [String: Any])
            ?? (usage["prompt_tokens_details"] as? [String: Any]) ?? [:]
        let output = (usage["output_tokens_details"] as? [String: Any])
            ?? (usage["completion_tokens_details"] as? [String: Any]) ?? [:]
        let duration = stage == .transcription
            ? (usageNumber(usage["seconds"]) ?? usageNumber(object?["duration"]) ?? usageNumber(audioSeconds)) : nil
        // Anthropic's input_tokens excludes cache reads/writes; preserve that provider-specific
        // contract instead of silently mixing it with the other providers' inclusive counters.
        return ProviderUsage(createdAt: createdAt, provider: provider, model: model,
            reportedModel: usageModel(object?["model"]), stage: stage, outcome: outcome, attempt: attempt,
            httpStatus: httpStatus,
            inputTokens: usageInteger(usage["input_tokens"]) ?? usageInteger(usage["prompt_tokens"]),
            outputTokens: usageInteger(usage["output_tokens"]) ?? usageInteger(usage["completion_tokens"]),
            cachedInputTokens: provider == .anthropic ? usageInteger(usage["cache_read_input_tokens"]) : usageInteger(input["cached_tokens"]),
            cacheWriteTokens: provider == .anthropic ? usageInteger(usage["cache_creation_input_tokens"]) : usageInteger(input["cache_write_tokens"]),
            audioInputTokens: usageInteger(input["audio_tokens"]),
            reasoningTokens: usageInteger(output["reasoning_tokens"]), audioSeconds: duration,
            providerCostUSD: provider == .openRouter ? usageNumber(usage["cost"]) : nil)
    }

    private static func usageInteger(_ value: Any?) -> Int? {
        guard let number = usageNumber(value), let integer = Int(exactly: number) else { return nil }
        return integer
    }

    private static func usageNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite && value >= 0 ? value : nil
    }

    private static func usageModel(_ value: Any?) -> String? {
        guard let model = value as? String else { return nil }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:")
        guard !trimmed.isEmpty, trimmed.utf8.count <= 200,
              trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return trimmed
    }

    private func retryDelay(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return 0.3 }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0, seconds <= 2 { return seconds }
        // Long delays and HTTP-date values are left for an explicit user retry.
        return nil
    }

    private func responseObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        if let error = object["error"], !(error is NSNull) { throw ProviderError.invalidResponse }
        return object
    }

    private func parseResponses(_ object: [String: Any]) throws -> String {
        guard object["status"] as? String == "completed" else { throw ProviderError.incompleteOutput }
        guard let output = object["output"] as? [[String: Any]] else { throw ProviderError.invalidResponse }
        var texts: [String] = []
        for item in output {
            if item["type"] as? String == "reasoning" { continue }
            guard item["type"] as? String == "message", item["role"] as? String == "assistant",
                  item["status"] as? String == "completed",
                  let blocks = item["content"] as? [[String: Any]] else { throw ProviderError.invalidResponse }
            for block in blocks {
                if block["type"] as? String == "refusal" { throw ProviderError.refused }
                guard block["type"] as? String == "output_text", let text = block["text"] as? String else {
                    throw ProviderError.invalidResponse
                }
                texts.append(text)
            }
        }
        return try validatedText(texts.joined())
    }

    private func parseChat(_ object: [String: Any]) throws -> String {
        guard let choices = object["choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first, let message = choice["message"] as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        if choice["finish_reason"] as? String == "content_filter" { throw ProviderError.refused }
        if let refusal = message["refusal"], !(refusal is NSNull) { throw ProviderError.refused }
        guard choice["finish_reason"] as? String == "stop" else { throw ProviderError.incompleteOutput }
        if let calls = message["tool_calls"], !(calls is NSNull) {
            guard let array = calls as? [Any], array.isEmpty else { throw ProviderError.invalidResponse }
        }
        guard message["role"] as? String == "assistant", let text = message["content"] as? String else {
            throw ProviderError.invalidResponse
        }
        return try validatedText(text)
    }

    private func parseMessages(_ object: [String: Any]) throws -> String {
        if object["stop_reason"] as? String == "refusal" { throw ProviderError.refused }
        guard object["stop_reason"] as? String == "end_turn" else { throw ProviderError.incompleteOutput }
        guard object["type"] as? String == "message", object["role"] as? String == "assistant",
              let blocks = object["content"] as? [[String: Any]] else { throw ProviderError.invalidResponse }
        var texts: [String] = []
        for block in blocks {
            if block["type"] as? String == "thinking" || block["type"] as? String == "redacted_thinking" { continue }
            guard block["type"] as? String == "text", let text = block["text"] as? String else {
                throw ProviderError.invalidResponse
            }
            texts.append(text)
        }
        return try validatedText(texts.joined())
    }

    private func validatedText(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ProviderError.emptyOutput }
        guard value.count <= 100_000, !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
        }) else { throw ProviderError.invalidResponse }
        return value
    }

    private func encodeJSON(_ object: [String: Any]) throws -> Data {
        do { return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        catch { throw ProviderError.invalidInput }
    }

    /// Whisper prompts condition style and spelling and should read like a transcript in the audio's
    /// language (Groq and OpenAI guidance), so this sends vocabulary plus a short Korean context line,
    /// never an English instruction. Terms are dropped from the end until the 224-token limit holds.
    func whisperTranscriptionPrompt(dictionary: [DictionaryEntry], profile: WritingProfile) throws -> String? {
        let hints = TranscriptionHints.make(dictionary: dictionary, profile: profile)
        // Without personal or profile vocabulary there is nothing to steer; keep the request minimal.
        guard !hints.keywords.isEmpty else { return nil }
        // Keep the priority order and skip only the terms that would not fit.
        var selected: [String] = []
        for term in hints.keywords {
            let candidate = selected + [term]
            if Self.estimatedWhisperTokens(TranscriptionHints.whisperPrompt(terms: candidate)) <= 224 { selected = candidate }
        }
        guard !selected.isEmpty else { return nil }
        return TranscriptionHints.whisperPrompt(terms: selected)
    }

    /// Conservative estimate for Whisper's byte-level BPE: Hangul and other multi-byte text tokenizes
    /// close to one token per two UTF-8 bytes; ASCII is over-counted, which only wastes budget.
    static func estimatedWhisperTokens(_ text: String) -> Int { (text.utf8.count + 1) / 2 }

    private func appendField(_ name: String, value: String, boundary: String, to data: inout Data) {
        data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Keep credentials and user data at the explicitly selected provider endpoint.
        completionHandler(nil)
    }
}
