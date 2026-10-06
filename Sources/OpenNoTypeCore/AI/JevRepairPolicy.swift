import Foundation

/// Content-free diagnostics for a deterministic local gate, never an inferred semantic verdict.
public enum JevLiteralConstraintFailure: String, Equatable, CaseIterable, Sendable {
    case emptyInput, numbers, quotes, code, urls, identities

    public var repairIssue: JevRepairIssue {
        switch self {
        case .emptyInput: .meaning
        case .numbers: .numbers
        case .quotes: .quotes
        case .code: .code
        case .urls: .urls
        case .identities: .entities
        }
    }
}

/// Conservative local gates for a single reviewed repair. A Jev signal never supplies new facts.
public enum JevRepairPolicy {
    public static func issues(in review: DecisionResult, threshold: Double = 0.9) -> [JevRepairIssue] {
        guard threshold.isFinite, (0...1).contains(threshold), validRisks(review) else { return [] }
        var selected: Set<JevRepairIssue> = []
        if review.meaningChanged >= threshold { selected.insert(.meaning) }
        if review.contentAdded >= threshold { selected.insert(.additions) }
        if review.contentOmitted >= threshold { selected.insert(.omissions) }
        for (axis, score) in review.detailRisks where score >= threshold {
            if let issue = JevRepairIssue(rawValue: axis.rawValue) { selected.insert(issue) }
        }
        return JevRepairIssue.allCases.filter(selected.contains)
    }

    public static func needsRepair(review: DecisionResult, transcript: String, output: String,
                                   terms: [DecisionTermCandidate], expression: DictationExpression = .init()) -> Bool {
        guard nonempty(transcript), nonempty(output), validRisks(review), validTerms(review, candidates: terms) else { return false }
        if !issues(in: review).isEmpty { return true }
        if !literalConstraintsPreserved(transcript: transcript, output: output, expression: expression) { return true }
        let byID = Dictionary(uniqueKeysWithValues: terms.map { ($0.id, $0) })
        return review.terms.contains { result in
            guard strongCandidate(result), let term = byID[result.id],
                  transcript.contains(term.original) else { return false }
            return output.contains(term.original) && !output.contains(term.candidate)
        }
    }

    public static func reviewIsValid(_ review: DecisionResult) -> Bool { validRisks(review) }

    public static func reviewMatchesCandidates(_ review: DecisionResult, terms: [DecisionTermCandidate]) -> Bool {
        validRisks(review) && validTerms(review, candidates: terms)
    }

    /// Combine verified semantic signals with exact local failure categories. A missed number
    /// or quote must not be learned merely as "meaning" or an unrelated name-spelling problem.
    public static func repairIssues(review: DecisionResult, transcript: String, output: String,
                                    terms: [DecisionTermCandidate], expression: DictationExpression = .init()) -> [JevRepairIssue] {
        guard validRisks(review), validTerms(review, candidates: terms) else { return [] }
        var selected = Set(issues(in: review))
        selected.formUnion(literalConstraintFailures(transcript: transcript, output: output,
                                                     expression: expression).map(\.repairIssue))
        let byID = Dictionary(uniqueKeysWithValues: terms.map { ($0.id, $0) })
        if review.terms.contains(where: { result in
            guard strongCandidate(result), let term = byID[result.id], transcript.contains(term.original) else { return false }
            return output.contains(term.original) && !output.contains(term.candidate)
        }) { selected.insert(.entities) }
        return JevRepairIssue.allCases.filter(selected.contains)
    }

    /// Recognition-source literal constraints are checked even when semantic review misses a risk.
    /// Newly rendered Latin names may be ordinary speech spelling repairs; this initial gate does
    /// not call those additions errors, while source Latin identities still have to stay intact.
    public static func literalConstraintsPreserved(transcript: String, output: String,
                                                   expression: DictationExpression = .init()) -> Bool {
        literalConstraintFailures(transcript: transcript, output: output, expression: expression).isEmpty
    }

