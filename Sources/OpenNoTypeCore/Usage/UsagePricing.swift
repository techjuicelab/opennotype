import Foundation

/// An intentionally small, verified public-price catalog for the app's default models.
/// Account discounts, credit purchases, tax, and unreported requests are outside this estimate.
public enum UsagePricing {
    public static let checkedAt = "2026-09-10"
    public static let openAIURL = "https://developers.openai.com/api/docs/pricing"
    public static let groqURL = "https://console.groq.com/docs/models"
    public static let anthropicURL = "https://platform.claude.com/docs/en/about-claude/pricing"
    public static let openRouterURL = "https://openrouter.ai/docs/cookbook/administration/usage-accounting"
    public static let typeSafeURL = "https://docs.typesafe.ai/models"
    public static let typeSafeCheckedAt = "2026-10-01"

    public static func cost(for usage: ProviderUsage) -> UsageCost {
        if usage.decisionProvider == .typeSafe { return typeSafeCost(for: usage) }
        guard let provider = usage.provider ?? (usage.decisionProvider == .openRouter ? .openRouter : nil) else {
            return UsageCost(kind: .local, usd: 0, note: L("이 Mac에서 처리했습니다. API 비용만 0이며 전력·기기 비용은 포함하지 않습니다.", "Processed on this Mac. API cost is zero; electricity and hardware costs are not included."))
        }
        if let reported = usage.providerCostUSD, reported.isFinite, reported >= 0 {
            return UsageCost(kind: .providerReported, usd: reported,
                             sourceURL: provider == .openRouter ? openRouterURL : source(for: provider),
                             checkedAt: checkedAt, note: L("이 요청의 API 응답에 보고된 금액입니다. 계정 전체 청구액은 공급자에서 확인하세요.", "The amount reported in this API response. Check your provider for total account charges."))
        }
        guard usage.outcome == .responseReceived else {
            return unavailable(L("실패·취소 요청의 실제 청구 여부를 확인할 수 없습니다.", "Charges for failed or cancelled requests could not be confirmed."), provider: provider)
        }
        guard usage.httpStatus.map({ (200..<300).contains($0) }) ?? true else {
            return unavailable(L("정상 응답이 아니어서 비용을 추정하지 않았습니다.", "No cost estimate is available because the response was unsuccessful."), provider: provider)
        }
        if provider == .openRouter {
            return unavailable(L("공급자 보고 금액이 없습니다. OpenRouter 경로별 가격을 임의로 추정하지 않습니다.", "The provider did not report a cost. Prices for individual OpenRouter routes are not estimated."), provider: provider)
        }
        let model = usage.effectiveModel
        if usage.stage == .transcription {
            let rate: UsageRate
            let source: String
            switch (provider, model) {
            case (.openAI, "gpt-transcribe"):
                rate = UsageRate(audioPerMinute: 0.0045)
                source = "https://developers.openai.com/api/docs/models/gpt-transcribe"
            case (.openAI, "whisper-1"):
                rate = UsageRate(audioPerMinute: 0.006)
                source = "https://developers.openai.com/api/docs/models/whisper-1"
            case (.groq, "whisper-large-v3-turbo"):
                rate = UsageRate(audioPerMinute: 0.04 / 60, minimumAudioSeconds: 10)
                source = "https://console.groq.com/docs/speech-to-text"
            case (.groq, "whisper-large-v3"):
                rate = UsageRate(audioPerMinute: 0.111 / 60, minimumAudioSeconds: 10)
                source = "https://console.groq.com/docs/speech-to-text"
            default:
                return unavailable(L("이 음성 모델의 과금 단위·가격을 확인하지 못했습니다. 토큰 기반 음성 모델은 시간만으로 환산하지 않습니다.", "Pricing for this speech model could not be verified. Token-based speech costs cannot be estimated from duration alone."), provider: provider)
            }
            guard let seconds = usage.audioSeconds, seconds.isFinite, seconds > 0 else {
                return unavailable(L("요청한 음성 길이를 확인할 수 없습니다.", "The audio duration could not be verified."), provider: provider)
            }
            let billedSeconds = max(seconds, rate.minimumAudioSeconds ?? 0)
            return UsageCost(kind: .estimated, usd: billedSeconds / 60 * rate.audioPerMinute!, sourceURL: source,
                             checkedAt: checkedAt,
                             note: rate.minimumAudioSeconds == nil ? L("음성 길이와 공개 분당 요금으로 추정했습니다.", "Estimated from audio duration and the published per-minute price.") : L("음성 길이와 공개 요금으로 추정했습니다. 요청당 최소 10초 과금을 반영했습니다.", "Estimated from audio duration and published pricing, including the 10-second minimum charge per request."),
                             rateSnapshot: rate)
        }
        guard let input = usage.inputTokens, input >= 0, let output = usage.outputTokens, output >= 0,
              (usage.cachedInputTokens ?? 0) >= 0, (usage.cacheWriteTokens ?? 0) == 0,
              (usage.audioInputTokens ?? 0) == 0, (usage.reasoningTokens ?? 0) >= 0,
              (usage.reasoningTokens ?? 0) <= output else {
            return unavailable(L("토큰 내역이 없거나 별도 과금 항목을 정확히 구분할 수 없습니다.", "Token details are missing or separately billed items could not be identified."), provider: provider)
        }
        let rate: UsageRate
        let source: String
        switch (provider, model) {
        case (.openAI, "gpt-4.1-mini"), (.openAI, "gpt-4.1-mini-2025-04-14"):
            rate = UsageRate(inputPerMillion: 0.40, outputPerMillion: 1.60, cachedInputPerMillion: 0.10)
            source = "https://developers.openai.com/api/docs/models/gpt-4.1-mini"
        case (.groq, "openai/gpt-oss-120b"):
            rate = UsageRate(inputPerMillion: 0.15, outputPerMillion: 0.60, cachedInputPerMillion: 0.075,
                             additionalSourceURLs: ["https://console.groq.com/docs/prompt-caching"])
            source = groqURL
        case (.groq, "openai/gpt-oss-20b"):
            rate = UsageRate(inputPerMillion: 0.075, outputPerMillion: 0.30, cachedInputPerMillion: 0.0375,
                             additionalSourceURLs: ["https://console.groq.com/docs/prompt-caching"])
            source = groqURL
        case (.anthropic, "claude-haiku-4-5"), (.anthropic, "claude-haiku-4-5-20251001"):
            rate = UsageRate(inputPerMillion: 1, outputPerMillion: 5, cachedInputPerMillion: 0.10)
            source = anthropicURL
        case (.anthropic, "claude-sonnet-4-5"), (.anthropic, "claude-sonnet-4-5-20250929"), (.anthropic, "claude-sonnet-4-6"):
            // Premium long-context tiers differ for older models, so do not extrapolate them.
            guard model == "claude-sonnet-4-6" || Double(input) + Double(usage.cachedInputTokens ?? 0) <= 200_000 else {
                return unavailable(L("이 모델의 긴 문맥 과금 조건을 확인할 수 없습니다.", "Long-context pricing for this model could not be verified."), provider: provider)
            }
            rate = UsageRate(inputPerMillion: 3, outputPerMillion: 15, cachedInputPerMillion: 0.30)
            source = anthropicURL
        default:
            return unavailable(L("이 모델의 현재 공개 요금을 확인하지 못했습니다.", "Current published pricing for this model could not be verified."), provider: provider)
        }
        let cached = usage.cachedInputTokens ?? 0
        // Claude input_tokens excludes its cache counters; OpenAI/Groq include cache reads in input.
        guard provider == .anthropic || cached <= input else {
            return unavailable(L("캐시 토큰과 입력 토큰의 관계가 올바르지 않습니다.", "The cached token count is inconsistent with the input token count."), provider: provider)
        }
        let uncached = provider == .anthropic ? input : input - cached
        let amount = (Double(uncached) * rate.inputPerMillion! + Double(cached) * rate.cachedInputPerMillion!
                      + Double(output) * rate.outputPerMillion!) / 1_000_000
        let cacheNote = usage.cachedInputTokens == nil ? L(" 캐시 할인 내역이 없어 표준 입력 단가로 추정했습니다.", " Standard input pricing was used because cache discount details are unavailable.") : ""
        return UsageCost(kind: .estimated, usd: amount, sourceURL: source, checkedAt: checkedAt,
                         note: L("응답 토큰과 표준 공개 요금으로 추정했습니다. 계정별 할인·세금은 포함하지 않습니다.", "Estimated from response token counts and standard published pricing. Account discounts and taxes are not included.") + cacheNote, rateSnapshot: rate)
    }

