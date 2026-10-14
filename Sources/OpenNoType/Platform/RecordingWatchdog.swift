import Foundation

/// Checks capture progress without waiting for the conversion/file-writing queue.
struct RecordingWatchdog {
    enum Failure: Equatable { case callbackStalled, deliveryStalled }

    private static let clock = ContinuousClock()
    private static let origin = clock.now

    /// Unlike system uptime, this clock also measures time spent asleep.
    static var now: TimeInterval {
        let elapsed = origin.duration(to: clock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
    }

    let readyAt: TimeInterval
    var callbackTimeout: TimeInterval = 5
    var deliveryTimeout: TimeInterval = 10

    func failure(at now: TimeInterval, progress: AudioCapture.Progress,
                 reachedDurationLimit: Bool = false) -> Failure? {
        // Remember gaps even if callbacks resumed before a timer or stop checked them.
        if progress.maximumCallbackGap >= callbackTimeout { return .callbackStalled }
        // Once the full duration is captured, admission intentionally stops receiving callbacks.
        guard !reachedDurationLimit else { return nil }
        if now - max(readyAt, progress.lastCallbackAt ?? readyAt) >= callbackTimeout {
            return .callbackStalled
        }
        // No queued input means the converter may simply be retaining its resampling tail.
        if progress.pendingBuffers > 0,
           now - max(readyAt, progress.lastDeliveryAt ?? readyAt) >= deliveryTimeout {
            return .deliveryStalled
        }
        return nil
    }
}
