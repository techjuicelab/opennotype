import Foundation

enum ProviderModelMenuSelection: Hashable, Sendable {
    case catalogID(String)
    case custom
}

/// Presentation and unapplied edits only. The owner writes a returned model ID after a user action.
struct ProviderModelPickerState: Equatable, Sendable {
    private(set) var menuSelection: ProviderModelMenuSelection
    private(set) var customDraft: String
    private(set) var observedSelection: String
    private(set) var choiceIDs: [String]
    private(set) var contextID: String
    private var pendingSelfApply: String?

    init(selection: String, choiceIDs: [String], contextID: String) {
        self.menuSelection = choiceIDs.contains(selection) ? .catalogID(selection) : .custom
        self.customDraft = selection
        self.observedSelection = selection
        self.choiceIDs = choiceIDs
        self.contextID = contextID
    }

    var usesCustomModel: Bool { menuSelection == .custom }
    var trimmedCustomDraft: String { customDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasUnappliedDraft: Bool { usesCustomModel && trimmedCustomDraft != observedSelection }
    var canApplyCustomModel: Bool { usesCustomModel && !trimmedCustomDraft.isEmpty && hasUnappliedDraft }

    mutating func synchronize(selection: String, choiceIDs: [String], contextID: String) {
        if contextID != self.contextID {
            self = Self(selection: selection, choiceIDs: choiceIDs, contextID: contextID)
            return
        }
        let rejectedCatalogSelection = pendingSelfApply != nil && pendingSelfApply != selection && !usesCustomModel
        if selection != observedSelection || rejectedCatalogSelection {
            if pendingSelfApply == selection {
                observedSelection = selection
            } else {
                menuSelection = choiceIDs.contains(selection) ? .catalogID(selection) : .custom
                customDraft = selection
                observedSelection = selection
            }
        }
        pendingSelfApply = nil
        self.choiceIDs = choiceIDs
        if case .catalogID(let id) = menuSelection, !choiceIDs.contains(id) {
            menuSelection = .custom
            customDraft = selection
        }
    }

    mutating func select(_ value: ProviderModelMenuSelection, isEnabled: Bool) -> String? {
        guard isEnabled else { return nil }
        switch value {
        case .custom:
            if !usesCustomModel { customDraft = observedSelection }
            menuSelection = .custom
            return nil
        case .catalogID(let id):
            guard choiceIDs.contains(id) else { return nil }
            menuSelection = .catalogID(id)
            customDraft = id
            guard id != observedSelection else { return nil }
            pendingSelfApply = id
            return id
        }
    }

    mutating func editCustomDraft(_ value: String, isEnabled: Bool) {
        guard isEnabled, usesCustomModel else { return }
        customDraft = value
    }

    mutating func applyCustomModel(isEnabled: Bool) -> String? {
        guard isEnabled, canApplyCustomModel else { return nil }
        let id = trimmedCustomDraft
        customDraft = id
        pendingSelfApply = id
        return id
    }
}
