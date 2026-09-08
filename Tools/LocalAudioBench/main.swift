import Foundation
import OpenNoTypeCore

private actor MemoryProfileStore: SpeakerProfileStoring {
    private var profile: SpeakerVoiceProfile?
    func loadSpeakerProfile() async throws -> SpeakerVoiceProfile? { profile }
    func saveSpeakerProfile(_ profile: SpeakerVoiceProfile) async throws { self.profile = profile }
    func deleteSpeakerProfile() async throws { profile = nil }
}

@main
struct LocalAudioBench {
    static func main() async {
        setbuf(stdout, nil)
        guard CommandLine.arguments.contains("--transcription") || CommandLine.arguments.contains("--speakers") else {
            print("사용법: swift run LocalAudioBench --transcription 또는 --speakers")
            print("합성 음성만 생성합니다. STT는 약627MB, 화자 모델은 약14MB를 다운로드할 수 있습니다.")
            return
        }
        do {
            if CommandLine.arguments.contains("--transcription") { try await runTranscription() }
            if CommandLine.arguments.contains("--speakers") { try await runSpeakers() }
        } catch {
            print("LOCAL_AUDIO_BENCH_ERROR: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func synthetic(voice: String, text: String) throws -> URL {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("opennotype-synthetic-\(UUID().uuidString).aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", voice, "-o", audioURL.path, text]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: audioURL)
            throw NSError(domain: "LocalAudioBench", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "macOS say 생성 실패"])
        }
        return audioURL
    }

    private static func runTranscription() async throws {
        let transcriber = LocalTranscriber()
        let start = Date()
        try await transcriber.prepare { state in
            switch state {
            case .downloading(let progress):
                if progress >= 1 { print("STT_DOWNLOAD_COMPLETE") }
            default: print("STT_MODEL: \(state.label)")
            }
        }
        print("STT_PREPARE_SECONDS: \(Date().timeIntervalSince(start))")
        for (voice, sentence) in [
            ("Yuna", "내일 오후 세 시에 회의가 있습니다. 회의 자료를 미리 준비해 주세요."),
            ("Samantha", "Please update the weather API and send the report tomorrow afternoon.")
        ] {
            let file = try synthetic(voice: voice, text: sentence)
            defer { try? FileManager.default.removeItem(at: file) }
            let start = Date()
            let result = try await transcriber.transcribe(audioURL: file, dictionary: [DictionaryEntry(spoken: "에이피아이", written: "API")])
            print("SYNTHETIC_STT_\(voice): \(result)")
            print("SYNTHETIC_INPUT_\(voice): \(sentence)")
            print("STT_\(voice)_SECONDS: \(Date().timeIntervalSince(start))")
        }
    }

    private static func runSpeakers() async throws {
        let store = MemoryProfileStore()
        let recognizer = LocalSpeakerRecognizer(profileStore: store)
        try await recognizer.prepare { state in
            switch state {
            case .downloading: break
            default: print("SPEAKER_MODEL: \(state.label)")
            }
        }
        let enrollment = try synthetic(voice: "Samantha", text: "This is my voice registration. I am speaking on my own in a quiet room. I want the application to recognize my voice when I dictate messages and write documents.")
        defer { try? FileManager.default.removeItem(at: enrollment) }
        let profile = try await recognizer.enroll(consumingRecordingAt: enrollment, name: "Synthetic Samantha")
        print("SYNTHETIC_SPEAKER_EMBEDDING_DIMENSIONS: \(profile.embedding.count)")
        print("ENROLLMENT_ORIGINAL_DELETED: \(!FileManager.default.fileExists(atPath: enrollment.path))")
        let text = "Tomorrow I will prepare the meeting notes and update the project documents. Please send the final report before the afternoon meeting begins."
        for voice in ["Samantha", "Daniel"] {
            let file = try synthetic(voice: voice, text: text)
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                let result = try await recognizer.filter(audioURL: file)
                print("SYNTHETIC_SPEAKER_\(voice): accepted=\(result.acceptedDuration), discarded=\(result.discardedDuration)")
            } catch LocalAudioError.noMatchingSpeaker {
                print("SYNTHETIC_SPEAKER_\(voice): noMatchingSpeaker")
            }
        }
        try await recognizer.deleteProfile()
        let hasProfile = try await recognizer.hasProfile()
        print("SYNTHETIC_PROFILE_DELETED: \(!hasProfile)")
        print("LIMITATION: \(LocalSpeakerRecognizer.limitation)")
    }
}
