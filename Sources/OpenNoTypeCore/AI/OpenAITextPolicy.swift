import Foundation

/// Direct OpenAI Responses policies for short-text processing.
/// Unknown/custom models retain their provider defaults.
enum OpenAITextPolicy {
    static func apply(to body: inout [String: Any], model: String, requiresTranslation: Bool) {
        guard model == "gpt-6-luna" else { return }
        // Match the existing Luna policy on OpenRouter: cleanup stays fast, while
        // translation uses medium effort to preserve meaning across languages.
        body["reasoning"] = ["effort": requiresTranslation ? "medium" : "none"]
    }
}
