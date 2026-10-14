import Foundation

public enum ShortcutActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case toggle, hold, holdOrToggle

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .toggle: L("눌러서 시작·종료", "Press to start and stop")
        case .hold: L("누르는 동안 녹음", "Hold to record")
        case .holdOrToggle: L("짧게 눌러 계속·길게 눌러 녹음", "Tap to toggle, hold to record")
        }
    }
}

public enum ShortcutActivationAction: Equatable, Sendable {
    case toggle, start, stop
}

public struct ShortcutActivationEvent: Equatable, Sendable {
    public var mode: InputMode
    public var action: ShortcutActivationAction

    public init(mode: InputMode, action: ShortcutActivationAction) {
        self.mode = mode
        self.action = action
    }
}

public enum ShortcutRecordingState: Equatable, Sendable {
    case idle, starting(InputMode), recording(InputMode), busy
}

/// Key gestures own only the recording they requested. A release during asynchronous
/// startup waits for that recording, and cancellation invalidates the pending stop.
public struct ShortcutActivationPolicy: Sendable {
    public static let defaultHoldThreshold: TimeInterval = 0.3
    public let holdThreshold: TimeInterval
    public private(set) var recordingState: ShortcutRecordingState = .idle

    private struct Gesture: Sendable {
        var mode: InputMode
        var activation: ShortcutActivationMode
        var pressedAt: TimeInterval
        var stopWhenReady = false
    }

    private var pressedModes: [InputMode] = []
    private var gesture: Gesture?
    private var pendingStart: InputMode?

    public init(holdThreshold: TimeInterval = Self.defaultHoldThreshold) {
        self.holdThreshold = holdThreshold.isFinite && holdThreshold > 0
            ? holdThreshold : Self.defaultHoldThreshold
    }

    public mutating func press(_ mode: InputMode, activation: ShortcutActivationMode,
                               at time: TimeInterval) -> ShortcutActivationEvent? {
        guard !pressedModes.contains(mode) else { return nil }
        pressedModes.append(mode)
        // Keep the established toggle contract, including the app's own busy feedback.
        if activation == .toggle { return .init(mode: mode, action: .toggle) }
        switch recordingState {
        case .recording(let recordingMode):
            cancelGesture()
            return .init(mode: recordingMode, action: .stop)
        case .starting, .busy:
            return nil
        case .idle:
            // The app may not have entered .starting yet when a second key arrives.
            guard pendingStart == nil else { return nil }
            pendingStart = mode
            gesture = .init(mode: mode, activation: activation, pressedAt: time)
            return .init(mode: mode, action: .start)
        }
    }

    public mutating func release(_ mode: InputMode, at time: TimeInterval) -> ShortcutActivationEvent? {
        guard let index = pressedModes.firstIndex(of: mode) else { return nil }
        pressedModes.remove(at: index)
        guard var owned = gesture, owned.mode == mode else { return nil }
        let elapsed = time - owned.pressedAt
        let shouldStop = owned.activation == .hold
            || elapsed.isFinite && elapsed >= holdThreshold
        guard shouldStop else { gesture = nil; return nil }
        if recordingState == .recording(mode) {
            cancelGesture()
            return .init(mode: mode, action: .stop)
        }
        // Release can arrive before the .start callback begins or while it awaits
        // microphone/model preparation. Never turn that release into another start.
        if pendingStart == mode || recordingState == .starting(mode) {
            owned.stopWhenReady = true
            gesture = owned
        } else { gesture = nil }
        return nil
    }

    public mutating func updateRecordingState(_ state: ShortcutRecordingState) -> ShortcutActivationEvent? {
        recordingState = state
        switch state {
        case .idle, .busy:
            cancelGesture()
        case .starting(let mode):
            if let pendingStart, pendingStart != mode { cancelGesture() }
            if let gesture, gesture.mode != mode { cancelGesture() }
        case .recording(let mode):
            pendingStart = nil
            guard let owned = gesture else { return nil }
            guard owned.mode == mode else { cancelGesture(); return nil }
            if owned.stopWhenReady {
                cancelGesture()
                return .init(mode: mode, action: .stop)
            }
        }
        return nil
    }

    /// Keep held keys suppressed until their release after cancellation or a setting change.
    public mutating func cancelGesture() {
        gesture = nil
        pendingStart = nil
    }

    /// Re-registering bindings can prevent old key-up events from reaching this app.
    public mutating func resetPressedKeys() {
        pressedModes.removeAll()
        cancelGesture()
    }
}
