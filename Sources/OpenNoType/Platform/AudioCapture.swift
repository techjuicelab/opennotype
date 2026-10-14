import AVFoundation
import Foundation

/// Owns conversion, file writes and snapshots on one queue. The tap only copies/enqueues buffers.
final class AudioCapture: @unchecked Sendable {
    enum Event { case ready, durationLimit, failure(Error) }
    struct Metrics {
        var sampleCount = 0
        var averageDB: Float = -160
        var peakDB: Float = -160
        var elapsed: TimeInterval { Double(sampleCount) / 16_000 }
    }
    struct Progress {
        var lastCallbackAt: TimeInterval?
        var lastDeliveryAt: TimeInterval?
        var maximumCallbackGap: TimeInterval = 0
        var pendingBuffers = 0
        // Input frames, independent of channel count and the output sample rate.
        // Accepted frames are cumulative admission; dropped also includes accepted
        // frames skipped after a terminal error or the intentional duration limit.
        // Once drained, callbackFrames == deliveredFrames + droppedFrames.
        // Delivered means input handled by conversion/writing, not samples retained
        // in the WAV: the last buffer may be trimmed at the intentional duration limit.
        var callbackFrames: UInt64 = 0
        var acceptedFrames: UInt64 = 0
        var droppedFrames: UInt64 = 0
        var deliveredFrames: UInt64 = 0
        var pendingFrames: UInt64 = 0
    }

    private let queue = DispatchQueue(label: "app.opennotype.audio-capture", qos: .userInitiated)
    private let admission = NSLock()
    private var accepting = true
    private var progress = Progress()
    private var failure: Error?
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var file: AVAudioFile?
    private var samples: [Float] = []
    private var metrics = Metrics()
    private let maximumSamples: Int
    private var hasNotifiedReady = false
    private var terminal = false
    private let onEvent: (Event) -> Void

    init(url: URL, inputFormat: AVAudioFormat, maximumDuration: TimeInterval,
         onEvent: @escaping (Event) -> Void) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw AudioRecorder.RecordingError.cannotStart
        }
        outputFormat = output
        self.converter = converter
        // Normal priming trims the resampler's filter delay. `.none` appends ringing past the input duration.
        converter.primeMethod = .normal
        maximumSamples = max(1, Int(maximumDuration * 16_000))
        self.onEvent = onEvent
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                                      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                      AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        admission.lock(); defer { admission.unlock() }
        guard accepting, buffer.frameLength > 0 else { return }
        let frames = UInt64(buffer.frameLength)
        let now = RecordingWatchdog.now
        if let previous = progress.lastCallbackAt {
            progress.maximumCallbackGap = max(progress.maximumCallbackGap, max(0, now - previous))
        }
        progress.lastCallbackAt = now
        progress.callbackFrames += frames
        // Refuse a discontinuous recording rather than silently dropping frames or growing without bound.
        guard progress.pendingBuffers < 32 else {
            reject(frames: frames, error: AudioRecorder.RecordingError.captureInterrupted)
            return
        }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            reject(frames: frames, error: AudioRecorder.RecordingError.cannotStart)
            return
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            if let fromData = from.mData, let toData = to.mData {
                memcpy(toData, fromData, Int(from.mDataByteSize))
            }
        }
        progress.acceptedFrames += frames
        progress.pendingFrames += frames
        progress.pendingBuffers += 1
        queue.async { [self] in
            let delivered = consume(copy)
            admission.lock()
            if delivered { progress.deliveredFrames += frames }
            else { progress.droppedFrames += frames }
            progress.pendingFrames -= frames
            progress.pendingBuffers -= 1
            admission.unlock()
        }
    }

    /// Caller holds admission. Latch immediately so stop cannot outrun the queued event.
    private func reject(frames: UInt64, error: Error) {
        progress.droppedFrames += frames
        if failure == nil { failure = error }
        accepting = false
        queue.async { [self] in fail(error) }
    }

    func snapshot(maximumSamples: Int? = nil) -> [Float] {
        queue.sync {
            guard let maximumSamples else { return samples }
            return Array(samples.suffix(max(0, maximumSamples)))
        }
    }

    func currentMetrics() -> Metrics {
        admission.lock(); defer { admission.unlock() }
        return metrics
    }

    func progressSnapshot() -> Progress {
        admission.lock(); defer { admission.unlock() }
        return progress
    }

    /// Closes admission before draining. Buffers admitted before stop finish; late taps cannot write.
    @discardableResult
    func finish() -> Error? {
        admission.lock(); accepting = false; admission.unlock()
        return queue.sync {
            if !terminal { flushConverter() }
            terminal = true; file = nil
            admission.lock(); defer { admission.unlock() }
            return failure
        }
    }

    private func consume(_ input: AVAudioPCMBuffer) -> Bool {
        guard !terminal else { return false }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            fail(AudioRecorder.RecordingError.cannotStart); return false
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !supplied else { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return input
        }
        guard status != .error, conversionError == nil else {
            fail(conversionError ?? AudioRecorder.RecordingError.audioWriteFailed as NSError); return false
        }
        return append(output)
    }

    @discardableResult
    private func append(_ output: AVAudioPCMBuffer) -> Bool {
        guard !terminal else { return false }
        guard output.frameLength > 0 else { return true }
        guard let channel = output.floatChannelData?[0], let writer = file else {
            fail(AudioRecorder.RecordingError.audioWriteFailed); return false
        }
        let remaining = maximumSamples - samples.count
        guard remaining > 0 else { return false }
        output.frameLength = min(output.frameLength, AVAudioFrameCount(remaining))
        let count = Int(output.frameLength)
        var energy: Double = 0
        for index in 0..<count {
            let value = channel[index].isFinite ? channel[index] : 0
            channel[index] = value
            energy += Double(value) * Double(value)
        }
        do { try writer.write(from: output) }
        catch { fail(error); return false }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        admission.lock()
        metrics.sampleCount = samples.count
        metrics.averageDB = energy > 0 ? max(-160, Float(20 * log10(sqrt(energy / Double(count))))) : -160
        metrics.peakDB = max(metrics.peakDB, metrics.averageDB)
        progress.lastDeliveryAt = RecordingWatchdog.now
        if samples.count >= maximumSamples { accepting = false }
        admission.unlock()
        if !hasNotifiedReady { hasNotifiedReady = true; onEvent(.ready) }
        if samples.count >= maximumSamples {
            terminal = true; file = nil; onEvent(.durationLimit)
        }
        return true
    }

    private func flushConverter() {
        // Resampling may retain a short tail. Finalize it before closing the WAV.
        for _ in 0..<8 {
            guard !terminal else { return }
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                fail(AudioRecorder.RecordingError.audioWriteFailed); return
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream; return nil
            }
            if status == .error || error != nil {
                fail(error ?? AudioRecorder.RecordingError.audioWriteFailed as NSError); return
            }
            append(output)
            if status == .endOfStream || output.frameLength == 0 { return }
        }
        // A bounded flush must not silently certify a converter that still has output.
        if !terminal { fail(AudioRecorder.RecordingError.audioWriteFailed) }
    }

    private func fail(_ error: Error) {
        admission.lock()
        if failure == nil { failure = error }
        let reportedError = failure ?? error
        accepting = false
        admission.unlock()
        guard !terminal else { return }
        terminal = true; file = nil; onEvent(.failure(reportedError))
    }
}
