import XCTest
@testable import OpenNoTypeCore

final class DictionaryHintsTests: XCTestCase {
    func testCorrectedGroqNameFeedsBothRecognitionAndTextCleanup() throws {
        let before = "GR5Q로 다시 진행해봤는데 잘 되는지 모르겠네요"
        let after = "GROQ로 다시 진행해봤는데 잘 되는지 모르겠네요"
        let entry = try XCTUnwrap(CorrectionLearner.suggestion(original: before, edited: after))
        XCTAssertEqual(TranscriptionHints.make(dictionary: [entry]).keywords, ["GROQ"])
        // The learned mapping remains relevant despite the attached Korean particle and
        // even when enough newer entries exist to overflow the text prompt budget.
        let prompt = try ProcessingPrompt.build(.init(mode: .dictation, transcript: before,
                                                     dictionary: [entry] + entries(250)))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.input.utf8)) as? [String: Any])
        let hints = try XCTUnwrap(payload["dictionary"] as? [[String: String]])
        XCTAssertEqual(hints.first?["spoken"], "GR5Q")
        XCTAssertEqual(hints.first?["written"], "GROQ")
    }

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

        let localHints = TranscriptionHints.make(dictionary: dictionary).localPrompt
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
        XCTAssertEqual(hints.count, 35, "Three relevant terms plus a bounded recent fallback")
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

    func testLargeDictionaryWithNoRelevantTermsSendsOnlyRecentFallback() {
        let dictionary = entries(1_000)
        let selected = DictionaryHints.select(dictionary, limit: 200, transcript: "회의 일정을 알려 주세요")
        XCTAssertEqual(selected.count, 32)
        XCTAssertEqual(selected.map(\.id), Array(dictionary.suffix(32).reversed()).map(\.id))
        XCTAssertEqual(DictionaryHints.select(dictionary, limit: 5, transcript: "회의 일정").count, 5)
    }

    func testTranscriptMatchingTermsAreNotDroppedToMakeRoomForFallback() {
        let dictionary = entries(250)
        let transcript = dictionary.prefix(205).map(\.written).joined(separator: " ")
        let selected = DictionaryHints.select(dictionary, limit: 200, transcript: transcript)
        XCTAssertEqual(selected.count, 200)
        XCTAssertEqual(selected.map(\.written), Array(dictionary[5..<205].reversed()).map(\.written))
    }

    func testSmallDictionaryAndRecognitionKeepExistingSelection() {
        let small = entries(200)
        XCTAssertEqual(DictionaryHints.select(small, limit: 200, transcript: "일정 확인").map(\.id), small.reversed().map(\.id))
        let large = entries(250)
        for empty in ["", " \n\t"] {
            XCTAssertEqual(DictionaryHints.select(large, limit: 200, transcript: empty).map(\.id),
                           Array(large.suffix(200).reversed()).map(\.id))
        }
        XCTAssertEqual(TranscriptionHints.make(dictionary: large).keywords,
                       TranscriptionHints.make(dictionary: Array(large.suffix(200))).keywords)
    }

    func testLargeDictionaryKeepsBoundaryMatchingAndStableResults() {
        let rain = DictionaryEntry(spoken: "레인", written: "rain")
        let api = DictionaryEntry(spoken: "에이피아이", written: "API")
        let dictionary = [rain, api] + entries(250)
        for _ in 0..<3 {
            let selected = DictionaryHints.select(dictionary, limit: 200, transcript: "The train API는 준비됐어요")
            XCTAssertEqual(selected.first?.id, api.id)
            XCTAssertFalse(selected.contains { $0.id == rain.id }, "rain is not relevant inside train")
            XCTAssertEqual(selected.count, 33)
        }
    }
}
