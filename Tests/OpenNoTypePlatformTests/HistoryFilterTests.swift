import Foundation
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class HistoryFilterTests: XCTestCase {
    func testFilteredMatchesFiltersByModeSearchAndAppNameAndSortsNewestFirst() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let older = HistoryEntry(
            createdAt: base,
            mode: .dictation,
            originalText: "원문 첫번째",
            resultText: "결과 첫번째",
            sourceBundleID: "com.openai.codex",
            provider: .groq
        )
        let newer = HistoryEntry(
            createdAt: base.addingTimeInterval(60),
            mode: .translation,
            originalText: "번역 원문",
            resultText: "Translated result",
            sourceBundleID: "com.apple.Notes",
            provider: .groq,
            targetLanguage: "English (United States)"
        )
        let dictationTranslation = HistoryEntry(
            createdAt: base.addingTimeInterval(30),
            mode: .dictation,
            originalText: "받아쓰기 번역 원문",
            resultText: "Dictated translation",
            sourceBundleID: "com.openai.codex",
            provider: .groq,
            outputLanguage: .english
        )

        let all = HistoryView.filteredMatches(from: [older, newer, dictationTranslation], search: "", modeFilter: .all)
        XCTAssertEqual(all.map(\.id), [newer.id, dictationTranslation.id, older.id])

        let translations = HistoryView.filteredMatches(from: [older, newer, dictationTranslation], search: "", modeFilter: .translation)
        XCTAssertEqual(translations.map(\.id), [newer.id, dictationTranslation.id])

        let byApp = HistoryView.filteredMatches(from: [older, newer, dictationTranslation], search: "codex", modeFilter: .all)
        XCTAssertEqual(byApp.map(\.id), [dictationTranslation.id, older.id])

        let byOriginal = HistoryView.filteredMatches(from: [older, newer, dictationTranslation], search: "첫번째", modeFilter: .dictation)
        XCTAssertEqual(byOriginal.map(\.id), [older.id])
    }
}
