import CryptoKit
import Foundation
import XCTest
@testable import OpenNoTypeCore

private final class JevLearningSecrets: SecretBackend, @unchecked Sendable {
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

final class JevLearningMemoryTests: XCTestCase {
    private var directory: URL!
    private var backend: JevLearningSecrets!
    private static let header = Data("OpenNoType.vault.1\n".utf8)
    private var vaultURL: URL { directory.appendingPathComponent("vault-v1.enc") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoTypeJevLearningTests-\(UUID().uuidString)")
        backend = JevLearningSecrets()
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func store(beforeCommit: (@Sendable () throws -> Void)? = nil) throws -> SecureStore {
        try SecureStore(directory: directory, backend: backend, beforeVaultCommit: beforeCommit)
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

    func testEncryptedRoundTripStoresOnlyIssueCountersAndPreservesOtherDomains() async throws {
        let subject = try store()
        let word = DictionaryEntry(spoken: "제브", written: "JEV")
        try await subject.saveDictionary([word])
        try await subject.recordJevRepairLesson(provider: .openRouter, model: "qwen/qwen3.7-flash", issues: [.numbers, .entities, .numbers])
        try await subject.recordJevRepairLesson(provider: .openRouter, model: "qwen/qwen3.7-flash", issues: [.numbers])
        let encrypted = try Data(contentsOf: vaultURL)
        for value in ["qwen/qwen3.7-flash", "numbers", "entities", "occurrences"] {
            XCTAssertNil(encrypted.range(of: Data(value.utf8)))
        }
        let reopened = try store()
        let snapshot = try await reopened.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.dictionary, [word])
        XCTAssertEqual(snapshot.jevLearningLessons.count, 1)
        XCTAssertEqual(snapshot.jevLearningLessons.first?.occurrences[.numbers], 2)
        XCTAssertEqual(snapshot.jevLearningLessons.first?.occurrences[.entities], 1)
        let issues = try await reopened.jevRepairLessons(provider: .openRouter, model: "qwen/qwen3.7-flash")
        XCTAssertEqual(issues, [.numbers, .entities])
        let json = try vaultJSON()
        let lesson = try XCTUnwrap((json["jevLearningLessons"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(lesson.keys), Set(["provider", "model", "occurrences"]))
        XCTAssertTrue(snapshot.history.isEmpty)
    }

    func testMissingFieldVaultMigrationKeepsExistingDataAndStartsWithNoLessons() async throws {
        let subject = try store()
        let word = DictionaryEntry(spoken: "오픈노타입", written: "OpenNoType")
        try await subject.saveDictionary([word])
        var json = try vaultJSON(); json.removeValue(forKey: "jevLearningLessons")
        try writeVaultJSON(json)
        let original = try Data(contentsOf: vaultURL)
        let reopened = try store()
        let before = try await reopened.snapshot(retentionDays: 30)
        XCTAssertEqual(before.dictionary, [word])
        XCTAssertTrue(before.jevLearningLessons.isEmpty)
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        try await reopened.recordJevRepairLesson(provider: .groq, model: "openai/gpt-oss-120b", issues: [.omissions])
        let after = try await reopened.snapshot(retentionDays: 30)
        XCTAssertEqual(after.dictionary, [word])
        XCTAssertEqual(after.jevLearningLessons.first?.issues, [.omissions])
    }

    func testProviderAndModelScopeNeverSharesLessonsAcrossContexts() async throws {
        let subject = try store()
        try await subject.recordJevRepairLesson(provider: .openRouter, model: "model-a", issues: [.numbers])
        try await subject.recordJevRepairLesson(provider: .groq, model: "model-a", issues: [.negation])
        try await subject.recordJevRepairLesson(provider: .openRouter, model: "model-b", issues: [.conditions])
        let routerA = try await subject.jevRepairLessons(provider: .openRouter, model: "model-a")
        let groqA = try await subject.jevRepairLessons(provider: .groq, model: "model-a")
        let routerB = try await subject.jevRepairLessons(provider: .openRouter, model: "model-b")
        let unknown = try await subject.jevRepairLessons(provider: .openAI, model: "model-a")
        XCTAssertEqual(routerA, [.numbers]); XCTAssertEqual(groqA, [.negation])
        XCTAssertEqual(routerB, [.conditions]); XCTAssertTrue(unknown.isEmpty)
    }

    func testExplicitClearRemovesAllLessonsWithoutDeletingDictionaryHistoryOrUsage() async throws {
        let subject = try store()
        let word = DictionaryEntry(spoken: "제브", written: "JEV")
        let history = HistoryEntry(mode: .dictation, originalText: "원문", resultText: "결과", provider: .groq)
        let usage = UsageRecord(jobID: UUID(), mode: .dictation,
                               event: ProviderUsage(provider: .groq, model: "model-a", stage: .textProcessing,
                                                    inputTokens: 10, outputTokens: 5))
        try await subject.saveDictionary([word]); _ = try await subject.appendHistory(history)
        try await subject.appendUsage(usage)
        try await subject.recordJevRepairLesson(provider: .openRouter, model: "model-a", issues: [.meaning])
        try await subject.clearJevRepairLessons()
        let snapshot = try await subject.snapshot(retentionDays: 30)
        XCTAssertTrue(snapshot.jevLearningLessons.isEmpty)
        XCTAssertEqual(snapshot.dictionary, [word]); XCTAssertEqual(snapshot.history.map(\.id), [history.id])
        XCTAssertEqual(snapshot.usageRecords, [usage])
        XCTAssertNil(try vaultJSON()["jevLearningLessons"])
    }

    func testInvalidModelIdentifiersDoNotChangeEncryptedVault() async throws {
        let subject = try store()
        try await subject.recordJevRepairLesson(provider: .openRouter, model: "model-a", issues: [.meaning])
        let original = try Data(contentsOf: vaultURL)
        let invalid = ["", " ", "private full sentence", "model\nprivate", "https://example.com/model", "<script>",
                       "sk-or-v1-synthetic-credential", "gsk_synthetic_credential", String(repeating: "a", count: 201)]
        for model in invalid {
            do { try await subject.recordJevRepairLesson(provider: .openRouter, model: model, issues: [.numbers]); XCTFail("Invalid model stored") }
            catch { XCTAssertEqual(error as? SecureStoreError, .invalidJevLearningContext) }
            XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        }
    }

    func testContextBoundEvictsOldestButARepeatedContextIsRefreshed() async throws {
        let subject = try store()
        for index in 0..<JevLearningMemory.maximumModelContexts {
            try await subject.recordJevRepairLesson(provider: .groq, model: "model-\(index)", issues: [.meaning])
        }
        try await subject.recordJevRepairLesson(provider: .groq, model: "model-0", issues: [.entities])
        try await subject.recordJevRepairLesson(provider: .groq, model: "model-new", issues: JevRepairIssue.allCases)
        let snapshot = try await subject.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.jevLearningLessons.count, JevLearningMemory.maximumModelContexts)
        XCTAssertEqual(snapshot.jevLearningLessons.first?.model, "model-new")
        XCTAssertEqual(Set(snapshot.jevLearningLessons.first?.issues ?? []), Set(JevRepairIssue.allCases))
        XCTAssertTrue(snapshot.jevLearningLessons.contains { $0.model == "model-0" })
        XCTAssertFalse(snapshot.jevLearningLessons.contains { $0.model == "model-1" })
    }

    func testIssueCountsSaturateAndOneRepairDoesNotDoubleCountAnIssue() {
        let initial = JevLearningLesson(provider: .groq, model: "model-a", occurrences: [.numbers: JevLearningMemory.maximumOccurrences, .entities: 1])
        let result = JevLearningMemory.recording([.numbers, .numbers, .entities, .entities], provider: .groq, model: "model-a", in: [initial])
        XCTAssertEqual(result.first?.occurrences[.numbers], JevLearningMemory.maximumOccurrences)
        XCTAssertEqual(result.first?.occurrences[.entities], 2)
        let overflow = JevLearningLesson(provider: .groq, model: "model-a", occurrences: [.numbers: Int.max])
        let bounded = JevLearningMemory.recording([.numbers], provider: .groq, model: "model-a", in: [overflow])
        XCTAssertEqual(bounded.first?.occurrences[.numbers], JevLearningMemory.maximumOccurrences)
    }

    func testConcurrentStoreWritersAccumulateWithoutOverwritingCounters() async throws {
        let first = try store(), second = try store()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                let writer = index.isMultiple(of: 2) ? first : second
                group.addTask { try await writer.recordJevRepairLesson(provider: .openRouter, model: "model-a", issues: [.numbers]) }
            }
            try await group.waitForAll()
        }
        let snapshot = try await first.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.jevLearningLessons.first?.occurrences[.numbers], 30)
    }

