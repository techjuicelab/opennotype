import Foundation
import XCTest
@testable import OpenNoTypeCore

final class JevModelEvaluationTests: XCTestCase {
    private let models = ["inclusionai/ling-3.0-flash", "openai/gpt-oss-20b"]
    private var example: ModelEvaluationCase { .init(transcript: "제브 설정 확인", approvedText: "JEV 설정 확인") }

    func testPlanReservesAllGenerationAndReviewCallsBeforeExecution() throws {
        let item = example
        let plan = try JevModelEvaluation.plan(cases: [item], models: models, provider: .openRouter,
            decisionProvider: .typeSafe, dictionary: [], budgetUSD: 0.05)
        XCTAssertEqual(plan.maximumCalls, 4)
        XCTAssertEqual(plan.models, models)
        XCTAssertEqual(plan.reservations.count, 2)
        XCTAssertTrue(plan.estimatedReservationUSD > 0)
        XCTAssertLessThanOrEqual(plan.estimatedReservationUSD, 0.05)
        XCTAssertEqual(plan.reservations.reduce(0) { $0 + $1.generationUSD + $1.reviewUSD }, plan.estimatedReservationUSD)
        XCTAssertTrue(plan.reservations.allSatisfy { $0.caseID == item.id && $0.generationUSD > 0 && $0.reviewUSD > 0 })
    }

    func testInvalidCasesModelsAndBudgetsFailClosed() {
        for cases in [[], Array(repeating: example, count: 6), [.init(transcript: "", approvedText: "answer")],
                      [.init(transcript: "source", approvedText: String(repeating: "가", count: 1_400))]] as [[ModelEvaluationCase]] {
            XCTAssertThrowsError(try JevModelEvaluation.plan(cases: cases, models: models, provider: .openRouter,
                decisionProvider: .typeSafe, dictionary: [], budgetUSD: 0.05))
        }
        for selection in [[models[0]], [models[0], models[0]], [" ", models[0]]] {
            XCTAssertThrowsError(try JevModelEvaluation.plan(cases: [example], models: selection, provider: .openRouter,
                decisionProvider: .typeSafe, dictionary: [], budgetUSD: 0.05))
        }
        for budget in [0, -1, Double.nan, Double.infinity, 0.21] {
            XCTAssertThrowsError(try JevModelEvaluation.plan(cases: [example], models: models, provider: .openRouter,
                decisionProvider: .typeSafe, dictionary: [], budgetUSD: budget))
        }
    }

    func testUnknownPricesAndInsufficientReservationStopBeforeRequests() {
        XCTAssertThrowsError(try JevModelEvaluation.plan(cases: [example], models: ["unknown", models[0]], provider: .openRouter,
            decisionProvider: .openRouter, dictionary: [], budgetUSD: 0.20)) { XCTAssertEqual($0 as? ModelEvaluationError, .unavailablePrice) }
        XCTAssertThrowsError(try JevModelEvaluation.plan(cases: [example], models: models, provider: .openRouter,
            decisionProvider: .typeSafe, dictionary: [], budgetUSD: 0.000_001)) {
            guard case .exceedsBudget(let estimate) = $0 as? ModelEvaluationError else { return XCTFail("Expected reservation rejection") }
            XCTAssertTrue(estimate > 0.000_001)
        }
    }

    func testOversizedDictionaryPayloadCannotBeSentByComparison() {
        let dictionary = (0..<200).map { DictionaryEntry(spoken: "\($0)" + String(repeating: "가", count: 119),
                                                        written: String(repeating: "x", count: 120)) }
        XCTAssertThrowsError(try JevModelEvaluation.plan(cases: [example], models: models, provider: .openRouter,
            decisionProvider: .typeSafe, dictionary: dictionary, budgetUSD: 0.20)) {
            XCTAssertEqual($0 as? ModelEvaluationError, .inputTooLarge)
        }
    }

