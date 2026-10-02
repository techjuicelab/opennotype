import Foundation
import XCTest
@testable import OpenNoTypeCore

final class JevRepairPolicyTests: XCTestCase {
    private var clear: DecisionResult { .init(meaningChanged: 0.01, contentAdded: 0.01, contentOmitted: 0.01) }
    private var spelling: DecisionTermCandidate { .init(id: "name", original: "제브", candidate: "JEV") }
    private func choice(_ selection: DecisionTermChoice = .useCandidate, confidence: Double = 0.9) -> DecisionTermResult {
        .init(id: "name", choice: selection,
              probabilities: Dictionary(uniqueKeysWithValues: DecisionTermChoice.allCases.map { ($0, $0 == selection ? 0.94 : 0.03) }),
              confidence: confidence)
    }
    private func accepted(_ source: String, _ repair: String, previous: String = "잘못된 결과",
                          review: DecisionResult? = nil, terms: [DecisionTermCandidate] = []) -> Bool {
        JevRepairPolicy.acceptsRepair(transcript: source, originalOutput: previous, repairedOutput: repair,
                                     review: review ?? clear, terms: terms)
    }

    func testStrongRiskCategoriesHaveStableTypedOrderAndExcludeWeakSignals() {
        let result = DecisionResult(meaningChanged: 0.92, contentAdded: 0.3, contentOmitted: 0.95,
                                   detailRisks: [.entities: 0.94, .numbers: 0.9, .negation: 0.2, .conditions: 0.91])
        XCTAssertEqual(JevRepairPolicy.issues(in: result), [.meaning, .omissions, .numbers, .conditions, .entities])
        XCTAssertEqual(JevRepairPolicy.issues(in: clear), [])
        for threshold in [-1, Double.nan, Double.infinity, 1.1] {
            XCTAssertTrue(JevRepairPolicy.issues(in: result, threshold: threshold).isEmpty)
        }
    }

    func testInvalidRiskDoesNotAuthorizeRepairOrAcceptance() {
        for value in [-0.1, 1.1, Double.nan, Double.infinity] {
            var review = clear; review.detailRisks[.numbers] = value
            XCTAssertFalse(JevRepairPolicy.reviewIsValid(review))
            XCTAssertFalse(JevRepairPolicy.needsRepair(review: review, transcript: "3시에 만나요", output: "4시에 만나요", terms: []))
            XCTAssertFalse(accepted("3시에 만나요", "3시에 만나요.", review: review))
            XCTAssertTrue(JevRepairPolicy.issues(in: review).isEmpty)
        }
    }

    func testCandidateMatchingRejectsIncompleteOrUntrustedInitialReviews() {
        XCTAssertTrue(JevRepairPolicy.reviewMatchesCandidates(clear, terms: []))
        var valid = clear; valid.terms = [choice()]
        XCTAssertTrue(JevRepairPolicy.reviewMatchesCandidates(valid, terms: [spelling]))
        XCTAssertFalse(JevRepairPolicy.reviewMatchesCandidates(valid, terms: []))
        XCTAssertFalse(JevRepairPolicy.reviewMatchesCandidates(clear, terms: [spelling]))
        var duplicate = valid; duplicate.terms.append(choice())
        XCTAssertFalse(JevRepairPolicy.reviewMatchesCandidates(duplicate, terms: [spelling]))
    }

