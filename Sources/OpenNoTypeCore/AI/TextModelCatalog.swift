import Foundation

/// Standard text-token rates for comparing models before a request.
/// These prices do not replace provider-reported usage costs or routing-specific billing.
public struct TextModelPrice: Equatable, Sendable {
    public let inputUSDPerMillion: Double
    public let outputUSDPerMillion: Double
    public let asOf: String
    public let sourceURL: URL

    public init(inputUSDPerMillion: Double, outputUSDPerMillion: Double, asOf: String, sourceURL: URL) {
        self.inputUSDPerMillion = inputUSDPerMillion
        self.outputUSDPerMillion = outputUSDPerMillion
        self.asOf = asOf
        self.sourceURL = sourceURL
    }
}

public struct TextModelCatalogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let price: TextModelPrice
    public let note: String?

    public init(id: String, title: String, price: TextModelPrice, note: String? = nil) {
        self.id = id
        self.title = title
        self.price = price
        self.note = note
    }
}

/// A curated public catalog, not an account-specific availability or quality guarantee.
/// Free, preview, automatic-router and coding-only models are intentionally excluded.
public enum TextModelCatalog {
    public static let checkedAt = "2026-10-01"

    public static func entries(for provider: AIProvider) -> [TextModelCatalogEntry] {
        switch provider {
        case .openRouter: openRouter
        case .groq: groq
        default: []
        }
    }

    public static func entry(id: String, provider: AIProvider) -> TextModelCatalogEntry? {
        entries(for: provider).first { $0.id == id }
    }

    private static let groq = [
        entry("openai/gpt-oss-120b", "GPT OSS 120B", input: 0.15, output: 0.60,
              source: "https://console.groq.com/docs/models"),
        entry("openai/gpt-oss-20b", "GPT OSS 20B", input: 0.075, output: 0.30,
              source: "https://console.groq.com/docs/models")
    ]

    private static let openRouter: [TextModelCatalogEntry] = [
        entry("openai/gpt-6-luna", "GPT-6 Luna", input: 0.10, output: 0.50,
              note: "합성 문장 16개 비교에서 한영 표기·의미 보존·정리 조건을 모두 충족했습니다. 실제 음성은 별도 확인이 필요합니다."),
        entry("deepseek/deepseek-v4.1-flash", "DeepSeek V4.1 Flash", input: 0.03, output: 0.50,
              note: "합성 문장 16개 비교에서 한영 표기·의미 보존·정리 조건을 모두 충족했습니다. 처리가 느릴 수 있으며, 실제 음성은 별도 확인이 필요합니다."),
        entry("qwen/qwen3.7-flash", "Qwen3.7 Flash", input: 0.03, output: 0.13,
              note: "저렴하고 빠른 비교 후보입니다. 합성 비교에서는 일부 영문 표기와 반복 정리가 남았습니다."),
        entry("qwen/qwen3.8-flash", "Qwen3.8 Flash", input: 0.15, output: 0.47),
        entry("deepseek/deepseek-v4-flash", "DeepSeek V4 Flash", input: 0.042, output: 0.084),
        entry("upstage/solar-mini4", "Solar Mini 4", input: 0.05, output: 0.20,
              note: "현재 공시 가격에는 할인이 반영되어 있습니다. 할인 종료 후 가격이 달라질 수 있습니다."),
        entry("upstage/solar-pro4", "Solar Pro 4", input: 0.09, output: 0.36,
              note: "현재 공시 가격에는 할인이 반영되어 있습니다. 할인 종료 후 가격이 달라질 수 있습니다."),
        entry("xiaomi/mimo-v2.6-flash", "MiMo V2.6 Flash", input: 0.14, output: 0.28),
        entry("z-ai/glm-5.3-flash", "GLM 5.3 Flash", input: 0.15, output: 0.50,
              note: "추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다."),
        entry("google/gemini-3.5-flash-lite", "Gemini 3.5 Flash Lite", input: 0.30, output: 2.50,
              note: "추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다."),
        entry("google/gemini-3.1-flash-lite", "Gemini 3.1 Flash Lite", input: 0.25, output: 1.50),
        entry("google/gemma-4-26b-a4b-it", "Gemma 4 26B A4B", input: 0.0765, output: 0.255),
        entry("google/gemma-4-31b-it", "Gemma 4 31B", input: 0.09, output: 0.34),
        entry("openai/gpt-oss-120b", "GPT OSS 120B", input: 0.037, output: 0.17),
        entry("openai/gpt-oss-20b", "GPT OSS 20B", input: 0.018, output: 0.09),
        entry("qwen/qwen3-30b-a3b-instruct-2507", "Qwen3 30B Instruct", input: 0.10, output: 0.30),
        entry("cohere/command-a-plus", "Command A+", input: 0.30, output: 1.50),
        entry("mistralai/mistral-small-2603", "Mistral Small 4", input: 0.15, output: 0.60),
        entry("inclusionai/ling-3.0-flash", "Ling 3.0 Flash", input: 0.021, output: 0.063,
              note: "현재 공시 가격에는 할인이 반영되어 있습니다. 할인 종료 후 가격이 달라질 수 있습니다."),
        entry("openai/gpt-4.1-mini", "GPT-4.1 Mini", input: 0.40, output: 1.60)
    ]

    private static func entry(_ id: String, _ title: String, input: Double, output: Double,
                              source: String = "https://openrouter.ai/api/v1/models", note: String? = nil) -> TextModelCatalogEntry {
        TextModelCatalogEntry(id: id, title: title,
            price: TextModelPrice(inputUSDPerMillion: input, outputUSDPerMillion: output,
                                  asOf: checkedAt, sourceURL: URL(string: source)!), note: note)
    }
}
