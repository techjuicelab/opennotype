import Foundation

public struct LearningCandidate: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var originalText: String
    public var editedText: String
    public var createdAt: Date

    public init(id: UUID = UUID(), originalText: String, editedText: String, createdAt: Date = Date()) {
        self.id = id
        self.originalText = originalText
        self.editedText = editedText
        self.createdAt = createdAt
    }
}

/// Evaluates only text supplied by the caller. It never observes keyboard events or other applications.
public enum CorrectionLearner {
    private struct Token {
        var text: String
        var range: Range<String.Index>
    }

    public static func suggestion(original: String, edited: String) -> DictionaryEntry? {
        guard original != edited, original.count <= 2_000, edited.count <= 2_000 else { return nil }
        let before = tokens(original)
        let after = tokens(edited)
        guard before.count == after.count, !before.isEmpty else { return nil }
        let changed = before.indices.filter { before[$0].text != after[$0].text }
        guard changed.count == 1, let index = changed.first else { return nil }
        let old = before[index]
        let new = after[index]
        guard String(original[..<old.range.lowerBound]) == String(edited[..<new.range.lowerBound]),
              String(original[old.range.upperBound...]) == String(edited[new.range.upperBound...]) else { return nil }
        let (from, to) = separatingSharedDigits(separatingSharedParticle(old.text, new.text))
        guard (2...24).contains(from.count), (2...24).contains(to.count),
              !isSemanticallySensitive(from), !isSemanticallySensitive(to) else { return nil }
        // Script changes are explicit user spelling corrections at exactly one location.
        // Keep any shared Korean particle out of the learned dictionary entry.
        let changesScript = isHangul(from) && isLatin(to) || isLatin(from) && isHangul(to)
        if changesScript { return DictionaryEntry(spoken: from, written: to, learned: true) }
        if isEmbeddedDigitNameCorrection(from, to) {
            return DictionaryEntry(spoken: from, written: to, learned: true)
        }
        let distance = editDistance(Array(from.lowercased()), Array(to.lowercased()))
        // A short replacement can change meaning even at edit distance one; Latin lexical
        // changes require a distinctive identifier/proper-name spelling signal.
        if isLatin(from) && isLatin(to) {
            let hasNameSignal = from.contains(where: \.isUppercase) || to.contains(where: \.isUppercase)
            guard hasNameSignal else { return nil }
        } else { return nil }
        guard distance <= 1 || min(from.count, to.count) >= 7 && distance <= 2 else { return nil }
        return DictionaryEntry(spoken: from, written: to, learned: true)
    }

    private static func isLatin(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-'’").contains($0) }
    }

    private static func isHangul(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }

    private static func isEmbeddedDigitNameCorrection(_ original: String, _ edited: String) -> Bool {
        let before = Array(original.utf8)
        let after = Array(edited.utf8)
        guard (4...24).contains(before.count), before.count == after.count,
              after.allSatisfy({ (65...90).contains($0) }) else { return false }
        let changed = before.indices.filter { before[$0] != after[$0] }
        guard changed.count == 1, let index = changed.first,
              index > 0, index < before.count - 1,
              (48...57).contains(before[index]) else { return false }
        // A single internal digit misrecognized inside an uppercase name is narrow enough
        // to learn. Keep trailing version numbers, mixed-case IDs and other edits for review.
        return true
    }

    /// "아이폰15" → "iPhone15": a trailing (or leading) digit run shared by both tokens is not part of the
    /// spelling being corrected, so it is removed before the script and name checks.
    private static func separatingSharedDigits(_ original: String, _ edited: String) -> (String, String) {
        func digitSuffix(_ text: String) -> String { String(text.reversed().prefix { $0.isNumber }.reversed()) }
        func digitPrefix(_ text: String) -> String { String(text.prefix { $0.isNumber }) }
        let suffix = digitSuffix(original)
        if !suffix.isEmpty, suffix == digitSuffix(edited), suffix.count < original.count, suffix.count < edited.count {
            return (String(original.dropLast(suffix.count)), String(edited.dropLast(suffix.count)))
        }
        let prefix = digitPrefix(original)
        if !prefix.isEmpty, prefix == digitPrefix(edited), prefix.count < original.count, prefix.count < edited.count {
            return (String(original.dropFirst(prefix.count)), String(edited.dropFirst(prefix.count)))
        }
        return (original, edited)
    }

    private static func separatingSharedDigits(_ pair: (String, String)) -> (String, String) {
        separatingSharedDigits(pair.0, pair.1)
    }

    private static func separatingSharedParticle(_ original: String, _ edited: String) -> (String, String) {
        let particles = ["으로부터", "에게서", "에서는", "으로는", "부터는", "까지는", "에서", "에게", "으로", "부터", "까지", "처럼", "보다", "하고", "이랑", "가", "이", "을", "를", "은", "는", "에", "와", "과", "도", "의", "로", "랑", "만"]
        for suffix in particles where original.hasSuffix(suffix) && edited.hasSuffix(suffix) {
            let before = String(original.dropLast(suffix.count))
            let after = String(edited.dropLast(suffix.count))
            // "챗지피티4로" → "ChatGPT4로": judge the script change on the stems without their shared digits.
            let (stemBefore, stemAfter) = separatingSharedDigits(before, after)
            if isHangul(stemBefore) && isLatin(stemAfter) || isLatin(stemBefore) && isHangul(stemAfter)
                || isLatin(stemBefore) && isLatin(stemAfter) || isEmbeddedDigitNameCorrection(before, after) {
                return (before, after)
            }
        }
        return (original, edited)
    }

    public static func reviewCandidate(original: String, edited: String) -> LearningCandidate? {
        guard original != edited, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              original.count <= 2_000, edited.count <= 2_000,
              suggestion(original: original, edited: edited) == nil else { return nil }
        return LearningCandidate(originalText: original, editedText: edited)
    }

    private static func tokens(_ text: String) -> [Token] {
        guard let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}]+(?:['’\\-][\\p{L}\\p{M}\\p{N}]+)*") else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return Token(text: String(text[range]), range: range)
        }
    }

    private static func isSemanticallySensitive(_ text: String) -> Bool {
        let lower = text.lowercased()
        let reserved: Set<String> = ["can", "can't", "cant", "cannot", "do", "don't", "dont", "not", "never", "no", "yes", "true", "false", "will", "won't", "wont", "may", "must", "shall", "should", "could", "would", "am", "pm", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "today", "tomorrow", "yesterday", "오전", "오후", "오늘", "내일", "어제", "확실", "아마", "절대", "금지", "허용", "가능", "불가", "찬성", "반대", "이상", "이하", "초과", "미만"]
        if reserved.contains(lower) { return true }
        let sensitivePrefixes = ["오전", "오후", "오늘", "내일", "어제", "확실", "아마", "절대", "금지", "허용", "가능", "불가", "찬성", "반대", "이상", "이하", "초과", "미만"]
        if sensitivePrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        let koreanNegations = ["않", "못", "없", "아니", "안돼", "된다", "된다면"]
        return koreanNegations.contains { lower.contains($0) }
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var row = [i + 1]
            for (j, right) in b.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = row
        }
        return previous[b.count]
    }
}
