import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class VoiceProfileDeletionTests: KoreanPresentationTestCase {
    func testBusyRecordingAndProcessingPreserveEnrolledVoice() async throws {
        for phase in [AppModel.Phase.starting, .recording, .enrolling, .processing] {
            let fixture = try await makeFixture()
            fixture.model.phase = phase

            await fixture.model.deleteVoice()

            let stored = try await fixture.store.speakerProfile()
            XCTAssertEqual(stored, fixture.profile, "A busy operation must retain its enrolled voice")
            XCTAssertTrue(fixture.model.hasSpeakerProfile)
            XCTAssertTrue(fixture.model.preferences.speakerFilterEnabled)
            XCTAssertTrue(fixture.model.phase == phase)
            XCTAssertNil(fixture.model.error)
        }
    }

    func testIdleDeletionRemovesStoredVoiceAndDisablesFilter() async throws {
        let fixture = try await makeFixture()

        await fixture.model.deleteVoice()

        let stored = try await fixture.store.speakerProfile()
        XCTAssertNil(stored)
        XCTAssertFalse(fixture.model.hasSpeakerProfile)
        XCTAssertFalse(fixture.model.preferences.speakerFilterEnabled)
        XCTAssertTrue(fixture.model.phase == .idle)
        XCTAssertNil(fixture.model.error)
    }

    func testFailedDeletionPreservesStoredVoiceAndVisibleFilterState() async throws {
        let commitFailure = VoiceProfileCommitFailure()
        let fixture = try await makeFixture(commitFailure: commitFailure)
        commitFailure.enable()

        await fixture.model.deleteVoice()

        let stored = try await fixture.store.speakerProfile()
        XCTAssertEqual(stored, fixture.profile)
        XCTAssertTrue(fixture.model.hasSpeakerProfile)
        XCTAssertTrue(fixture.model.preferences.speakerFilterEnabled)
        XCTAssertNotNil(fixture.model.error)
    }

    private struct Fixture {
        let store: SecureStore
        let model: AppModel
        let profile: Data
    }

    private func makeFixture(commitFailure: VoiceProfileCommitFailure = .init()) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-VoiceDeletion-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try SecureStore(directory: root, backend: VoiceProfileMemorySecrets(),
                                    beforeVaultCommit: { try commitFailure.check() })
        let profile = try JSONEncoder().encode(SpeakerVoiceProfile(name: "Synthetic voice", embedding: [1, 0],
                                                                   modelIdentifier: "synthetic-offline-model"))
        try await store.saveSpeakerProfile(profile)
        var runtime = AppRuntime()
        runtime.readKey = { _ in nil }
        runtime.readStartupKey = { _ in XCTFail("Voice deletion must not read the real Keychain"); return nil }
        runtime.accessibilityPermitted = { true }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("Voice deletion must not request microphone access"); return false }
        runtime.startRecording = { _ in XCTFail("Voice deletion must not record audio") }
        var preferences = Preferences.koreanForTesting
        preferences.speakerFilterEnabled = true
        let model = AppModel(store: store, runtime: runtime, startServices: false, preferences: preferences)
        model.hasSpeakerProfile = true
        return Fixture(store: store, model: model, profile: profile)
    }
}

private final class VoiceProfileCommitFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    func enable() { lock.lock(); defer { lock.unlock() }; enabled = true }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if enabled { throw CocoaError(.fileWriteOutOfSpace) }
    }
}

private final class VoiceProfileMemorySecrets: SecretBackend, @unchecked Sendable {
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
