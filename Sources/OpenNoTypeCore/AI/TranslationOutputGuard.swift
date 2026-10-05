import Foundation

/// Narrow local rejection checks, not a semantic or language-quality evaluator.
/// Ordinary quotations and quantities may translate. Ambiguous URL boundaries, clock periods,
/// mixed 24-hour speech and unsupported clock forms deliberately remain outside these checks.
enum TranslationOutputGuard {
    private enum LiteralKind { case code, quotedCode, url }
    private struct Literal {
        let value: String
        let range: NSRange
        let kind: LiteralKind
    }
    private struct URLs {
        var literals: [Literal] = []
        var hasAmbiguousUnicode = false
    }

    static func validate(source: String, output: String, targetLanguage: String) throws {
        let sourceURLs = urls(in: source), outputURLs = urls(in: output)
        let literals = protectedCode(in: source) + sourceURLs.literals
        let required = discardingAdjacentCorrections(literals, in: source)
        let outputQuotedValues = Set(quotedContents(in: output).map { Data($0.value.utf8) })
        let outputCodeValues = Set(backticks(in: output).map { Data($0.value.utf8) })
        let outputURLValues = Set(outputURLs.literals.map { Data($0.value.utf8) })
        for literal in required {
            let bytes = Data(literal.value.utf8)
            if literal.kind == .url {
                // A Hangul/Japanese suffix may be a particle or part of an international URL.
                // Do not freeze it or accept only its ASCII prefix as proof of preservation.
                if sourceURLs.hasAmbiguousUnicode || outputURLs.hasAmbiguousUnicode { continue }
                guard outputURLValues.contains(bytes) else { throw ProviderError.translationLiteralChanged }
            } else {
                guard outputQuotedValues.contains(bytes) || outputCodeValues.contains(bytes)
                    || containsDelimitedLiteral(literal.value, in: output) else {
                    throw ProviderError.translationLiteralChanged
                }
            }
        }
        let language = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["ko", "ko-kr", "korean", "한국어", "en", "en-us", "en-gb", "english", "영어",
               "english (united states)", "english (united kingdom)", "영어 (영국식)",
               "ja", "ja-jp", "japanese", "일본어"].contains(language) else { return }
        try validateClockPeriods(source: source, output: output)
    }

