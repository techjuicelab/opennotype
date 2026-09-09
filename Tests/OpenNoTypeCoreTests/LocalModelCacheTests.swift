import Foundation
import XCTest
@testable import OpenNoTypeCore

final class LocalModelCacheTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("opennotype-cache-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ path: String, in directory: URL, data: Data = Data("fixture".utf8)) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func testMissingCachesDoNotCreateDirectoriesOrClaimReadiness() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = LocalTranscriber(cacheDirectory: directory)
        let speaker = LocalSpeakerRecognizer(profileStore: CacheTestProfileStore(), cacheDirectory: directory)
        let transcriptionPrepared = try await transcriber.prepareCached()
        let speakerPrepared = try await speaker.prepareCached()
        XCTAssertFalse(transcriptionPrepared)
        XCTAssertFalse(speakerPrepared)
        let transcriptionState = await transcriber.state
        let speakerState = await speaker.state
        XCTAssertEqual(transcriptionState, .notPrepared)
        XCTAssertEqual(speakerState, .notPrepared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testWhisperCacheRequiresAllThreeModelsAndTokenizerConfiguration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = "models/argmaxinc/whisperkit-coreml/\(LocalSpeechModel.largeV3.variant)"
        try write("\(model)/MelSpectrogram.mlmodelc/coremldata.bin", in: directory)
        try write("\(model)/AudioEncoder.mlmodelc/coremldata.bin", in: directory)
        XCTAssertNil(LocalTranscriber.cachedFiles(for: .largeV3, in: directory))
        try write("\(model)/TextDecoder.mlmodelc/coremldata.bin", in: directory)
        try write("models/openai/whisper-large-v3/tokenizer.json", in: directory)
        XCTAssertNil(LocalTranscriber.cachedFiles(for: .largeV3, in: directory))
        try write("models/openai/whisper-large-v3/tokenizer_config.json", in: directory)
        let files = try XCTUnwrap(LocalTranscriber.cachedFiles(for: .largeV3, in: directory))
        XCTAssertEqual(files.model, directory.appendingPathComponent(model))
        XCTAssertEqual(files.tokenizer, directory.appendingPathComponent("models/openai/whisper-large-v3"))
        XCTAssertNil(LocalTranscriber.cachedFiles(for: .base, in: directory))
    }

    func testSpeakerCacheRequiresBothCompiledModels() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("pyannote_segmentation.mlmodelc/coremldata.bin", in: directory)
        XCTAssertNil(LocalSpeakerRecognizer.cachedModelFiles(in: directory))
        try write("wespeaker_v2.mlmodelc/coremldata.bin", in: directory)
        XCTAssertNotNil(LocalSpeakerRecognizer.cachedModelFiles(in: directory))
    }

    func testMalformedLocalTokenizerFailsWithoutCallingTheHubFallback() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let modelFolder = "models/argmaxinc/whisperkit-coreml/\(LocalSpeechModel.largeV3.variant)"
        for model in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try write("\(modelFolder)/\(model).mlmodelc/coremldata.bin", in: directory)
        }
        let tokenizerFolder = "models/openai/whisper-large-v3"
        try write("\(tokenizerFolder)/tokenizer.json", in: directory, data: Data("not json".utf8))
        try write("\(tokenizerFolder)/tokenizer_config.json", in: directory, data: Data("{}".utf8))
        let transcriber = LocalTranscriber(cacheDirectory: directory)
        do {
            _ = try await transcriber.prepareCached()
            XCTFail("A corrupt local tokenizer must fail instead of downloading a replacement")
        } catch {
            XCTAssertFalse(error is URLError, "Parsing local JSON should never reach an HTTP request")
        }
        let state = await transcriber.state
        guard case .failed = state else { return XCTFail("Corrupt cache must remain unavailable") }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("\(tokenizerFolder)/tokenizer.json")), Data("not json".utf8))
    }
}

private actor CacheTestProfileStore: SpeakerProfileStoring {
    func loadSpeakerProfile() async throws -> SpeakerVoiceProfile? { nil }
    func saveSpeakerProfile(_ profile: SpeakerVoiceProfile) async throws { }
    func deleteSpeakerProfile() async throws { }
}
