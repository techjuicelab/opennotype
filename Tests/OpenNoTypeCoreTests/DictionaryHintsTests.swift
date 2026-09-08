import XCTest
@testable import OpenNoTypeCore

final class DictionaryHintsTests: XCTestCase {
    private func entries(_ count: Int) -> [DictionaryEntry] {
        (0..<count).map { .init(spoken: "말\($0)", written: "Term\($0)", createdAt: Date(timeIntervalSince1970: Double($0))) }
    }

    func testRecentRegistrationAndOldEntryEditedNowSurviveOverflow() {
        var dictionary = entries(250)
        // Editing preserves createdAt but moves the entry to the end of the stored array.
        var corrected = dictionary.removeFirst()
        corrected.written = "CorrectedName"
        dictionary.append(corrected)
        let selected = DictionaryHints.select(dictionary, limit: 200)
        XCTAssertEqual(selected.count, 200)
        XCTAssertEqual(selected.first?.id, corrected.id)
        XCTAssertEqual(selected[1].written, "Term249")
        XCTAssertFalse(selected.contains { $0.written == "Term1" })

        let localHints = LocalTranscriber.dictionaryHint(dictionary)
        XCTAssertTrue(localHints.hasPrefix("CorrectedName, Term249"))
        XCTAssertFalse(localHints.components(separatedBy: ", ").contains("Term1"))
        XCTAssertLessThanOrEqual(localHints.components(separatedBy: ", ").count, 80)
    }

    func testActualPromptPrioritizesTranscriptThenContextThenRecency() throws {
        let dictionary = entries(250)
        let prompt = try ProcessingPrompt.build(.init(mode: .dictation, transcript: "Term0과 말1을 확인해 줘",
                                                     context: "Term2 관련 메모", dictionary: dictionary))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.input.utf8)) as? [String: Any])
        let hints = try XCTUnwrap(payload["dictionary"] as? [[String: String]])
        XCTAssertEqual(hints.count, 200)
        XCTAssertEqual(Array(hints.prefix(4)).compactMap { $0["written"] }, ["Term1", "Term0", "Term2", "Term249"])
    }

    func testLatinBoundariesStillAllowKoreanParticlesAndWrittenVariants() {
        let dictionary: [DictionaryEntry] = [
            .init(spoken: "레인", written: "rain"),
            .init(spoken: "에이피아이", written: "API"),
            .init(spoken: "최신", written: "Newest")
        ]
        XCTAssertEqual(DictionaryHints.select(dictionary, limit: 1, transcript: "The train is here").first?.written, "Newest")
        XCTAssertEqual(DictionaryHints.select(dictionary, limit: 1, transcript: "이 API는 rain일 때 사용해").first?.written, "API")
        XCTAssertEqual(DictionaryHints.select(dictionary, limit: 1, transcript: "레인이 맞아").first?.written, "rain")
    }

    func testStableOrderingWithEqualDatesAndEmptyEntries() {
        let date = Date(timeIntervalSince1970: 0)
        let dictionary: [DictionaryEntry] = [
            .init(spoken: "가", written: "Alpha", createdAt: date),
            .init(spoken: "나", written: "Beta", createdAt: date),
            .init(spoken: " ", written: "Invalid", createdAt: date)
        ]
        for _ in 0..<5 {
            XCTAssertEqual(DictionaryHints.select(dictionary, limit: 200).map(\.written), ["Beta", "Alpha"])
        }
        XCTAssertTrue(DictionaryHints.select(dictionary, limit: 0).isEmpty)
        XCTAssertTrue(DictionaryHints.select(dictionary, limit: -1).isEmpty)
    }

    func testContextOutsidePrivacyWindowCannotPromoteAnEntry() throws {
        let dictionary = entries(250)
        let prompt = try ProcessingPrompt.build(.init(mode: .dictation, transcript: "안녕",
                                                     context: "Term0 " + String(repeating: "x", count: 1_001), dictionary: dictionary))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.input.utf8)) as? [String: Any])
        let hints = try XCTUnwrap(payload["dictionary"] as? [[String: String]])
        XCTAssertFalse(hints.contains { $0["written"] == "Term0" })
    }

    func testWhisperTokenBudgetPreservesHighestPriorityStart() {
        XCTAssertEqual(LocalTranscriber.vocabularyTokens(Array(0..<300), specialTokenBegin: 50257), Array(0..<192))
    }
}
