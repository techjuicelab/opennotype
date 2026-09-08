import Foundation

/// AppModel appends newly registered, learned, and edited entries to the stored array.
/// Preserve that recency signal: creation dates do not change when a term is edited.
enum DictionaryHints {
    static func select(_ entries: [DictionaryEntry], limit: Int,
                       transcript: String = "", context: String? = nil) -> [DictionaryEntry] {
        guard limit > 0 else { return [] }
        let speech = normalized(transcript)
        let surroundingText = normalized(context ?? "")
        return entries.enumerated().compactMap { index, entry -> (Int, Int, DictionaryEntry)? in
            let spellings = [entry.spoken, entry.written].map(normalized)
            guard spellings.allSatisfy({ !$0.isEmpty }) else { return nil }
            let relevance = spellings.contains(where: { contains($0, in: speech) }) ? 2
                : spellings.contains(where: { contains($0, in: surroundingText) }) ? 1 : 0
            return (relevance, index, entry)
        }.sorted {
            $0.0 == $1.0 ? $0.1 > $1.1 : $0.0 > $1.0
        }.prefix(limit).map { $0.2 }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func contains(_ term: String, in text: String) -> Bool {
        guard !term.isEmpty, !text.isEmpty else { return false }
        var start = text.startIndex
        while start < text.endIndex, let range = text.range(of: term, range: start..<text.endIndex) {
            // A Latin identifier must not match inside another one (rain ≠ train).
            // Korean particles may directly follow Latin terms: API는, rain일 때.
            let leftIsWord = range.lowerBound > text.startIndex && asciiWord(text[text.index(before: range.lowerBound)])
            let rightIsWord = range.upperBound < text.endIndex && asciiWord(text[range.upperBound])
            if !(term.first.map(asciiWord) == true && leftIsWord)
                && !(term.last.map(asciiWord) == true && rightIsWord) { return true }
            start = text.index(after: range.lowerBound)
        }
        return false
    }

    private static func asciiWord(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value else { return false }
        return (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value) || value == 95
    }
}
