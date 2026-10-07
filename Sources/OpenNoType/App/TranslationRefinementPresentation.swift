import Foundation

/// Disposable UI state, never encoded into history, preferences or recovery audio metadata.
struct TranslationRefinementPresentation: Equatable, Sendable {
    let draft: String
    var output: String?
    var status: String
    var isProcessing: Bool
    var held: Bool
}
