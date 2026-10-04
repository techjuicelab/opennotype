import Observation
import SwiftUI
import XCTest
@testable import OpenNoType
import OpenNoTypeCore

@MainActor
final class JevModelComparisonCaseBindingTests: XCTestCase {
    func testDeletingEditedCaseDoesNotReadItsBindingDuringArrayMutation() {
        let fixture = CaseBindingFixture()
        let first = ModelEvaluationCase(transcript: "first", approvedText: "first approved")
        let last = ModelEvaluationCase(transcript: "last", approvedText: "last approved")
        fixture.cases = [first, last]
        let text = JevModelComparisonCaseBindings.text(in: fixture.binding, id: last.id, field: \.transcript)

        // The row captures the value's ID before removeAll starts its exclusive mutation.
        let row = fixture.cases[1]
        fixture.cases.removeAll { $0.id == row.id }

        XCTAssertEqual(fixture.cases, [first])
        XCTAssertEqual(text.wrappedValue, "")
        text.wrappedValue = "stale editor update"
        XCTAssertEqual(fixture.cases, [first])
    }

    func testDeletingEarlierCaseKeepsLaterEditorBoundToItsIdentity() {
        let fixture = CaseBindingFixture()
        let first = ModelEvaluationCase(transcript: "first", approvedText: "first approved")
        let last = ModelEvaluationCase(transcript: "last", approvedText: "last approved")
        fixture.cases = [first, last]
        let text = JevModelComparisonCaseBindings.text(in: fixture.binding, id: last.id, field: \.transcript)
        fixture.cases.removeAll { $0.id == first.id }

        XCTAssertEqual(text.wrappedValue, "last")
        text.wrappedValue = "edited last"
        XCTAssertEqual(fixture.cases.count, 1)
        XCTAssertEqual(fixture.cases[0].id, last.id)
        XCTAssertEqual(fixture.cases[0].transcript, "edited last")
        XCTAssertEqual(fixture.cases[0].approvedText, "last approved")
    }

    func testReorderedCasesKeepApprovedAnswerEditorBoundToItsIdentity() {
        let fixture = CaseBindingFixture()
        let first = ModelEvaluationCase(transcript: "first", approvedText: "first approved")
        let last = ModelEvaluationCase(transcript: "last", approvedText: "last approved")
        fixture.cases = [first, last]
        let text = JevModelComparisonCaseBindings.text(in: fixture.binding, id: first.id, field: \.approvedText)
        fixture.cases.reverse()

        XCTAssertEqual(text.wrappedValue, "first approved")
        text.wrappedValue = "edited answer"
        XCTAssertEqual(fixture.cases[0], last)
        XCTAssertEqual(fixture.cases[1].id, first.id)
        XCTAssertEqual(fixture.cases[1].transcript, "first")
        XCTAssertEqual(fixture.cases[1].approvedText, "edited answer")
    }
}

@MainActor @Observable
private final class CaseBindingFixture {
    var cases: [ModelEvaluationCase] = []
    var binding: Binding<[ModelEvaluationCase]> {
        Binding(get: { self.cases }, set: { self.cases = $0 })
    }
}
