import CryptoKit
import Foundation
import XCTest
@testable import OpenNoTypeCore

private final class MemorySecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private(set) var saveCount = 0

    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return items[service + ":" + account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        saveCount += 1
        items[service + ":" + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        items.removeValue(forKey: service + ":" + account)
    }
    func replaceKeys(with data: Data) {
        lock.lock(); defer { lock.unlock() }
        for key in items.keys { items[key] = data }
    }
    func removeKeys() { lock.lock(); defer { lock.unlock() }; items.removeAll() }
}

private final class StorageClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

final class StorageTests: XCTestCase {
    private var directory: URL!
    private var backend: MemorySecrets!
    private var clock: StorageClock!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("OpenNoTypeStorageTests-\(UUID().uuidString)", isDirectory: true)
        backend = MemorySecrets()
        clock = StorageClock()
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func store() throws -> SecureStore {
        let testClock = clock!
        return try SecureStore(directory: directory, backend: backend, now: { testClock.now() })
    }
    private var vaultURL: URL { directory.appendingPathComponent("vault-v1.enc") }
    private func historyEntry(age: TimeInterval = 0, text: String = "저장된 개인 결과") -> HistoryEntry {
        HistoryEntry(createdAt: clock.now().addingTimeInterval(-age), mode: .dictation, originalText: "개인 원문", resultText: text, provider: .openAI)
    }
    private func failedRecording(age: TimeInterval = 0) -> FailedRecording {
        FailedRecording(createdAt: clock.now().addingTimeInterval(-age), mode: .translation, provider: .anthropic, targetLanguage: "한국어")
    }

    func testEncryptedRoundTripContainsNoPlaintextAndPreservesAllDomains() async throws {
        let subject = try store()
        let entry = historyEntry()
        let word = DictionaryEntry(spoken: "오픈에이아이", written: "OpenAI")
        let failure = failedRecording()
        let audio = Data("private raw audio fingerprint".utf8)
        let profile = Data("private speaker embedding".utf8)
        try await subject.saveHistory([entry])
        try await subject.saveDictionary([word])
        try await subject.saveFailure(failure, audio: audio)
        try await subject.saveSpeakerProfile(profile)
        let disk = try Data(contentsOf: vaultURL)
        for value in [entry.originalText, entry.resultText, word.spoken, word.written, String(decoding: audio, as: UTF8.self), String(decoding: profile, as: UTF8.self)] {
            XCTAssertNil(disk.range(of: Data(value.utf8)))
        }
        let reopened = try store()
        let history = try await reopened.history()
        let dictionary = try await reopened.dictionary()
        let failures = try await reopened.failures()
        let recoveredAudio = try await reopened.failureAudio(id: failure.id)
        let recoveredProfile = try await reopened.speakerProfile()
        XCTAssertEqual(history.first?.id, entry.id)
        XCTAssertEqual(dictionary, [word])
        XCTAssertEqual(failures.first?.id, failure.id)
        XCTAssertEqual(recoveredAudio, audio)
        XCTAssertEqual(recoveredProfile, profile)
        XCTAssertEqual(backend.saveCount, 1)
    }

    func testMissingKeyNeverCreatesReplacementOrModifiesVault() async throws {
        let subject = try store()
        try await subject.saveHistory([historyEntry()])
        let original = try Data(contentsOf: vaultURL)
        let emptyBackend = MemorySecrets()
        XCTAssertThrowsError(try SecureStore(directory: directory, backend: emptyBackend)) { error in
            XCTAssertEqual(error as? SecureStoreError, .missingEncryptionKey)
        }
        XCTAssertEqual(emptyBackend.saveCount, 0)
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
    }

