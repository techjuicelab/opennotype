import Foundation

/// Semantic cleanup is performed in the existing text request, never by deleting source tokens locally.
/// These examples are authored acceptance examples, not captured output from another product.
enum DictationCleanupInstructions {
    /// Dictation-only naming guidance; voice edits retain their explicitly requested terminology.
    static let technicalSpellings = """
    OFFICIAL TECHNICAL SPELLINGS: established products, services, apps, libraries, programming languages,
    protocols and abbreviations use official Latin spelling/case/digits even when spoken in Hangul.
    Normalize the same concept, never translate. All profiles; no dictionary needed. Examples are
    not a closed list. Use context; never guess unknown names or turn ordinary words into brands.
    Keep Korean loanwords 파일, 프로젝트, 폴더, 서버 in Hangul. Dictionary hints spell the same concept;
    an explicit spelling or literal instruction always wins, including Hangul. Preserve quotes, identifiers and URLs.

    오픈 라우터 API 키는 원 패스워드에 저장되어 있어요 → OpenRouter API 키는 1Password에 저장되어 있어요.
    오픈 노타입은 타이프리스를 대신하고 그록을 써서 깃허브와 노션의 에이피아이를 연결해요 → OpenNoType은 Typeless를 대신하고 Groq를 써서 GitHub와 Notion의 API를 연결해요.
    프로젝트 파일을 폴더에 넣고 서버에 올려 주세요 → 프로젝트 파일을 폴더에 넣고 서버에 올려 주세요.
    제품 이름은 '오픈 라우터'라고 한글 그대로 적어 주세요 → 제품 이름은 '오픈 라우터'라고 한글 그대로 적어 주세요.
    """

    private static let cleanupContract = """
    CLEANUP CONTRACT: express each distinct meaning once, with all its details.
    Removing an accidental duplicate is not summarizing. Actively remove hesitation-only fillers,
    abandoned sentence starts and redundant phrases, including a repeated request later in the utterance.
    When two phrases express the same point, combine their information: retain every added subject,
    action, object, name, time, place, reason, condition, exception and limit. Do not keep a false start
    merely to avoid deleting information; carry its still-valid details into the completed sentence.
    """

    private static let faithfulCleanupContract = """
    CLEANUP CONTRACT: express each distinct meaning once, with all its details.
    Remove hesitation-only fillers, in any language.
    Merge sentence/clause restarts of the same proposition, across pauses or changed endings.
    A complete clause can still restart a thought. Combine subjects, actions, objects, names,
    times, places, goals/reasons, conditions, exceptions, limits, stance and unfinished tone.
    Remove the redundant clause, not its details or goal-to-action link. This is not a summary.
    Split connective from filler: "그런데 말이죠" → "그런데"; never change contrast to addition.
    """

    /// Default dictation clarifies restart cleanup without changing translation or expression modes.
    static var faithfulRules: String {
        rules.replacingOccurrences(of: cleanupContract, with: faithfulCleanupContract)
    }

    static let rules = """

    \(cleanupContract)

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

    SPOKEN SPELLING CORRECTION: a name immediately followed by its individual letters in the same
    utterance clarifies that one name, even without "아니" or "철자는". Join those letters into ONE
    Latin token and replace the preceding phonetic/misrecognized name; do not output both forms.
    Letters may be recognized as Korean letter names, spaced Latin letters, or a mixture. Decode
    every letter in order: 제이 이 브이 / J E V means JEV, not JV. Use uppercase for a spelled acronym
    unless the speaker specifies another case. Retain any attached Korean particle after the joined name.
    This explicit spelling wins over a conflicting dictionary or familiar brand. It also works for
    unfamiliar names; no vocabulary registration is needed. Remove only redundant pronunciation and
    spelling-repair scaffolding, keeping the name's role and all other facts, requests and uncertainty.
    "영어 철자는 ...예요" and "...가 아니라 ..." can supply that same correction across clauses;
    after resolving it, use the complete joined spelling for that name and drop its redundant explanation.
    Do not infer a spelling from the phonetic name alone, or join unrelated letters in a list or lesson.
    Preserve literal quotes, code, a request to keep Hangul, or an explicit request for separated letters.
    An existing identifier such as j_e_v is NOT a letter sequence: never remove its underscores or
    change its case. This correction applies only to a name being spelled out, not to every similar token.

    제브 제이 이 브이 활용하기 좋은 아이디어들 적용하고 싶어요 → JEV 활용하기 좋은 아이디어들을 적용하고 싶어요.
    제부 J E V로 문장을 검토해 주세요 → JEV로 문장을 검토해 주세요.
    제브 제이 이 브이를 써서 표기를 확인해 주세요 → JEV를 써서 표기를 확인해 주세요.
    제브라는 모델이고 영어 철자는 제이 이 브이예요. 이 모델로 검토하고 싶어요 → JEV라는 모델이고 이 모델로 검토하고 싶어요.
    제부가 아니라 제브, 영어 철자는 J E V예요. 그걸로 표기를 검토해 주세요 → JEV로 표기를 검토해 주세요.
    우리 도구 이름은 루멕스이고 철자는 R U M E X야. 루멕스에 저장하고 싶어 → 우리 도구 이름은 RUMEX야. RUMEX에 저장하고 싶어.
    제부가 내일 집에 온대요 → 제부가 내일 집에 온대요.
    코드의 j_e_v 변수 이름은 바꾸지 말고 설명만 짧게 정리해 주세요 → 코드의 j_e_v 변수 이름은 바꾸지 말고 설명만 짧게 정리해 주세요.

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
