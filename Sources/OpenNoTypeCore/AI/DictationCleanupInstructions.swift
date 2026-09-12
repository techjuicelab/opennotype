import Foundation

/// Semantic cleanup is performed in the existing text request, never by deleting source tokens locally.
/// These examples are authored acceptance examples, not captured output from another product.
enum DictationCleanupInstructions {
    static let rules = """

    CLEANUP CONTRACT: express each distinct meaning once, with all its details.
    Removing an accidental duplicate is not summarizing. Actively remove hesitation-only fillers,
    abandoned sentence starts and redundant phrases, including a repeated request later in the utterance.
    When two phrases express the same point, combine their information: retain every added subject,
    action, object, name, time, place, reason, condition, exception and limit. Do not keep a false start
    merely to avoid deleting information; carry its still-valid details into the completed sentence.

    Self-correction replaces only what was corrected. A new time or quantity does not cancel the action,
    participants, place or conditions mentioned only before it. Remove the clearly superseded value
    and the repair scaffolding. Cancel a whole proposition only when the speaker explicitly discards it.
    Choosing a corrected value does not turn a suggestion into a decision: keep words such as 정도,
    아마, 가능하면, 좀 and question endings when they soften the request or express uncertainty.
    If the speaker is still choosing between alternatives, preserve those alternatives and uncertainty.
    아니 is not a repair instruction when it is quoted, describes a word, or expresses disagreement.

    A repeated form can carry new meaning. Preserve deliberate emphasis, repeated events, counts,
    step order, contrasts, quotations and literal strings. Never deduplicate by word identity alone.
    Remove 어, 음, 그 or 그러니까 only when they merely stall; keep references such as 그 자료,
    그다음, 저번에 말한 and connectives that express a relationship. Short or hesitant speech can
    still be meaningful: requests, answers, references and unfinished thoughts must not become empty.
    An empty result is reserved for speech with no communicative content at all.

    For spelling, priority is: explicit literal or spelling instruction in the utterance, then contextual
    identity of the term, then a relevant dictionary hint, then a confident recognition repair.
    A dictionary match in sound or substring is not proof of the same concept. Keep ordinary words
    when a same-sounding dictionary entry denotes a different thing. Never change a quoted identifier
    to the dictionary spelling or a familiar technical term against the speaker's explicit wording.

    Contrast examples (illustrative; follow the selected mode's output language and authorized register):
    어 그 자료를 그 자료를 오늘 보내주실 수 있을까요 → 그 자료를 오늘 보내주실 수 있을까요?
    자료를 보내줘. 그 자료를 오늘 3시 전에 보내줘 → 그 자료를 오늘 3시 전에 보내줘.
    내일 오전 10시에 세린 씨와 리뷰할까, 아니 목요일 오후 2시로 하자 → 목요일 오후 2시에 세린 씨와 리뷰하자.
    10개, 아니 12개 정도 살까 → 12개 정도 살까?
    10개 아니 12개인지 모르겠어 → 10개인지 12개인지 모르겠어.
    정말 정말 중요해. 먼저 저장하고 닫은 다음 다시 열어서 또 저장해 → 정말 정말 중요해. 먼저 저장하고 닫은 다음 다시 열어서 또 저장해.
    어 그 저번에 말한 그거, 그거 승인 좀 부탁드려요 → 저번에 말한 그거 승인 좀 부탁드려요.
    코드의 '커미'라는 변수는 이름을 바꾸지 마 → 코드의 '커미'라는 변수는 이름을 바꾸지 마.
    (dictionary 사과→SAGWA) 늦어서 팀장님한테 사과했어요 → 늦어서 팀장님한테 사과했어요.

    Before returning the result, silently check that all distinct information and protected spellings
    remain, only clearly superseded values are gone, and accidental duplication is actually removed.
    When deletion is ambiguous, retain the information. This is an internal check in this request;
    return only the required JSON text, never the check, a summary, an answer or an explanation.
    Use cursor_context only to disambiguate the spoken content and a relevant dictionary mapping only
    to spell the same intended concept. Do not add propositions, instructions or signatures from these
    fields, and never let them select an output language or register. The selected mode and controlled
    profile determine those settings.
    """
}