    public static func literalConstraintFailures(transcript: String, output: String,
                                                expression: DictationExpression = .init()) -> [JevLiteralConstraintFailure] {
        guard nonempty(transcript), nonempty(output) else { return [.emptyInput] }
        let source = supportedLiterals(in: transcript)
        let actual = literalCounts(in: output)
        let sourceLiterals = literals(in: transcript)
        let names = Set(sourceLiterals.filter { $0.kind == .name }.map(\.value))
        let kindByValue = sourceLiterals.reduce(into: [String: Literal.Kind]()) { $0[$1.value] = $1.kind }
        var failures = Set<JevLiteralConstraintFailure>()
        for (value, count) in source {
            let outputCount = actual[value, default: 0]
            let preserved = expression.isActive ? outputCount > 0
                : names.contains(value) ? (1...count).contains(outputCount) : outputCount == count
            if !preserved, let kind = kindByValue[value] {
                failures.insert(kind.failure)
            }
        }
        let extra = Set(actual.keys).subtracting(source.keys)
        for literal in literals(in: output) where extra.contains(literal.value) && literal.kind != .name {
            failures.insert(literal.kind.failure)
        }
        return JevLiteralConstraintFailure.allCases.filter(failures.contains)
    }

    public static func acceptsRepair(transcript: String, originalOutput: String, repairedOutput: String,
                                     review: DecisionResult, terms: [DecisionTermCandidate],
                                     expression: DictationExpression = .init()) -> Bool {
        guard nonempty(transcript), nonempty(originalOutput), nonempty(repairedOutput),
              repairedOutput != originalOutput, transcript.utf8.count <= 320_000,
              originalOutput.utf8.count <= 24_000, repairedOutput.utf8.count <= 24_000,
              validRisks(review), review.maximumRiskProbability < 0.5,
              validTerms(review, candidates: terms) else { return false }

        // Facts come from the recognition source, not the previous (possibly wrong) result.
        // A strong contextual choice may resolve a supplied spelling; it cannot invent a new one.
        var supportedSource = transcript
        let byID = Dictionary(uniqueKeysWithValues: terms.map { ($0.id, $0) })
        for result in review.terms {
            guard let term = byID[result.id] else { return false }
            let sourceMentionsTerm = transcript.contains(term.original) || transcript.contains(term.candidate)
            guard sourceMentionsTerm else { continue }
            switch result.choice {
            case .useCandidate:
                guard strongCandidate(result), repairedOutput.contains(term.candidate) else { return false }
                supportedSource = applyingSpelling(term, to: supportedSource)
            case .keepOriginal:
                guard result.confidence >= 0.6, (result.probabilities[.keepOriginal] ?? 0) >= 0.9,
                      repairedOutput.contains(term.original) else { return false }
            case .uncertain: return false
            }
        }
        // Names explicitly present in the source cannot disappear. A wrong mapping in the earlier
        // output is not authority: a keepOriginal choice must still be able to undo that mapping.
        for term in terms where transcript.contains(term.candidate) {
            guard repairedOutput.contains(term.candidate) else { return false }
        }
        let source = supportedLiterals(in: supportedSource), actual = literalCounts(in: repairedOutput)
        // An active style may consolidate or restate an already-supported fact. It may never
        // remove the last occurrence, substitute a different value, or create a protected literal.
        guard Set(source.keys) == Set(actual.keys) else { return false }
        return expression.isActive || faithfulLiteralCountsPreserved(source: source, actual: actual,
                                                                     sourceText: supportedSource)
    }

    /// A reservation for one generation and one Jev review, not a provider bill or a retry budget.
    /// Unknown prices and invalid/oversized prompts fail closed before an auxiliary call.
    public static func repairReservationUSD(request: ProcessingRequest, configuration: ProviderConfiguration) -> Double? {
        guard request.effectiveMode == .dictation, request.previousOutput != nil,
              let bytes = try? ProviderClient.processingInputBytes(request), bytes <= 100_000 else { return nil }
        let input = bytes + 4_096
        let generation: Double
        if configuration.provider == .openRouter {
            guard let price = TextModelCatalog.entry(id: configuration.textModel, provider: configuration.provider)?.price,
                  price.inputUSDPerMillion.isFinite, price.inputUSDPerMillion >= 0,
                  price.outputUSDPerMillion.isFinite, price.outputUSDPerMillion >= 0 else { return nil }
            generation = (Double(input) * price.inputUSDPerMillion
                          + Double(JevModelEvaluation.maximumOutputTokens) * price.outputUSDPerMillion) / 1_000_000
        } else {
            let usage = ProviderUsage(provider: configuration.provider, model: configuration.textModel,
                                      stage: .textProcessing, inputTokens: input,
                                      outputTokens: JevModelEvaluation.maximumOutputTokens)
            guard let value = UsagePricing.cost(for: usage).usd else { return nil }
            generation = value
        }
        // Exceeds the existing maximum Jev input-byte reservation at its verified input price.
        let total = generation + 0.003
        return total.isFinite && total >= 0 ? total : nil
    }

