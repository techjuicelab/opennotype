import Foundation
import XCTest
@testable import OpenNoType

@MainActor
final class InputActivationTests: XCTestCase {
    @MainActor private final class Environment {
        let targetPID: pid_t = 41001
        let ownPID: pid_t = 41002
        let otherPID: pid_t = 41003
        var frontmost: pid_t?
        var ownActive = false
        var running = true
        var cancelled = false
        var elapsed: TimeInterval = 0
        var directDelay: TimeInterval?
        var ownDelay: TimeInterval? = 0.2
        var ownFrontmostDelay: TimeInterval?
        var ownWasFrontmost = false
        var targetDelay: TimeInterval? = 0.05
        var directRequested: TimeInterval?
        var ownRequested: TimeInterval?
        var handoffRequested: TimeInterval?
        var ownBecameActive: TimeInterval?
        var directCalls = 0
        var ownCalls = 0
        var handoffCalls = 0
        var handoffsBeforeOwnActive = 0
        var onPause: (() -> Void)?

        init() { frontmost = otherPID }

        var operations: InputActivationEnvironment {
            InputActivationEnvironment(frontmostPID: { self.frontmost }, ownIsActive: { self.ownActive },
                targetRunning: { self.running }, activateTarget: {
                    self.directCalls += 1; self.directRequested = self.elapsed
                }, activateOwn: {
                    self.ownCalls += 1; self.ownRequested = self.elapsed
                }, handoff: {
                    self.handoffCalls += 1
                    if !self.ownActive { self.handoffsBeforeOwnActive += 1 }
                    if self.frontmost == self.ownPID || self.ownActive {
                        self.handoffRequested = self.elapsed
                    }
                }, now: { self.elapsed }, pause: { interval in
                    self.elapsed += interval
                    if let requested = self.directRequested, let delay = self.directDelay,
                       self.elapsed - requested + 0.000_001 >= delay {
                        self.frontmost = self.targetPID; self.ownActive = false
                        self.directRequested = nil
                    }
                    if let requested = self.ownRequested, let delay = self.ownDelay,
                       self.elapsed - requested + 0.000_001 >= delay, self.ownBecameActive == nil {
                        self.frontmost = self.ownPID; self.ownActive = true
                        self.ownBecameActive = self.elapsed
                    }
                    if let requested = self.ownRequested, let delay = self.ownFrontmostDelay,
                       self.elapsed - requested + 0.000_001 >= delay, !self.ownWasFrontmost {
                        self.frontmost = self.ownPID; self.ownWasFrontmost = true
                    }
                    if let requested = self.handoffRequested, let delay = self.targetDelay,
                       self.elapsed - requested + 0.000_001 >= delay {
                        self.frontmost = self.targetPID; self.ownActive = false
                        self.handoffRequested = nil
                    }
                    self.onPause?()
                })
        }

        func bringToFront() async -> Bool {
            await InputActivation.bringToFront(targetPID: targetPID, ownPID: ownPID,
                environment: operations, isCancelled: { self.cancelled })
        }
    }

    func testAlreadyFrontmostTargetNeedsNoActivation() async {
        let fixture = Environment(); fixture.frontmost = fixture.targetPID
        let result = await fixture.bringToFront()
        XCTAssertTrue(result)
        XCTAssertEqual(fixture.directCalls + fixture.ownCalls + fixture.handoffCalls, 0)
        XCTAssertEqual(fixture.elapsed, 0)
    }

    func testDirectActivationReturnsWithoutActivatingOwnApp() async {
        let fixture = Environment(); fixture.directDelay = 0.1
        let result = await fixture.bringToFront()
        XCTAssertTrue(result)
        XCTAssertEqual(fixture.directCalls, 1)
        XCTAssertEqual(fixture.ownCalls + fixture.handoffCalls, 0)
        XCTAssertLessThanOrEqual(fixture.elapsed, 0.15)
    }

    func testAlreadyActiveOwnAppCanHandOffWithoutOwnActivation() async {
        let fixture = Environment(); fixture.frontmost = fixture.ownPID; fixture.ownActive = true
        let result = await fixture.bringToFront()
        XCTAssertTrue(result)
        XCTAssertEqual(fixture.ownCalls, 0)
        XCTAssertEqual(fixture.handoffCalls, 1)
        XCTAssertLessThanOrEqual(fixture.elapsed, 1.0)
    }

