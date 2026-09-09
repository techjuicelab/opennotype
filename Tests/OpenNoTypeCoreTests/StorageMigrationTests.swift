import CryptoKit
import Foundation
import XCTest
@testable import OpenNoTypeCore

private final class MigrationSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[service + account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: service + account)
    }
    var key: SymmetricKey { lock.lock(); defer { lock.unlock() }; return SymmetricKey(data: values.values.first!) }
}

private final class MigrationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: Double) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

final class StorageMigrationTests: XCTestCase {
    private var directory: URL!
    private var backend: MigrationSecrets!
    private var clock: MigrationClock!
    private static let header = Data("OpenNoType.vault.1\n".utf8)
    private var vaultURL: URL { directory.appendingPathComponent("vault-v1.enc") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("OpenNoTypeMigrationTests-\(UUID().uuidString)")
        backend = MigrationSecrets(); clock = MigrationClock()
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func store(limit: Int = SecureStore.maximumFailedRecordingBytes,
                       beforeCommit: (@Sendable () throws -> Void)? = nil) throws -> SecureStore {
        let clock = clock!
        return try SecureStore(directory: directory, backend: backend, now: { clock.now() }, audioLimitBytes: limit, beforeVaultCommit: beforeCommit)
    }
    private func item(age: Double = 0) -> FailedRecording {
        .init(createdAt: clock.now().addingTimeInterval(-age), mode: .dictation, provider: .openAI, targetLanguage: "Korean")
    }
    private func history(_ text: String) -> HistoryEntry {
        .init(createdAt: clock.now(), mode: .dictation, originalText: text, resultText: text, provider: .openAI)
    }
    private func blobs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("audio-") && $0.pathExtension == "enc" }
    }
    private func vaultJSON() throws -> [String: Any] {
        let encrypted = try Data(contentsOf: vaultURL)
        let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(Self.header.count))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: AES.GCM.open(box, using: backend.key, authenticating: Self.header)) as? [String: Any])
    }
    private func writeVaultJSON(_ json: [String: Any]) throws {
        let plaintext = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let encrypted = try Self.header + AES.GCM.seal(plaintext, using: backend.key, authenticating: Self.header).combined!
        try encrypted.write(to: vaultURL)
    }
    private func installLegacy(_ failures: [(FailedRecording, Data)], history: [HistoryEntry] = [], dictionary: [DictionaryEntry] = []) throws -> Data {
        _ = try store() // Creates a mock key, never accesses the real Keychain.
        struct LegacyFailure: Encodable { let item: FailedRecording; let audio: Data }
        struct LegacyVault: Encodable {
            let version = 1
            let retentionDays = 30
            let history: [HistoryEntry]
            let dictionary: [DictionaryEntry]
            let failures: [LegacyFailure]
        }
        let plaintext = try JSONEncoder().encode(LegacyVault(history: history, dictionary: dictionary, failures: failures.map { .init(item: $0.0, audio: $0.1) }))
        let encrypted = try Self.header + AES.GCM.seal(plaintext, using: backend.key, authenticating: Self.header).combined!
        try encrypted.write(to: vaultURL)
        return encrypted
    }

    func testLegacyMigrationPreservesLiveAudioAndAllMetadataAndPrunesExpiredAudio() async throws {
        let live = item(), expired = item(age: 86_400)
        let audio = Data(repeating: 53, count: 250_000)
        let entry = history("기존 기록"), word = DictionaryEntry(spoken: "테스트", written: "Test")
        _ = try installLegacy([(live, audio), (expired, Data([7]))], history: [entry], dictionary: [word])
        let subject = try store()
        let snapshot = try await subject.snapshot(retentionDays: 30)
        let recovered = try await subject.failureAudio(id: live.id)
        XCTAssertEqual(snapshot.history.first?.id, entry.id)
        XCTAssertEqual(snapshot.dictionary, [word])
        XCTAssertEqual(snapshot.failedRecordings.map(\.id), [live.id])
        XCTAssertEqual(recovered, audio)
        XCTAssertEqual(try blobs().count, 1)
        XCTAssertLessThan(try Data(contentsOf: vaultURL).count, 5_000)
        let json = try vaultJSON()
        XCTAssertEqual(json["version"] as? Int, 2)
        let metadata = try XCTUnwrap((json["failures"] as? [[String: Any]])?.first)
        XCTAssertNil(metadata["audio"])
        XCTAssertNotNil(metadata["blob"])
        let reopened = try store()
        let again = try await reopened.failureAudio(id: live.id)
        XCTAssertEqual(again, audio)
    }

    func testMigrationCommitFailureLeavesOriginalVaultRecoverableAndRetrySucceeds() async throws {
        let recording = item(), audio = Data([1, 8, 3, 9])
        let original = try installLegacy([(recording, audio)])
        XCTAssertThrowsError(try store(beforeCommit: { throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        XCTAssertEqual(try blobs().count, 1) // Recoverable orphan, original still authoritative.
        XCTAssertThrowsError(try store(beforeCommit: { throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try blobs().count, 1) // Repeated interruption does not multiply audio copies.
        let reopened = try store()
        let recovered = try await reopened.failureAudio(id: recording.id)
        XCTAssertEqual(recovered, audio)
        XCTAssertEqual(try blobs().count, 1) // Completed blob is validated and reused on retry.
        clock.advance(86_401)
        _ = try await reopened.snapshot(retentionDays: 30)
        XCTAssertTrue(try blobs().isEmpty)
    }

    func testMigrationPreservesLegacyAudioEvenAboveNewQuota() async throws {
        let recording = item(), audio = Data(repeating: 8, count: 20_000)
        _ = try installLegacy([(recording, audio)])
        let subject = try store(limit: 10_000)
        let recovered = try await subject.failureAudio(id: recording.id)
        XCTAssertEqual(recovered, audio)
        do { try await subject.saveFailure(item(), audio: Data([1])); XCTFail("Quota not enforced") }
        catch { XCTAssertEqual(error as? SecureStoreError, .recordingStorageFull) }
    }

    func testBlobTamperingDoesNotMakeMetadataSnapshotsReadAudio() async throws {
        let subject = try store(), recording = item()
        try await subject.saveFailure(recording, audio: Data(repeating: 123, count: 500_000))
        let blob = try XCTUnwrap(blobs().first)
        var encrypted = try Data(contentsOf: blob)
        XCTAssertNil(encrypted.range(of: Data(repeating: 123, count: 64)))
        encrypted[encrypted.count - 1] ^= 1
        try encrypted.write(to: blob)
        let snapshot = try await subject.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.failedRecordings.map(\.id), [recording.id])
        XCTAssertLessThan(try Data(contentsOf: vaultURL).count, 5_000)
        do { _ = try await subject.failureAudio(id: recording.id); XCTFail("Tampered audio accepted") }
        catch { XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
    }

    func testSwappedBlobsCannotReturnAnotherRecordingsAudio() async throws {
        let subject = try store(), first = item(), second = item()
        try await subject.saveFailure(first, audio: Data([1, 2, 3]))
        let firstURL = try XCTUnwrap(blobs().first)
        try await subject.saveFailure(second, audio: Data([7, 8, 9]))
        let secondURL = try XCTUnwrap(blobs().first { $0 != firstURL })
        let firstBytes = try Data(contentsOf: firstURL)
        try Data(contentsOf: secondURL).write(to: firstURL)
        try firstBytes.write(to: secondURL)
        for recording in [first, second] {
            do { _ = try await subject.failureAudio(id: recording.id); XCTFail("Swapped audio accepted") }
            catch { XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
        }
    }

    func testFailedReplacementKeepsOriginalReferenceAndAudio() async throws {
        let subject = try store(), recording = item(), original = Data([1, 2])
        try await subject.saveFailure(recording, audio: original)
        let before = try Data(contentsOf: vaultURL)
        let failing = try store(beforeCommit: { throw CocoaError(.fileWriteOutOfSpace) })
        do { try await failing.saveFailure(recording, audio: Data([3, 4])); XCTFail("Commit should fail") } catch {}
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        let recovered = try await subject.failureAudio(id: recording.id)
        XCTAssertEqual(recovered, original)
        XCTAssertEqual(try blobs().count, 2)
        try await subject.saveFailure(recording, audio: Data([5, 6]))
        let replacement = try await subject.failureAudio(id: recording.id)
        XCTAssertEqual(replacement, Data([5, 6]))
        XCTAssertEqual(try blobs().count, 2) // Original deleted, uncommitted orphan remains until expiry.
    }

    func testDeleteAndExpiryRemoveOnlyTheirReferencedBlobs() async throws {
        let subject = try store(), first = item(), second = item()
        try await subject.saveFailure(first, audio: Data([1]))
        try await subject.saveFailure(second, audio: Data([2]))
        try await subject.deleteFailure(id: first.id)
        XCTAssertEqual(try blobs().count, 1)
        let remaining = try await subject.failureAudio(id: second.id)
        XCTAssertEqual(remaining, Data([2]))
        clock.advance(86_401)
        _ = try await subject.snapshot(retentionDays: 30)
        XCTAssertTrue(try blobs().isEmpty)
    }

    func testRestartFinishesDeletionCommittedBeforeProcessStopped() async throws {
        let subject = try store(), recording = item()
        try await subject.saveFailure(recording, audio: Data([1, 6, 3]))
        var json = try vaultJSON()
        let failure = try XCTUnwrap((json["failures"] as? [[String: Any]])?.first)
        let reference = try XCTUnwrap(failure["blob"])
        // Simulate the durable checkpoint immediately after metadata rename but before unlink.
        json["failures"] = []
        json["pendingAudioDeletions"] = [reference]
        try writeVaultJSON(json)
        XCTAssertEqual(try blobs().count, 1)
        let reopened = try store()
        let snapshot = try await reopened.snapshot(retentionDays: 30)
        XCTAssertTrue(snapshot.failedRecordings.isEmpty)
        XCTAssertTrue(try blobs().isEmpty)
        XCTAssertNil(try vaultJSON()["pendingAudioDeletions"])
    }

    func testQuotaFailurePreservesExistingAudioAndExplicitDeleteMakesRoom() async throws {
        let subject = try store(limit: 14_000), first = item(), second = item()
        try await subject.saveFailure(first, audio: Data(repeating: 1, count: 8_000))
        do { try await subject.saveFailure(second, audio: Data(repeating: 2, count: 8_000)); XCTFail("Quota not enforced") }
        catch { XCTAssertEqual(error as? SecureStoreError, .recordingStorageFull) }
        let remaining = try await subject.failureAudio(id: first.id)
        XCTAssertEqual(remaining.count, 8_000)
        XCTAssertEqual(try blobs().count, 1)
        try await subject.deleteFailure(id: first.id)
        try await subject.saveFailure(second, audio: Data(repeating: 2, count: 8_000))
        let snapshot = try await subject.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.failedRecordings.map(\.id), [second.id])
    }

    func testBlobSymlinkNeverReadsOrChangesOutsideFile() async throws {
        let subject = try store(), recording = item()
        try await subject.saveFailure(recording, audio: Data([1]))
        let blob = try XCTUnwrap(blobs().first)
        let outside = directory.appendingPathComponent("unrelated.txt"), bytes = Data("unrelated data".utf8)
        try bytes.write(to: outside)
        try FileManager.default.removeItem(at: blob)
        try FileManager.default.createSymbolicLink(at: blob, withDestinationURL: outside)
        do { _ = try await subject.failureAudio(id: recording.id); XCTFail("Symlink followed") }
        catch { XCTAssertEqual(error as? SecureStoreError, .unsafeStoragePath) }
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
    }

    func testInterruptedFirstVaultIsPreservedAndNeverReplacedByEmptyStore() throws {
        _ = try store()
        let staging = directory.appendingPathComponent(".vault-first.tmp"), bytes = Data([2, 5])
        try bytes.write(to: staging)
        XCTAssertThrowsError(try store()) { XCTAssertEqual($0 as? SecureStoreError, .corruptedStorage) }
        XCTAssertEqual(try Data(contentsOf: staging), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.path))
    }

    func testUnreferencedCorruptBlobIsQuarantinedAndExpiresWithoutBlockingHistory() async throws {
        let subject = try store(), entry = history("정상 기록")
        _ = try await subject.appendHistory(entry)
        let original = try Data(contentsOf: vaultURL)
        let orphan = directory.appendingPathComponent("audio-\(UUID().uuidString).enc")
        let fragment = Data([0, 1, 2])
        try fragment.write(to: orphan)
        let snapshot = try await subject.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.history.first?.id, entry.id)
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        XCTAssertTrue(try blobs().isEmpty)
        let recovery = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".recovery-") })
        XCTAssertEqual(try Data(contentsOf: recovery), fragment)
        clock.advance(86_401)
        _ = try await subject.snapshot(retentionDays: 30)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
    }

    func testAtomicHistoryAndDictionaryMutationsPreserveConcurrentSameDomainChanges() async throws {
        let first = try store(), second = try store()
        let entries = (0..<30).map { history("entry-\($0)") }
        let words = (0..<30).map { DictionaryEntry(spoken: "word-\($0)", written: "Word-\($0)") }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in entries.indices {
                let target = index.isMultiple(of: 2) ? first : second
                group.addTask { _ = try await target.appendHistory(entries[index]) }
                group.addTask { _ = try await target.upsertDictionaryEntries([words[index]]) }
            }
            try await group.waitForAll()
        }
        let snapshot = try await first.snapshot(retentionDays: 30)
        XCTAssertEqual(Set(snapshot.history.map(\.id)), Set(entries.map(\.id)))
        XCTAssertEqual(Set(snapshot.dictionary.map(\.id)), Set(words.map(\.id)))
        async let deleteOld = first.deleteHistory(id: entries[0].id)
        async let appendNew = second.appendHistory(history("another"))
        _ = try await (deleteOld, appendNew)
        let after = try await first.history()
        XCTAssertEqual(after.count, 30)
        XCTAssertFalse(after.contains { $0.id == entries[0].id })
    }

    func testDictionaryMutationPreservesIdentityNormalizesAndNeverResurrectsDeletedEntry() async throws {
        let first = try store(), second = try store()
        let word = DictionaryEntry(spoken: " original ", written: " Value ", createdAt: clock.now(), learned: true)
        let inserted = try await first.upsertDictionaryEntries([word])
        XCTAssertEqual(inserted.first?.id, word.id)
        XCTAssertEqual(inserted.first?.createdAt, word.createdAt)
        XCTAssertEqual(inserted.first?.spoken, "original")
        let updated = try await second.updateDictionaryEntry(id: word.id, spoken: " ORIGINAL ", written: " Changed ")
        XCTAssertEqual(updated.first?.written, "Changed")
        XCTAssertEqual(updated.first?.learned, true)
        _ = try await first.deleteDictionaryEntry(id: word.id)
        let staleEdit = try await second.updateDictionaryEntry(id: word.id, spoken: "original", written: "Stale")
        XCTAssertTrue(staleEdit.isEmpty)
    }

    func testUndoDictionaryChangeRespectsLaterManualEditsAndReplacementEntries() async throws {
        let subject = try store()
        let prior = DictionaryEntry(spoken: "term", written: "Prior")
        let applied = DictionaryEntry(spoken: "term", written: "Learned", learned: true)
        _ = try await subject.upsertDictionaryEntries([prior])
        _ = try await subject.upsertDictionaryEntries([applied])
        let restored = try await subject.undoDictionaryChange(applied: applied, previous: prior)
        XCTAssertTrue(restored)
        let dictionary = try await subject.dictionary()
        XCTAssertEqual(dictionary, [prior])
        _ = try await subject.upsertDictionaryEntries([applied])
        _ = try await subject.updateDictionaryEntry(id: applied.id, spoken: "term", written: "Manual")
        let rejected = try await subject.undoDictionaryChange(applied: applied, previous: prior)
        XCTAssertFalse(rejected)
        let manual = try await subject.dictionary()
        XCTAssertEqual(manual.first?.written, "Manual")
        _ = try await subject.upsertDictionaryEntries([DictionaryEntry(spoken: "term", written: "Replacement")])
        let rejectedReplacement = try await subject.undoDictionaryChange(applied: applied, previous: prior)
        XCTAssertFalse(rejectedReplacement)
    }

    func testLearnedChangeReturnsActualPriorRevisionForSafeUndo() async throws {
        let first = try store(), second = try store()
        let original = DictionaryEntry(spoken: "term", written: "Original")
        let manual = DictionaryEntry(spoken: "term", written: "Latest manual")
        _ = try await first.upsertDictionaryEntries([original])
        _ = try await second.upsertDictionaryEntries([manual])
        let entry = DictionaryEntry(spoken: " term ", written: " Learned ", learned: true)
        let change = try await first.applyLearnedDictionaryEntry(entry)
        XCTAssertEqual(change.previous, manual)
        XCTAssertEqual(change.applied.id, entry.id)
        XCTAssertEqual(change.applied.spoken, "term")
        XCTAssertEqual(change.applied.written, "Learned")
        let restored = try await second.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertTrue(restored)
        let dictionary = try await first.dictionary()
        XCTAssertEqual(dictionary, [manual])
    }

    func testCancelledLearnedChangeDoesNotModifyVault() async throws {
        let subject = try store()
        let original = DictionaryEntry(spoken: "term", written: "Original")
        _ = try await subject.upsertDictionaryEntries([original])
        let before = try Data(contentsOf: vaultURL)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await subject.applyLearnedDictionaryEntry(.init(spoken: "term", written: "Learned", learned: true))
        }
        do { _ = try await task.value; XCTFail("Cancelled change committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
    }
}
