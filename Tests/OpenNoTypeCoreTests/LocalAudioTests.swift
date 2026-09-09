import XCTest
@testable import OpenNoTypeCore

final class LocalAudioTests: XCTestCase {
    private func vector(at index: Int) -> [Float] {
        var result = [Float](repeating: 0, count: 256)
        result[index] = 1
        return result
    }

    func testDictionaryHintsPreserveMixedScriptAndLimitSize() {
        let entries = [
            DictionaryEntry(spoken: "에이피아이", written: "API"),
            DictionaryEntry(spoken: "API", written: "API"),
            DictionaryEntry(spoken: "오픈노타입", written: "OpenNoType"),
            DictionaryEntry(spoken: "연수구", written: "연수구"),
            DictionaryEntry(spoken: "", written: "  ")
        ]
        let hints = TranscriptionHints.make(dictionary: entries)
        XCTAssertEqual(hints.keywords, ["연수구", "OpenNoType", "API"])
        XCTAssertTrue(hints.localPrompt.hasPrefix("연수구, OpenNoType, API. "))
        let many = (0..<200).map { DictionaryEntry(spoken: "term\($0)", written: "TechnicalTerm\($0)") }
        XCTAssertLessThanOrEqual(TranscriptionHints.make(dictionary: many).keywords.count, 24)
    }

    func testWhisperControlTokensExcludedFromVocabularyPrompt() {
        // Actual multilingual Whisper encoding of "API", which previously produced empty STT.
        XCTAssertEqual(LocalTranscriber.vocabularyTokens([50258, 50364, 4715, 40, 50257], specialTokenBegin: 50257), [4715, 40])
        XCTAssertEqual(LocalTranscriber.vocabularyTokens([50258, 50257], specialTokenBegin: 50257), [])
        XCTAssertEqual(LocalTranscriber.vocabularyTokens(Array(0..<300), specialTokenBegin: 50257).count, 192)
    }

    func testFilterRejectsOtherSpeakerAndOverlappingSpeech() {
        let profile = SpeakerVoiceProfile(name: "Test", embedding: vector(at: 0), modelIdentifier: LocalSpeakerRecognizer.modelIdentifier)
        let candidates = [
            SpeakerSegmentCandidate(speakerID: "self", start: 0, end: 2, embedding: vector(at: 0)),
            SpeakerSegmentCandidate(speakerID: "other", start: 3, end: 4, embedding: vector(at: 1)),
            SpeakerSegmentCandidate(speakerID: "self", start: 5, end: 8, embedding: vector(at: 0)),
            SpeakerSegmentCandidate(speakerID: "other", start: 6, end: 7, embedding: vector(at: 1))
        ]
        XCTAssertEqual(LocalSpeakerRecognizer.acceptedRanges(candidates, profile: profile, audioDuration: 10), [0.0..<2.0])
    }

    func testFilterDoesNotDoubleCountDuplicatedSegmentsOrAcceptInvalidEmbedding() {
        let profile = SpeakerVoiceProfile(name: "Test", embedding: vector(at: 0), modelIdentifier: LocalSpeakerRecognizer.modelIdentifier)
        let candidates = [
            SpeakerSegmentCandidate(speakerID: "self", start: 0, end: 2, embedding: vector(at: 0)),
            SpeakerSegmentCandidate(speakerID: "self", start: 1, end: 3, embedding: vector(at: 0)),
            SpeakerSegmentCandidate(speakerID: "self", start: 4, end: 5, embedding: [Float](repeating: .nan, count: 256))
        ]
        XCTAssertEqual(LocalSpeakerRecognizer.acceptedRanges(candidates, profile: profile, audioDuration: 6), [0.0..<3.0])
        XCTAssertNil(LocalSpeakerRecognizer.normalized([Float](repeating: 0, count: 256)))
        XCTAssertNil(LocalSpeakerRecognizer.normalized([1, 0]))
    }

