import Foundation

/// A model reported by a provider's model list. Listing a model is not proof that it works with
/// OpenNoType's prompts; that is what the compatibility test checks.
public struct DiscoveredModel: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, speech }
    public var provider: AIProvider
    public var modelID: String
    public var name: String?
    public var kind: Kind
    public var inputUSDPerMillion: Double?
    public var outputUSDPerMillion: Double?
    public var firstSeenAt: Date
    /// Appeared after the first search and not yet acknowledged.
    public var isNew: Bool
    public var id: String { "\(provider.rawValue):\(modelID)" }

    public init(provider: AIProvider, modelID: String, name: String? = nil, kind: Kind,
                inputUSDPerMillion: Double? = nil, outputUSDPerMillion: Double? = nil,
                firstSeenAt: Date = Date(), isNew: Bool = false) {
        self.provider = provider; self.modelID = modelID; self.name = name; self.kind = kind
        self.inputUSDPerMillion = inputUSDPerMillion; self.outputUSDPerMillion = outputUSDPerMillion
        self.firstSeenAt = firstSeenAt; self.isNew = isNew
    }
}

/// The result of running a short synthetic request through the real processing path.
public struct ModelCompatibilityResult: Codable, Equatable, Sendable {
    public var provider: AIProvider
    public var modelID: String
    public var task: String
    public var passed: Bool
    public var latencySeconds: Double
    public var reportedModel: String?
    public var costUSD: Double?
    public var failure: String?
    public var checkedAt: Date

    public init(provider: AIProvider, modelID: String, task: String, passed: Bool, latencySeconds: Double,
                reportedModel: String? = nil, costUSD: Double? = nil, failure: String? = nil, checkedAt: Date = Date()) {
        self.provider = provider; self.modelID = modelID; self.task = task; self.passed = passed
        self.latencySeconds = latencySeconds; self.reportedModel = reportedModel; self.costUSD = costUSD
        self.failure = failure; self.checkedAt = checkedAt
    }

    public static func key(provider: AIProvider, modelID: String, task: String) -> String {
        "\(provider.rawValue):\(modelID):\(task)"
    }
}

public enum ModelDiscovery {
    public enum Failure: Error, Equatable, Sendable { case http(Int), invalidResponse, connection }

    /// Parses OpenRouter's public list. Keeps paid text models that support structured output,
    /// which OpenNoType's strict JSON responses require. Free, routing and non-text models are skipped.
    public static func parseOpenRouter(_ data: Data, now: Date = Date()) throws -> [DiscoveredModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else { throw Failure.invalidResponse }
        return items.compactMap { item in
            // Variants such as ":free", ":batch" or ":online" change billing or routing; only base IDs are listed.
            guard let id = item["id"] as? String, !id.isEmpty, !id.contains(":"), !id.hasPrefix("openrouter/") else { return nil }
            let architecture = item["architecture"] as? [String: Any]
            let inputs = architecture?["input_modalities"] as? [String] ?? ["text"]
            let outputs = architecture?["output_modalities"] as? [String] ?? ["text"]
            guard inputs.contains("text"), outputs == ["text"] || outputs.contains("text") && !outputs.contains("image") else { return nil }
            let parameters = item["supported_parameters"] as? [String] ?? []
            guard parameters.contains("structured_outputs") || parameters.contains("response_format") else { return nil }
            let pricing = item["pricing"] as? [String: Any]
            let input = perMillion(pricing?["prompt"]), output = perMillion(pricing?["completion"])
            guard let input, let output, input > 0 || output > 0 else { return nil }
            return DiscoveredModel(provider: .openRouter, modelID: id, name: item["name"] as? String, kind: .text,
                                   inputUSDPerMillion: input, outputUSDPerMillion: output, firstSeenAt: now)
        }
    }

    /// Parses an OpenAI-compatible model list (OpenAI, Groq). These lists carry no prices.
    public static func parseModelIDs(_ data: Data, provider: AIProvider, now: Date = Date()) throws -> [DiscoveredModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else { throw Failure.invalidResponse }
        return items.compactMap { item in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            if let active = item["active"] as? Bool, !active { return nil }
            guard let kind = classify(id, provider: provider) else { return nil }
            return DiscoveredModel(provider: provider, modelID: id, name: item["display_name"] as? String, kind: kind, firstSeenAt: now)
        }
    }

    /// Which list entries can serve OpenNoType's text or speech requests.
    public static func classify(_ id: String, provider: AIProvider) -> DiscoveredModel.Kind? {
        let lower = id.lowercased()
        if lower.contains("transcribe") || lower.contains("whisper") {
            return provider == .anthropic ? nil : .speech
        }
        let excluded = ["embedding", "tts", "realtime", "audio", "image", "dall-e", "moderation", "search", "guard",
                        "playai", "davinci", "babbage", "computer-use", "codex", "sora", "omni-moderation"]
        if excluded.contains(where: lower.contains) { return nil }
        switch provider {
        case .openAI: return lower.hasPrefix("gpt-") || lower.hasPrefix("o") && lower.dropFirst().first?.isNumber == true ? .text : nil
        case .anthropic: return lower.hasPrefix("claude-") ? .text : nil
        case .groq, .openRouter: return .text
        }
    }

    /// Merges a new listing into what was seen before. The first listing establishes a baseline
    /// without marking anything new; later listings mark models that were not seen before and
    /// are not in the built-in catalog.
    public static func merge(previous: [DiscoveredModel], fetched: [DiscoveredModel], provider: AIProvider,
                             catalogIDs: Set<String>, isFirstSearch: Bool) -> [DiscoveredModel] {
        let known = Dictionary(previous.filter { $0.provider == provider }.map { ($0.modelID, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = previous.filter { $0.provider != provider }
        for var model in fetched {
            if let earlier = known[model.modelID] {
                model.firstSeenAt = earlier.firstSeenAt
                model.isNew = earlier.isNew
            } else {
                model.isNew = !isFirstSearch && !catalogIDs.contains(model.modelID)
            }
            merged.append(model)
        }
        return merged
    }

    private static func perMillion(_ value: Any?) -> Double? {
        let perToken: Double?
        switch value {
        case let text as String: perToken = Double(text)
        case let number as NSNumber: perToken = number.doubleValue
        default: perToken = nil
        }
        guard let perToken, perToken.isFinite, perToken >= 0 else { return nil }
        return perToken * 1_000_000
    }

    /// Fetches one provider's list. Only providers with a key already in memory are listed, except
    /// OpenRouter's public list. Responses are size- and time-bounded.
    public static func fetch(_ provider: AIProvider, apiKey: String?, session: URLSession = .shared,
                             now: Date = Date()) async throws -> [DiscoveredModel] {
        let url: URL
        var request: URLRequest
        switch provider {
        case .openRouter:
            url = URL(string: "https://openrouter.ai/api/v1/models")!
            request = URLRequest(url: url)
        case .openAI:
            url = URL(string: "https://api.openai.com/v1/models")!
            request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        case .groq:
            url = URL(string: "https://api.groq.com/openai/v1/models")!
            request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/models?limit=100")!
            request = URLRequest(url: url)
            request.setValue(apiKey ?? "", forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let response: BoundedProviderResponse
        do {
            response = try await BoundedProviderResponse.receive(request, session: session, maximumBytes: 4_000_000, timeout: 15)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.connection
        }
        guard (200..<300).contains(response.http.statusCode) else { throw Failure.http(response.http.statusCode) }
        return provider == .openRouter
            ? try parseOpenRouter(response.data, now: now)
            : try parseModelIDs(response.data, provider: provider, now: now)
    }
}
