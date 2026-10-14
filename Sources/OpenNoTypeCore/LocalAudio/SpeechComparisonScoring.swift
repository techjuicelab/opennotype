import Foundation

public struct SpeechComparisonScore: Equatable, Sendable {
    public let edits: Int
    public let referenceScalars: Int
    public let recognizedScalars: Int
    /// Insertions can make CER exceed 100%. An empty reference has no defined CER.
    public var characterErrorRate: Double? {
        referenceScalars == 0 ? nil : Double(edits) / Double(referenceScalars)
    }
}

public enum SpeechComparisonScoringError: LocalizedError, Sendable {
    case tooLong

    public var errorDescription: String? {
        L("비교 문장은 공백을 제외하고 각각 8,000자 이내로 입력해 주세요.",
          "Keep each comparison text within 8,000 Unicode scalars excluding whitespace.")
    }
}

/// Unicode-scalar Levenshtein distance after canonical composition and whitespace
/// removal. Punctuation, case, numbers, and identifiers remain part of the comparison.
public enum SpeechComparisonScoring {
    public static let maximumScalars = 8_000

    public static func score(reference: String, recognized: String) throws -> SpeechComparisonScore {
        let reference = scalars(reference), recognized = scalars(recognized)
        guard reference.count <= maximumScalars, recognized.count <= maximumScalars else {
            throw SpeechComparisonScoringError.tooLong
        }
        // Keep only one DP row, using the shorter text for its width.
        let columns = reference.count <= recognized.count ? reference : recognized
        let rows = reference.count <= recognized.count ? recognized : reference
        var previous = Array(0...columns.count)
        for (rowIndex, row) in rows.enumerated() {
            try Task.checkCancellation()
            var current = [Int](repeating: 0, count: columns.count + 1)
            current[0] = rowIndex + 1
            for (columnIndex, column) in columns.enumerated() {
                let substitution = previous[columnIndex] + (row == column ? 0 : 1)
                current[columnIndex + 1] = min(substitution,
                    min(previous[columnIndex + 1] + 1, current[columnIndex] + 1))
            }
            previous = current
        }
        return .init(edits: previous[columns.count], referenceScalars: reference.count,
                     recognizedScalars: recognized.count)
    }

    /// A visible review aid only; Korean number words still need human review.
    public static func numericFragments(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\p{N}+(?:[.,:/-]\p{N}+)*"#) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func scalars(_ text: String) -> [Unicode.Scalar] {
        let compact = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        })).precomposedStringWithCanonicalMapping
        return Array(compact.unicodeScalars.prefix(maximumScalars + 1))
    }
}