    func testSlowOwnActivationWaitsForReadinessBeforeOneHandoff() async throws {
        let fixture = Environment()
        let result = await fixture.bringToFront()
        XCTAssertTrue(result, "A 200ms own activation must not be handed off after a fixed 50ms")
        let ownRequested = try XCTUnwrap(fixture.ownRequested)
        let ownReady = try XCTUnwrap(fixture.ownBecameActive)
        XCTAssertGreaterThanOrEqual(ownReady - ownRequested, 0.2 - 0.000_001)
        XCTAssertEqual(fixture.directCalls, 1)
        XCTAssertEqual(fixture.ownCalls, 1)
        XCTAssertEqual(fixture.handoffCalls, 1)
        XCTAssertLessThanOrEqual(fixture.elapsed, 1.05 + 0.000_001)
        XCTAssertEqual(fixture.frontmost, fixture.targetPID)
    }

    func testOwnActivationThatNeverBecomesReadyDoesNotHandOffOrExtendDeadline() async {
        let fixture = Environment(); fixture.ownDelay = nil
        let result = await fixture.bringToFront()
        XCTAssertFalse(result)
        XCTAssertEqual(fixture.handoffCalls, 0)
        XCTAssertEqual(fixture.frontmost, fixture.otherPID)
        XCTAssertLessThanOrEqual(fixture.elapsed, 1.05 + 0.000_001)
    }

    func testFrontmostOwnPIDBeforeActiveSignalStillWaitsForReadiness() async {
        let fixture = Environment(); fixture.ownFrontmostDelay = 0.02
        let result = await fixture.bringToFront()
        XCTAssertTrue(result)
        XCTAssertNotNil(fixture.ownBecameActive)
        XCTAssertEqual(fixture.handoffCalls, 1)
        XCTAssertEqual(fixture.handoffsBeforeOwnActive, 0, "Frontmost PID alone does not establish activation readiness")
        XCTAssertLessThanOrEqual(fixture.elapsed, 1.05 + 0.000_001)
    }

    func testFrontmostOwnPIDWithoutActiveSignalNeverHandsOff() async {
        let fixture = Environment(); fixture.ownFrontmostDelay = 0.02; fixture.ownDelay = nil
        let result = await fixture.bringToFront()
        XCTAssertFalse(result)
        XCTAssertEqual(fixture.handoffCalls, 0)
        XCTAssertEqual(fixture.handoffsBeforeOwnActive, 0)
        XCTAssertLessThanOrEqual(fixture.elapsed, 1.05 + 0.000_001)
    }

    func testCancellationWhileOwnAppIsPreparingStopsBeforeHandoff() async {
        let fixture = Environment()
        fixture.onPause = {
            if let requested = fixture.ownRequested, fixture.elapsed - requested >= 0.1 {
                fixture.cancelled = true
            }
        }
        let result = await fixture.bringToFront()
        XCTAssertFalse(result)
        XCTAssertEqual(fixture.handoffCalls, 0)
        XCTAssertLessThan(fixture.elapsed, 0.8)
    }

    func testTargetTerminationWhileOwnAppIsPreparingStopsBeforeHandoff() async {
        let fixture = Environment()
        fixture.onPause = {
            if let requested = fixture.ownRequested, fixture.elapsed - requested >= 0.1 {
                fixture.running = false
            }
        }
        let result = await fixture.bringToFront()
        XCTAssertFalse(result)
        XCTAssertEqual(fixture.handoffCalls, 0)
        XCTAssertLessThan(fixture.elapsed, 0.8)
    }

    func testUnresponsiveTargetUsesTheExistingBoundedTwoAttemptsOnly() async {
        let fixture = Environment(); fixture.targetDelay = nil
        let result = await fixture.bringToFront()
        XCTAssertFalse(result)
        XCTAssertEqual(fixture.directCalls, 1)
        XCTAssertEqual(fixture.ownCalls, 1)
        XCTAssertEqual(fixture.handoffCalls, 1)
        XCTAssertLessThanOrEqual(fixture.elapsed, 1.05 + 0.000_001)
    }

    func testTargetAlreadyGoneDoesNotActivateAnyApp() async {
        let fixture = Environment(); fixture.running = false
        let result = await fixture.bringToFront()
        XCTAssertFalse(result)
        XCTAssertEqual(fixture.directCalls + fixture.ownCalls + fixture.handoffCalls, 0)
        XCTAssertEqual(fixture.elapsed, 0)
    }
}
