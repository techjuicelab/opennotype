import Foundation

public enum WritingProfileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case general, conversation, notes, development, email

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: L("일반", "General")
        case .conversation: L("대화", "Conversation")
        case .notes: L("메모", "Notes")
        case .development: L("개발", "Development")
        case .email: L("이메일", "Email")
        }
    }
}

public enum WritingTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case preserve, casual, polite, formal

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .preserve: L("말한 말투 유지", "Preserve spoken tone")
        case .casual: L("편한 반말", "Casual")
        case .polite: L("자연스러운 존댓말", "Polite")
        case .formal: L("격식 있는 존댓말", "Formal")
        }
    }
}

public struct WritingProfile: Codable, Equatable, Sendable {
    public var kind: WritingProfileKind
    public var tone: WritingTone

    public init(kind: WritingProfileKind = .general, tone: WritingTone = .preserve) {
        self.kind = kind
        self.tone = tone
    }

    // Exact app identities only: an app's category does not reveal its recipient or website.
    private static let defaultKinds: [String: WritingProfileKind] = [
        "com.openai.codex": .development,
        "com.google.antigravity": .development,
        "com.microsoft.VSCode": .development,
        "com.microsoft.VSCodeInsiders": .development,
        "com.kakao.KakaoTalkMac": .conversation,
        "ru.keepcoder.Telegram": .conversation,
        "com.hnc.Discord": .conversation,
        "com.tinyspeck.slackmacgap": .conversation,
        "com.apple.Notes": .notes,
        "notion.id": .notes,
        "md.obsidian": .notes,
        "com.apple.mail": .email,
        "com.anthropic.claudefordesktop": .general,
        "com.google.Chrome": .general
    ]

    public static var knownAppBundleIDs: [String] { defaultKinds.keys.sorted() }

    public static func defaultForApp(bundleID: String?) -> WritingProfile {
        guard let bundleID, let kind = defaultKinds[bundleID] else { return .init() }
        return .init(kind: kind)
    }
}
