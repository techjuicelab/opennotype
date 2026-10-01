import Foundation

// Compiled in the same module as the real Core sources: no duplicated question or parser.
func request(_ fixture: [String: Any]) throws -> DecisionRequest {
    guard let transcript = fixture["transcript"] as? String,
          let cleaned = fixture["cleaned_text"] as? String,
          let terms = fixture["term_candidates"] as? [[String: String]] else {
        throw DecisionError.invalidInput
    }
    let candidates = try terms.map { term -> DecisionTermCandidate in
        guard let id = term["id"], let original = term["original"], let candidate = term["candidate"] else {
            throw DecisionError.invalidInput
        }
        return .init(id: id, original: original, candidate: candidate)
    }
    return .init(transcript: transcript, cleanedText: cleaned, termCandidates: candidates)
}

func usageObject(_ usage: ProviderUsage) -> [String: Any] {
    ["input_tokens": usage.inputTokens as Any? ?? NSNull(),
     "output_tokens": usage.outputTokens as Any? ?? NSNull(),
     "provider_reported_cost_usd": usage.providerCostUSD as Any? ?? NSNull()]
}

func errorCode(_ error: Error) -> String {
    guard let error = error as? DecisionError else { return "harness_error" }
    switch error {
    case .missingAPIKey: return "missing_api_key"
    case .invalidInput: return "invalid_input"
    case .inputTooLarge: return "input_too_large"
    case .responseTooLarge: return "response_too_large"
    case .invalidResponse: return "invalid_response"
    case .timedOut: return "timed_out"
    case .connectionFailed: return "connection_failed"
    case .httpStatus: return "http_status"
    }
}

func run() throws -> Any {
    guard CommandLine.arguments.count >= 2 else { throw DecisionError.invalidInput }
    if CommandLine.arguments[1] == "export", CommandLine.arguments.count == 3 {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cases = document["cases"] as? [[String: Any]] else { throw DecisionError.invalidInput }
        return try cases.map { fixture -> [String: Any] in
            guard let id = fixture["id"] as? String else { throw DecisionError.invalidInput }
            // No key/env access: this synthetic constant is discarded with the headers.
            let exported = try DecisionClient.makeRequest(request(fixture), apiKey: "synthetic-benchmark-key")
            guard let body = exported.httpBody else { throw DecisionError.invalidInput }
            return ["id": id, "body_base64": body.base64EncodedString(), "request_bytes": body.count,
                    "runtime_deadline_seconds": DecisionClient.timeout,
                    "endpoint": exported.url!.absoluteString]
        }
    }
    if CommandLine.arguments[1] == "parse", CommandLine.arguments.count == 2 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fixture = input["fixture"] as? [String: Any],
              let status = input["http_status"] as? Int else { throw DecisionError.invalidInput }
        let object = input["response"] as? [String: Any]
        let usage = ProviderClient.usage(object: object, provider: .openRouter, model: DecisionClient.model,
            stage: .decisionReview, outcome: (200...299).contains(status) ? .responseReceived : .failed,
            attempt: 1, createdAt: Date(), httpStatus: status, audioSeconds: nil)
        do {
            guard (200...299).contains(status) else { throw DecisionError.httpStatus(status) }
            guard let object else { throw DecisionError.invalidResponse }
            let parsed = try DecisionClient.parse(object, candidates: request(fixture).termCandidates, usage: usage)
            let terms = parsed.terms.map { term -> [String: Any] in
                ["id": term.id, "choice": term.choice.rawValue, "confidence": term.confidence,
                 "probabilities": Dictionary(uniqueKeysWithValues: term.probabilities.map { ($0.key.rawValue, $0.value) })]
            }
            return ["ok": true, "risk": ["meaning_changed": parsed.meaningChanged,
                    "content_added": parsed.contentAdded, "content_omitted": parsed.contentOmitted],
                    "terms": terms, "reported_model": parsed.reportedModel, "usage": usageObject(usage)]
        } catch {
            return ["ok": false, "error": errorCode(error), "usage": usageObject(usage)]
        }
    }
    throw DecisionError.invalidInput
}

do {
    let value = try run()
    let output = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    // Never reflect raw response, request text, environment, or error descriptions.
    FileHandle.standardError.write(Data((errorCode(error) + "\n").utf8))
    exit(1)
}
