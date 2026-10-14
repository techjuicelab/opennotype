import Foundation
import XCTest
@testable import OpenNoTypeCore

final class LocalModelPolicyTests: XCTestCase {
    func testIdleUnloadRequiresConfiguredIntervalAndDoesNotUnloadAfterClockMovesBack() {
        let lastUse = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(LocalModelUnloadPolicy.never.shouldUnload(lastUse: lastUse, now: lastUse.addingTimeInterval(100_000)))
        XCTAssertFalse(LocalModelUnloadPolicy.afterFiveMinutes.shouldUnload(lastUse: nil, now: lastUse))
        XCTAssertFalse(LocalModelUnloadPolicy.afterFiveMinutes.shouldUnload(lastUse: lastUse, now: lastUse.addingTimeInterval(-1)))
        XCTAssertFalse(LocalModelUnloadPolicy.afterFiveMinutes.shouldUnload(lastUse: lastUse, now: lastUse.addingTimeInterval(299)))
        XCTAssertTrue(LocalModelUnloadPolicy.afterFiveMinutes.shouldUnload(lastUse: lastUse, now: lastUse.addingTimeInterval(300)))
        XCTAssertFalse(LocalModelUnloadPolicy.afterFifteenMinutes.shouldUnload(lastUse: lastUse, now: lastUse.addingTimeInterval(899)))
        XCTAssertTrue(LocalModelUnloadPolicy.afterThirtyMinutes.shouldUnload(lastUse: lastUse, now: lastUse.addingTimeInterval(1_800)))
    }

    func testPreviewRejectsShortAndInvalidRecentAudioAndBoundsMemory() throws {
        XCTAssertNil(LocalPreviewPolicy.recentWindow(Array(repeating: 0.2, count: 31_999)))
        XCTAssertNotNil(LocalPreviewPolicy.recentWindow(Array(repeating: 0.2, count: 32_000)))
        var samples = Array(repeating: Float(0.1), count: 16_000 * 60)
        samples[0] = .nan
        samples[samples.count - 1] = 0.8
        let recent = try XCTUnwrap(LocalPreviewPolicy.recentWindow(samples))
        XCTAssertEqual(recent.count, 16_000 * 12)
        XCTAssertEqual(recent.last, 0.8)
        samples[samples.count - 1] = .infinity
        XCTAssertNil(LocalPreviewPolicy.recentWindow(samples))
    }

    func testSelectingModelNeverDownloadsOrRemovesExistingFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try completeCache(.largeV3, in: directory)
        let transcriber = LocalTranscriber(cacheDirectory: directory)
        try await transcriber.selectModel(.small)
        let model = await transcriber.model
        let state = await transcriber.state
        let statuses = await transcriber.cacheStatuses()
        XCTAssertEqual(model, .small)
        XCTAssertEqual(state, .notPrepared)
        XCTAssertTrue(try XCTUnwrap(statuses.first { $0.model == .largeV3 }).isDownloaded)
        XCTAssertFalse(try XCTUnwrap(statuses.first { $0.model == .small }).isDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: LocalModelCache.modelFolder(.small, in: directory).path))
        XCTAssertTrue(statuses.allSatisfy { !$0.isLoaded })
    }

    func testDeletingSelectedCachePreservesOtherModelsSharedTokenizerAndUserRecordings() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try completeCache(.base, in: directory)
        try completeCache(.largeV3, in: directory)
        let sharedTokenizer = directory.appendingPathComponent("tokenizer.json")
        let recording = directory.appendingPathComponent("recordings/user.wav")
        try write(sharedTokenizer, data: Data("legacy shared tokenizer".utf8))
        try write(recording, data: Data("user recording".utf8))
        let transcriber = LocalTranscriber(model: .base, cacheDirectory: directory)
        let before = await transcriber.cacheStatuses()
        XCTAssertTrue(try XCTUnwrap(before.first { $0.model == .base }).isDownloaded)
        try await transcriber.deleteSelectedModelCache()
        let after = await transcriber.cacheStatuses()
        XCTAssertFalse(try XCTUnwrap(after.first { $0.model == .base }).isDownloaded)
        XCTAssertEqual(try XCTUnwrap(after.first { $0.model == .base }).storedBytes, 0)
        XCTAssertTrue(try XCTUnwrap(after.first { $0.model == .largeV3 }).isDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: LocalModelCache.tokenizerFolder(.base, in: directory).path))
        XCTAssertEqual(try Data(contentsOf: sharedTokenizer), Data("legacy shared tokenizer".utf8))
        XCTAssertEqual(try Data(contentsOf: recording), Data("user recording".utf8))
        // A second deletion is safe when all selected-model directories are absent.
        try await transcriber.deleteSelectedModelCache()
    }

    func testDeletionRefusesLinkedParentWithoutTouchingExternalFiles() async throws {
        let directory = temporaryDirectory()
        let external = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: external)
        }
        let retained = external.appendingPathComponent("whisper-base/tokenizer.json")
        try write(retained, data: Data("must remain".utf8))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("models"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("models/openai"), withDestinationURL: external)
        let transcriber = LocalTranscriber(model: .base, cacheDirectory: directory)
        do {
            try await transcriber.deleteSelectedModelCache()
            XCTFail("Deletion must reject symbolic links in its path")
        } catch {
            guard case LocalAudioError.unsafeModelCache = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: retained), Data("must remain".utf8))
    }

    func testCacheSizeDoesNotFollowLinksInsideModelDirectory() throws {
        let directory = temporaryDirectory()
        let external = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: external)
        }
        let folder = LocalModelCache.modelFolder(.base, in: directory)
        try write(folder.appendingPathComponent("owned.bin"), data: Data(repeating: 0, count: 7))
        try write(external.appendingPathComponent("external.bin"), data: Data(repeating: 0, count: 1_000))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("external"), withDestinationURL: external)
        XCTAssertEqual(LocalModelCache.storedBytes(.base, in: directory), 7)
    }

    func testPreviewAndIdleUnloadDoNothingWithoutPreparedEngine() async throws {
        let directory = temporaryDirectory()
        let transcriber = LocalTranscriber(cacheDirectory: directory)
        let preview = try await transcriber.preview(samples: Array(repeating: 0.2, count: 32_000), dictionary: [])
        let unloaded = try await transcriber.unloadIfIdle(policy: .afterFiveMinutes,
            now: Date().addingTimeInterval(1_000_000))
        XCTAssertNil(preview)
        XCTAssertFalse(unloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("opennotype-model-policy-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ file: URL, data: Data = Data("fixture".utf8)) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    private func completeCache(_ model: LocalSpeechModel, in directory: URL) throws {
        let folder = LocalModelCache.modelFolder(model, in: directory)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try write(folder.appendingPathComponent("\(component).mlmodelc/coremldata.bin"))
        }
        let tokenizer = LocalModelCache.tokenizerFolder(model, in: directory)
        try write(tokenizer.appendingPathComponent("tokenizer.json"))
        try write(tokenizer.appendingPathComponent("tokenizer_config.json"))
    }
}
