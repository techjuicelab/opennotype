import Foundation
import OpenNoTypeCore

/// A review is bound to this exact pair of texts, never to whichever result is visible later.
struct JevReviewTarget: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case recent, history, reprocessed }
    let id: UUID
    let kind: Kind
    let transcript: String
    let output: String
    var sourceHistoryID: UUID? = nil
    var previewID: UUID? = nil
    var purpose: DecisionReviewPurpose = .dictation
    var textProvider: AIProvider? = nil
    var textModel: String? = nil
    var writingProfile: WritingProfile = .init()

    var mode: InputMode { purpose.mode }
    var comparisonSource: String {
        if case .rewrite(let original) = purpose { return original }
        return transcript
    }
    var sourceTitle: String {
        if case .rewrite = purpose { return L("선택했던 원문", "Selected source text") }
        return L("인식 원문", "Transcript")
    }
    var outputTitle: String {
        switch purpose {
        case .dictation: L("문장 정리 결과", "Cleaned text")
        case .translation: L("번역 결과", "Translation")
        case .rewrite: L("수정 결과", "Edited result")
        }
    }

    var title: String {
        switch kind {
        case .recent: L("최근 결과", "Latest result")
        case .history: L("선택한 기록", "Selected history")
        case .reprocessed: L("다시 처리한 미리보기", "Reprocessed preview")
        }
    }
}

/// A spelling proposal stays advisory until the user explicitly confirms a dictionary write.
struct JevSpellingProposal: Identifiable, Equatable, Sendable {
    let id: UUID
    let reviewID: UUID
    let targetID: UUID
    let original: String
    let candidate: String
    let choice: DecisionTermChoice
    var probabilities: [DecisionTermChoice: Double] = [:]
    var confidence: Double = 0

    /// Display-only provisional bands. They never authorize an edit or represent calibrated accuracy.
    var evidence: JevSpellingEvidence {
        guard choice != .uncertain else { return .uncertain }
        guard confidence.isFinite, (0...1).contains(confidence),
              probabilities.count == DecisionTermChoice.allCases.count,
              probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(probabilities.values.reduce(0, +) - 1) <= 0.02,
              let chosen = probabilities[choice] else { return .needsCloserReview }
        let alternative = probabilities.filter { $0.key != choice }.values.max() ?? 1
        return confidence >= 0.6 && chosen - alternative >= 0.2 ? .candidatePreferred : .needsCloserReview
    }
    var canSave: Bool { choice == .useCandidate }
    var title: String {
        if choice == .uncertain { return "\(original) / \(candidate)" }
        if choice == .keepOriginal {
            return L("\(candidate) → \(original) · 원문 표기 유지", "\(candidate) → \(original) · Keep original spelling")
        }
        return "\(original) → \(candidate)"
    }
}

struct JevRiskSignal: Identifiable, Equatable, Sendable {
    enum Axis: String, Sendable { case meaningChanged, contentAdded, contentOmitted, numbers, negation, conditions, intent, entities }
    let id: Axis
    let score: Double
    /// A provisional signal threshold, not a measure of correctness or calibrated accuracy.
    var isHigh: Bool { score >= 0.9 }
    var title: String {
        switch id {
        case .meaningChanged: L("의미 변경", "Meaning change")
        case .contentAdded: L("내용 추가", "Added content")
        case .contentOmitted: L("내용 누락", "Omitted content")
        case .numbers: L("숫자·단위", "Numbers and units")
        case .negation: L("부정 표현", "Negation")
        case .conditions: L("조건·불확실성", "Conditions and uncertainty")
        case .intent: L("요청·약속·완료", "Requests, commitments and completion")
        case .entities: L("이름·행위 주체", "Names and actors")
        }
    }
    var detail: String {
        switch id {
        case .meaningChanged: L("부정·조건·숫자·의도 등이 달라졌는지 검토합니다.", "Reviews changes to negation, conditions, numbers, or intent.")
        case .contentAdded: L("원문에 없는 사실·요청·답변이 추가됐는지 검토합니다.", "Reviews facts, requests, or answers added without support in the transcript.")
        case .contentOmitted: L("원문의 중요한 정보나 요청이 빠졌는지 검토합니다.", "Reviews whether meaningful information or requests were omitted.")
        case .numbers: L("말로 한 수량과 단위를 같은 뜻으로 정리했는지 확인합니다.", "Checks whether quantities and units preserve the spoken meaning.")
        case .negation: L("하지 않음·금지·제외가 반대로 바뀌었는지 확인합니다.", "Checks whether negation, prohibition or exclusion was reversed.")
        case .conditions: L("조건부 행동이나 아직 확정하지 않은 말을 보존했는지 확인합니다.", "Checks whether conditions and undecided statements were preserved.")
        case .intent: L("부탁을 약속이나 이미 끝난 행동으로 바꾸지 않았는지 확인합니다.", "Checks whether a request became a commitment or a completed action.")
        case .entities: L("이름이나 누가 무엇을 하는지가 바뀌었는지 확인합니다.", "Checks whether names or who performs an action changed.")
        }
    }
}

