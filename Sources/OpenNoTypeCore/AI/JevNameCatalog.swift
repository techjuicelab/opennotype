import Foundation

/// Local candidate retrieval from names the caller has explicitly approved. Similar spelling is
/// not proof of identity: every result still needs a contextual Choice and user confirmation.
public enum JevNameCatalog {
    /// Shared with callers that present a catalog editor, so unsupported entries are not silently
    /// accepted by the UI and then ignored during retrieval. Preserve the approved Unicode spelling.
    public static func normalizedCanonicalName(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard (2...100).contains(text.count), text.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
                || " .+_-()&".unicodeScalars.contains($0)
        }), text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        return text
    }

    public static func candidates(in transcript: String, canonicalNames: [String], limit: Int = 4) -> [DecisionTermCandidate] {
        guard limit > 0, !transcript.isEmpty else { return [] }
        var seenNames = Set<String>()
        let names = canonicalNames.prefix(128).compactMap { raw -> Name? in
            guard let text = normalizedCanonicalName(raw),
                  seenNames.insert(text.lowercased()).inserted else { return nil }
            return Name(text: text, latin: latin(text), skeleton: skeleton(latin(text)))
        }
        guard !names.isEmpty else { return [] }
        let spans = spans(in: String(transcript.prefix(6_000)))
        var matches: [(Double, Int, Int, String, String)] = []
        for (nameIndex, name) in names.enumerated() {
            var best: (Double, Int, String)?
            for group in spans {
                // An already-correct name followed by a Korean particle needs no proposal;
                // otherwise the unstripped variant could suggest dropping that particle.
                if group.contains(where: { $0.text == name.text }) { continue }
                for span in group {
                    guard let score = score(span, name) else { continue }
                    if best == nil || score < best!.0 || (score == best!.0 && span.offset < best!.1) {
                        best = (score, span.offset, span.text)
                    }
                }
            }
            if let best { matches.append((best.0, best.1, nameIndex, best.2, name.text)) }
        }
        matches.sort { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            return a.2 < b.2
        }
        return matches.prefix(min(limit, 4)).enumerated().map { index, item in
            .init(id: "catalog_\(index)", original: item.3, candidate: item.4)
        }
    }

    private struct Name { let text: String; let latin: String; let skeleton: String }
    private struct Span { let text: String; let offset: Int; let latin: String; let skeleton: String; let hasHangul: Bool; let includesParticle: Bool }
    private static let particles = ["으로부터", "에게서", "한테서", "이라고", "이라는", "에서는", "으로는", "으로", "에게", "한테", "에서", "처럼", "하고", "까지", "부터", "라도", "를", "을", "은", "는", "이", "가", "에", "의", "도", "로", "와", "과", "만"]

    private static func spans(in text: String) -> [[Span]] {
        guard let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}_]+") else { return [] }
        let ranges = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).prefix(128).compactMap {
            Range($0.range, in: text)
        }
        var result: [[Span]] = []
        for start in ranges.indices {
            for end in start..<min(start + 3, ranges.count) {
                if end > start {
                    let gap = text[ranges[end - 1].upperBound..<ranges[end].lowerBound]
                    guard !gap.isEmpty, gap.allSatisfy({ $0 == " " || $0 == "\t" }) else { break }
                    let previous = text[ranges[end - 1]]
                    // A particle ends a name phrase: do not shortlist "OpenNoType에 있어요".
                    if particles.contains(where: { previous.hasSuffix($0) && previous.count > $0.count + 1 }) { break }
                }
                let range = ranges[start].lowerBound..<ranges[end].upperBound
                let raw = String(text[range])
                guard raw.count <= 40, !raw.contains("_"), raw.contains(where: \.isLetter) else { continue }
                var variants = [raw]
                for suffix in particles where raw.hasSuffix(suffix) && raw.count > suffix.count + 1 {
                    variants.append(String(raw.dropLast(suffix.count)))
                }
                var seen = Set<String>()
                result.append(variants.compactMap { value in
                    guard seen.insert(value).inserted else { return nil }
                    let roman = latin(value)
                    return Span(text: value, offset: NSRange(range, in: text).location, latin: roman,
                                skeleton: skeleton(roman), hasHangul: value.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) },
                                includesParticle: variants.count > 1 && value == raw)
                })
            }
        }
        return result
    }

    private static func score(_ span: Span, _ name: Name) -> Double? {
        guard !span.latin.isEmpty, !name.latin.isEmpty else { return nil }
        let longest = max(span.latin.count, name.latin.count)
        if !span.hasHangul {
            // Short Latin words must match exactly; do not turn rain into Brain or a code token.
            guard abs(span.latin.count - name.latin.count) <= max(1, longest / 6) else { return nil }
            let distance = editDistance(span.latin, name.latin)
            guard distance == 0 || min(span.latin.count, name.latin.count) >= 5 && distance <= max(1, longest / 6) else { return nil }
            return Double(distance) / Double(longest)
        }
        // Reject impossible consonant shapes before the more expensive full edit distance.
        guard min(span.skeleton.count, name.skeleton.count) >= 2,
              abs(span.skeleton.count - name.skeleton.count) <= 1 else { return nil }
        let consonantDistance = editDistance(span.skeleton, name.skeleton)
        guard consonantDistance == 0 || min(span.skeleton.count, name.skeleton.count) >= 4 && consonantDistance == 1 else { return nil }
        let ratio = Double(editDistance(span.latin, name.latin)) / Double(longest)
        guard ratio <= (consonantDistance == 0 ? 0.65 : 0.5) else { return nil }
        return ratio + Double(consonantDistance) * 0.3 + (span.includesParticle ? 0.25 : 0)
    }

    private static func latin(_ text: String) -> String {
        (text.applyingTransform(.toLatin, reverse: false) ?? text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func skeleton(_ value: String) -> String {
        var output = ""
        for letter in value {
            if "aeiouy".contains(letter) { continue }
            let mapped: Character
            switch letter {
            case "b", "v", "f", "p": mapped = "p"
            case "l", "r": mapped = "r"
            case "c", "q", "g", "k": mapped = "k"
            default: mapped = letter
            }
            if output.last != mapped { output.append(mapped) }
        }
        return output
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let a = Array(left), b = Array(right)
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
