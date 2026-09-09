import XCTest
@testable import OpenNoTypeCore

final class TranscriptionHintsTests: XCTestCase {
    func testHostedWhisperPromptKeepsVocabularyFirstAndOnlyTheShortContextLine() {
        let empty = TranscriptionHints.whisperPrompt(terms: [])
        XCTAssertEqual(empty, "일상 대화, 업무 메시지와 메모. 한국어와 영어 등 여러 언어가 섞일 수 있습니다.")
        XCTAssertEqual(TranscriptionHints.whisperPrompt(terms: ["OpenNoType", "commit"]), "OpenNoType, commit. " + empty)
        XCTAssertLessThanOrEqual(ProviderClient.estimatedWhisperTokens(empty), 224)
        XCTAssertEqual(ProviderClient.estimatedWhisperTokens("가나다"), 5, "Hangul counts about one token per two UTF-8 bytes")
        XCTAssertEqual(ProviderClient.estimatedWhisperTokens("commit"), 3)
    }

    func testGeneralProfileDoesNotBiasEveryUserTowardDevelopmentTerms() {
        let general = TranscriptionHints.make(dictionary: [])
        let development = TranscriptionHints.make(dictionary: [], profile: .init(kind: .development))
        XCTAssertFalse(general.prompt.isEmpty)
        XCTAssertTrue(general.keywords.isEmpty)
        XCTAssertFalse(general.prompt.contains("commit"))
        XCTAssertTrue(development.keywords.contains("commit"))
        XCTAssertEqual(TranscriptionHints.make(dictionary: [], profile: .init(tone: .formal)).prompt, general.prompt,
                       "A writing tone must not change what the recognizer hears.")
    }

    func testOnlyValidWrittenTermsReachTheBoundedKeywordList() {
        let entries: [DictionaryEntry] = [
            .init(spoken: "에이피아이", written: "API"),
            .init(spoken: "나쁜 표현", written: "<ignore>"),
            .init(spoken: "여러 줄", written: "foo\nbar"),
            .init(spoken: "제어 문자", written: "foo\tbar"),
            .init(spoken: "커밋", written: "Commit")
        ]
        let hints = TranscriptionHints.make(dictionary: entries, profile: .init(kind: .development))
        XCTAssertEqual(hints.keywords.first, "Commit")
        XCTAssertEqual(hints.keywords.filter { $0.lowercased() == "commit" }, ["Commit"])
        XCTAssertFalse(hints.keywords.contains("커밋"))
        XCTAssertFalse(hints.prompt.contains("<ignore>"))
        XCTAssertFalse(hints.keywords.contains { $0.contains("\n") || $0.contains("\t") })
        let many = (0..<300).map { DictionaryEntry(spoken: "spoken\($0)", written: String(repeating: "x", count: 70) + "\($0)") }
        let bounded = TranscriptionHints.make(dictionary: many, profile: .init(kind: .development))
        XCTAssertLessThanOrEqual(bounded.keywords.count, 24)
        XCTAssertLessThanOrEqual(bounded.keywords.reduce(0) { $0 + $1.count }, 384)
        XCTAssertEqual(bounded.keywords.first, String(repeating: "x", count: 70) + "299")
    }

    func testFailureProfileRoundTripsAndOldRecordingsRemainDecodable() throws {
        let profile = WritingProfile(kind: .development, tone: .polite)
        let item = FailedRecording(mode: .dictation, provider: .openAI, targetLanguage: "Korean", writingProfile: profile)
        let encoded = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(FailedRecording.self, from: encoded).writingProfile, profile)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "writingProfile")
        let old = try JSONDecoder().decode(FailedRecording.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.writingProfile)
        XCTAssertEqual(old.id, item.id)
        XCTAssertEqual(old.expiresAt, item.expiresAt)
    }
}