/// A presentation hint from existing typed answers, not an extra model request.
enum JevSpellingEvidence: Equatable, Sendable {
    case uncertain, needsCloserReview, candidatePreferred

    var title: String {
        switch self {
        case .uncertain: L("판단 보류", "Undecided")
        case .needsCloserReview: L("추가 확인 필요", "Check the spelling carefully")
        case .candidatePreferred: L("표기 제안", "Spelling suggestion")
        }
    }
    var detail: String {
        switch self {
        case .uncertain: L("문맥만으로 표기를 고르지 못했습니다. 사전에 자동 저장하지 않습니다.", "The context did not resolve the spelling. It is not saved automatically.")
        case .needsCloserReview: L("선택의 차이가 작거나 검토 신호가 약합니다. 원문과 표기를 직접 확인해 주세요.", "The choices are close or the review signal is weak. Check the source and spelling yourself.")
        case .candidatePreferred: L("모델이 선호한 표기이며 정확성을 보장하지 않습니다.", "This is the model’s preferred spelling, not a guarantee of correctness.")
        }
    }
}

/// A bounded local token comparison. Differences are not classified as semantic errors.
struct JevTextComparison: Equatable, Sendable {
    let sourceOnly: [String]
    let resultOnly: [String]
    let sourceNumbers: [String]
    let resultNumbers: [String]
    let truncated: Bool
    var hasDifferences: Bool { !sourceOnly.isEmpty || !resultOnly.isEmpty }
    var numbersDiffer: Bool { sourceNumbers != resultNumbers }

    init(source: String, result: String) {
        let left = Self.tokens(source), right = Self.tokens(result)
        let difference = right.values.difference(from: left.values)
        var removed: [(Int, String)] = [], added: [(Int, String)] = []
        for change in difference {
            switch change {
            case .remove(let offset, let value, _): removed.append((offset, value))
            case .insert(let offset, let value, _): added.append((offset, value))
            }
        }
        let removedValues = removed.sorted { $0.0 < $1.0 }.map(\.1)
        let addedValues = added.sorted { $0.0 < $1.0 }.map(\.1)
        sourceOnly = Array(removedValues.prefix(16)); resultOnly = Array(addedValues.prefix(16))
        sourceNumbers = Array(left.values.filter { $0.first?.isNumber == true }.prefix(16))
        resultNumbers = Array(right.values.filter { $0.first?.isNumber == true }.prefix(16))
        truncated = left.truncated || right.truncated || removedValues.count > 16 || addedValues.count > 16
            || left.values.filter { $0.first?.isNumber == true }.count > 16
            || right.values.filter { $0.first?.isNumber == true }.count > 16
    }

    private static func tokens(_ text: String) -> (values: [String], truncated: Bool) {
        let bounded = String(text.prefix(6_000))
        guard let expression = try? NSRegularExpression(pattern: "[\\p{L}\\p{M}_]+|\\p{N}+(?:[.,:]\\p{N}+)*|[^\\s]") else {
            return ([], !text.isEmpty)
        }
        let matches = expression.matches(in: bounded, range: NSRange(bounded.startIndex..., in: bounded))
        let values = matches.prefix(240).compactMap { match in
            Range(match.range, in: bounded).map { String(bounded[$0]) }
        }
        return (values, text.count > 6_000 || matches.count > 240)
    }
}
