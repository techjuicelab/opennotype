import XCTest
import Observation
@testable import OpenNoTypeCore

private final class LocalizationObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func mark() { lock.withLock { stored = true } }
}

final class LocalizationTests: XCTestCase {
    func testLanguagesKeepStableIDsAndNativeNames() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["en", "ko"])
        XCTAssertEqual(AppLanguage.allCases.map(\.title), ["English", "한국어"])
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en_US")
        XCTAssertEqual(AppLanguage.korean.locale.identifier, "ko_KR")
    }

    func testSwitchUpdatesObservedTextAndEvaluatesOnlySelectedLanguage() {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.language = previous }
        AppLocalization.shared.language = .english
        var evaluatedKorean = false
        func korean() -> String { evaluatedKorean = true; return "준비" }
        XCTAssertEqual(L(korean(), "Ready"), "Ready")
        XCTAssertFalse(evaluatedKorean)
        let changed = LocalizationObservationFlag()
        withObservationTracking { _ = L("준비", "Ready") } onChange: { changed.mark() }
        AppLocalization.shared.language = .korean
        XCTAssertTrue(changed.value)
        XCTAssertEqual(L(korean(), "Ready"), "준비")
        XCTAssertTrue(evaluatedKorean)
        AppLocalization.shared.language = .english
        XCTAssertEqual(L("총 \(12)개", "Total: \(12)"), "Total: 12")
    }

    func testInterfaceLanguageDoesNotChangeAIRequestOrSpeechHints() throws {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.language = previous }
        let request = ProcessingRequest(mode: .translation, transcript: "Keep API and 한국어.", targetLanguage: "Korean")
        AppLocalization.shared.language = .english
        let english = try ProcessingPrompt.build(request)
        let englishHints = TranscriptionHints.make(dictionary: [])
        AppLocalization.shared.language = .korean
        let korean = try ProcessingPrompt.build(request)
        XCTAssertEqual(english.instructions, korean.instructions)
        XCTAssertEqual(english.input, korean.input)
        XCTAssertEqual(englishHints.prompt, TranscriptionHints.make(dictionary: []).prompt)
    }
}
