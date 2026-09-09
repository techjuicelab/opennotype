import Foundation

public enum WritingProfileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case general, conversation, notes, development, email

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: "일반"
        case .conversation: "대화"
        case .notes: "메모"
        case .development: "개발"
        case .email: "이메일"
        }
    }
}

public enum WritingTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case preserve, casual, polite, formal

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .preserve: "말한 말투 유지"
        case .casual: "편한 반말"
        case .polite: "자연스러운 존댓말"
        case .formal: "격식 있는 존댓말"
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
