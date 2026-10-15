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
    private static let openAICheckedAt = "2026-10-15"
    private static let anthropicCheckedAt = "2026-10-15"

    public static func entries(for provider: AIProvider) -> [TextModelCatalogEntry] {
        let models: [TextModelCatalogEntry] = switch provider {
        case .openAI: openAI
        case .openRouter: openRouter
        case .groq: groq
        case .anthropic: anthropic
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

    private static var openAI: [TextModelCatalogEntry] { [
        openAIEntry("gpt-6-luna", "GPT-6 Luna", input: 0.10, output: 0.50),
        openAIEntry("gpt-5.4-nano", "GPT-5.4 Nano", input: 0.20, output: 1.25,
                    note: L("OpenAI API 지원 종료 예정일은 2027-04-01입니다.", "OpenAI API support is scheduled to end on 2027-04-01.")),
        openAIEntry("gpt-4.1-mini", "GPT-4.1 Mini", input: 0.40, output: 1.60,
                    note: L("OpenAI API 지원 종료 예정일은 2027-01-14입니다.", "OpenAI API support is scheduled to end on 2027-01-14.")),
        openAIEntry("gpt-4.1", "GPT-4.1", input: 2.00, output: 8.00,
                    note: L("OpenAI API 지원 종료 예정일은 2027-01-14입니다.", "OpenAI API support is scheduled to end on 2027-01-14.")),
        openAIEntry("gpt-6-sol", "GPT-6 Sol", input: 2.00, output: 10.00),
        openAIEntry("gpt-6.1-sol", "GPT-6.1 Sol", input: 2.00, output: 10.00,
                    note: L("추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다.", "Reasoning cannot be disabled for this model. Reasoning tokens may increase cost and processing time.")),
        openAIEntry("gpt-6-astra", "GPT-6 Astra", input: 10.00, output: 50.00,
                    note: L("추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다.", "Reasoning cannot be disabled for this model. Reasoning tokens may increase cost and processing time."))
    ] }

    private static func openAIEntry(_ id: String, _ title: String, input: Double, output: Double,
                                    note: String? = nil) -> TextModelCatalogEntry {
        entry(id, title, input: input, output: output,
              source: "https://developers.openai.com/api/docs/pricing", asOf: openAICheckedAt, note: note)
    }

    private static var anthropic: [TextModelCatalogEntry] { [
        anthropicEntry("claude-haiku-4-5-20251001", "Claude Haiku 4.5", input: 1, output: 5,
            note: L("현재 기본값인 이전 세대 모델입니다. 새 모델을 선택해도 기존 기본값은 자동으로 바뀌지 않습니다.", "A legacy model and the existing default. Adding newer choices does not automatically change the default.")),
        anthropicEntry("claude-sonnet-4-6", "Claude Sonnet 4.6", input: 3, output: 15,
            note: L("현재 사용 가능한 이전 세대 모델입니다.", "An available legacy model.")),
        anthropicEntry("claude-opus-4-6", "Claude Opus 4.6", input: 5, output: 25,
            note: L("현재 사용 가능한 이전 세대 모델입니다.", "An available legacy model.")),
        anthropicEntry("claude-haiku-5-5", "Claude Haiku 5.5", input: 0.10, output: 0.50,
            note: L("메뉴 가격은 입력 100,000토큰 이하 기준입니다. 캐시 읽기·쓰기를 포함한 전체 입력이 이를 초과하면 입력 $0.50·출력 $2.50/100만 토큰입니다. 기본 적응형 추론으로 처리 시간과 비용이 늘어날 수 있습니다.", "Menu prices apply to prompts up to 100,000 tokens. Above that total, including cache reads and writes, input is $0.50 and output $2.50 per million tokens. Default adaptive thinking may increase time and cost.")),
        anthropicEntry("claude-sonnet-5-5", "Claude Sonnet 5.5", input: 2, output: 10,
            note: L("기본 적응형 추론을 사용합니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다.", "Uses adaptive thinking by default. Thinking tokens may increase cost and processing time.")),
        anthropicEntry("claude-opus-5-5", "Claude Opus 5.5", input: 4, output: 20,
            note: L("추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다.", "Thinking cannot be disabled for this model. Thinking tokens may increase cost and processing time.")),
        anthropicEntry("claude-fable-5-1", "Claude Fable 5.1", input: 10, output: 50,
            note: L("추론을 끌 수 없는 모델입니다. 추론 토큰에 따라 비용과 처리 시간이 늘어날 수 있습니다.", "Thinking cannot be disabled for this model. Thinking tokens may increase cost and processing time."))
    ] }

    private static func anthropicEntry(_ id: String, _ title: String, input: Double, output: Double,
                                       note: String? = nil) -> TextModelCatalogEntry {
        entry(id, title, input: input, output: output,
              source: "https://platform.claude.com/docs/en/about-claude/pricing", asOf: anthropicCheckedAt, note: note)
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
