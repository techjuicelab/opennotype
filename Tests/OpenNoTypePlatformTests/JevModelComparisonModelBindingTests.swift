import SwiftUI
import XCTest
@testable import OpenNoType

@MainActor
final class JevModelComparisonModelBindingTests: XCTestCase {
    func testReopeningOneSelectedModelPreservesItAndAddsASecondSlot() {
        XCTAssertEqual(JevModelComparisonModelBindings.fillingRequiredRows(
            in: ["first"], choices: ["first", "second"]), ["first", "second"])
        XCTAssertEqual(JevModelComparisonModelBindings.fillingRequiredRows(
            in: ["saved-custom"], choices: []), ["saved-custom", ""])
    }

    func testCommittedValueChangesOnlyTheChosenModel() {
        let fixture = ModelBindingFixture()
        let binding = fixture.model(at: 1)

        binding.wrappedValue = "committed-custom-model"

        XCTAssertEqual(fixture.models, ["first", "committed-custom-model", "third"])
    }

    func testRemovedThirdRowRejectsLateCommit() {
        let fixture = ModelBindingFixture()
        let binding = fixture.model(at: 2)
        fixture.models.removeLast()

        XCTAssertEqual(binding.wrappedValue, "")
        binding.wrappedValue = "late-third"

        XCTAssertEqual(fixture.models, ["first", "second"])
    }

    func testReplacementThirdRowWithSameCountRejectsOldRowCommit() {
        let fixture = ModelBindingFixture()
        let binding = fixture.model(at: 2)
        fixture.models.removeLast()
        fixture.models.append("replacement-third")
        fixture.context = "openRouter-replacement-row"

        binding.wrappedValue = "late-old-third"

        XCTAssertEqual(fixture.models, ["first", "second", "replacement-third"])
    }

    func testProviderChangeRejectsOldProviderCommit() {
        let fixture = ModelBindingFixture()
        let binding = fixture.model(at: 0)
        fixture.models = ["new-first", "new-second", "new-third"]
        fixture.context = "anthropic-row"

        XCTAssertEqual(binding.wrappedValue, "")
        binding.wrappedValue = "late-openRouter-model"

        XCTAssertEqual(fixture.models, ["new-first", "new-second", "new-third"])
    }

    func testArrayCountChangeRejectsAnOldBinding() {
        let fixture = ModelBindingFixture()
        let binding = fixture.model(at: 0)
        fixture.models.removeLast()

        binding.wrappedValue = "late-first"

        XCTAssertEqual(fixture.models, ["first", "second"])
    }

    func testBecomingReadOnlyRejectsLateCommit() {
        let fixture = ModelBindingFixture()
        let binding = fixture.model(at: 1)
        fixture.editable = false

        binding.wrappedValue = "late-read-only-model"

        XCTAssertEqual(fixture.models, ["first", "second", "third"])
    }
}

@MainActor
private final class ModelBindingFixture {
    var models = ["first", "second", "third"]
    var context = "openRouter-row"
    var editable = true

    func model(at index: Int) -> Binding<String> {
        JevModelComparisonModelBindings.text(
            in: Binding(get: { self.models }, set: { self.models = $0 }), at: index,
            contextID: context, currentContextID: { self.context }, isEditable: { self.editable })
    }
}
