import AppKit
import Foundation
import Sparkle
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class UpdaterTests: XCTestCase {
    private var validInfo: [String: Any] {
        ["SUFeedURL": Updater.feedURL.absoluteString,
         "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
         "CFBundleShortVersionString": "0.1.10", "CFBundleVersion": "11"]
    }

    private func makeUpdater(_ backend: FakeUpdateBackend) -> Updater {
        Updater(info: validInfo, isPreview: false) { feed in
            XCTAssertEqual(feed, Updater.feedURL)
            return backend
        }
    }

    func testSparkleOptionalDelegateSelectorsAreImplementedWithoutStartingUpdater() {
        // An optional Objective-C delegate method can silently stop matching after a rename.
        let selectors = [#selector(SPUUpdaterDelegate.feedURLString(for:)),
                         #selector(SPUUpdaterDelegate.updater(_:mayPerform:)),
                         #selector(SPUUpdaterDelegate.updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)),
                         #selector(SPUUpdaterDelegate.updater(_:didFinishUpdateCycleFor:error:))]
        for selector in selectors {
            XCTAssertTrue(SparkleUpdateBackend.instancesRespond(to: selector), NSStringFromSelector(selector))
        }
    }

    func testMissingOrPartialConfigurationNeverCreatesBackend() {
        for info in [[:], ["SUFeedURL": Updater.feedURL.absoluteString], ["SUPublicEDKey": ""], ["SUFeedURL": 4]] as [[String: Any]] {
            let updater = Updater(info: info, isPreview: false) { _ in XCTFail("Unconfigured updater must not start Sparkle"); return FakeUpdateBackend() }
            XCTAssertFalse(updater.isConfigured)
            XCTAssertFalse(updater.canCheck)
            XCTAssertFalse(updater.isStarted)
            XCTAssertNotNil(updater.configurationMessage)
            updater.check()
            updater.setAutomaticChecks(true)
        }
    }

    func testPreviewNeverCreatesBackendEvenWithValidConfiguration() {
        let updater = Updater(info: validInfo, isPreview: true) { _ in XCTFail("Preview must never create a network updater"); return FakeUpdateBackend() }
        XCTAssertFalse(updater.isConfigured)
        XCTAssertFalse(updater.canCheck)
        XCTAssertTrue(updater.isPreview)
        updater.check()
        updater.setAutomaticChecks(true)
    }

    func testFeedRejectsCredentialsSpoofedHostsAndUnapprovedPaths() {
        let path = "/techjuicelab/opennotype/releases/latest/download/appcast.xml"
        for feed in ["http://github.com" + path, "https://github.com.evil.test" + path,
                     "https://github.com@evil.test" + path, "https://user@github.com" + path,
                     "https://user:password@github.com" + path, "https://github.com:444" + path,
                     "https://github.com" + path + "?token=test", "https://github.com" + path + "#fragment",
                     "https://github.com/another/project/releases/latest/download/appcast.xml",
                     "https://github.com" + path.replacingOccurrences(of: "appcast", with: "%61ppcast"),
                     "https://github.com." + path, "https://", "github.com" + path] {
            var info = validInfo; info["SUFeedURL"] = feed
            let updater = Updater(info: info, isPreview: false) { _ in XCTFail("Rejected feed created backend: \(feed)"); return FakeUpdateBackend() }
            XCTAssertFalse(updater.isConfigured, feed)
            XCTAssertFalse(updater.canCheck, feed)
        }
        XCTAssertTrue(Updater.validFeed("HTTPS://GITHUB.COM" + path))
    }

    func testPublicKeyRequiresCanonicalBase64EncodingOf32Bytes() {
        let valid = Data(repeating: 7, count: 32).base64EncodedString()
        for key in ["not-base64", Data(repeating: 7, count: 31).base64EncodedString(),
                    Data(repeating: 0, count: 32).base64EncodedString(),
                    Data(repeating: 7, count: 33).base64EncodedString(), valid + "\n", " " + valid,
                    String(valid.dropLast()), valid.replacingOccurrences(of: "=", with: "!")] {
            var info = validInfo; info["SUPublicEDKey"] = key
            let updater = Updater(info: info, isPreview: false) { _ in XCTFail("Invalid key created backend"); return FakeUpdateBackend() }
            XCTAssertFalse(updater.isConfigured)
        }
        XCTAssertTrue(Updater.validPublicKey(valid))
    }

    func testLaunchReadsStoredAutomaticChoiceWithoutWritingEitherValue() {
        for enabled in [true, false] {
            let backend = FakeUpdateBackend()
            backend.state.automaticallyChecks = enabled
            let updater = makeUpdater(backend)
            XCTAssertTrue(updater.isConfigured)
            XCTAssertTrue(updater.isStarted)
            XCTAssertEqual(updater.automaticChecks, enabled)
            XCTAssertEqual(backend.starts, 1)
            XCTAssertEqual(backend.automaticWrites, [])
            XCTAssertEqual(updater.version, "0.1.10 (11)")
        }
    }

    func testAutomaticPreferenceWritesOnlyWhenUserChangesIt() {
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        updater.setAutomaticChecks(false)
        updater.setAutomaticChecks(true)
        updater.setAutomaticChecks(true)
        updater.setAutomaticChecks(false)
        XCTAssertEqual(backend.automaticWrites, [true, false])
        XCTAssertFalse(updater.automaticChecks)
    }

    func testBackendChangesUpdateCheckButtonDateAndAutomaticChoice() {
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        XCTAssertTrue(updater.canCheck)
        backend.state = .init(canCheck: false, automaticallyChecks: true, lastCheck: Date(timeIntervalSince1970: 123))
        backend.stateChanged?()
        XCTAssertFalse(updater.canCheck)
        XCTAssertTrue(updater.automaticChecks)
        XCTAssertEqual(updater.lastCheck, Date(timeIntervalSince1970: 123))
        updater.check()
        XCTAssertEqual(backend.checks, 0)
        backend.state.canCheck = true; backend.stateChanged?()
        updater.check()
        XCTAssertEqual(backend.checks, 1)
        XCTAssertFalse(updater.canCheck)
    }

    func testStartupFailureDisablesActionsAndSurfacesError() {
        let backend = FakeUpdateBackend()
        backend.startError = NSError(domain: "synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "시작 실패"])
        let updater = makeUpdater(backend)
        XCTAssertTrue(updater.isConfigured)
        XCTAssertFalse(updater.isStarted)
        XCTAssertFalse(updater.canCheck)
        XCTAssertTrue(updater.errorMessage?.contains("시작 실패") == true)
        updater.check(); updater.setAutomaticChecks(true)
        XCTAssertEqual(backend.checks, 0)
        XCTAssertEqual(backend.automaticWrites, [])
    }

    func testFailedCheckIsVisibleAndNewCheckClearsIt() {
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        backend.cycleFinished?(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertNotNil(updater.errorMessage)
        updater.check()
        XCTAssertNil(updater.errorMessage)
        XCTAssertEqual(backend.checks, 1)
    }

    func testNoUpdateOrCanceledInstallationIsNotReportedAsFailure() {
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        for code in [SUError.noUpdateError.rawValue, SUError.installationCanceledError.rawValue,
                     SUError.installationAuthorizeLaterError.rawValue] {
            backend.cycleFinished?(NSError(domain: SUSparkleErrorDomain, code: Int(code)))
            XCTAssertNil(updater.errorMessage)
        }
        backend.cycleFinished?(NSError(domain: "another.domain", code: Int(SUError.noUpdateError.rawValue)))
        XCTAssertNotNil(updater.errorMessage)
        backend.cycleFinished?(nil)
        XCTAssertNil(updater.errorMessage)
    }

    func testBusyWorkBlocksManualAndScheduledChecksWithoutCancellingWork() {
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        var busy = true
        updater.observeActivity { busy }
        XCTAssertFalse(updater.canCheck)
        XCTAssertEqual(backend.mayCheck?(), false)
        updater.check()
        XCTAssertEqual(backend.checks, 0)
        XCTAssertTrue(busy)
        busy = false
        XCTAssertTrue(updater.canCheck)
        XCTAssertEqual(backend.mayCheck?(), true)
    }

    func testBusyInstallationWaitsForExplicitRetryAfterWorkFinishes() {
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        var busy = true
        var installed = 0
        updater.observeActivity { busy }
        XCTAssertEqual(backend.postponeRelaunch? { installed += 1 }, true)
        XCTAssertTrue(updater.hasDeferredInstallation)
        updater.resumeInstallation()
        XCTAssertEqual(installed, 0)
        busy = false
        XCTAssertEqual(installed, 0, "Finishing work must not silently relaunch the app")
        XCTAssertFalse(updater.canCheck)
        updater.resumeInstallation()
        updater.resumeInstallation()
        XCTAssertEqual(installed, 1, "A retained Sparkle handler is invoked at most once")
        XCTAssertFalse(updater.hasDeferredInstallation)
    }

    func testIdleInstallationNeedsNoDeferralAndFinishedCycleDropsStaleHandler() {
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        XCTAssertEqual(backend.postponeRelaunch? { XCTFail("Idle handler belongs to Sparkle") }, false)
        updater.observeActivity { true }
        XCTAssertEqual(backend.postponeRelaunch? { XCTFail("An aborted cycle must not resume later") }, true)
        backend.cycleFinished?(NSError(domain: "synthetic", code: 2))
        updater.observeActivity { false }
        updater.resumeInstallation()
        XCTAssertFalse(updater.hasDeferredInstallation)
    }

    func testTerminationGuardProtectsBusyWorkAndAllowsQuitAfterCancellation() {
        let delegate = UpdateApplicationDelegate()
        var busy = true
        var notices = 0
        delegate.isBusy = { busy }
        delegate.terminationBlocked = { notices += 1 }
        XCTAssertEqual(delegate.requestTermination(), .terminateCancel)
        XCTAssertEqual(notices, 1)
        XCTAssertTrue(busy, "The termination guard must never cancel work")
        busy = false // The user explicitly cancels the current job before retrying Quit.
        XCTAssertEqual(delegate.requestTermination(), .terminateNow)
        XCTAssertEqual(notices, 1)
    }

    func testRealModelRecordingCancellationReenablesUpdatesAndTermination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenNoType-UpdaterTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try SecureStore(directory: directory, backend: UpdaterMemorySecrets())
        var runtime = AppRuntime()
        runtime.readKey = { _ in "synthetic-offline-key" }
        runtime.frontmostApplication = { nil }
        runtime.capture = { _ in InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
                                            originalValue: nil, range: nil, selectedText: nil, context: nil) }
        runtime.accessibilityPermitted = { true }
        runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("No microphone permission requests"); return false }
        runtime.startRecording = { _ in }
        runtime.makeTemporaryAudioURL = { directory.appendingPathComponent("synthetic.wav") }
        runtime.hotkeyConflictWarnings = { _ in [] }
        let model = AppModel(store: store, runtime: runtime, startServices: false, preferences: Preferences())
        defer { model.cancel() }
        let backend = FakeUpdateBackend()
        let updater = makeUpdater(backend)
        let delegate = UpdateApplicationDelegate()
        let isBusy = { model.isBusy || model.historyReprocessing?.isProcessing == true }
        updater.observeActivity(isBusy)
        delegate.isBusy = isBusy
        await model.toggle(.dictation)
        XCTAssertTrue(model.isRecording)
        XCTAssertFalse(updater.canCheck)
        XCTAssertEqual(delegate.requestTermination(), .terminateCancel)
        model.cancel() // The explicit Quit menu performs this same action before terminating.
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(updater.canCheck)
        XCTAssertEqual(delegate.requestTermination(), .terminateNow)
        XCTAssertEqual(backend.checks, 0)
    }
}

private final class UpdaterMemorySecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[service + ":" + account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + ":" + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + ":" + account] = nil
    }
}

@MainActor
private final class FakeUpdateBackend: UpdateBackend {
    var state = UpdateState(canCheck: true)
    var stateChanged: (() -> Void)?
    var cycleFinished: ((Error?) -> Void)?
    var mayCheck: (() -> Bool)?
    var postponeRelaunch: ((@escaping () -> Void) -> Bool)?
    var startError: Error?
    var starts = 0
    var checks = 0
    var automaticWrites: [Bool] = []

    func start() throws { starts += 1; if let startError { throw startError } }
    func check() { checks += 1; state.canCheck = false; stateChanged?() }
    func setAutomaticallyChecks(_ enabled: Bool) {
        automaticWrites.append(enabled)
        state.automaticallyChecks = enabled
        stateChanged?()
    }
}
