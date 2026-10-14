import AVFoundation
import Foundation
import XCTest
@testable import OpenNoType

final class AudioCaptureTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func buffer(sampleRate: Double = 16_000, channels: AVAudioChannelCount = 1,
                        frames: AVAudioFrameCount, value: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: channels, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, frames))!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for index in 0..<Int(frames) { buffer.floatChannelData![channel][index] = value }
        }
        return buffer
    }

    func testConverts48kStereoIntoPrivate16kMonoWAVAndIndependentPCMTail() throws {
        let input = buffer(sampleRate: 48_000, channels: 2, frames: 4800, value: 0.25)
        let url = root.appendingPathComponent("synthetic.wav")
        var ready = 0
        let subject = try AudioCapture(url: url, inputFormat: input.format, maximumDuration: 2) { event in
            if case .ready = event { ready += 1 }
            if case .failure(let error) = event { XCTFail("Unexpected conversion failure: \(error)") }
        }
        subject.enqueue(input)
        let first = subject.snapshot()
        subject.enqueue(input)
        subject.finish()
        XCTAssertEqual(ready, 1)
        let all = subject.snapshot()
        XCTAssertEqual(all.count, 3200, "Finalizing must flush the converter and trim its filter delay")
        XCTAssertFalse(first.isEmpty, "Live output may lag while the resampler retains its filter tail")
        XCTAssertLessThan(first.count, all.count)
        XCTAssertEqual(subject.snapshot(maximumSamples: 100), Array(all.suffix(100)))
        XCTAssertTrue(subject.snapshot(maximumSamples: 0).isEmpty)
        XCTAssertTrue(subject.snapshot(maximumSamples: -1).isEmpty)
        XCTAssertEqual(subject.currentMetrics().peakDB, -12.04, accuracy: 0.5)
        let progress = subject.progressSnapshot()
        XCTAssertEqual(progress.callbackFrames, 9600, "Input frames must not be multiplied by the channel count")
        XCTAssertEqual(progress.acceptedFrames, 9600)
        XCTAssertEqual(progress.deliveredFrames, 9600)
        XCTAssertEqual(progress.droppedFrames, 0)
        XCTAssertEqual(progress.pendingFrames, 0)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.streamDescription.pointee.mBitsPerChannel, 16)
        XCTAssertEqual(Int(file.length), all.count)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["synthetic.wav"])
    }

    func testResamplingFlushPreservesEndOfSpeechWithoutExtraPadding() throws {
        let input = buffer(sampleRate: 48_000, channels: 1, frames: 4800, value: 0)
        for index in 4320..<4800 { input.floatChannelData![0][index] = 0.75 }
        let url = root.appendingPathComponent("tail.wav")
        let subject = try AudioCapture(url: url, inputFormat: input.format, maximumDuration: 1) { _ in }
        subject.enqueue(input)
        let before = subject.snapshot()
        subject.finish()
        let after = subject.snapshot()
        XCTAssertEqual(after.count, 1600)
        XCTAssertLessThan(before.count, after.count, "The converter holds a tail until end-of-stream")
        XCTAssertGreaterThan(after.suffix(100).reduce(0, +) / 100, 0.7,
                             "Speech at the end must survive finalization")
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 1600)
    }

    func testStopsAtExactDurationAndRejectsBuffersAfterFinish() throws {
        let input = buffer(frames: 1024, value: 0.5)
        let url = root.appendingPathComponent("limit.wav")
        var limits = 0
        let subject = try AudioCapture(url: url, inputFormat: input.format, maximumDuration: 0.1) { event in
            if case .durationLimit = event { limits += 1 }
        }
        subject.enqueue(input); subject.enqueue(input)
        subject.finish()
        XCTAssertEqual(subject.snapshot().count, 1600)
        XCTAssertEqual(subject.currentMetrics().elapsed, 0.1, accuracy: 0.00001)
        XCTAssertEqual(limits, 1)
        subject.enqueue(input)
        subject.finish()
        XCTAssertEqual(subject.snapshot().count, 1600)
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 1600)
        let stopped = subject.progressSnapshot()
        subject.enqueue(input)
        XCTAssertEqual(subject.progressSnapshot().callbackFrames, stopped.callbackFrames,
                       "Late taps must not change a finished session's counters")
    }

    func testEmptyBuffersDoNotSignalReadyButValidSilenceDoes() throws {
        let empty = buffer(frames: 0, value: 0)
        let silence = buffer(frames: 1024, value: 0)
        var ready = 0
        let subject = try AudioCapture(url: root.appendingPathComponent("silence.wav"), inputFormat: silence.format,
                                       maximumDuration: 1) { event in if case .ready = event { ready += 1 } }
        subject.enqueue(empty)
        XCTAssertTrue(subject.snapshot().isEmpty)
        XCTAssertEqual(ready, 0)
        XCTAssertEqual(subject.progressSnapshot().callbackFrames, 0)
        XCTAssertNil(subject.progressSnapshot().lastCallbackAt)
        subject.enqueue(silence)
        XCTAssertNil(subject.finish())
        XCTAssertEqual(ready, 1, "Capture readiness is sample arrival, not speech detection")
        XCTAssertEqual(subject.currentMetrics().peakDB, -160)
        let progress = subject.progressSnapshot()
        XCTAssertEqual(progress.callbackFrames, 1024)
        XCTAssertEqual(progress.deliveredFrames, 1024)
        XCTAssertEqual(progress.droppedFrames, 0)
        XCTAssertNotNil(progress.lastCallbackAt)
        XCTAssertNotNil(progress.lastDeliveryAt, "Valid silence advances delivery like any other PCM")
    }

    func testTapBufferIsCopiedBeforeItsOwnerReusesMemory() throws {
        let input = buffer(frames: 1024, value: 0.25)
        let subject = try AudioCapture(url: root.appendingPathComponent("copy.wav"), inputFormat: input.format,
                                       maximumDuration: 1) { _ in }
        subject.enqueue(input)
        for index in 0..<1024 { input.floatChannelData![0][index] = -0.75 }
        subject.finish()
        let samples = subject.snapshot()
        XCTAssertEqual(samples.count, 1024)
        XCTAssertTrue(samples.allSatisfy { abs($0 - 0.25) < 0.0001 })
    }

    func testMetersAndProgressDoNotWaitForBlockedConsumer() throws {
        let input = buffer(frames: 1024, value: 0.25)
        let blocked = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let subject = try AudioCapture(url: root.appendingPathComponent("blocked.wav"), inputFormat: input.format,
                                       maximumDuration: 10) { event in
            if case .ready = event {
                blocked.signal()
                release.wait()
            }
        }
        subject.enqueue(input)
        guard blocked.wait(timeout: .now() + 3) == .success else {
            release.signal()
            subject.finish()
            return XCTFail("The consumer did not reach its first delivery")
        }
        let observed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            XCTAssertEqual(subject.currentMetrics().sampleCount, 1024)
            let progress = subject.progressSnapshot()
            XCTAssertEqual(progress.pendingBuffers, 1)
            XCTAssertEqual(progress.pendingFrames, 1024)
            XCTAssertNotNil(progress.lastDeliveryAt)
            observed.signal()
        }
        let result = observed.wait(timeout: .now() + 1)
        release.signal()
        XCTAssertNil(subject.finish())
        XCTAssertEqual(result, .success, "Meters and watchdog progress must not wait for the writer queue")
        // Also join the reader when testing an implementation that incorrectly blocks it.
        if result != .success { XCTAssertEqual(observed.wait(timeout: .now() + 3), .success) }
    }

    func testOverrunCountsWholeStereoFramesAndFinishPreservesFailure() throws {
        let input = buffer(channels: 2, frames: 1024, value: 0.25)
        let blocked = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        var failures = 0
        let subject = try AudioCapture(url: root.appendingPathComponent("overrun.wav"), inputFormat: input.format,
                                       maximumDuration: 10) { event in
            switch event {
            case .ready:
                blocked.signal()
                release.wait()
            case .failure: failures += 1
            case .durationLimit: XCTFail("This sample is shorter than the duration limit")
            }
        }
        subject.enqueue(input)
        guard blocked.wait(timeout: .now() + 3) == .success else {
            release.signal()
            subject.finish()
            return XCTFail("The consumer did not reach its first delivery")
        }
        for _ in 0..<31 { subject.enqueue(input) }
        subject.enqueue(input) // The in-flight buffer and 31 queued buffers already fill admission.
        let overloaded = subject.progressSnapshot()
        XCTAssertEqual(overloaded.pendingBuffers, 32)
        XCTAssertEqual(overloaded.pendingFrames, 32 * 1024)
        XCTAssertEqual(overloaded.callbackFrames, 33 * 1024)
        XCTAssertEqual(overloaded.acceptedFrames, 32 * 1024)
        XCTAssertEqual(overloaded.droppedFrames, 1024)
        XCTAssertEqual(overloaded.deliveredFrames + overloaded.droppedFrames + overloaded.pendingFrames,
                       overloaded.callbackFrames)
        XCTAssertEqual(failures, 0, "The failure event is still behind the blocked consumer")
        release.signal()
        let failure = subject.finish()
        guard case .captureInterrupted? = failure as? AudioRecorder.RecordingError else {
            return XCTFail("finish must expose the overrun even before a UI event handler runs")
        }
        XCTAssertEqual(failures, 1)
        let drained = subject.progressSnapshot()
        XCTAssertEqual(drained.pendingBuffers, 0)
        XCTAssertEqual(drained.pendingFrames, 0)
        XCTAssertEqual(drained.deliveredFrames, 32 * 1024)
        XCTAssertEqual(drained.deliveredFrames + drained.droppedFrames, drained.callbackFrames)
        XCTAssertEqual(subject.snapshot().count, 32 * 1024)
        XCTAssertTrue(subject.snapshot().allSatisfy { abs($0 - 0.25) < 0.0001 })
        subject.enqueue(input)
        XCTAssertEqual(subject.progressSnapshot().callbackFrames, drained.callbackFrames)
        guard case .captureInterrupted? = subject.finish() as? AudioRecorder.RecordingError else {
            return XCTFail("Repeated finish must retain the original failure")
        }
        XCTAssertEqual(failures, 1)
    }
}
