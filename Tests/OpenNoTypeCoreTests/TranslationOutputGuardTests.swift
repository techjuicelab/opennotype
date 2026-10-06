import Foundation
import XCTest
@testable import OpenNoTypeCore

/// Deterministic rejection coverage, not proof of native wording or full semantic preservation.
final class TranslationOutputGuardTests: XCTestCase {
    private func validate(_ source: String, _ output: String, language: String = "English (United States)") throws {
        try TranslationOutputGuard.validate(source: source, output: output, targetLanguage: language)
    }

    private func rejects(_ source: String, _ output: String, _ expected: ProviderError,
                         language: String = "English (United States)", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try validate(source, output, language: language), file: file, line: line) {
            XCTAssertEqual($0 as? ProviderError, expected, file: file, line: line)
        }
    }

    func testBacktickCodeAllowsQuoteStyleButRequiresExactCaseAndSeparators() throws {
        let source = "`sora_key` 값은 그대로 두세요."
        try validate(source, "Please keep the sora_key value.")
        try validate(source, "「sora_key」の値を維持してください。", language: "Japanese")
        rejects(source, "Keep `Sora_key`.", .translationLiteralChanged)
        rejects(source, "Keep `soraKey`.", .translationLiteralChanged)
    }

    func testExplicitCodeNamesKeepHangulContentsWhileOrdinaryQuotationsTranslate() throws {
        let source = "코드의 '달솔'이라는 변수는 그대로 두세요."
        try validate(source, "コードの「달솔」という変数は維持してください。", language: "Japanese")
        try validate(source, "コードの달솔という変数は維持してください。", language: "Japanese")
        try validate(source, "코드 변수는달솔이라는 이름을 유지해 주세요.", language: "Korean")
        rejects(source, "コードの「달ソル」という変数は維持してください。", .translationLiteralChanged, language: "Japanese")
        rejects("'마루'라는 변수명은 유지하세요.", "Keep the variable name 'Maru'.", .translationLiteralChanged)
        rejects("'솜결'이라는 함수명을 유지하세요.", "Keep the function name 'Somgyeol'.", .translationLiteralChanged)
        try validate("'좋은 하루'라고 인사해 주세요.", "Please say 'Have a good day'.")
        try validate("변수는 중요해요. 그는 '좋은 하루'라고 말했어요.", "Variables matter. He said 'Have a good day'.")
    }

    func testLiteralBoundaryRejectsNamesInsideOtherIdentifiers() throws {
        let source = "변수 이름은 'pin'입니다."
        try validate(source, "The variable name is pin.")
        rejects(source, "The variable name is spindle.", .translationLiteralChanged)
        rejects(source, "The variable name is pin_backup.", .translationLiteralChanged)
        rejects(source, "変数名は「pinの別名」です。", .translationLiteralChanged, language: "Japanese")
        try validate(source, "コードのpinという変数は維持してください。", language: "Japanese")
        try validate(source, "変数pinの値は維持してください。", language: "Japanese")
    }

    func testLiteralUTF8DoesNotFoldCanonicallyEquivalentNames() throws {
        let source = "변수 이름은 'café'입니다."
        try validate(source, "The variable is 'café'.")
        rejects(source, "The variable is 'cafe\u{0301}'.", .translationLiteralChanged)
    }

    func testASCIILinksKeepFullURLRatherThanMatchingPrefixAndIgnoreSentencePunctuation() throws {
        let source = "Visit https://guide.invalid/open."
        try validate(source, "https://guide.invalid/open をご覧ください。", language: "Japanese")
        rejects(source, "Visit https://guide.invalid/open/more.", .translationLiteralChanged)
        rejects(source, "Visit https://guide.invalid/opened.", .translationLiteralChanged)
        try validate("See https://guide.invalid/a_(b).", "https://guide.invalid/a_(b) を参照してください。", language: "Japanese")
    }

    func testAmbiguousUnicodeLinksAreSkippedInsteadOfFreezingParticlesOrASCIIFragments() throws {
        try validate("https://guide.invalid/open를 확인해 주세요.", "Please check https://guide.invalid/open.")
        try validate("https://guide.invalid/자료를 확인해 주세요.", "Please check the page.")
        try validate("See https://guide.invalid/open.", "https://guide.invalid/openをご覧ください。", language: "Japanese")
        // Code delimiters make the full international URL an explicit literal instead.
        rejects("Keep `https://guide.invalid/자료`.", "Keep `https://guide.invalid/data`.", .translationLiteralChanged)
    }

    func testClearAdjacentLiteralCorrectionsDoNotRequireTheDiscardedValue() throws {
        try validate("Use `early_key`, no, `final_key`.", "Use `final_key`.")
        try validate("변수는 `먼저`로, 아니 `나중`으로 적어 주세요.", "Use `나중` as the variable name.")
        try validate("Use `early_key`, actually use `final_key` instead.", "Use `final_key`.")
        rejects("Keep `early_key`; perhaps use `final_key`, I'm not sure.", "Use `final_key`.", .translationLiteralChanged)
        rejects("Keep `early_key`, do not replace it with `final_key`.", "Use `final_key`.", .translationLiteralChanged)
    }

    func testLiteralCountsMayChangeWhenAccidentalRepetitionIsCleaned() throws {
        try validate("Use `sora_key`, `sora_key`.", "Use `sora_key`.")
    }

    func testUnspecifiedNumericClockCannotGainSupportedPeriodNotation() throws {
        let source = "내일 4시까지 보내 주세요."
        for output in ["Please send it by 4 PM tomorrow.", "Please send it by 4 p.m. tomorrow.",
                       "Please send it by 4\u{202F}p.m. tomorrow.", "Please send it by 4 pm tomorrow.",
                       "Please send it at 4:00 AM tomorrow."] {
            rejects(source, output, .translationTimeInferred)
        }
        rejects(source, "내일 오후 4시까지 보내 주세요.", .translationTimeInferred, language: "Korean")
        rejects(source, "明日の午後4時までに送ってください。", .translationTimeInferred, language: "Japanese")
    }

    func testUnqualifiedClockFormatsAndNonTemporalQuantitiesRemainAllowed() throws {
        try validate("월요일 9시 이후에 보내 주세요.", "Please send it after 9:00 on Monday.")
        try validate("7시까지 18개를 보내고 4개는 제외해 주세요.", "Send 18 items by 7 o'clock and exclude four.")
        try validate("작업은 4시간 걸려요.", "The work takes four hours.")
        // Other numeric changes are outside this period-only check.
        try validate("4시까지 보내 주세요.", "Please send it by 5 PM.")
    }

    func testExplicitPeriodMixedSpeechAnd24HourSpeechOptOutConservatively() throws {
        try validate("내일 오후 4시까지 보내 주세요.", "Please send it by 4 PM tomorrow.")
        try validate("내일 16시까지 보내 주세요.", "Please send it by 4 PM tomorrow.")
        try validate("오전 8시 회의 후 4시까지 보내 주세요.", "Please send it by 4 PM after the morning meeting.")
        try validate("16:30은 어렵고 4시에 가능해요.", "It may be possible at 4 PM.")
    }

    func testCodeAndURLTimeLikeContentsDoNotSupplyOrTriggerAClockPeriod() throws {
        try validate("4시까지 `4PM` 값을 보내 주세요.", "Send the 4PM value by 4 o'clock.")
        try validate("4시까지 https://guide.invalid/4PM 보내 주세요.", "Send https://guide.invalid/4PM by 4 o'clock.")
        rejects("4시까지 https://guide.invalid/4PM 보내 주세요.", "Send https://guide.invalid/4PM by 4 PM.", .translationTimeInferred)
        try validate("4시에 확인해 주세요. 측정 단위도 유지해 주세요.", "Check at 4 o'clock. The unit is 4 pm.")
    }

    func testUnparsedWordClocksAndActorsAreOutsideLocalGuardCoverage() throws {
        try validate("네 시까지 보내 주세요.", "Please send it by 4 PM.")
        try validate("Send it by 4 o'clock.", "Please send it by 4 PM.")
        try validate("승인되면 시작할 수도 있어요.", "We might start if approved.")
    }
}