    private static func protectedCode(in text: String) -> [Literal] {
        let code = backticks(in: text)
        let ns = text as NSString
        let quotes = quotedContents(in: text).filter { quote in
            guard !code.contains(where: { NSIntersectionRange($0.range, quote.range).length > 0 }) else { return false }
            let before = ns.substring(with: NSRange(location: max(0, quote.range.location - 80),
                length: min(80, quote.range.location)))
            let end = NSMaxRange(quote.range)
            let after = ns.substring(with: NSRange(location: end, length: min(80, ns.length - end)))
            return matches(#"(?:\b(?:variable|identifier|function|parameter|key|field|constant)(?:\s+(?:name|named|called))?\s*|(?:변수|식별자|함수|매개변수|키|필드|상수)(?:\s*(?:이름|명))?(?:은|는|이|가|의|을|를)?\s*|(?:変数|識別子|関数|キー|フィールド|定数)(?:名|の名前)?(?:は|の)?\s*)$"#, in: before)
                || matches(#"^\s*(?:(?:이?라는|이란|인|의)\s*)?(?:변수|식별자|함수|매개변수|키|필드|상수)(?:\s*(?:이름|명))?(?:[은는이가을를의]|\s|[,.:;!?]|$)|^\s*(?:という|の)(?:変数|識別子|関数|キー|フィールド|定数)|^\s*(?:variable|identifier|function|parameter|key|field|constant)\b"#, in: after)
        }
        return code + quotes.map { Literal(value: $0.value, range: $0.range, kind: .quotedCode) }
    }

    private static func backticks(in text: String) -> [Literal] {
        captures(#"(?<!`)`([^`\n]+)`(?!`)"#, in: text).map { Literal(value: $0.value, range: $0.range, kind: .code) }
    }

    private static func quotedContents(in text: String) -> [Literal] {
        let pattern = ProtectedLiteralPatterns.quotedText + #"|「[^」\n]+」|『[^』\n]+』"#
        return captures(pattern, in: text, contentGroup: nil).map {
            Literal(value: String($0.value.dropFirst().dropLast()), range: $0.range, kind: .quotedCode)
        }
    }

    private static func urls(in text: String) -> URLs {
        var result = URLs()
        let code = backticks(in: text)
        for match in captures(#"https?://[^\s<>\"'“”‘’「」『』。，、！？]+"#, in: text, contentGroup: nil) {
            guard !code.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
            guard match.value.unicodeScalars.allSatisfy({ $0.isASCII }) else {
                result.hasAmbiguousUnicode = true; continue
            }
            var value = match.value
            while let last = value.last {
                if ".,;!?".contains(last) { value.removeLast(); continue }
                if let opening = [")": "(", "]": "[", "}": "{"][String(last)],
                   value.filter({ String($0) == String(last) }).count > value.filter({ String($0) == opening }).count {
                    value.removeLast(); continue
                }
                break
            }
            if !value.isEmpty { result.literals.append(.init(value: value, range: match.range, kind: .url)) }
        }
        return result
    }

    private static func discardingAdjacentCorrections(_ literals: [Literal], in text: String) -> [Literal] {
        let sorted = literals.sorted { $0.range.location < $1.range.location }
        let ns = text as NSString
        return sorted.enumerated().compactMap { index, literal in
            guard index + 1 < sorted.count else { return literal }
            let next = sorted[index + 1], end = NSMaxRange(literal.range)
            guard literal.kind == next.kind, end <= next.range.location else { return literal }
            let connector = ns.substring(with: NSRange(location: end, length: next.range.location - end))
            // Only a bare adjacent repair marker replaces the earlier literal. An unresolved
            // alternative, a contrast, a quoted word or an intervening clause is not a correction.
            if matches(#"^[\s,;:!?…—–-]*(?:(?:으로|로|을|를|은|는|이|가)[\s,;:!?…—–-]*)?(?:아니(?:요)?|no|sorry|i\s+mean|いや)[\s,;:!?…—–-]*$"#, in: connector) { return nil }
            // A longer explicit repair can supersede the older literal without fitting the bare
            // connector form. Do not resolve its grammar here or insist that the older value survive.
            if !matches(#"\b(?:maybe|perhaps|uncertain|not\s+sure)\b|모르|아마|일지도|かも|わから"#, in: connector),
               matches(#"\b(?:actually|i\s+mean)\b|(?:^|[\s,;:])아니(?:요)?(?=[\s,;:…])|정정|訂正|言い直"#, in: connector) { return nil }
            return literal
        }
    }

    private static func containsDelimitedLiteral(_ literal: String, in text: String) -> Bool {
        !delimitedLiteralRanges(literal, in: text).isEmpty
    }

    private static func delimitedLiteralRanges(_ literal: String, in text: String) -> [NSRange] {
        let ns = text as NSString
        var search = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []
        let quotedRanges = (quotedContents(in: text) + backticks(in: text)).map(\.range)
        while search.length > 0 {
            let found = ns.range(of: literal, options: .literal, range: search)
            guard found.location != NSNotFound, found.length > 0, let range = Range(found, in: text) else { break }
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            // Unquoted CJK adjacency may be a particle or part of a longer identifier. Opt out
            // of proving a change from that boundary alone instead of parsing target grammar.
            // Explicit quote/code bounds and Latin/digit/underscore extensions remain strict.
            let ambiguousJoin = !quotedRanges.contains { NSIntersectionRange($0, found).length > 0 }
            let leftBoundary = !isIdentifierCharacter(before)
                || (ambiguousJoin && isCJKCharacter(before))
            let rightBoundary = !isIdentifierCharacter(after)
                || (ambiguousJoin && isCJKCharacter(after))
            if leftBoundary, rightBoundary,
               Array(text[range].utf8) == Array(literal.utf8) { ranges.append(found) }
            let end = NSMaxRange(found)
            search = NSRange(location: end, length: ns.length - end)
        }
        return ranges
    }

    private static func isIdentifierCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character == "_" || character.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }
    }

    private static func isCJKCharacter(_ character: Character?) -> Bool {
        character?.unicodeScalars.contains {
            (0x1100...0x11FF).contains($0.value) || (0x3040...0x30FF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        } ?? false
    }

    private static func validateClockPeriods(source: String, output: String) throws {
        let sourcePlain = maskingCodeAndURLs(in: source)
        let outputPlain = maskingCodeAndURLs(in: output, preserving: protectedCode(in: source))
        // Explicit periods anywhere, including another clock or a discarded 24-hour value,
        // opt out conservatively: this small check does not resolve temporal coreference.
        if matches(#"오전|오후|아침|저녁|밤|정오|자정|午前|午後|正午|深夜|朝|夕方|夜|\b(?:morning|afternoon|evening|night|noon|midnight)\b|\b\d{1,2}(?::[0-5]\d)?\s*[ap]\.?\s*m\.?\b"#, in: sourcePlain) { return }
        let clocks = captures(#"(?<![A-Za-z0-9_])([0-9]{1,2})\s*(?:시(?!간)|時(?!間))"#, in: sourcePlain)
        let hours = Set(clocks.compactMap { Int($0.value) })
        if hours.contains(where: { (13...24).contains($0) })
            || matches(#"(?<![0-9])(?:1[3-9]|2[0-4]):[0-5][0-9](?![0-9])"#, in: sourcePlain) { return }
        let unspecified = hours.filter { (1...12).contains($0) }
        guard !unspecified.isEmpty else { return }
        for clock in captures(#"(?<![A-Za-z0-9_])([0-9]{1,2})(?::[0-5][0-9])?\s*([ap]\.?\s*m\.?)(?![A-Za-z0-9_])"#, in: outputPlain) {
            guard let hour = Int(clock.value), unspecified.contains(hour) else { continue }
            let ns = outputPlain as NSString
            let full = ns.substring(with: clock.range)
            let prefix = ns.substring(with: NSRange(location: max(0, clock.range.location - 32), length: min(32, clock.range.location)))
            // Lowercase bare "pm" can be picometers. Require dotted/uppercase clock notation,
            // minutes, or a nearby time preposition instead of treating every unit as a period.
            if matches(#"[ap]\.\s*m"#, in: full) || full.contains(":") || full.contains("AM") || full.contains("PM")
                || matches(#"\b(?:at|by|before|after|from|until|around)\s*$"#, in: prefix) {
                throw ProviderError.translationTimeInferred
            }
        }
        for clock in captures(#"(?:오전|오후|午前|午後)\s*([0-9]{1,2})\s*(?:시(?!간)|時(?!間))"#, in: outputPlain) {
            if let hour = Int(clock.value), unspecified.contains(hour) { throw ProviderError.translationTimeInferred }
        }
    }

    private static func maskingCodeAndURLs(in text: String, preserving literals: [Literal] = []) -> String {
        let ranges = protectedCode(in: text).map(\.range)
            + captures(#"https?://[^\s<>\"'“”‘’「」『』。，、！？]+"#, in: text, contentGroup: nil).map(\.range)
            + literals.flatMap { delimitedLiteralRanges($0.value, in: text) }
        let mutable = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            // Mask in place so overlapping URL/code spans keep their original offsets.
            mutable.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return mutable as String
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        captures(pattern, in: text, contentGroup: nil).isEmpty == false
    }

    private static func captures(_ pattern: String, in text: String, contentGroup: Int? = 1) -> [Literal] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let content = contentGroup.map { match.range(at: $0) } ?? match.range
            guard content.location != NSNotFound else { return nil }
            return Literal(value: ns.substring(with: content), range: match.range, kind: .code)
        }
    }
}
