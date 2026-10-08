import Foundation

/// Indexed output prevents structural segment loss; semantic fidelity still needs review.
enum PromptCompositionSegmentResponse {
    static let maximumSegments = 64

    static func schema(ids: [String]) -> [String: Any] {
        ["type": "object", "properties": ["segments": [
            "type": "array", "minItems": ids.count, "maxItems": ids.count,
            "items": ["type": "object", "properties": [
                "id": ["type": "string", "enum": ids], "text": ["type": "string"]
            ], "required": ["id", "text"], "additionalProperties": false]
        ]], "required": ["segments"], "additionalProperties": false]
    }

    static func decode(_ object: [String: Any], ids: [String]) throws -> String {
        guard !ids.isEmpty, ids.count <= maximumSegments, Set(ids).count == ids.count,
              Set(object.keys) == ["segments"],
              let segments = object["segments"] as? [[String: Any]], segments.count == ids.count else {
            throw ProviderError.invalidResponse
        }
        var fragments: [String] = []
        for (segment, expectedID) in zip(segments, ids) {
            guard Set(segment.keys) == ["id", "text"],
                  let id = segment["id"] as? String, id == expectedID,
                  let text = segment["text"] as? String else { throw ProviderError.invalidResponse }
            let fragment = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fragment.isEmpty { fragments.append(fragment) }
        }
        guard !fragments.isEmpty else { throw PromptCompositionFailure.invalidOutput }
        return fragments.joined(separator: "\n")
    }
}