    private static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private static func validRisks(_ review: DecisionResult) -> Bool {
        ([review.meaningChanged, review.contentAdded, review.contentOmitted] + Array(review.detailRisks.values))
            .allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
    private static func strongCandidate(_ result: DecisionTermResult) -> Bool {
        result.choice == .useCandidate && result.confidence >= 0.6 && (result.probabilities[.useCandidate] ?? 0) >= 0.9
    }
    private static func validTerms(_ review: DecisionResult, candidates: [DecisionTermCandidate]) -> Bool {
        guard candidates.count <= 4, Set(candidates.map(\.id)).count == candidates.count,
              candidates.allSatisfy({ nonempty($0.id) && nonempty($0.original) && nonempty($0.candidate)
                  && $0.original.count <= 100 && $0.candidate.count <= 100
                  && !($0.original + $0.candidate).unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }),
              Set(review.terms.map(\.id)) == Set(candidates.map(\.id)), review.terms.count == candidates.count else { return false }
        return review.terms.allSatisfy { result in
            result.confidence.isFinite && (0...1).contains(result.confidence)
                && Set(result.probabilities.keys) == Set(DecisionTermChoice.allCases)
                && result.probabilities.values.allSatisfy { $0.isFinite && (0...1).contains($0) }
                && abs(result.probabilities.values.reduce(0, +) - 1) <= 0.02
                && result.probabilities[result.choice] == result.probabilities.values.max()
        }
    }

    private struct Literal {
        enum Kind {
            case url, quote, code, number, name
            var failure: JevLiteralConstraintFailure {
                switch self {
                case .url: .urls
                case .quote: .quotes
                case .code: .code
                case .number: .numbers
                case .name: .identities
                }
            }
        }
        let range: Range<String.Index>
        let value: String
        let kind: Kind
    }
    private static func literals(in text: String) -> [Literal] {
        // Longest protected forms win: a number inside a URL, code or literal quote is not re-counted.
        let protected = ProtectedLiteralPatterns.protected
        let koreanOnes = "(?:하나|한|둘|두|셋|세|넷|네|다섯|여섯|일곱|여덟|아홉)"
        let native = "(?:(?:스물|스무|서른|마흔|쉰|예순|일흔|여든|아흔|열)(?:\\s*" + koreanOnes + ")?|" + koreanOnes + ")"
        let sino = "(?:[일이삼사오육칠팔구십백천만](?:\\s*[일이삼사오육칠팔구십백천만])*)"
        let englishOnes = "(?:one|two|three|four|five|six|seven|eight|nine)"
        let english = "(?:(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[-\\s]+" + englishOnes + ")?|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|" + englishOnes + ")"
        let unitPattern = countedUnits.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let spokenUnitPattern = countedUnits.keys.filter { ["개", "명", "시", "분", "초", "원", "시간"].contains($0)
            || $0.allSatisfy(\.isASCII) && $0.count > 1 }.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let koreanUnitEnd = #"(?=$|[^\p{L}\p{N}_]|(?:이에요|입니다|이다|이었다|이었어요|이면|이라고|이라는|에게서|에게|에서|으로|부터|까지|보다|만큼|정도|에|를|을|가|이|은|는|로|만|도|씩|과|와)(?=$|[^\p{L}\p{N}_]))"#
        let spoken = #"(?<![\p{L}\p{N}_])(?:"# + native + "|" + sino + "|(?i:" + english + #"))\s*(?:"# + spokenUnitPattern + ")" + koreanUnitEnd
        let digits = #"(?<![A-Za-z0-9_])[+−-]?[$€£₩]?\p{N}+(?:[.,:/-]\p{N}+)*(?:\s*(?:"# + unitPattern + #"))?(?![A-Za-z0-9_])"#
        let pattern = protected + "|" + spoken + "|" + digits
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let raw = String(text[range])
            let kind: Literal.Kind
            let value: String
            if raw.hasPrefix("http") { kind = .url; value = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?")) }
            else if raw.hasPrefix("`") { kind = .code; value = raw }
            else if raw.first.map({ "\"'“‘".contains($0) }) == true { kind = .quote; value = "quote:" + String(raw.dropFirst().dropLast()) }
            else if raw.contains("_") { kind = .code; value = raw }
            else if let counted = countedNumber(raw) {
                kind = .number
                // Unsupported larger phrases are not allowed to become a small number by matching
                // just their final word (e.g. "hundred one minutes").
                let preceding = String(text[..<range.lowerBound].suffix(32))
                let unsupportedPrefix = #"(?i:\b(?:hundred|thousand|million)(?:\s+and)?\s+)$|(?<![\p{L}\p{N}_])(?:[일이삼사오육칠팔구십백천만\p{N}]+)?(?:억|조)\s+$"#
                value = preceding.range(of: unsupportedPrefix, options: .regularExpression) == nil ? counted : raw
            }
            else if raw.first.map({ "일이삼사오육칠팔구십백천만".contains($0) }) == true { kind = .number; value = raw }
            else if raw.first?.isNumber == true || raw.first.map({ "$€£₩+−-".contains($0) }) == true { kind = .number; value = raw }
            else { kind = .name; value = raw }
            return Literal(range: range, value: value, kind: kind)
        }
    }
    /// Equivalence is limited to explicit counted units and settled integers 1...99,999.
    /// Korean larger counts require an unambiguous, descending-unit spelling. Ordinary words,
    /// bare spoken numbers, code, quotes, URLs, fractions and unsupported values stay literal.
    private static let countedUnits: [String: String] = [
        "개": "items", "명": "people", "시": "clock-hour", "분": "minutes", "초": "seconds", "원": "KRW",
        "시간": "hours", "일": "days", "월": "months", "년": "years", "번": "times", "배": "multiples",
        "items": "items", "item": "items", "people": "people", "persons": "people", "person": "people",
        "minutes": "minutes", "minute": "minutes", "seconds": "seconds", "second": "seconds",
        "hours": "hours", "hour": "hours", "days": "days", "day": "days", "months": "months", "month": "months",
        "years": "years", "year": "years", "times": "times", "time": "times", "won": "KRW",
        "%": "%", "USD": "USD", "EUR": "EUR", "KRW": "KRW", "kg": "kg", "km": "km", "cm": "cm",
        "mm": "mm", "ms": "ms", "GB": "GB", "MB": "MB", "g": "g", "m": "m", "L": "L", "l": "L", "h": "hours", "s": "seconds"
    ]
    private static func countedNumber(_ raw: String) -> String? {
        guard let unit = countedUnits.keys.sorted(by: { $0.count > $1.count }).first(where: raw.hasSuffix),
              let normalizedUnit = countedUnits[unit] else { return nil }
        let token = String(raw.dropLast(unit.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.first.map({ "+−-".contains($0) }) != true else { return nil }
        let value = Int(token) ?? koreanNumber(token) ?? englishNumber(token)
        guard let value, (1...99_999).contains(value) else { return nil }
        return "quantity:\(value):\(normalizedUnit)"
    }
    private static func koreanNumber(_ token: String) -> Int? {
        let compact = token.filter { !$0.isWhitespace }
        let ones = ["하나": 1, "한": 1, "둘": 2, "두": 2, "셋": 3, "세": 3, "넷": 4, "네": 4,
                    "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9]
        if let value = ones[compact] { return value }
        for (prefix, tens) in ["열": 10, "스물": 20, "스무": 20, "서른": 30, "마흔": 40, "쉰": 50,
                               "예순": 60, "일흔": 70, "여든": 80, "아흔": 90] where compact.hasPrefix(prefix) {
            let suffix = String(compact.dropFirst(prefix.count))
            if suffix.isEmpty { return tens }
            if let value = ones[suffix], prefix != "스무" { return tens + value }
            return nil
        }
        let sino: [Character: Int] = ["일": 1, "이": 2, "삼": 3, "사": 4, "오": 5, "육": 6, "칠": 7, "팔": 8, "구": 9]
        let groups = compact.split(separator: "만", omittingEmptySubsequences: false)
        guard groups.count <= 2 else { return nil }
        var high = 0, remainder = compact
        if groups.count == 2 {
            let leading = Array(groups[0])
            guard leading.isEmpty || leading.count == 1 && sino[leading[0]] != nil else { return nil }
            high = (leading.first.flatMap { sino[$0] } ?? 1) * 10_000
            remainder = String(groups[1])
        }
        if remainder.isEmpty { return high > 0 ? high : nil }
        let units: [Character: Int] = ["십": 10, "백": 100, "천": 1_000]
        var subtotal = 0, previousUnit = 10_000
        var pendingDigit: Int?
        for character in remainder {
            if let digit = sino[character] {
                guard pendingDigit == nil else { return nil }
                pendingDigit = digit
            } else if let unit = units[character] {
                guard unit < previousUnit else { return nil }
                subtotal += (pendingDigit ?? 1) * unit
                pendingDigit = nil; previousUnit = unit
            } else { return nil }
        }
        let value = high + subtotal + (pendingDigit ?? 0)
        return (1...99_999).contains(value) ? value : nil
    }
    private static func englishNumber(_ token: String) -> Int? {
        let parts = token.lowercased().replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace).map(String.init)
        let ones = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9]
        let teens = ["ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
                     "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        if parts.count == 1 { return ones[parts[0]] ?? teens[parts[0]] ?? tens[parts[0]] }
        if parts.count == 2, let first = tens[parts[0]], let last = ones[parts[1]] { return first + last }
        return nil
    }
    private static func literalCounts(in text: String) -> [String: Int] {
        literals(in: text).reduce(into: [:]) { $0[$1.value, default: 0] += 1 }
    }
    private static func faithfulLiteralCountsPreserved(source: [String: Int], actual: [String: Int],
                                                       sourceText: String) -> Bool {
        let names = Set(literals(in: sourceText).filter { $0.kind == .name }.map(\.value))
        // A faithful spoken restart can repeat a name without supplying another fact. Only
        // references may decrease; Jev still reviews every distinct action, actor and condition.
        // Numbers, quotations, code and URLs retain exact counts, even when their text repeats.
        return source.allSatisfy { value, count in
            guard let outputCount = actual[value] else { return false }
            return names.contains(value) ? (1...count).contains(outputCount) : outputCount == count
        }
    }
    private static func applyingSpelling(_ term: DecisionTermCandidate, to text: String) -> String {
        let protected = literals(in: text).filter { [.url, .quote, .code].contains($0.kind) }
        guard let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: term.original)) else { return text }
        let replacements = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
            .filter { range in !protected.contains { range.overlaps($0.range) } }
        var value = text
        for range in replacements.reversed() { value.replaceSubrange(range, with: term.candidate) }
        return value
    }
    private static func supportedLiterals(in text: String) -> [String: Int] {
        let values = literals(in: text)
        var removed: Set<Int> = []
        for index in values.indices.dropLast() {
            let current = values[index], next = values[index + 1]
            guard current.kind == next.kind, current.value != next.value else { continue }
            let gap = String(text[current.range.upperBound..<next.range.lowerBound])
            let following = String(text[next.range.upperBound...].prefix(64))
            guard gap.count <= 64,
                  explicitCorrectionGap(gap),
                  (gap + following).range(of: #"모르|불확실|아마|혹시|maybe|not sure|unsure"#, options: [.regularExpression, .caseInsensitive]) == nil else { continue }
            if current.kind == .number {
                // The time and attendee count in "3시에 있고, 제가 아니라 4명" are separate
                // facts. Even same-unit numbers need an adjacent correction, not another clause.
                let currentRaw = String(text[current.range]), nextRaw = String(text[next.range])
                guard numericDimension(currentRaw) == numericDimension(nextRaw) else { continue }
            }
            // "not A but B" places the marker before A. The between-literal cue must be explicit;
            // broad semantic alternatives are deliberately left for a manual decision.
            removed.insert(index)
        }
        return values.enumerated().filter { !removed.contains($0.offset) }.reduce(into: [:]) { $0[$1.element.value, default: 0] += 1 }
    }

    private static func explicitCorrectionGap(_ gap: String) -> Bool {
        // A narrow cue grammar retains settled corrections and a short tentative restart. It
        // deliberately refuses intervening statements, roles, alternatives and sentence breaks.
        let pattern = #"^\s*(?:이에요|예요|입니다|[이가은는을를에])?\s*(?:볼까|갈까|할까|일까|인가|였나|맞나)?\s*[,，…]*\s*(?:아닌가|아니(?:라|고|야|요|다|었)?|말고|(?i:I mean|sorry))\s*[,，…]*\s*(?:(?:오전|오후|(?i:AM|PM))\s*)?$"#
        return gap.range(of: pattern, options: .regularExpression) != nil
    }

    private static func numericDimension(_ raw: String) -> String {
        if let unit = countedUnits.keys.sorted(by: { $0.count > $1.count }).first(where: raw.hasSuffix) {
            return "unit:" + countedUnits[unit, default: unit]
        }
        // Currency and separators distinguish bare quantities, dates, times and versions.
        return raw.replacingOccurrences(of: #"^[+−-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\p{N}+"#, with: "#", options: .regularExpression)
    }
}
