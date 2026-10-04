import SwiftUI
import OpenNoTypeCore

/// A text editor can retain its binding briefly after a case is removed or reordered.
/// Resolve the stable identity on every access rather than retaining an array index.
enum JevModelComparisonCaseBindings {
    static func text(in cases: Binding<[ModelEvaluationCase]>, id: UUID,
                     field: WritableKeyPath<ModelEvaluationCase, String>) -> Binding<String> {
        Binding(get: {
            cases.wrappedValue.first { $0.id == id }?[keyPath: field] ?? ""
        }, set: { text in
            var edited = cases.wrappedValue
            guard let index = edited.firstIndex(where: { $0.id == id }) else { return }
            edited[index][keyPath: field] = text
            cases.wrappedValue = edited
        })
    }
}
