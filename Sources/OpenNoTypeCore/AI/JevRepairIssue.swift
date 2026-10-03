import Foundation

/// Fixed repair categories. They carry no user utterance, fact, spelling or model-authored instruction.
public enum JevRepairIssue: String, Codable, CaseIterable, Sendable {
    case meaning, additions, omissions, numbers, negation, conditions, intent, entities, quotes, code, urls

    public var title: String {
        switch self {
        case .meaning: L("의미 보존", "Meaning")
        case .additions: L("내용 추가", "Added content")
        case .omissions: L("내용 누락", "Omitted content")
        case .numbers: L("숫자·단위", "Numbers & units")
        case .negation: L("부정", "Negation")
        case .conditions: L("조건·불확실성", "Conditions & uncertainty")
        case .intent: L("요청·의도", "Requests & intent")
        case .entities: L("이름·주체", "Names & actors")
        case .quotes: L("인용문", "Quoted text")
        case .code: L("코드·식별자", "Code & identifiers")
        case .urls: L("URL", "URLs")
        }
    }

    /// Only these source-controlled sentences may enter generation instructions.
    var preservationRule: String {
        switch self {
        case .meaning: "Preserve each distinct source meaning, stance, certainty and unfinished thought."
        case .additions: "Remove unsupported additions; do not invent facts, actions, explanations or recipients."
        case .omissions: "Retain each distinct source point; do not summarize away qualifying or repeated emphasis."
        case .numbers: "Preserve numbers, amounts, units, dates and times; only an explicit settled self-correction selects a new value."
        case .negation: "Preserve negation and its scope; do not turn a refusal, exception or negative condition into an affirmative."
        case .conditions: "Preserve conditions, exceptions and uncertainty; do not resolve an unsettled thought into a definite decision."
        case .intent: "Preserve whether the speaker asks, suggests, hopes or commits; do not strengthen an intention into a promise."
        case .entities: "Preserve named identities, actors and relationships; use only source-supported spellings and supplied relevant dictionary mappings."
        case .quotes: "Preserve the exact contents and occurrence count of explicit quotations; ordinary contraction apostrophes are not quotations."
        case .code: "Preserve code and code identifiers exactly, including case, punctuation and occurrence counts."
        case .urls: "Preserve URLs exactly; do not invent, rewrite or remove a source URL."
        }
    }
}
