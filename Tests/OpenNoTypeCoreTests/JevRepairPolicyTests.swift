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
                          review: DecisionResult? = nil, terms: [DecisionTermCandidate] = [],
                          expression: DictationExpression = .init()) -> Bool {
        JevRepairPolicy.acceptsRepair(transcript: source, originalOutput: previous, repairedOutput: repair,
                                     review: review ?? clear, terms: terms, expression: expression)
    }

    func testActiveExpressionMayConsolidateOrRestateRepeatedSupportedLiterals() {
        let source = "JEV로 3시에 검토해요. JEV로 3시에 검토하는 거예요."
        let consolidated = "JEV로 3시에 검토해요."
        let expanded = "JEV로 3시에 검토해요. 검토 시간은 3시이고 검토 도구는 JEV예요."
        XCTAssertFalse(accepted(source, consolidated))
        XCTAssertFalse(accepted(consolidated, expanded))
        for style in DictationExpressionStyle.allCases where style != .faithful {
            let expression = DictationExpression(style: style, strength: 70)
            XCTAssertTrue(accepted(source, consolidated, expression: expression), style.rawValue)
            XCTAssertTrue(accepted(consolidated, expanded, expression: expression), style.rawValue)
            XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: source, output: consolidated,
                                                                      expression: expression), style.rawValue)
            XCTAssertFalse(JevRepairPolicy.needsRepair(review: clear, transcript: source, output: consolidated,
                                                       terms: [], expression: expression), style.rawValue)
        }
        XCTAssertFalse(accepted(source, consolidated, expression: .init(style: .summary, strength: 0)))
        XCTAssertFalse(accepted(source, consolidated, expression: .init(style: .faithful, strength: 100)))
    }

    func testFaithfulSpokenRestartMayReduceRepeatedNameReferencesWithoutLosingTheirFacts() {
        let source = "나는 OpenNoType을 개발하고 싶어서 JEV를 리서치하고 있어요. JEV를 리서치하고 있는데요.. 음.. 그런데 말이죠.. 음.. JEV를 리서치할 때 또 필요한 것이 OpenRouter인데요."
        let cleaned = "나는 OpenNoType을 개발하고 싶어서 JEV를 리서치하고 있어요. 그런데 JEV를 리서치할 때 또 필요한 것이 OpenRouter인데요."
        for expression in [DictationExpression(), .init(style: .summary, strength: 0),
                           .init(style: .faithful, strength: 100)] {
            XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: source, output: cleaned,
                                                                      expression: expression))
            XCTAssertFalse(JevRepairPolicy.needsRepair(review: clear, transcript: source, output: cleaned,
                                                       terms: [], expression: expression))
            XCTAssertTrue(accepted(source, cleaned, expression: expression))
        }
        XCTAssertTrue(accepted("JEV로 검토해 주세요. JEV로 검토해 주세요.", "JEV로 검토해 주세요."))
    }

    func testFaithfulCleanupCannotLoseLastNameReferenceChangeIdentityOrInventNameOccurrences() {
        let source = "JEV로 OpenNoType을 검토해요. JEV를 사용해요."
        for output in ["OpenNoType을 검토해요.", "JEV로 검토해요.",
                       "JEV로 OpenType을 검토해요.",
                       "JEV로 OpenNoType과 NewApp을 검토해요.",
                       "JEV로 OpenNoType을 검토해요. JEV를 써요. JEV가 좋아요."] {
            XCTAssertFalse(accepted(source, output), output)
        }
        XCTAssertFalse(JevRepairPolicy.literalConstraintsPreserved(transcript: "JEV로 검토해요.",
            output: "JEV로 검토해요. JEV를 사용해요."))
        // Initial spelling review retains its existing permission to render a spoken name in Latin.
        XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: "제브를 검토해요.",
                                                                  output: "JEV를 검토해요."))
    }

    func testFaithfulCleanupRetainsStrictCountsForNumbersQuotesCodeAndURLs() {
        for repeated in ["3시", "‘JEV’", "`retry_count`", "retry_count", "https://example.com/check"] {
            let source = "\(repeated) 확인. \(repeated) 확인."
            let consolidated = "\(repeated) 확인."
            XCTAssertFalse(JevRepairPolicy.literalConstraintsPreserved(transcript: source,
                                                                      output: consolidated), repeated)
            XCTAssertTrue(JevRepairPolicy.needsRepair(review: clear, transcript: source, output: consolidated,
                                                      terms: []), repeated)
            XCTAssertFalse(accepted(source, consolidated), repeated)
        }
        for output in ["JEV로 3시에 검토해요.", "JEV로 3시 또는 5시에 검토해요.",
                       "JEV로 3시 또는 4시 또는 5시에 검토해요."] {
            XCTAssertFalse(accepted("JEV로 3시 또는 4시에 검토해요.", output), output)
        }
    }

    func testFaithfulNameConsolidationNeverOverridesReviewedDistinctActionNegationOrConditionLoss() {
        let source = "승인되면 JEV로 검토해 주세요. JEV로 배포해 주세요. JEV는 삭제하지 마세요."
        let output = "JEV로 검토해 주세요."
        // Name identity counts cannot decide whether a repeated reference supplied another action.
        XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: source, output: output))
        for axis in [DecisionDetailAxis.intent, .negation, .conditions, .entities] {
            var review = clear; review.detailRisks[axis] = 0.97
            XCTAssertTrue(JevRepairPolicy.needsRepair(review: review, transcript: source, output: output,
                                                      terms: []), axis.rawValue)
            XCTAssertFalse(accepted(source, output, review: review), axis.rawValue)
        }
        var omitted = clear; omitted.contentOmitted = 0.95
        XCTAssertTrue(JevRepairPolicy.needsRepair(review: omitted, transcript: source, output: output, terms: []))
        XCTAssertFalse(accepted(source, output, review: omitted))
    }

    func testActiveExpressionCannotRemoveChangeOrAddADistinctProtectedLiteral() {
        let expression = DictationExpression(style: .summary, strength: 100)
        let source = "JEV와 OpenNoType을 3시 또는 4시에 검토해요."
        for output in ["JEV를 3시에 검토해요.", "JEV와 OpenNoType을 3시에 검토해요.",
                       "JEV와 OpenNoType을 3시 또는 5시에 검토해요.",
                       "JEV와 OpenNoType을 3시 또는 4시 또는 5시에 검토해요.",
                       "JEV와 OpenType을 3시 또는 4시에 검토해요.",
                       "JEV와 OpenNoType과 NewApp을 3시 또는 4시에 검토해요."] {
            XCTAssertFalse(accepted(source, output, expression: expression), output)
        }
        for (source, output) in [("`retry_count` 유지", "`retry_total` 유지"),
                                 ("https://example.com/a 유지", "https://example.com/b 유지"),
                                 ("‘3시’를 그대로 적어", "‘4시’를 그대로 적어")] {
            XCTAssertFalse(accepted(source, output, expression: expression), output)
            XCTAssertFalse(JevRepairPolicy.literalConstraintsPreserved(transcript: source, output: output,
                                                                       expression: expression), output)
        }
    }

    func testActiveExpressionNeverOverridesReviewedFactNegationConditionOrIntentRisk() {
        let expression = DictationExpression(style: .creative, strength: 100)
        let source = "승인되면 JEV로 검토하되 배포하지 마세요."
        for axis in DecisionDetailAxis.allCases {
            var review = clear; review.detailRisks[axis] = 0.97
            XCTAssertTrue(JevRepairPolicy.needsRepair(review: review, transcript: source,
                output: "JEV로 검토하고 바로 배포할게요.", terms: [], expression: expression), axis.rawValue)
            XCTAssertFalse(accepted(source, "JEV로 검토하고 바로 배포할게요.", review: review,
                                    expression: expression), axis.rawValue)
        }
        var invented = clear; invented.contentAdded = 0.95
        XCTAssertFalse(accepted("검토해요", "안전하므로 검토해요.", review: invented, expression: expression))
        var lost = clear; lost.contentOmitted = 0.95
        XCTAssertFalse(accepted(source, "검토해요.", review: lost, expression: expression))
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

    func testEnglishApostrophesAreNotProtectedQuotationMarks() {
        for (source, output) in [
            ("I don't think it's necessary.", "I do not think it is necessary."),
            ("I don’t think it’s necessary.", "I do not think it is necessary."),
            ("James' book is Alice's choice.", "The book belonging to James is Alice's choice."),
            ("James’ book is Alice’s choice.", "The book belonging to James is Alice’s choice.")
        ] {
            XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: source, output: output), source)
            XCTAssertTrue(accepted(source, output), source)
        }
        for (source, changed) in [
            ("Keep 'don't change' exactly.", "Keep 'do not change' exactly."),
            ("Keep ‘don’t change’ exactly.", "Keep ‘do not change’ exactly."),
            ("'3시'를 유지해요.", "'4시'를 유지해요."),
            ("‘3시’를 유지해요.", "‘4시’를 유지해요.")
        ] {
            XCTAssertTrue(accepted(source, source + " "), source)
            XCTAssertFalse(accepted(source, changed), source)
        }
    }

    func testUnrelatedNumbersCannotBeConsumedBySomeoneElseCorrection() {
        for source in ["회의는 3시에 있고, 제가 아니라 4명이 참석해요.",
                       "예산은 30원이고, 제가 아니라 4명이 참석해요.",
                       "회의는 3시에 있고, 제가 아니라 4시에 퇴근해요.",
                       "버전은 1.2예요. 아니 4명이 참석해요.",
                       "날짜는 10/03이고, 장소가 아니라 4개를 바꿔요."] {
            XCTAssertTrue(JevRepairPolicy.literalConstraintsPreserved(transcript: source, output: source), source)
            XCTAssertTrue(accepted(source, source + " "), source)
        }
        XCTAssertFalse(accepted("회의는 3시에 있고, 제가 아니라 4명이 참석해요.", "제 대신 4명이 참석해요."))
        XCTAssertFalse(accepted("회의는 3시에 있고, 제가 아니라 4시에 퇴근해요.", "제 대신 4시에 퇴근해요."))
        for (source, corrected) in [("회의는 3시 아니 4시에 시작해요.", "회의는 4시에 시작해요."),
                                    ("금액은 30원 아니 40원이에요.", "금액은 40원이에요."),
                                    ("버전은 1.2 아니 1.3이에요.", "버전은 1.3이에요."),
                                    ("날짜는 10/03 아니 10/04예요.", "날짜는 10/04예요.")] {
            XCTAssertTrue(accepted(source, corrected), source)
        }
    }

    func testLiteralDiagnosticsDriveExactRepairAndLearningCategories() {
        for (source, changed, failure, issue) in [
            ("3시에 만나요", "4시에 만나요", JevLiteralConstraintFailure.numbers, JevRepairIssue.numbers),
            ("‘원문’을 유지", "‘수정’을 유지", .quotes, .quotes),
            ("`retry_count` 유지", "`retry_total` 유지", .code, .code),
            ("https://example.com/a 유지", "https://example.com/b 유지", .urls, .urls),
            ("OpenNoType 유지", "OpenType 유지", .identities, .entities)
        ] {
            XCTAssertEqual(JevRepairPolicy.literalConstraintFailures(transcript: source, output: changed), [failure])
            XCTAssertEqual(JevRepairPolicy.repairIssues(review: clear, transcript: source, output: changed, terms: []), [issue])
        }
        XCTAssertEqual(JevRepairPolicy.literalConstraintFailures(transcript: "", output: "문장"), [.emptyInput])
        XCTAssertEqual(JevRepairPolicy.literalConstraintFailures(transcript: "3시 ‘원문’ `retry_count` JEV",
            output: "4시 ‘수정’ `retry_total` JAV"), [.numbers, .quotes, .code, .identities])
        var review = clear; review.contentOmitted = 0.95
        XCTAssertEqual(JevRepairPolicy.repairIssues(review: review, transcript: "3시에 만나요",
            output: "4시에 만나요", terms: []), [.omissions, .numbers])
        XCTAssertEqual(JevRepairPolicy.repairIssues(review: clear, transcript: "정상이에요",
            output: "정상이에요.", terms: []), [])
    }

    func testAnyRemainingRiskAtHalfOrAboveRejectsAutomaticInsertion() {
        for issue in JevRepairIssue.allCases where ![.quotes, .code, .urls].contains(issue) {
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