    func testInitialLiteralFactsTriggerEvenWhenJevMissesThem() {
        XCTAssertTrue(JevRepairPolicy.needsRepair(review: clear, transcript: "3시에 만나요", output: "4시에 만나요", terms: []))
        XCTAssertFalse(JevRepairPolicy.needsRepair(review: clear, transcript: "안녕하세요", output: "안녕하세요.", terms: []))
        XCTAssertTrue(JevRepairPolicy.needsRepair(review: .init(meaningChanged: 0.95, contentAdded: 0.01, contentOmitted: 0.01),
                                                transcript: "안녕하세요", output: "안녕하세요.", terms: []))
        // New Latin rendering of a spoken product is not itself an invented-number alarm.
        XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: "오픈 라우터를 사용해요", output: "OpenRouter를 사용해요."))
        XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: "원 패스워드를 사용해요", output: "1Password를 사용해요."))
    }

    func testStrongSourceSupportedSpellingChoiceCanTriggerAndRepair() {
        var review = clear; review.terms = [choice()]
        XCTAssertTrue(JevRepairPolicy.needsRepair(review: review, transcript: "제브를 써요", output: "제브를 써요.", terms: [spelling]))
        XCTAssertFalse(JevRepairPolicy.needsRepair(review: review, transcript: "제브를 써요", output: "JEV를 써요.", terms: [spelling]))
        XCTAssertTrue(accepted("제브를 써요", "JEV를 써요.", previous: "제브를 써요.", review: review, terms: [spelling]))
        XCTAssertFalse(accepted("제브를 써요", "JAB를 써요.", review: review, terms: [spelling]))
    }

    func testUncertainUnapprovedOrMalformedChoicesCannotAuthorizeRepair() {
        for result in [choice(.uncertain), choice(confidence: 0.5),
                       .init(id: "name", choice: .useCandidate, probabilities: [.useCandidate: 1], confidence: 0.9),
                       .init(id: "name", choice: .useCandidate,
                             probabilities: [.useCandidate: .nan, .keepOriginal: 0, .uncertain: 0], confidence: 0.9)] {
            var review = clear; review.terms = [result]
            XCTAssertFalse(accepted("제브를 써요", "JEV를 써요.", review: review, terms: [spelling]))
        }
        var review = clear; review.terms = [choice()]
        XCTAssertFalse(accepted("그 앱을 써요", "JEV를 써요.", review: review, terms: [spelling]))
        XCTAssertFalse(accepted("제브를 써요", "JEV를 써요.", review: review, terms: []))
        XCTAssertFalse(accepted("제브를 써요", "JEV를 써요.", review: clear, terms: [spelling]))
        XCTAssertFalse(accepted("제브를 써요", "JEV를 써요.", review: review, terms: [spelling, spelling]))
        var keep = clear; keep.terms = [choice(.keepOriginal)]
        XCTAssertTrue(accepted("제브를 한글로 적어", "제브를 한글로 적어.", previous: "JEV를 한글로 적어.", review: keep, terms: [spelling]))
    }

    func testKnownNamesAlreadyResolvedCannotBeUndoneDuringAnotherRepair() {
        var review = clear; review.terms = [choice()]
        XCTAssertTrue(accepted("제브에서 3시에 확인해요", "JEV에서 3시에 확인해요.", previous: "JEV에서 4시에 확인해요.", review: review, terms: [spelling]))
        XCTAssertFalse(accepted("제브에서 3시에 확인해요", "제브에서 3시에 확인해요.", previous: "JEV에서 4시에 확인해요.", review: review, terms: [spelling]))
        XCTAssertFalse(accepted("JEV에서 확인해요", "JAB에서 확인해요."))
        XCTAssertFalse(accepted("OpenNoType에서 확인해요", "OpenNotype에서 확인해요."))
    }

    func testSourceFactsWinOverAnIncorrectInitialOutput() {
        XCTAssertTrue(accepted("3시에 만나요", "3시에 만나요.", previous: "4시에 만나요."))
        XCTAssertFalse(accepted("3시에 만나요", "5시에 만나요.", previous: "4시에 만나요."))
        XCTAssertFalse(accepted("만나요", "3시에 만나요."))
        XCTAssertFalse(accepted("2시간 뒤에 만나요", "2분 뒤에 만나요."))
        XCTAssertFalse(accepted("거리는 2m입니다", "거리는 3m입니다."))
        XCTAssertFalse(accepted("온도 차이는 -3입니다", "온도 차이는 3입니다."))
        XCTAssertFalse(accepted("차이는 −3분입니다", "차이는 3분입니다."))
        XCTAssertTrue(accepted("차이는 -3분입니다", "차이는 -3분입니다."))
        XCTAssertFalse(accepted("금액은 $2입니다", "금액은 €2입니다."))
    }

    func testCountedKoreanIntegersHaveNarrowEquivalentDigitSpellings() {
        for (spoken, digits) in [("세 시에 만나요", "3시에 만나요."), ("파일 두 개를 주세요", "파일 2개를 주세요."),
                                 ("한 명을 불러요", "1명을 불러요."), ("열두 명이 와요", "12명이 와요."),
                                 ("서른세 개를 주세요", "33개를 주세요."), ("삼십오 분 뒤에 와요", "35분 뒤에 와요."),
                                 ("아흔아홉 초만 기다려요", "99초만 기다려요."), ("구십구 원이에요", "99원이에요.")] {
            XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: spoken, output: digits), spoken)
            XCTAssertTrue(accepted(spoken, digits), spoken)
        }
        XCTAssertFalse(accepted("세 시에 만나요", "4시에 만나요."))
        XCTAssertFalse(accepted("두 개 주세요", "3개 주세요."))
        XCTAssertFalse(accepted("세 분 뒤에 와요", "3초 뒤에 와요."))
        XCTAssertTrue(accepted("일 분 아니 삼 분 뒤에", "3분 뒤에."))
    }

    func testSpokenCountNormalizationDoesNotTouchProtectedOrOrdinaryWords() {
        for source in ["‘세 시’를 그대로 적어", "`두 개`라는 이름", "https://example.com/세시", "한 일을 기록해요", "세상을 기록해요"] {
            XCTAssertTrue(accepted(source, source + "."))
        }
        XCTAssertFalse(accepted("‘세 시’를 그대로 적어", "‘3시’를 그대로 적어."))
        XCTAssertFalse(accepted("`두 개`라는 이름", "`2개`라는 이름."))
        XCTAssertFalse(accepted("백삼십 분 뒤에", "30분 뒤에."))
        XCTAssertFalse(accepted("세라고 적어", "3이라고 적어."))
    }

    func testCountedEnglishIntegersNormalizeOnlyWithSupportedUnits() {
        XCTAssertTrue(accepted("three minutes later", "3 minutes later."))
        XCTAssertTrue(accepted("twenty-one items", "21 items."))
        XCTAssertTrue(accepted("ninety nine seconds", "99 seconds."))
        XCTAssertFalse(accepted("three minutes later", "4 minutes later."))
        XCTAssertFalse(accepted("one hundred one minutes", "1 minute."))
        XCTAssertFalse(accepted("one hundred and one minutes", "1 minute."))
        XCTAssertFalse(accepted("three", "3"))
    }

    func testExplicitSettledNumericCorrectionsKeepOnlyTheSupportedFinalValue() {
        let source = "오전 7시에 볼까… 아닌가… 오후 3시에 보자"
        XCTAssertTrue(accepted(source, "오후 3시에 보자.", previous: "오전 7시에 보자."))
        XCTAssertFalse(accepted(source, "오후 4시에 보자."))
        XCTAssertFalse(accepted(source, "오전 7시와 오후 3시에 보자."))
        XCTAssertTrue(accepted("2개 아니 3개 주세요", "3개 주세요."))
        XCTAssertTrue(accepted("retry_count 말고 retry_total로 적어", "retry_total로 적어."))
    }

    func testUnsettledOrAlternativeValuesAreNeverResolvedByTheLocalGate() {
        XCTAssertTrue(accepted("오전 7시에 볼까… 아닌가… 잘 모르겠어", "오전 7시에 볼까? 아닌가, 잘 모르겠어."))
        XCTAssertFalse(accepted("오전 7시에 볼까… 아닌가… 잘 모르겠어", "오후 3시에 보자."))
        XCTAssertFalse(accepted("2개 아니 아마 3개일까", "3개 주세요."))
        XCTAssertFalse(accepted("2개 또는 3개 주세요", "3개 주세요."))
        XCTAssertFalse(accepted("2개가 아닌 경우 3개를 주문해요", "3개를 주문해요."))
        XCTAssertFalse(accepted("2개 아니면 3개 주세요", "3개 주세요."))
        XCTAssertFalse(accepted("2개 아니 3개인지 잘 모르겠어", "3개 주세요."))
        XCTAssertFalse(accepted("3 is not equal to 4", "4"))
        XCTAssertTrue(accepted("2, I mean 3", "3"))
    }

    func testURLsQuotesAndCodeCannotBeRewrittenOrInventedDespiteLowSemanticRisk() {
        for (source, changed) in [
            ("https://example.com/a 사용", "https://example.com/b 사용"),
            ("`retry_count`를 유지", "`retry_total`를 유지"),
            ("retry_count 유지", "retry_total 유지"),
            ("‘커미’를 유지", "‘commit’을 유지"),
            ("안녕하세요", "안녕하세요 ‘새 내용’"),
            ("JEV와 OpenNoType", "JEV와 OpenType")
        ] { XCTAssertFalse(accepted(source, changed)) }
        XCTAssertTrue(accepted("‘커미’를 유지", "'커미'를 유지하세요."))
        var review = clear; review.terms = [choice()]
        XCTAssertFalse(accepted("‘제브’를 한글 그대로 유지", "‘JEV’를 유지", review: review, terms: [spelling]))
    }

    func testAnyRemainingRiskAtHalfOrAboveRejectsAutomaticInsertion() {
        for issue in JevRepairIssue.allCases {
            var review = clear
            switch issue {
            case .meaning: review.meaningChanged = 0.5
            case .additions: review.contentAdded = 0.5
            case .omissions: review.contentOmitted = 0.5
            default: review.detailRisks[DecisionDetailAxis(rawValue: issue.rawValue)!] = 0.5
            }
            XCTAssertFalse(accepted("안녕하세요", "안녕하세요.", review: review), issue.rawValue)
        }
    }

    func testEmptyUnchangedAndOversizedRepairCannotPass() {
        XCTAssertFalse(accepted("안녕하세요", " "))
        XCTAssertFalse(accepted("안녕하세요", "안녕하세요", previous: "안녕하세요"))
        XCTAssertFalse(accepted("", "안녕하세요."))
        XCTAssertFalse(accepted("안녕하세요", String(repeating: "가", count: 8_001)))
    }

    func testReservationUsesCurrentProviderKnownPriceAndActualPromptBytes() throws {
        let request = ProcessingRequest(mode: .dictation, transcript: "3시에 만나요", previousOutput: "4시에 만나요", repairIssues: [.numbers])
        let configuration = ProviderConfiguration(provider: .groq, apiKey: "not-a-secret", transcriptionModel: "whisper-large-v3-turbo", textModel: "openai/gpt-oss-20b")
        let amount = try XCTUnwrap(JevRepairPolicy.repairReservationUSD(request: request, configuration: configuration))
        let bytes = try ProviderClient.processingInputBytes(request)
        XCTAssertEqual(amount, (Double(bytes + 4_096) * 0.075 + 16_384 * 0.30) / 1_000_000 + 0.003)
        XCTAssertLessThan(amount, 0.05)
        var unknown = configuration; unknown.textModel = "unknown"
        XCTAssertNil(JevRepairPolicy.repairReservationUSD(request: request, configuration: unknown))
        XCTAssertNil(JevRepairPolicy.repairReservationUSD(request: .init(mode: .dictation, transcript: "안녕"), configuration: configuration))
        XCTAssertNil(JevRepairPolicy.repairReservationUSD(request: .init(mode: .translation, transcript: "안녕", previousOutput: "hi"), configuration: configuration))
        let huge = ProcessingRequest(mode: .dictation, transcript: String(repeating: "가", count: 40_000), previousOutput: "안녕")
        XCTAssertNil(JevRepairPolicy.repairReservationUSD(request: huge, configuration: configuration))
    }

    func testExpensiveKnownReservationIsReturnedForCallerBudgetGate() throws {
        let request = ProcessingRequest(mode: .dictation, transcript: "안녕", previousOutput: "반가워", repairIssues: [.meaning])
        let expensive = ProviderConfiguration(provider: .anthropic, apiKey: "not-a-secret", transcriptionModel: "unused", textModel: "claude-sonnet-4-6")
        XCTAssertGreaterThan(try XCTUnwrap(JevRepairPolicy.repairReservationUSD(request: request, configuration: expensive)), 0.05)
    }
}
