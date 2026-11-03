import CryptoKit
import Foundation
import XCTest
@testable import OpenNoTypeCore

final class LocalModelPinTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("LocalModelPinTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testManifestPinsEveryFileThatEachModelLoads() throws {
        let commit = try NSRegularExpression(pattern: "^[0-9a-f]{40}$")
        let digest = try NSRegularExpression(pattern: "^[0-9a-f]{64}$")
        func matches(_ expression: NSRegularExpression, _ value: String) -> Bool {
            expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        }
        func check(_ files: [LocalModelFile], _ label: String) {
            XCTAssertFalse(files.isEmpty, label)
            XCTAssertEqual(Set(files.map(\.path)).count, files.count, "\(label) lists a file twice")
            for file in files {
                XCTAssertTrue(matches(digest, file.sha256), "\(label): \(file.path)")
                XCTAssertGreaterThan(file.size, 0, "\(label): \(file.path)")
                XCTAssertFalse(file.path.hasPrefix("/") || file.path.split(separator: "/").contains(".."), file.path)
            }
        }
        XCTAssertTrue(matches(commit, LocalModelManifest.whisperModels.revision))
        XCTAssertTrue(matches(commit, LocalModelManifest.speakerModels.revision))
        for model in LocalSpeechModel.allCases {
            let files = LocalModelManifest.whisperFiles(model)
            check(files, model.rawValue)
            XCTAssertEqual(files.reduce(0) { $0 + $1.size }, model.downloadBytes, "The pin must cover exactly the advertised download")
            XCTAssertTrue(files.allSatisfy { $0.path.hasPrefix(model.variant + "/") })
            for part in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
                XCTAssertTrue(files.contains { $0.path == "\(model.variant)/\(part).mlmodelc/coremldata.bin" }, "\(model) \(part)")
            }
            let tokenizer = LocalModelManifest.tokenizer(model)
            XCTAssertTrue(matches(commit, tokenizer.revision))
            check(LocalModelManifest.tokenizerFiles(model), tokenizer.repository)
            XCTAssertEqual(Set(LocalModelManifest.tokenizerFiles(model).map(\.path)), Set(LocalModelManifest.tokenizerFileNames))
            // Files are downloaded exactly where the local-only loader looks for them.
            XCTAssertEqual(LocalModelIntegrity.repositoryFolder(LocalModelManifest.whisperModels, in: root)
                .appendingPathComponent(model.variant).path, LocalModelCache.modelFolder(model, in: root).path)
            XCTAssertEqual(LocalModelIntegrity.repositoryFolder(tokenizer, in: root).path,
                           LocalModelCache.tokenizerFolder(model, in: root).path)
        }
        let speaker = LocalModelManifest.speakerFiles
        check(speaker, "speaker")
        XCTAssertEqual(speaker.reduce(0) { $0 + $1.size }, 5_766_532 + 7_954_144)
        for folder in LocalModelManifest.speakerFolders {
            XCTAssertTrue(speaker.contains { $0.path == "\(folder)/coremldata.bin" }, folder)
        }
        XCTAssertTrue(speaker.allSatisfy { file in LocalModelManifest.speakerFolders.contains { file.path.hasPrefix($0 + "/") } })
    }

    func testIntegrityAcceptsExactFilesAndRemovesOnlyMismatches() throws {
        let one = try write("weights/one.bin", "alpha"), two = try write("two.json", "{\"b\":1}")
        let manifest = [entry("weights/one.bin", "alpha"), entry("two.json", "{\"b\":1}")]
        XCTAssertNoThrow(try LocalModelIntegrity.verify(manifest, in: root))

        try Data("alphX".utf8).write(to: one) // Same size, different content.
        XCTAssertThrowsError(try LocalModelIntegrity.verify(manifest, in: root, removingMismatches: false)) {
            XCTAssertEqual($0 as? LocalAudioError, .modelIntegrityFailed)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: one.path), "A check without removal keeps the file")
        XCTAssertThrowsError(try LocalModelIntegrity.verify(manifest, in: root)) {
            XCTAssertEqual($0 as? LocalAudioError, .modelIntegrityFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: one.path), "A mismatch is removed so it is downloaded again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: two.path), "Matching files are kept")
        XCTAssertThrowsError(try LocalModelIntegrity.verify(manifest, in: root), "A missing file fails")
    }

    func testIntegrityNeverFollowsOrRemovesSymbolicLinks() throws {
        let outside = root.appendingPathComponent("outside.bin")
        try Data("alpha".utf8).write(to: outside)
        let link = root.appendingPathComponent("cache/one.bin")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try LocalModelIntegrity.verify([entry("one.bin", "alpha")], in: root.appendingPathComponent("cache"))) {
            XCTAssertEqual($0 as? LocalAudioError, .unsafeModelCache)
        }
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data("alpha".utf8))
    }

    func testPreparationRequestsOnlyPinnedCommitsAndNeverLoadsUnverifiedFiles() async throws {
        let downloader = RecordingModelDownloader()
        let transcriber = LocalTranscriber(model: .base, cacheDirectory: root, downloader: downloader)
        do {
            try await transcriber.prepare()
            XCTFail("Unverified files must not be prepared")
        } catch {
            XCTAssertEqual(error as? LocalAudioError, .modelIntegrityFailed)
        }
        let requests = await downloader.requests
        XCTAssertEqual(requests.map(\.pin), [LocalModelManifest.whisperModels, LocalModelManifest.tokenizer(.base)])
        XCTAssertEqual(requests.map(\.globs), [["openai_whisper-base/*"], LocalModelManifest.tokenizerFileNames])
        XCTAssertTrue(requests.allSatisfy { $0.base.path == root.path })
        XCTAssertNil(LocalTranscriber.cachedFiles(for: .base, in: root), "Tampered files are removed instead of loaded later")
        guard case .failed = await transcriber.state else { return XCTFail("The failure must be visible") }
    }

    func testSpeakerPreparationKeepsExistingModelsWhenTheDownloadDoesNotVerify() async throws {
        let existing = root.appendingPathComponent("pyannote_segmentation.mlmodelc/coremldata.bin")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("previously downloaded".utf8).write(to: existing)
        let downloader = RecordingModelDownloader()
        let recognizer = LocalSpeakerRecognizer(profileStore: PinTestProfileStore(), cacheDirectory: root, downloader: downloader)
        do {
            try await recognizer.prepare()
            XCTFail("An unverified download must not be installed")
        } catch {
            XCTAssertEqual(error as? LocalAudioError, .modelIntegrityFailed)
        }
        let requests = await downloader.requests
        XCTAssertEqual(requests.map(\.pin), [LocalModelManifest.speakerModels])
        XCTAssertEqual(requests.first?.globs, ["pyannote_segmentation.mlmodelc/*", "wespeaker_v2.mlmodelc/*"])
        XCTAssertNotEqual(requests.first?.base.path, root.path, "Downloads are staged outside the model cache")
        XCTAssertEqual(try Data(contentsOf: existing), Data("previously downloaded".utf8))
    }

    @discardableResult
    private func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func entry(_ path: String, _ text: String) -> LocalModelFile {
        let data = Data(text.utf8)
        return LocalModelFile(path, Int64(data.count), SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
}

/// Records each request and writes tampered copies of the files a loader looks for, so only
/// verification stands between these files and a model load.
private actor RecordingModelDownloader: LocalModelDownloading {
    struct Request { let pin: LocalModelPin; let globs: [String]; let base: URL }
    private(set) var requests: [Request] = []

    func download(_ pin: LocalModelPin, matching globs: [String], into downloadBase: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        requests.append(Request(pin: pin, globs: globs, base: downloadBase))
        let folder = LocalModelIntegrity.repositoryFolder(pin, in: downloadBase)
        let prefixes = globs.map { $0.hasSuffix("/*") ? String($0.dropLast()) : $0 }
        let candidates = pin == LocalModelManifest.whisperModels ? LocalSpeechModel.allCases.flatMap(LocalModelManifest.whisperFiles)
            : pin == LocalModelManifest.speakerModels ? LocalModelManifest.speakerFiles : LocalModelManifest.tokenizerFiles(.base)
        for file in candidates where prefixes.contains(where: { file.path.hasPrefix($0) })
            && (file.path.hasSuffix("coremldata.bin") || file.path.hasPrefix("tokenizer")) {
            let target = folder.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("tampered".utf8).write(to: target)
        }
        progress(1)
    }
}

private actor PinTestProfileStore: SpeakerProfileStoring {
    func loadSpeakerProfile() async throws -> SpeakerVoiceProfile? { nil }
    func saveSpeakerProfile(_ profile: SpeakerVoiceProfile) async throws {}
    func deleteSpeakerProfile() async throws {}
}
