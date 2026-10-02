import Foundation

/// Bounded literal differences for comparing recognition hypotheses. These are not semantic
/// errors, nor evidence that either recognizer heard the audio correctly.
public struct TranscriptDifferences: Equatable, Sendable {
    public let originalOnly: [String]
    public let alternativeOnly: [String]
    public let truncated: Bool
    public var hasDifferences: Bool { !originalOnly.isEmpty || !alternativeOnly.isEmpty }

    public init(original: String, alternative: String) {
        let left = Self.tokens(original), right = Self.tokens(alternative)
        var removed: [(Int, String)] = [], added: [(Int, String)] = []
        for change in right.0.difference(from: left.0) {
            switch change {
            case .remove(let offset, let value, _): removed.append((offset, value))
            case .insert(let offset, let value, _): added.append((offset, value))
            }
        }
        originalOnly = removed.sorted { $0.0 < $1.0 }.prefix(24).map(\.1)
        alternativeOnly = added.sorted { $0.0 < $1.0 }.prefix(24).map(\.1)
        truncated = left.1 || right.1 || removed.count > 24 || added.count > 24
    }

    private static func tokens(_ text: String) -> ([String], Bool) {
        let bounded = String(text.prefix(6_000))
        guard let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{M}_]+|\\p{N}+(?:[.,:]\\p{N}+)*|[^\\s]") else { return ([], !text.isEmpty) }
        let matches = regex.matches(in: bounded, range: NSRange(bounded.startIndex..., in: bounded))
        let values = matches.prefix(240).compactMap { Range($0.range, in: bounded).map { String(bounded[$0]) } }
        return (values, text.count > 6_000 || matches.count > 240)
    }
}
