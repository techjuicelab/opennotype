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

    var title: String {
        switch kind {
        case .recent: L("최근 받아쓰기", "Latest dictation")
        case .history: L("선택한 받아쓰기 기록", "Selected dictation history")
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
    var canSave: Bool { choice == .useCandidate }
    var title: String {
        if choice == .keepOriginal {
            return L("\(candidate) → \(original) · 원문 표기 유지", "\(candidate) → \(original) · Keep original spelling")
        }
        return "\(original) → \(candidate)"
    }
}

struct JevRiskSignal: Identifiable, Equatable, Sendable {
    enum Axis: String, Sendable { case meaningChanged, contentAdded, contentOmitted }
    let id: Axis
    let score: Double
    /// A provisional signal threshold, not a measure of correctness or calibrated accuracy.
    var isHigh: Bool { score >= 0.9 }
    var title: String {
        switch id {
        case .meaningChanged: L("의미 변경", "Meaning change")
        case .contentAdded: L("내용 추가", "Added content")
        case .contentOmitted: L("내용 누락", "Omitted content")
        }
    }
    var detail: String {
        switch id {
        case .meaningChanged: L("부정·조건·숫자·의도 등이 달라졌는지 검토합니다.", "Reviews changes to negation, conditions, numbers, or intent.")
        case .contentAdded: L("원문에 없는 사실·요청·답변이 추가됐는지 검토합니다.", "Reviews facts, requests, or answers added without support in the transcript.")
        case .contentOmitted: L("원문의 중요한 정보나 요청이 빠졌는지 검토합니다.", "Reviews whether meaningful information or requests were omitted.")
        }
    }
}
