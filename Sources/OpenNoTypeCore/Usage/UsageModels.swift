import Foundation

public enum UsageStage: String, Codable, CaseIterable, Sendable {
    case transcription, textProcessing
    public var title: String { self == .transcription ? "음성 인식" : "문장 처리" }
}

public enum UsageOutcome: String, Codable, CaseIterable, Sendable {
    case responseReceived, failed, cancelled
    public var title: String {
        switch self { case .responseReceived: "응답 수신"; case .failed: "실패"; case .cancelled: "취소" }
    }
}

/// Numeric request metadata only. Never contains prompts, transcripts, credentials or raw audio.
public struct ProviderUsage: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    /// nil identifies an on-device operation; a cloud request always supplies its provider.
    public var provider: AIProvider?
    public var model: String
    public var reportedModel: String?
    public var stage: UsageStage
    public var outcome: UsageOutcome
    public var attempt: Int
    public var httpStatus: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedInputTokens: Int?
    public var cacheWriteTokens: Int?
    public var audioInputTokens: Int?
    public var reasoningTokens: Int?
    public var audioSeconds: Double?
    public var providerCostUSD: Double?

    public init(id: UUID = UUID(), createdAt: Date = Date(), provider: AIProvider? = nil,
                model: String, reportedModel: String? = nil, stage: UsageStage,
                outcome: UsageOutcome = .responseReceived, attempt: Int = 1, httpStatus: Int? = nil,
                inputTokens: Int? = nil, outputTokens: Int? = nil, cachedInputTokens: Int? = nil,
                cacheWriteTokens: Int? = nil, audioInputTokens: Int? = nil, reasoningTokens: Int? = nil,
                audioSeconds: Double? = nil, providerCostUSD: Double? = nil) {
        self.id = id; self.createdAt = createdAt; self.provider = provider; self.model = model
        self.reportedModel = reportedModel; self.stage = stage; self.outcome = outcome
        self.attempt = max(1, attempt); self.httpStatus = httpStatus
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens; self.cacheWriteTokens = cacheWriteTokens
        self.audioInputTokens = audioInputTokens; self.reasoningTokens = reasoningTokens
        self.audioSeconds = audioSeconds; self.providerCostUSD = providerCostUSD
    }

    public var effectiveModel: String {
        let reported = reportedModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reported.isEmpty ? model : reported
    }
}

/// Public list rates used for one estimate, in USD. Missing rates are unknown, never zero.
public struct UsageRate: Codable, Equatable, Sendable {
    public var inputPerMillion: Double?
    public var outputPerMillion: Double?
    public var cachedInputPerMillion: Double?
    public var audioPerMinute: Double?
    public var minimumAudioSeconds: Double?
    public var additionalSourceURLs: [String]?
    public init(inputPerMillion: Double? = nil, outputPerMillion: Double? = nil,
                cachedInputPerMillion: Double? = nil, audioPerMinute: Double? = nil, minimumAudioSeconds: Double? = nil,
                additionalSourceURLs: [String]? = nil) {
        self.inputPerMillion = inputPerMillion; self.outputPerMillion = outputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion; self.audioPerMinute = audioPerMinute
        self.minimumAudioSeconds = minimumAudioSeconds
        self.additionalSourceURLs = additionalSourceURLs
    }
}

public struct UsageCost: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case providerReported, estimated, local, unavailable
        public var title: String {
            switch self {
            case .providerReported: "공급자 보고"
            case .estimated: "추정"
            case .local: "로컬 · API 비용 없음"
            case .unavailable: "미확인"
            }
        }
    }
    public var kind: Kind
    public var usd: Double?
    public var sourceURL: String?
    public var checkedAt: String?
    public var note: String?
    public var rateSnapshot: UsageRate?
    public init(kind: Kind, usd: Double? = nil, sourceURL: String? = nil, checkedAt: String? = nil,
                note: String? = nil, rateSnapshot: UsageRate? = nil) {
        self.kind = kind; self.usd = usd; self.sourceURL = sourceURL; self.checkedAt = checkedAt; self.note = note
        self.rateSnapshot = rateSnapshot
    }
}

public struct UsageRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { event.id }
    public var jobID: UUID
    public var mode: InputMode
    public var isRecovery: Bool
    public var event: ProviderUsage
    /// Snapshot of the pricing used when this request was recorded; later price changes do not rewrite history.
    public var cost: UsageCost
    public init(jobID: UUID, mode: InputMode, isRecovery: Bool = false, event: ProviderUsage, cost: UsageCost? = nil) {
        self.jobID = jobID; self.mode = mode; self.isRecovery = isRecovery; self.event = event
        self.cost = cost ?? UsagePricing.cost(for: event)
    }
}
