import Foundation

/// Explicit short-text policies, checked against OpenRouter's model metadata on 2026-10-01.
/// Unknown/custom models retain the existing strict-schema request with their provider defaults.
enum OpenRouterTextPolicy {
    static func apply(to body: inout [String: Any], model: String, requiresTranslation: Bool = false,
                      isPromptComposition: Bool = false) {
        // This endpoint supports JSON mode, but not JSON-schema enforcement. The shared parser
        // still accepts only a completed JSON object containing exactly one string field: text.
        if ["qwen/qwen3.7-flash", "inclusionai/ling-3.0-flash"].contains(model) {
            body["response_format"] = ["type": "json_object"]
        }
        switch model {
        case "openai/gpt-6-luna":
            body["reasoning"] = ["effort": requiresTranslation ? "medium" : "none", "exclude": true]
        case "upstage/solar-mini4", "upstage/solar-pro4":
            body["reasoning"] = ["effort": "none", "exclude": true]
        case "qwen/qwen3.7-flash", "qwen/qwen3.8-flash",
             "deepseek/deepseek-v4.1-flash", "deepseek/deepseek-v4-flash",
             "xiaomi/mimo-v2.6-flash", "inclusionai/ling-3.0-flash":
            body["reasoning"] = ["enabled": false, "exclude": true]
        case "openai/gpt-oss-120b", "openai/gpt-oss-20b":
            // Task prompts need bounded intent/constraint checks beyond ordinary short-text cleanup.
            // Only this mode opts into medium; all existing OSS transformations retain low effort.
            body["reasoning"] = ["effort": isPromptComposition ? "medium" : "low", "exclude": true]
        case "z-ai/glm-5.3-flash":
            // These models require reasoning. Exclusion hides it; it does not remove its cost.
            body["reasoning"] = ["effort": "low", "exclude": true]
        case "google/gemini-3.5-flash-lite", "google/gemini-3.1-flash-lite":
            body["reasoning"] = ["effort": "minimal", "exclude": true]
        default:
            break
        }
    }
}
