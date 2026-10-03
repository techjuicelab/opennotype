import Foundation

/// Repair and model evaluation share quote boundaries. Apostrophes inside Latin words (including
/// possessives) are punctuation, while apostrophes inside an actual quote remain protected text.
enum ProtectedLiteralPatterns {
    static let url = #"https?://[^\s<>\"'“”‘’]+"#
    static let code = #"`[^`\n]+`"#
    static let quotedText = #"\"[^\"\n]+\"|(?<![A-Za-z0-9_])'(?:[^'\n]|(?<=[A-Za-z0-9])'(?=[A-Za-z0-9]))+'(?![A-Za-z0-9_])|“[^”\n]+”|(?<![A-Za-z0-9_])‘(?:[^’\n]|(?<=[A-Za-z0-9])’(?=[A-Za-z0-9]))+’(?![A-Za-z0-9_])"#
    static let identifier = #"[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+|(?<![A-Za-z0-9_])(?=[A-Za-z0-9]*[A-Z][A-Za-z0-9]*[A-Z])[A-Za-z][A-Za-z0-9]*(?![A-Za-z0-9_])"#
    static let protected = url + "|" + code + "|" + quotedText + "|" + identifier
}