    func testCommitFailureKeepsPreviousLessonsRecoverable() async throws {
        let subject = try store()
        try await subject.recordJevRepairLesson(provider: .groq, model: "model-a", issues: [.numbers])
        let original = try Data(contentsOf: vaultURL)
        let failing = try store(beforeCommit: { throw CocoaError(.fileWriteOutOfSpace) })
        do { try await failing.recordJevRepairLesson(provider: .groq, model: "model-a", issues: [.entities]); XCTFail("Expected write failure") }
        catch {}
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
        let reopened = try store()
        let issues = try await reopened.jevRepairLessons(provider: .groq, model: "model-a")
        XCTAssertEqual(issues, [.numbers])
    }

    func testCancelledRepairDoesNotCommitLateLearning() async throws {
        let subject = try store()
        try await subject.recordJevRepairLesson(provider: .groq, model: "model-a", issues: [.numbers])
        let original = try Data(contentsOf: vaultURL)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await subject.recordJevRepairLesson(provider: .groq, model: "model-a", issues: [.entities])
        }
        do { try await task.value; XCTFail("Cancelled repair learned") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
    }

    func testInvalidAuthenticatedLearningCountersFailWithoutOverwritingStorage() async throws {
        let subject = try store()
        try await subject.recordJevRepairLesson(provider: .groq, model: "model-a", issues: [.numbers])
        var json = try vaultJSON()
        let invalid = JevLearningLesson(provider: .groq, model: "model-a", occurrences: [.numbers: -1])
        json["jevLearningLessons"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([invalid]))
        try writeVaultJSON(json)
        let original = try Data(contentsOf: vaultURL)
        XCTAssertThrowsError(try store()) { XCTAssertEqual($0 as? SecureStoreError, .corruptedStorage) }
        do { try await subject.clearJevRepairLessons(); XCTFail("Invalid authenticated vault overwritten") }
        catch { XCTAssertEqual(error as? SecureStoreError, .corruptedStorage) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), original)
    }
}
