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
/// Splits space-delimited scripts by word, splits non-space-delimited CJK scripts by character,
/// and preserves line breaks and original spacing when reconstructing segments.
enum TranscriptDiff {
    struct Segment: Equatable {
        let text: String
        let changed: Bool
    }

    struct Comparison: Equatable {
        let original: [Segment]
        let result: [Segment]
    }

    private struct Token {
        let text: String
        let leadingSpace: String
    }

    static let maxTokenCount = 400

    static func compare(original: String, result: String) -> Comparison? {
        guard original != result else { return nil }
        let (origTokens, origTrailing) = tokenize(original)
        let (resTokens, resTrailing) = tokenize(result)
        guard !origTokens.isEmpty, !resTokens.isEmpty,
              origTokens.count <= maxTokenCount, resTokens.count <= maxTokenCount else {
            return nil
        }

        let m = origTokens.count
        let n = resTokens.count
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                if origTokens[i].text == resTokens[j].text {
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
            if origTokens[i].text == resTokens[j].text {
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
        appendRaw(origTrailing, changed: false, to: &origSegments)
        appendRaw(resTrailing, changed: false, to: &resSegments)
        return Comparison(original: origSegments, result: resSegments)
    }

    static func attributed(
        _ segments: [Segment],
        highlightBackground: Color,
        highlightForeground: Color,
        strikethrough: Bool = false
    ) -> AttributedString {
        var combined = AttributedString()
        for segment in segments {
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

    private static func tokenize(_ text: String) -> (tokens: [Token], trailingSpace: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var tokens: [Token] = []
        var pendingSpace = ""
        var currentWord = ""

        func flushWord() {
            guard !currentWord.isEmpty else { return }
            tokens.append(Token(text: currentWord, leadingSpace: pendingSpace))
            currentWord = ""
            pendingSpace = ""
        }

        for char in normalized {
            if char == "\n" {
                flushWord()
                tokens.append(Token(text: "\n", leadingSpace: pendingSpace))
                pendingSpace = ""
            } else if char.isWhitespace {
                flushWord()
                pendingSpace.append(char)
            } else if isCharacterGranularScript(char) {
                flushWord()
                tokens.append(Token(text: String(char), leadingSpace: pendingSpace))
                pendingSpace = ""
            } else {
                currentWord.append(char)
            }
        }
        flushWord()
        return (tokens, pendingSpace)
    }

    /// Japanese (Hiragana/Katakana), Chinese/Kanji (Han), and CJK punctuation are not space-delimited,
    /// so splitting them per character produces useful diffs instead of marking entire sentences changed.
    private static func isCharacterGranularScript(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3001...0x303F, // CJK symbols & punctuation (excluding U+3000 ideographic space)
             0x3040...0x309F, // Hiragana
             0x30A0...0x30FF, // Katakana
             0x31F0...0x31FF, // Katakana Phonetic Extensions
             0x3400...0x4DBF, // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0xF900...0xFAFF, // CJK Compatibility Ideographs
             0xFF01...0xFF0F, // Fullwidth punctuation
             0xFF1A...0xFF20,
             0xFF3B...0xFF40,
             0xFF5B...0xFF65,
             0xFF66...0xFF9F, // Halfwidth Katakana
             0x20000...0x2FA1F: // CJK Unified Ideographs Extensions B–I & Compatibility
            return true
        default:
            return false
        }
    }

    private static func append(_ token: Token, changed: Bool, to segments: inout [Segment]) {
        if token.text == "\n" {
            appendRaw(token.leadingSpace + "\n", changed: false, to: &segments)
            return
        }
        if changed {
            if !token.leadingSpace.isEmpty {
                if segments.last?.changed == true {
                    appendRaw(token.leadingSpace, changed: true, to: &segments)
                } else {
                    appendRaw(token.leadingSpace, changed: false, to: &segments)
                }
            }
            appendRaw(token.text, changed: true, to: &segments)
        } else {
            appendRaw(token.leadingSpace + token.text, changed: false, to: &segments)
        }
    }

    private static func appendRaw(_ text: String, changed: Bool, to segments: inout [Segment]) {
        guard !text.isEmpty else { return }
        if let last = segments.last, last.changed == changed {
            segments[segments.count - 1] = Segment(text: last.text + text, changed: changed)
        } else {
            segments.append(Segment(text: text, changed: changed))
        }
    }
}
