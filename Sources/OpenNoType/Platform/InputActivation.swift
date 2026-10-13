import Foundation

/// Activation operations are injectable without reading another app or posting input events.
@MainActor
struct InputActivationEnvironment {
    var frontmostPID: () -> pid_t?
    var ownIsActive: () -> Bool
    var targetRunning: () -> Bool
    var activateTarget: () -> Void
    var activateOwn: () -> Void
    var handoff: () -> Void
    var now: () -> TimeInterval
    var pause: (TimeInterval) async -> Void
}

@MainActor
enum InputActivation {
    static func bringToFront(targetPID: pid_t, ownPID: pid_t,
                             environment: InputActivationEnvironment,
                             isCancelled: () -> Bool) async -> Bool {
        func frontmostIsTarget() -> Bool { environment.frontmostPID() == targetPID }
        // The frontmost PID may lead the app's active signal during activation.
        func ownIsReady() -> Bool { environment.ownIsActive() }
        func waitForTarget(until deadline: TimeInterval) async -> Bool {
            while true {
                guard !isCancelled(), environment.targetRunning() else { return false }
                if frontmostIsTarget() { return true }
                let remaining = deadline - environment.now()
                guard remaining > 0 else { return false }
                await environment.pause(min(0.05, remaining))
            }
        }
        guard !isCancelled() else { return false }
        if frontmostIsTarget() { return true }
        guard environment.targetRunning() else { return false }
        environment.activateTarget()
        if await waitForTarget(until: environment.now() + 0.5) { return true }
        guard !isCancelled(), environment.targetRunning() else { return false }

        let needsOwnActivation = !ownIsReady()
        // Keep the existing two-attempt time budget. Own activation and the target handoff share
        // the second attempt; a slow activation never adds another independent timeout.
        let deadline = environment.now() + (needsOwnActivation ? 0.55 : 0.5)
        if needsOwnActivation {
            environment.activateOwn()
            while !ownIsReady() {
                guard !isCancelled(), environment.targetRunning() else { return false }
                if frontmostIsTarget() { return true }
                let remaining = deadline - environment.now()
                guard remaining > 0 else { return false }
                await environment.pause(min(0.02, remaining))
            }
        }
        guard !isCancelled(), environment.targetRunning() else { return false }
        if frontmostIsTarget() { return true }
        guard ownIsReady(), environment.now() < deadline else { return false }
        environment.handoff()
        return await waitForTarget(until: deadline)
    }
}
