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
    private static let openRouterCheckedAt = "2026-10-06"

    public static func entries(for provider: AIProvider) -> [TextModelCatalogEntry] {
        let models: [TextModelCatalogEntry] = switch provider {
        case .openRouter: openRouter
        case .groq: groq
        default: []
        }
        // Compare equal input/output token counts; actual request proportions vary.
        return models.sorted {
            let lhs = $0.price.inputUSDPerMillion + $0.price.outputUSDPerMillion
            let rhs = $1.price.inputUSDPerMillion + $1.price.outputUSDPerMillion
            if lhs != rhs { return lhs < rhs }
            if $0.price.inputUSDPerMillion != $1.price.inputUSDPerMillion {
                return $0.price.inputUSDPerMillion < $1.price.inputUSDPerMillion
            }
            return $0.id < $1.id
        }
    }

    public static func entry(id: String, provider: AIProvider) -> TextModelCatalogEntry? {
        entries(for: provider).first { $0.id == id }
    }

    private static let groq = [
        entry("openai/gpt-oss-120b", "GPT OSS 120B", input: 0.15, output: 0.60,
              source: "https://console.groq.com/docs/models", asOf: checkedAt),
        entry("openai/gpt-oss-20b", "GPT OSS 20B", input: 0.075, output: 0.30,
              source: "https://console.groq.com/docs/models", asOf: checkedAt)
    ]

    private static var openRouter: [TextModelCatalogEntry] { [
        entry("openai/gpt-6-luna", "GPT-6 Luna", input: 0.10, output: 0.50,
              note: L("이전 한영 혼합 받아쓰기의 합성 16문장 비교에서 표기·의미 보존·정리 조건을 충족했습니다. 번역과 실제 음성 품질은 별도 확인이 필요합니다.", "Met spelling, meaning preservation, and cleanup criteria in an earlier comparison of 16 synthetic Korean-English dictation texts. Translation and real speech quality need separate testing.")),
        entry("deepseek/deepseek-v4.1-flash", "DeepSeek V4.1 Flash", input: 0.003, output: 2.40,
              note: L("이전 한영 혼합 받아쓰기의 합성 16문장 비교에서 표기·의미 보존·정리 조건을 충족했습니다. 당시 비교에서는 처리가 더 느렸으며, 번역과 실제 음성 품질은 별도 확인이 필요합니다.", "Met spelling, meaning preservation, and cleanup criteria in an earlier comparison of 16 synthetic Korean-English dictation texts. Processing was slower in that comparison; translation and real speech quality need separate testing.")),
        entry("qwen/qwen3.7-flash", "Qwen3.7 Flash", input: 0.03, output: 0.13,
              note: L("이전 한영 혼합 받아쓰기의 합성 비교에서 일부 영문 표기와 반복 정리가 남았습니다. 번역 품질과는 별도의 결과입니다.", "Some English spellings and repetitions were left unchanged in an earlier synthetic Korean-English dictation comparison. This is separate from translation quality.")),
        entry("qwen/qwen3.8-flash", "Qwen3.8 Flash", input: 0.15, output: 0.47),
        entry("deepseek/deepseek-v4-flash", "DeepSeek V4 Flash", input: 0.0106, output: 1.28),
        entry("upstage/solar-mini4", "Solar Mini 4", input: 0.05, output: 0.20,
              note: L("현재 공시 가격에는 할인이 반영되어 있습니다. 할인 종료 후 가격이 달라질 수 있습니다.", "Published prices currently include a discount and may change when it ends.")),
        entry("upstage/solar-pro4", "Solar Pro 4", input: 0.09, output: 0.36,
              note: L("현재 공시 가격에는 할인이 반영되어 있습니다. 할인 종료 후 가격이 달라질 수 있습니다.", "Published prices currently include a discount and may change when it ends.")),
        entry("xiaomi/mimo-v2.6-flash", "MiMo V2.6 Flash", input: 0.14, output: 0.28),
        entry("z-ai/glm-5.3-flash", "GLM 5.3 Flash", input: 0.15, output: 0.50,
              note: L("추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다.", "Reasoning cannot be disabled for this model. Reasoning tokens may increase cost and processing time.")),
        entry("google/gemini-3.5-flash-lite", "Gemini 3.5 Flash Lite", input: 0.30, output: 2.50,
              note: L("추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다.", "Reasoning cannot be disabled for this model. Reasoning tokens may increase cost and processing time.")),
        entry("google/gemini-3.1-flash-lite", "Gemini 3.1 Flash Lite", input: 0.25, output: 1.50),
        entry("google/gemma-4-26b-a4b-it", "Gemma 4 26B A4B", input: 0.0765, output: 0.255),
        entry("google/gemma-4-31b-it", "Gemma 4 31B", input: 0.09, output: 0.34),
        entry("openai/gpt-oss-120b", "GPT OSS 120B", input: 0.037, output: 0.17),
        entry("openai/gpt-oss-20b", "GPT OSS 20B", input: 0.018, output: 0.09),
        entry("qwen/qwen3-30b-a3b-instruct-2507", "Qwen3 30B Instruct", input: 0.10, output: 0.30),
        entry("cohere/command-a-plus", "Command A+", input: 0.30, output: 1.50),
        entry("mistralai/mistral-small-2603", "Mistral Small 4", input: 0.15, output: 0.60),
        entry("inclusionai/ling-3.0-flash", "Ling 3.0 Flash", input: 0.021, output: 0.063,
              note: L("현재 공시 가격에는 할인이 반영되어 있습니다. 할인 종료 후 가격이 달라질 수 있습니다.", "Published prices currently include a discount and may change when it ends.")),
        entry("openai/gpt-4.1-mini", "GPT-4.1 Mini", input: 0.40, output: 1.60)
    ] }

    private static func entry(_ id: String, _ title: String, input: Double, output: Double,
                              source: String = "https://openrouter.ai/api/v1/models",
                              asOf: String = openRouterCheckedAt, note: String? = nil) -> TextModelCatalogEntry {
        TextModelCatalogEntry(id: id, title: title,
            price: TextModelPrice(inputUSDPerMillion: input, outputUSDPerMillion: output,
                                  asOf: asOf, sourceURL: URL(string: source)!), note: note)
    }
}
