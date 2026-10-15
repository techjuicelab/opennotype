import XCTest
@testable import OpenNoType

final class ProviderModelPickerStateTests: XCTestCase {
    private let choices = ["catalog-a", "catalog-b"]

    func testUnknownSavedModelStartsCustomWithoutReplacingTheID() {
        let state = ProviderModelPickerState(selection: "private/model-v1", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .custom)
        XCTAssertEqual(state.observedSelection, "private/model-v1")
        XCTAssertEqual(state.customDraft, "private/model-v1")
        XCTAssertFalse(state.hasUnappliedDraft)
    }

    func testChoosingCustomKeepsTheSavedModelUntilApply() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        XCTAssertNil(state.select(.custom, isEnabled: true))
        state.editCustomDraft("private/new-model", isEnabled: true)
        XCTAssertEqual(state.observedSelection, "catalog-a")
        XCTAssertEqual(state.customDraft, "private/new-model")
        XCTAssertTrue(state.hasUnappliedDraft)
        XCTAssertTrue(state.canApplyCustomModel)
    }

    func testTypingACatalogIDDoesNotCloseCustomEditingOrApplyIt() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("catalog-b", isEnabled: true)
        XCTAssertEqual(state.menuSelection, .custom)
        XCTAssertEqual(state.observedSelection, "catalog-a")
        XCTAssertTrue(state.hasUnappliedDraft)
    }

    func testApplyingACatalogIDKeepsCustomEditingAfterTheOwnerAcknowledgesIt() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("  catalog-b \n", isEnabled: true)
        XCTAssertEqual(state.applyCustomModel(isEnabled: true), "catalog-b")
        state.synchronize(selection: "catalog-b", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .custom)
        XCTAssertEqual(state.observedSelection, "catalog-b")
        XCTAssertEqual(state.customDraft, "catalog-b")
        XCTAssertFalse(state.hasUnappliedDraft)
        XCTAssertNil(state.applyCustomModel(isEnabled: true))
    }

    func testBlankCustomDraftCannotClearTheSavedModel() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft(" \n\t ", isEnabled: true)
        XCTAssertFalse(state.canApplyCustomModel)
        XCTAssertNil(state.applyCustomModel(isEnabled: true))
        XCTAssertEqual(state.observedSelection, "catalog-a")
    }

    func testDisabledActionsCannotChangeMenuDraftOrReturnAModelWrite() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        let original = state
        XCTAssertNil(state.select(.custom, isEnabled: false))
        XCTAssertNil(state.select(.catalogID("catalog-b"), isEnabled: false))
        state.editCustomDraft("private/new-model", isEnabled: false)
        XCTAssertNil(state.applyCustomModel(isEnabled: false))
        XCTAssertEqual(state, original)

        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("private/new-model", isEnabled: true)
        let edited = state
        XCTAssertNil(state.applyCustomModel(isEnabled: false))
        XCTAssertEqual(state, edited)
    }

    func testExternalSelectionReclassifiesAnOpenPickerAndDiscardsItsOldDraft() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("private/unapplied", isEnabled: true)
        state.synchronize(selection: "catalog-b", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .catalogID("catalog-b"))
        XCTAssertEqual(state.customDraft, "catalog-b")

        state.synchronize(selection: "private/external", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .custom)
        XCTAssertEqual(state.customDraft, "private/external")
        XCTAssertFalse(state.hasUnappliedDraft)
    }

    func testProviderContextChangeResetsDraftEvenWhenSavedIDAndChoicesMatch() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-a-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("private/unapplied", isEnabled: true)
        state.synchronize(selection: "catalog-a", choiceIDs: choices, contextID: "provider-b-text")
        XCTAssertEqual(state.menuSelection, .catalogID("catalog-a"))
        XCTAssertEqual(state.customDraft, "catalog-a")
        XCTAssertEqual(state.contextID, "provider-b-text")
        XCTAssertEqual(state.observedSelection, "catalog-a")
    }

    func testRemovingACatalogEntryRevealsItsSavedIDWithoutAReplacement() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        state.synchronize(selection: "catalog-a", choiceIDs: ["catalog-b"], contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .custom)
        XCTAssertEqual(state.customDraft, "catalog-a")
        XCTAssertEqual(state.observedSelection, "catalog-a")
        XCTAssertFalse(state.hasUnappliedDraft)
    }

    func testCatalogChangesAndReorderingKeepAnUnappliedCustomDraft() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("private/new-model", isEnabled: true)
        state.synchronize(selection: "catalog-a", choiceIDs: ["private/new-model", "catalog-b", "catalog-a"], contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .custom)
        XCTAssertEqual(state.customDraft, "private/new-model")
        XCTAssertEqual(state.observedSelection, "catalog-a")
    }

    func testCatalogSelectionDiscardsDraftButSelectingCurrentModelNeedsNoWrite() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("private/unapplied", isEnabled: true)
        XCTAssertNil(state.select(.catalogID("catalog-a"), isEnabled: true))
        XCTAssertEqual(state.menuSelection, .catalogID("catalog-a"))
        XCTAssertEqual(state.customDraft, "catalog-a")
        XCTAssertEqual(state.select(.catalogID("catalog-b"), isEnabled: true), "catalog-b")
        state.synchronize(selection: "catalog-b", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .catalogID("catalog-b"))
    }

    func testStaleCatalogEventCannotWriteAnIDFromAnotherProvider() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        let original = state
        XCTAssertNil(state.select(.catalogID("other-provider/model"), isEnabled: true))
        XCTAssertEqual(state, original)
    }

    func testARealModelIDCannotCollideWithTheCustomMenuOption() {
        let id = "__custom_model__"
        var state = ProviderModelPickerState(selection: id, choiceIDs: [id], contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .catalogID(id))
        XCTAssertNotEqual(state.menuSelection, .custom)
        XCTAssertNil(state.select(.custom, isEnabled: true))
        XCTAssertEqual(state.observedSelection, id)
        XCTAssertEqual(state.customDraft, id)
    }

    func testRejectedApplyDoesNotMakeALaterExternalChangeLookLikeSelfApply() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("catalog-b", isEnabled: true)
        XCTAssertEqual(state.applyCustomModel(isEnabled: true), "catalog-b")
        state.synchronize(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        XCTAssertTrue(state.hasUnappliedDraft)
        state.synchronize(selection: "catalog-b", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .catalogID("catalog-b"))
    }

    func testRejectedCatalogSelectionReturnsToTheActualOwnerValue() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.select(.catalogID("catalog-b"), isEnabled: true), "catalog-b")
        XCTAssertEqual(state.menuSelection, .catalogID("catalog-b"))
        state.synchronize(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        XCTAssertEqual(state.menuSelection, .catalogID("catalog-a"))
        XCTAssertEqual(state.observedSelection, "catalog-a")
        XCTAssertEqual(state.customDraft, "catalog-a")
    }

    func testReselectingCustomDoesNotDiscardAnUnappliedDraft() {
        var state = ProviderModelPickerState(selection: "catalog-a", choiceIDs: choices, contextID: "provider-text")
        _ = state.select(.custom, isEnabled: true)
        state.editCustomDraft("private/unapplied", isEnabled: true)
        XCTAssertNil(state.select(.custom, isEnabled: true))
        XCTAssertEqual(state.customDraft, "private/unapplied")
        XCTAssertEqual(state.observedSelection, "catalog-a")
    }
}
