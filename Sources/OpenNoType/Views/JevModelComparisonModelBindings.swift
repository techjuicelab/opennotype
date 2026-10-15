import SwiftUI

/// Fixed model slots may outlive a removed third row or a provider change briefly.
/// Reject late commits instead of applying them to a replacement row or provider.
enum JevModelComparisonModelBindings {
    static func fillingRequiredRows(in models: [String], choices: [String]) -> [String] {
        var selected = models
        while selected.count < 2 {
            let current = Set(selected.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            selected.append(choices.first(where: { !current.contains($0) }) ?? "")
        }
        return selected
    }

    static func text(in models: Binding<[String]>, at index: Int, contextID: String,
                     currentContextID: @escaping () -> String?,
                     isEditable: @escaping () -> Bool) -> Binding<String> {
        let expectedCount = models.wrappedValue.count
        return Binding(get: {
            guard currentContextID() == contextID,
                  models.wrappedValue.indices.contains(index) else { return "" }
            return models.wrappedValue[index]
        }, set: { value in
            guard isEditable(), currentContextID() == contextID else { return }
            var edited = models.wrappedValue
            guard edited.count == expectedCount, edited.indices.contains(index) else { return }
            edited[index] = value
            models.wrappedValue = edited
        })
    }
}