    func testMissingModelCannotPretendToTranscribe() async {
        let transcriber = LocalTranscriber()
        do {
            _ = try await transcriber.transcribe(samples: [0.2], dictionary: [])
            XCTFail("An unprepared engine must not report success")
        } catch {
            guard case LocalAudioError.notPrepared = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testEnrollmentFailureStillDeletesDisposableOriginal() async throws {
        let store = LocalAudioTestProfileStore()
        let recognizer = LocalSpeakerRecognizer(profileStore: store)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try Data("disposable enrollment fixture".utf8).write(to: file)
        do {
            _ = try await recognizer.enroll(consumingRecordingAt: file)
            XCTFail("Expected missing model error")
        } catch {
            guard case LocalAudioError.notPrepared = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let profile = try await store.loadSpeakerProfile()
        XCTAssertNil(profile)
    }

    /// Explicit opt-in only: downloads ~627 MB and runs genuine local Core ML inference.
    /// Synthetic fixtures verify the integration, not natural speech or mixed-language accuracy.
    func testOptInLocalTranscriptionIntegration() async throws {
        guard ProcessInfo.processInfo.environment["OPENNOTYPE_RUN_LOCAL_AUDIO_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENNOTYPE_RUN_LOCAL_AUDIO_INTEGRATION=1 to download the model and run synthetic audio.")
        }
        let transcriber = LocalTranscriber()
        try await transcriber.prepare { print("LOCAL_MODEL: \($0.label)") }
        let fixtures = [
            ("Yuna", "내일 오후 세 시에 회의가 있습니다. 회의 자료를 미리 준비해 주세요."),
            ("Samantha", "Please update the weather API and send the report tomorrow afternoon.")
        ]
        for (voice, sentence) in fixtures {
            let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aiff")
            defer { try? FileManager.default.removeItem(at: audioURL) }
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-o", audioURL.path, sentence]
            try say.run(); say.waitUntilExit()
            XCTAssertEqual(say.terminationStatus, 0)
            let text = try await transcriber.transcribe(audioURL: audioURL, dictionary: [DictionaryEntry(spoken: "에이피아이", written: "API")])
            XCTAssertFalse(text.isEmpty)
            if voice == "Yuna" { XCTAssertTrue(text.contains("회의"), "Korean fixture should contain its central topic") }
            if voice == "Samantha" { XCTAssertTrue(text.lowercased().contains("weather"), "English fixture should contain its central topic") }
            print("SYNTHETIC_\(voice)_INPUT: \(sentence)")
            print("SYNTHETIC_\(voice)_OUTPUT: \(text)")
        }
    }

    /// Uses only pre-existing model/tokenizer files and synthetic speech; never downloads.
    func testOptInCachedLocalTranscriptionIntegration() async throws {
        guard ProcessInfo.processInfo.environment["OPENNOTYPE_RUN_CACHED_AUDIO_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENNOTYPE_RUN_CACHED_AUDIO_INTEGRATION=1 to load existing caches and transcribe synthetic speech.")
        }
        let transcriber = LocalTranscriber()
        let prepared = try await transcriber.prepareCached { print("CACHED_LOCAL_MODEL: \($0.label)") }
        guard prepared else { throw XCTSkip("Model or tokenizer cache is missing; this test never downloads it.") }
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aiff")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Yuna", "-o", audioURL.path, "내일 오후 세 시에 회의가 있습니다. 회의 자료를 미리 준비해 주세요."]
        try say.run(); say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)
        let text = try await transcriber.transcribe(audioURL: audioURL, dictionary: [])
        XCTAssertTrue(text.contains("회의"), "Cached preparation must preserve multilingual decoding; got: \(text)")
        print("CACHED_SYNTHETIC_OUTPUT: \(text)")
    }
}

private actor LocalAudioTestProfileStore: SpeakerProfileStoring {
    var profile: SpeakerVoiceProfile?
    func loadSpeakerProfile() async throws -> SpeakerVoiceProfile? { profile }
    func saveSpeakerProfile(_ profile: SpeakerVoiceProfile) async throws { self.profile = profile }
    func deleteSpeakerProfile() async throws { profile = nil }
}