    func testWrongKeyCannotInitializeOrOverwriteExistingVault() async throws {
        let subject = try store()
        try await subject.saveHistory([historyEntry()])
        let original = try Data(contentsOf: vaultURL)
        backend.replaceKeys(with: Data(repeating: 0x57, count: 32))
        XCTAssertThrowsError(try store()) { error in XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
    }

    func testKeyRemovalDuringSessionStopsWritesWithoutOverwriting() async throws {
        let subject = try store()
        try await subject.saveHistory([historyEntry()])
        let original = try Data(contentsOf: vaultURL)
        backend.removeKeys()
        do { try await subject.saveDictionary([]); XCTFail("Missing key was ignored") }
        catch { XCTAssertEqual(error as? SecureStoreError, .missingEncryptionKey) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        XCTAssertEqual(backend.saveCount, 1)
    }

    func testInvalidLengthKeyIsNotSilentlyReplaced() async throws {
        _ = try store()
        backend.replaceKeys(with: Data([1, 2, 3]))
        XCTAssertThrowsError(try store()) { error in XCTAssertEqual(error as? SecureStoreError, .invalidEncryptionKey) }
        XCTAssertEqual(backend.saveCount, 1)
    }

    func testTamperedHeaderCiphertextAndTagFailClosed() async throws {
        let subject = try store()
        try await subject.saveHistory([historyEntry()])
        let original = try Data(contentsOf: vaultURL)
        for offset in [0, original.count / 2, original.count - 1] {
            var corrupted = original
            corrupted[offset] ^= 0x01
            try corrupted.write(to: vaultURL)
            XCTAssertThrowsError(try store()) { error in XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
            do { try await subject.saveDictionary([]); XCTFail("Corrupted data was overwritten") }
            catch { XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
            do { try await subject.deleteAllHistory(); XCTFail("Corrupted data was deleted") }
            catch { XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
            XCTAssertEqual(try Data(contentsOf: vaultURL), corrupted)
        }
    }

    func testTruncatedVaultFailsClosed() async throws {
        let subject = try store()
        try await subject.saveHistory([historyEntry()])
        let truncated = try Data(contentsOf: vaultURL).prefix(24)
        try truncated.write(to: vaultURL)
        XCTAssertThrowsError(try store()) { error in XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), truncated)
    }

    func testDefaultHistoryRetentionAndZeroDisableArePersisted() async throws {
        let subject = try store()
        let recent = historyEntry(age: 29 * 86_400)
        try await subject.saveHistory([historyEntry(age: 30 * 86_400), recent])
        var results = try await subject.history()
        XCTAssertEqual(results.map(\.id), [recent.id])
        _ = try await subject.history(retentionDays: 0)
        try await subject.saveHistory([historyEntry()])
        let reopened = try store()
        results = try await reopened.history(retentionDays: 0)
        XCTAssertTrue(results.isEmpty)
    }

    func testLongerRetentionSurvivesStartup() async throws {
        let subject = try store()
        _ = try await subject.history(retentionDays: 90)
        let older = historyEntry(age: 60 * 86_400)
        try await subject.saveHistory([older])
        let reopened = try store()
        let result = try await reopened.history(retentionDays: 90)
        XCTAssertEqual(result.first?.id, older.id)
        do { _ = try await reopened.history(retentionDays: -2); XCTFail("Invalid negative retention accepted") }
        catch { XCTAssertEqual(error as? SecureStoreError, .invalidRetention) }
    }

    func testExpiredFailureIsRemovedAtStartup() async throws {
        let subject = try store()
        let failure = failedRecording()
        try await subject.saveFailure(failure, audio: Data([1, 2, 3]))
        let previous = try Data(contentsOf: vaultURL)
        clock.advance(86_400)
        let reopened = try store()
        let remaining = try await reopened.failures()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertNotEqual(try Data(contentsOf: vaultURL), previous)
        do { _ = try await reopened.failureAudio(id: failure.id); XCTFail("Expired audio returned") }
        catch { XCTAssertEqual(error as? SecureStoreError, .recordingNotFound) }
    }

    func testExpiredAudioLookupPersistsCleanupDuringUse() async throws {
        let subject = try store()
        let failure = failedRecording()
        try await subject.saveFailure(failure, audio: Data([8, 9]))
        let before = try Data(contentsOf: vaultURL)
        clock.advance(86_401)
        do { _ = try await subject.failureAudio(id: failure.id); XCTFail("Expired audio returned") }
        catch { XCTAssertEqual(error as? SecureStoreError, .recordingNotFound) }
        XCTAssertNotEqual(try Data(contentsOf: vaultURL), before)
        let failures = try await subject.failures()
        XCTAssertTrue(failures.isEmpty)
    }

    func testInterruptedStagingFileIsValidatedAndRemovedAtStartup() async throws {
        let subject = try store()
        try await subject.saveFailure(failedRecording(), audio: Data([1, 7, 4]))
        let staged = directory.appendingPathComponent(".vault-interrupted.tmp")
        try FileManager.default.copyItem(at: vaultURL, to: staged)
        clock.advance(86_400)
        let reopened = try store()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        let remaining = try await reopened.failures()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCorruptStagingFileBlocksMutationAndRemainsRecoverable() async throws {
        let subject = try store()
        try await subject.saveHistory([historyEntry()])
        let original = try Data(contentsOf: vaultURL)
        let staged = directory.appendingPathComponent(".vault-interrupted.tmp")
        let corrupt = Data([0, 1, 2])
        try corrupt.write(to: staged)
        XCTAssertThrowsError(try store()) { error in XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        XCTAssertEqual(try Data(contentsOf: staged), corrupt)
    }

    func testCallerCannotExtendFailureBeyond24Hours() async throws {
        let subject = try store()
        var failure = failedRecording(age: 86_000)
        failure.expiresAt = clock.now().addingTimeInterval(10 * 86_400)
        try await subject.saveFailure(failure, audio: Data([1]))
        let saved = try await subject.failures()
        XCTAssertEqual(saved.first?.expiresAt, failure.createdAt.addingTimeInterval(86_400))
        clock.advance(401)
        let remaining = try await subject.failures()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testAlreadyExpiredFailureIsRejected() async throws {
        let subject = try store()
        do { try await subject.saveFailure(failedRecording(age: 86_400), audio: Data([1])); XCTFail("Expired audio stored") }
        catch { XCTAssertEqual(error as? SecureStoreError, .recordingExpired) }
        let results = try await subject.failures()
        XCTAssertTrue(results.isEmpty)
    }

    func testDeletionIsScopedAndReopenable() async throws {
        let subject = try store()
        let word = DictionaryEntry(spoken: "노타입", written: "NoType")
        let failure = failedRecording()
        try await subject.saveHistory([historyEntry()])
        try await subject.saveDictionary([word])
        try await subject.saveFailure(failure, audio: Data([7]))
        try await subject.saveSpeakerProfile(Data([9]))
        try await subject.deleteAllHistory()
        try await subject.deleteFailure(id: failure.id)
        try await subject.deleteSpeakerProfile()
        let reopened = try store()
        let history = try await reopened.history()
        let failures = try await reopened.failures()
        let dictionary = try await reopened.dictionary()
        let profile = try await reopened.speakerProfile()
        XCTAssertTrue(history.isEmpty)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertNil(profile)
        XCTAssertEqual(dictionary, [word])
    }

    func testFilesArePrivateAndReadDoesNotRewriteCiphertext() async throws {
        let subject = try store()
        try await subject.saveHistory([historyEntry()])
        let original = try Data(contentsOf: vaultURL)
        _ = try await subject.history()
        _ = try await subject.dictionary()
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        let dirMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: vaultURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(dirMode?.intValue, 0o700)
        XCTAssertEqual(fileMode?.intValue, 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testSeparateActorsReloadVaultBeforeChangingAnotherDomain() async throws {
        let first = try store()
        let second = try store()
        let entry = historyEntry()
        let word = DictionaryEntry(spoken: "테스트", written: "Test")
        try await first.saveHistory([entry])
        try await second.saveDictionary([word])
        let history = try await second.history()
        let dictionary = try await first.dictionary()
        XCTAssertEqual(history.first?.id, entry.id)
        XCTAssertEqual(dictionary, [word])
    }

    func testSymlinkVaultCannotBeReadOrOverwritten() async throws {
        let subject = try store()
        let outside = directory.appendingPathComponent("outside.txt")
        let bytes = Data("unrelated user data".utf8)
        try bytes.write(to: outside)
        try FileManager.default.createSymbolicLink(at: vaultURL, withDestinationURL: outside)
        do { try await subject.saveHistory([historyEntry()]); XCTFail("Symlink was followed") }
        catch { XCTAssertEqual(error as? SecureStoreError, .unsafeStoragePath) }
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
    }

    func testProviderSecretsRemainIsolatedWithoutRealKeychainAccess() throws {
        try KeychainSecrets.save("openai-test-key", for: .openAI, backend: backend)
        try KeychainSecrets.save("router-test-key", for: .openRouter, backend: backend)
        XCTAssertEqual(try KeychainSecrets.read(for: .openAI, backend: backend), "openai-test-key")
        XCTAssertEqual(try KeychainSecrets.read(for: .openRouter, backend: backend), "router-test-key")
        XCTAssertNil(try KeychainSecrets.read(for: .anthropic, backend: backend))
        try KeychainSecrets.delete(for: .openAI, backend: backend)
        XCTAssertNil(try KeychainSecrets.read(for: .openAI, backend: backend))
        XCTAssertEqual(try KeychainSecrets.read(for: .openRouter, backend: backend), "router-test-key")
        XCTAssertThrowsError(try KeychainSecrets.save(" \n", for: .anthropic, backend: backend))
    }

    func testLearningCandidatesAreEncryptedExpireAndDeleteWithHistory() async throws {
        let subject = try store()
        let candidate = LearningCandidate(originalText: "검토 전 개인 문장", editedText: "검토 후 개인 문장", createdAt: clock.now())
        try await subject.saveLearningCandidates([candidate])
        XCTAssertNil(try Data(contentsOf: vaultURL).range(of: Data(candidate.originalText.utf8)))
        let reopened = try store()
        let results = try await reopened.learningCandidates()
        XCTAssertEqual(results, [candidate])
        clock.advance(30 * 86_400)
        let expired = try await reopened.learningCandidates()
        XCTAssertTrue(expired.isEmpty)
        let current = LearningCandidate(originalText: "개인 원문", editedText: "개인 교정", createdAt: clock.now())
        try await reopened.saveLearningCandidates([current])
        try await reopened.deleteAllHistory()
        let deleted = try await reopened.learningCandidates()
        XCTAssertTrue(deleted.isEmpty)
    }

    func testForeverRetentionPreservesOldHistoryAndCandidatesButNotExpiredAudio() async throws {
        let subject = try store()
        _ = try await subject.history(retentionDays: -1)
        let oldEntry = historyEntry(age: 365 * 86_400)
        let candidate = LearningCandidate(originalText: "예전 원문", editedText: "예전 교정", createdAt: oldEntry.createdAt)
        try await subject.saveHistory([oldEntry])
        try await subject.saveLearningCandidates([candidate])
        try await subject.saveFailure(failedRecording(), audio: Data([9]))
        clock.advance(366 * 86_400)
        let reopened = try store()
        let kept = try await reopened.history(retentionDays: -1)
        let candidates = try await reopened.learningCandidates()
        let expiredAudio = try await reopened.failures()
        XCTAssertEqual(kept.first?.id, oldEntry.id)
        XCTAssertEqual(candidates, [candidate])
        XCTAssertTrue(expiredAudio.isEmpty)
        _ = try await reopened.history(retentionDays: 0)
        let cleared = try await reopened.learningCandidates()
        XCTAssertTrue(cleared.isEmpty)
    }
}