    private static func typeSafeCost(for usage: ProviderUsage) -> UsageCost {
        func unknown(_ note: String) -> UsageCost {
            UsageCost(kind: .unavailable, sourceURL: typeSafeURL, checkedAt: typeSafeCheckedAt, note: note)
        }
        guard usage.outcome == .responseReceived,
              usage.httpStatus.map({ (200..<300).contains($0) }) ?? true else {
            return unknown(L("실패·취소 요청의 실제 청구 여부를 확인할 수 없습니다.", "Charges for failed or cancelled requests could not be confirmed."))
        }
        guard usage.provider == nil, usage.stage == .decisionReview,
              usage.model == DecisionProvider.typeSafe.model,
              usage.reportedModel == DecisionProvider.typeSafe.model else {
            return unknown(L("이 TypeSafe 요청의 모델·공개 요금을 확인할 수 없습니다.", "The model or published pricing for this TypeSafe request could not be verified."))
        }
        guard let input = usage.inputTokens, input >= 0, let output = usage.outputTokens, output >= 0 else {
            return unknown(L("응답 토큰 내역이 없어 비용을 추정할 수 없습니다.", "Cost cannot be estimated without response token counts."))
        }
        // TypeSafe documents input-token pricing and free output, but no response cost field.
        let rate = UsageRate(inputPerMillion: 0.042, outputPerMillion: 0)
        return UsageCost(kind: .estimated, usd: Double(input) * 0.042 / 1_000_000,
                         sourceURL: typeSafeURL, checkedAt: typeSafeCheckedAt,
                         note: L("TypeSafe 입력 토큰과 공개 요금으로 추정했습니다. 출력 토큰은 무료이며 실제 청구액은 공급자에서 확인하세요.", "Estimated from TypeSafe input tokens and published pricing. Output tokens are free. Check your provider for actual charges."),
                         rateSnapshot: rate)
    }

    private static func source(for provider: AIProvider) -> String {
        switch provider { case .openAI: openAIURL; case .groq: groqURL; case .anthropic: anthropicURL; case .openRouter: openRouterURL }
    }
    private static func unavailable(_ note: String, provider: AIProvider) -> UsageCost {
        UsageCost(kind: .unavailable, sourceURL: source(for: provider), checkedAt: checkedAt, note: note)
    }
}
