import Foundation
import XCTest
@preconcurrency import WhisperKit
@testable import OpenNoTypeCore

final class LocalTranscriberArbitrationTests: XCTestCase {
    func testFinalCancelsPreviewAndWaitsForItsEngineWorkBeforeStarting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("opennotype-arbitration-\(UUID().uuidString)")
        let engine = try await ArbitrationWhisperEngine(directory: directory)
        let transcriber = LocalTranscriber(preparedEngine: engine, cacheDirectory: directory)
        let preview = Task { try await transcriber.preview(samples: Array(repeating: 0.2, count: 32_000), dictionary: []) }
        await fulfillment(of: [engine.previewStarted], timeout: 3)
        let final = Task { try await transcriber.transcribe(samples: Array(repeating: 0.3, count: 16_000), dictionary: []) }
        defer { preview.cancel(); final.cancel(); Task { await engine.releasePreview() } }
        await fulfillment(of: [engine.previewCancelled], timeout: 3)

        // Cancellation has been requested but the preview's engine is deliberately still
        // unwinding. It must retain exclusive use of that engine throughout this interval.
        let skipped = try await transcriber.preview(samples: Array(repeating: 0.2, count: 32_000), dictionary: [])
        XCTAssertNil(skipped)
        do { try await transcriber.selectModel(.base); XCTFail("Model selection must not replace the active preview engine") }
        catch { guard case LocalAudioError.busy = error else { return XCTFail("Unexpected error: \(error)") } }
        do { try await transcriber.deleteSelectedModelCache(); XCTFail("Cache deletion must not interrupt engine work") }
        catch { guard case LocalAudioError.busy = error else { return XCTFail("Unexpected error: \(error)") } }
        let unloaded = try await transcriber.unloadIfIdle(policy: .afterFiveMinutes, now: Date().addingTimeInterval(10_000))
        XCTAssertFalse(unloaded)
        XCTAssertEqual(engine.callCounts.total, 1)

        await engine.releasePreview()
        let text = try await final.value
        XCTAssertEqual(text, "최종 API v0.2.8")
        do { _ = try await preview.value; XCTFail("A preempted preview must not publish stale text") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(engine.callCounts.total, 2)
        XCTAssertEqual(engine.callCounts.maximumConcurrent, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "Arbitration must not create a model cache")
    }
}

/// Uses only WhisperKit's unloaded constructor; every inference call is a test double.
private final class ArbitrationWhisperEngine: WhisperKit, @unchecked Sendable {
    let previewStarted = XCTestExpectation(description: "Preview started")
    let previewCancelled = XCTestExpectation(description: "Final requested preview cancellation")
    private let release = PreviewReleaseGate()
    private let lock = NSLock()
    private var total = 0
    private var active = 0
    private var maximumConcurrent = 0

    init(directory: URL) async throws {
        try await super.init(WhisperKitConfig(modelFolder: directory.path, verbose: false,
            prewarm: false, load: false, download: false))
    }

    var callCounts: (total: Int, maximumConcurrent: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (total, maximumConcurrent)
    }

    private func beginCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        total += 1
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        return total
    }

    private func finishCall() {
        lock.lock()
        defer { lock.unlock() }
        active -= 1
    }

    func releasePreview() async { await release.open() }

    override func transcribe(audioArray: [Float], decodeOptions: DecodingOptions? = nil,
                             callback: TranscriptionCallback? = nil,
                             segmentCallback: SegmentDiscoveryCallback? = nil) async throws -> [TranscriptionResult] {
        let call = beginCall()
        defer { finishCall() }
        if call == 1 {
            previewStarted.fulfill()
            await withTaskCancellationHandler {
                await release.wait()
            } onCancel: { [previewCancelled] in
                previewCancelled.fulfill()
            }
            try Task.checkCancellation()
        }
        return [TranscriptionResult(text: "최종 API v0.2.8", segments: [], language: "ko", timings: .init())]
    }
}

private actor PreviewReleaseGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func open() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
