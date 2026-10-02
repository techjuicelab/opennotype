import Foundation
import Observation

/// Interface language only. It never selects a transcription or translation language.
public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case korean = "ko"
    public var id: String { rawValue }
    public var title: String { self == .english ? "English" : "한국어" }
    public var locale: Locale { Locale(identifier: self == .english ? "en_US" : "ko_KR") }
}

/// Shared so menu commands, floating panels and errors use the same explicit choice.
/// Reads participate in SwiftUI observation; background error formatting is synchronized.
@Observable public final class AppLocalization: @unchecked Sendable {
    public static let shared = AppLocalization()
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var storedLanguage: AppLanguage = .english

    public var language: AppLanguage {
        get {
            access(keyPath: \.language)
            return lock.withLock { storedLanguage }
        }
        set {
            withMutation(keyPath: \.language) {
                lock.withLock { storedLanguage = newValue }
            }
        }
    }

    private init() {}
}

/// Keep both translations next to the UI call site, with compiler-checked interpolation.
/// Lazy arguments avoid formatting errors or data in a language that is not displayed.
public func L(_ korean: @autoclosure () -> String, _ english: @autoclosure () -> String) -> String {
    AppLocalization.shared.language == .korean ? korean() : english()
}