    func testQuotedIdentifiersNumbersAndURLsOverrideLowJevSignals() {
        let review = DecisionResult(meaningChanged: 0.01, contentAdded: 0.01, contentOmitted: 0.01)
        for (approved, changed) in [("JEV를 써요", "JV를 써요"), ("값은 3이에요", "값은 4이에요"),
            ("`retry_count`는 2", "`retry_counts`는 2"), ("‘커미’를 유지", "‘commit’을 유지"),
            ("https://example.com/a 사용", "https://example.com/b 사용"), ("retry_count 유지", "retry_number 유지")] {
            XCTAssertFalse(JevModelEvaluation.passes(approvedText: approved, output: changed, review: review))
            XCTAssertTrue(JevModelEvaluation.passes(approvedText: approved, output: approved, review: review))
        }
    }

    func testCamelCaseNamesRemainExactEvenWhenJevMissesTheChange() {
        let review = DecisionResult(meaningChanged: 0.01, contentAdded: 0.01, contentOmitted: 0.01)
        for changed in ["OpenType을 써요", "Opennotype을 써요", "OpenNotype을 써요", "오픈노타입을 써요"] {
            XCTAssertFalse(JevModelEvaluation.passes(approvedText: "OpenNoType을 써요", output: changed, review: review))
        }
        XCTAssertFalse(JevModelEvaluation.passes(approvedText: "OpenRouter 설정", output: "Openrouter 설정", review: review))
        XCTAssertFalse(JevModelEvaluation.passes(approvedText: "OpenNoType OpenNoType", output: "OpenNoType", review: review))
        XCTAssertTrue(JevModelEvaluation.passes(approvedText: "JEV로 OpenNoType을 개선하고 싶어요.",
            output: "JEV로 OpenNoType을 개선하고 싶어요.", review: review))
    }

    func testModelComparisonSeparatesApostrophesFromRealQuotedText() {
        let review = DecisionResult(meaningChanged: 0.01, contentAdded: 0.01, contentOmitted: 0.01)
        for source in ["I don't think it's necessary.", "I don’t think it’s necessary."] {
            XCTAssertTrue(JevModelEvaluation.passes(approvedText: source,
                output: "I do not think it is necessary.", review: review), source)
        }
        for (source, changed) in [("Keep 'don't change'.", "Keep 'do not change'."),
                                 ("Keep ‘don’t change’.", "Keep ‘do not change’."),
                                 ("Keep `retry_count` and https://example.com/a.",
                                  "Keep `retry_total` and https://example.com/b.")] {
            XCTAssertTrue(JevModelEvaluation.passes(approvedText: source, output: source, review: review))
            XCTAssertFalse(JevModelEvaluation.passes(approvedText: source, output: changed, review: review))
        }
    }

    func testUncertainOrInvalidJevSignalsNeverPass() {
        for score in [0.5, 0.9, 1, -0.1, Double.nan, Double.infinity] {
            XCTAssertFalse(JevModelEvaluation.passes(approvedText: "안녕하세요", output: "안녕하세요",
                review: .init(meaningChanged: score, contentAdded: 0.01, contentOmitted: 0.01)))
        }
        XCTAssertFalse(JevModelEvaluation.passes(approvedText: "안녕하세요", output: " ",
            review: .init(meaningChanged: 0, contentAdded: 0, contentOmitted: 0)))
    }

    func testRecommendationRequiresEveryCaseAndKnownCostThenPrefersCostAndLatency() {
        func row(_ model: String, _ passed: Int, _ cost: Double?, _ seconds: Double) -> ModelEvaluationRow {
            var row = ModelEvaluationRow(model: model, expectedCount: 2)
            row.completedCount = 2; row.passedCount = passed; row.totalCostUSD = cost
            row.outputs = [.init(caseID: UUID(), text: "sample", passed: true, issue: nil, seconds: seconds)]
            return row
        }
        let partial = row("partial-cheap", 1, 0.001, 0.1), costly = row("costly", 2, 0.03, 0.1)
        let slow = row("slow", 2, 0.01, 2), fast = row("fast", 2, 0.01, 1), unknown = row("unknown", 2, nil, 0.01)
        XCTAssertEqual(JevModelEvaluation.recommendedModel([partial, costly, slow, fast, unknown]), "fast")
        XCTAssertNil(JevModelEvaluation.recommendedModel([partial, unknown]))
        var failed = fast; failed.errors = ["failed"]
        XCTAssertEqual(JevModelEvaluation.recommendedModel([failed, slow]), "slow")
    }
}
