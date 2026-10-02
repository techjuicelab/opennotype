import Foundation

/// A bounded, text-free summary of verified repair outcomes for one provider and model.
/// It contains no transcript, corrected sentence, dictionary spelling, or secret.
public struct JevLearningLesson: Codable, Equatable, Sendable {
    public let provider: AIProvider
    public let model: String
    public private(set) var occurrences: [JevRepairIssue: Int]

    public init(provider: AIProvider, model: String, occurrences: [JevRepairIssue: Int]) {
        self.provider = provider
        self.model = model
        self.occurrences = occurrences
    }

    public var issues: [JevRepairIssue] {
        JevRepairIssue.allCases.filter { (occurrences[$0] ?? 0) > 0 }.sorted {
            if occurrences[$0] != occurrences[$1] { return occurrences[$0, default: 0] > occurrences[$1, default: 0] }
            return JevRepairIssue.allCases.firstIndex(of: $0)! < JevRepairIssue.allCases.firstIndex(of: $1)!
        }
    }

    mutating func record(_ issues: [JevRepairIssue]) {
        for issue in Set(issues) {
            let prior = min(JevLearningMemory.maximumOccurrences, max(0, occurrences[issue, default: 0]))
            occurrences[issue] = prior == JevLearningMemory.maximumOccurrences ? prior : prior + 1
        }
    }
}

/// Only verified issue kinds are carried into a later prompt. Specific words still
/// require the separate, user-approved personal dictionary workflow.
public enum JevLearningMemory {
    public static let maximumModelContexts = 24
    public static let maximumModelIDLength = 200
    public static let maximumOccurrences = 65_535

    /// Provider model IDs use a narrow grammar so prose, URLs, or a copied credential
    /// cannot accidentally become a persistent lesson context.
    public static func normalizedModelID(_ model: String) -> String? {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= maximumModelIDLength,
              !value.contains("://"), !value.hasPrefix("sk-"), !value.hasPrefix("gsk_") else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              value.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else { return nil }
        return value
    }

    public static func issues(in lessons: [JevLearningLesson], provider: AIProvider, model: String) -> [JevRepairIssue] {
        guard let model = normalizedModelID(model) else { return [] }
        return lessons.first { $0.provider == provider && $0.model == model }?.issues ?? []
    }

    /// Recording refreshes one context's position; the least recently repaired context
    /// is discarded at the fixed limit. One repair counts each issue kind only once.
    public static func recording(_ issues: [JevRepairIssue], provider: AIProvider, model: String,
                                 in lessons: [JevLearningLesson]) -> [JevLearningLesson] {
        guard let model = normalizedModelID(model), !issues.isEmpty else { return lessons }
        var next = lessons
        let index = next.firstIndex { $0.provider == provider && $0.model == model }
        var lesson = index.map { next.remove(at: $0) } ?? .init(provider: provider, model: model, occurrences: [:])
        lesson.record(issues)
        next.insert(lesson, at: 0)
        return Array(next.prefix(maximumModelContexts))
    }

    static func validates(_ lessons: [JevLearningLesson]) -> Bool {
        guard lessons.count <= maximumModelContexts else { return false }
        var contexts = Set<String>()
        for lesson in lessons {
            guard normalizedModelID(lesson.model) == lesson.model,
                  !lesson.occurrences.isEmpty,
                  lesson.occurrences.count <= JevRepairIssue.allCases.count,
                  lesson.occurrences.values.allSatisfy({ (1...maximumOccurrences).contains($0) }),
                  contexts.insert(lesson.provider.rawValue + "\n" + lesson.model).inserted else { return false }
        }
        return true
    }
}
