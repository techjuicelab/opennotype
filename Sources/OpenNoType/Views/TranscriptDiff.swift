import AppKit
import SwiftUI

/// Caches friendly application names resolved from bundle identifiers.
@MainActor
enum AppDisplayName {
    private static var cache: [String: String] = [:]

    static func name(for bundleID: String) -> String {
        if let cached = cache[bundleID] { return cached }
        let resolved: String
        if bundleID == "com.openai.codex" {
            resolved = "Codex"
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            resolved = url.deletingPathExtension().lastPathComponent
        } else {
            resolved = bundleID
        }
        cache[bundleID] = resolved
        return resolved
    }
}

/// Lightweight token-level diff for comparing speech transcripts with cleaned text.
enum TranscriptDiff {
    struct Segment: Equatable {
        let text: String
        let changed: Bool
    }

    struct Comparison: Equatable {
        let original: [Segment]
        let result: [Segment]
    }

    static let maxTokenCount = 240

    static func compare(original: String, result: String) -> Comparison? {
        guard original != result else { return nil }
        let origTokens = tokenize(original)
        let resTokens = tokenize(result)
        guard !origTokens.isEmpty, !resTokens.isEmpty,
              origTokens.count <= maxTokenCount, resTokens.count <= maxTokenCount else {
            return nil
        }

        let m = origTokens.count
        let n = resTokens.count
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                if origTokens[i] == resTokens[j] {
                    lcs[i][j] = lcs[i + 1][j + 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var origSegments: [Segment] = []
        var resSegments: [Segment] = []
        var i = 0
        var j = 0
        while i < m && j < n {
            if origTokens[i] == resTokens[j] {
                append(origTokens[i], changed: false, to: &origSegments)
                append(resTokens[j], changed: false, to: &resSegments)
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                append(origTokens[i], changed: true, to: &origSegments)
                i += 1
            } else {
                append(resTokens[j], changed: true, to: &resSegments)
                j += 1
            }
        }
        while i < m {
            append(origTokens[i], changed: true, to: &origSegments)
            i += 1
        }
        while j < n {
            append(resTokens[j], changed: true, to: &resSegments)
            j += 1
        }
        return Comparison(original: origSegments, result: resSegments)
    }

    static func attributed(
        _ segments: [Segment],
        highlightBackground: Color,
        highlightForeground: Color,
        strikethrough: Bool = false
    ) -> AttributedString {
        var combined = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { combined.append(AttributedString(" ")) }
            var piece = AttributedString(segment.text)
            if segment.changed {
                piece.backgroundColor = highlightBackground
                piece.foregroundColor = highlightForeground
                if strikethrough {
                    piece.strikethroughStyle = .single
                }
            }
            combined.append(piece)
        }
        return combined
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func append(_ token: String, changed: Bool, to segments: inout [Segment]) {
        if let last = segments.last, last.changed == changed {
            segments[segments.count - 1] = Segment(text: last.text + " " + token, changed: changed)
        } else {
            segments.append(Segment(text: token, changed: changed))
        }
    }
}
