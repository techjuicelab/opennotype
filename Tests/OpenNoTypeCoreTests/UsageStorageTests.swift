import CryptoKit
import Foundation
import XCTest
@testable import OpenNoTypeCore

private final class UsageMemorySecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return items[service + ":" + account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; items[service + ":" + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; items.removeValue(forKey: service + ":" + account)
    }
}

final class UsageStorageTests: XCTestCase {
    private var directory: URL!
    private var secrets: UsageMemorySecrets!
    private let current = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoTypeUsageTests-\(UUID().uuidString)", isDirectory: true)
        secrets = UsageMemorySecrets()
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func store() throws -> SecureStore {
        let now = current
        return try SecureStore(directory: directory, backend: secrets, now: { now })
    }
    private func record(at date: Date? = nil) -> UsageRecord {
        UsageRecord(jobID: UUID(), mode: .dictation, event: ProviderUsage(createdAt: date ?? current,
                    provider: .openAI, model: "gpt-4.1-mini", stage: .textProcessing, inputTokens: 100, outputTokens: 10))
    }

    func testEncryptedUsageRoundTripAndIdempotentLateCostUpdate() async throws {
        let subject = try store()
        var item = record()
        try await subject.appendUsage(item)
        try await subject.appendUsage(item)
        item.event.providerCostUSD = 0.0009
        item.cost = UsagePricing.cost(for: item.event)
        try await subject.appendUsage(item)
        let reopened = try store()
        let records = try await reopened.usageRecords()
        XCTAssertEqual(records, [item])
        let data = try Data(contentsOf: directory.appendingPathComponent("vault-v1.enc"))
        XCTAssertNil(data.range(of: Data("gpt-4.1-mini".utf8)))
        XCTAssertNil(data.range(of: Data("inputTokens".utf8)))
        let snapshot = try await reopened.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.usageTrackingStartedAt, current)
        XCTAssertEqual(snapshot.usageDiscardedCount, 0)
    }

    func testHistoryRetentionAndDeletionDoNotEraseUsage() async throws {
        let subject = try store()
        let item = record(at: current.addingTimeInterval(-40 * 86_400))
        try await subject.appendUsage(item)
        try await subject.appendHistory(HistoryEntry(createdAt: current, mode: .dictation, originalText: "원문", resultText: "결과", provider: .openAI))
        let snapshot = try await subject.snapshot(retentionDays: 0)
        XCTAssertTrue(snapshot.history.isEmpty)
        XCTAssertEqual(snapshot.usageRecords, [item])
        try await subject.deleteAllHistory()
        let usage = try await subject.usageRecords()
        XCTAssertEqual(usage, [item])
    }

    func testClearUsagePreservesOtherDomainsAndRejectsOldCallbacksAfterReopen() async throws {
        let subject = try store()
        let old = record(at: current.addingTimeInterval(-10))
        let history = HistoryEntry(createdAt: current, mode: .dictation, originalText: "원문", resultText: "결과", provider: .openAI)
        let word = DictionaryEntry(spoken: "타입", written: "Type")
        try await subject.appendHistory(history)
        try await subject.upsertDictionaryEntries([word])
        try await subject.saveSpeakerProfile(Data([1, 2]))
        try await subject.appendUsage(old)
        try await subject.clearUsage()
        let reopened = try store()
        try await reopened.appendUsage(old)
        let fresh = record(at: current.addingTimeInterval(1))
        try await reopened.appendUsage(fresh)
        let snapshot = try await reopened.snapshot(retentionDays: -1)
        XCTAssertEqual(snapshot.usageRecords, [fresh])
        XCTAssertEqual(snapshot.history.map(\.id), [history.id])
        XCTAssertEqual(snapshot.dictionary, [word])
        XCTAssertTrue(snapshot.hasVoiceProfile)
        XCTAssertEqual(snapshot.usageTrackingStartedAt, current)
        XCTAssertEqual(snapshot.usageDiscardedCount, 0)
    }

    func testCancelledRequestStillCommitsAccounting() async throws {
        let subject = try store()
        var item = record(); item.event.outcome = .cancelled; item.cost = UsagePricing.cost(for: item.event)
        let cancelledItem = item
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await subject.appendUsage(cancelledItem)
        }
        try await task.value
        let records = try await subject.usageRecords()
        XCTAssertEqual(records, [item])
        XCTAssertNil(records.first?.cost.usd)
    }

    func testPreviousV2VaultWithoutUsageFieldsRemainsReadable() async throws {
        let subject = try store()
        let word = DictionaryEntry(spoken: "타입", written: "Type")
        try await subject.upsertDictionaryEntries([word])
        try editVault { json in
            for key in ["usageRecords", "usageTrackingStartedAt", "usageResetAt", "usageDiscardedCount", "usageDiscardedThrough"] {
                json.removeValue(forKey: key)
            }
        }
        let reopened = try store()
        let before = try await reopened.snapshot(retentionDays: 30)
        XCTAssertTrue(before.usageRecords.isEmpty)
        XCTAssertNil(before.usageTrackingStartedAt)
        try await reopened.appendUsage(record())
        let after = try await reopened.snapshot(retentionDays: 30)
        XCTAssertEqual(after.dictionary, [word])
        XCTAssertEqual(after.usageRecords.count, 1)
    }

    func testLimitDropsOldestAndDoesNotResurrectDiscardedEvent() async throws {
        let subject = try store()
        let initial = (0..<SecureStore.maximumUsageRecords).map { record(at: current.addingTimeInterval(Double($0))) }
        try await subject.appendUsage(initial[0])
        // Seed an authenticated fixture once; 10,000 individual encrypted writes are unnecessary.
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(initial))
        try editVault { $0["usageRecords"] = encoded }
        let fresh = record(at: current.addingTimeInterval(20_000))
        try await subject.appendUsage(fresh)
        try await subject.appendUsage(initial[0])
        try await subject.appendUsage(fresh)
        let snapshot = try await subject.snapshot(retentionDays: 0)
        XCTAssertEqual(snapshot.usageRecords.count, 10_000)
        XCTAssertEqual(snapshot.usageRecords.first, fresh)
        XCTAssertFalse(snapshot.usageRecords.contains(where: { $0.id == initial[0].id }))
        XCTAssertEqual(snapshot.usageDiscardedCount, 1)
    }

    func testConcurrentStoreInstancesKeepBothUsageRecords() async throws {
        let first = try store(), second = try store()
        let a = record(), b = record()
        async let saveA: Void = first.appendUsage(a)
        async let saveB: Void = second.appendUsage(b)
        _ = try await (saveA, saveB)
        let records = try await first.usageRecords()
        XCTAssertEqual(Set(records.map(\.id)), Set([a.id, b.id]))
    }

    func testOutOfOrderResponsesKeepTheEarliestTrackingStart() async throws {
        let subject = try store()
        try await subject.appendUsage(record(at: current.addingTimeInterval(10)))
        try await subject.appendUsage(record(at: current))
        let snapshot = try await subject.snapshot(retentionDays: 30)
        XCTAssertEqual(snapshot.usageTrackingStartedAt, current)
    }

    private func editVault(_ edit: (inout [String: Any]) throws -> Void) throws {
        let account = SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = SymmetricKey(data: try XCTUnwrap(secrets.read(service: "app.opennotype.encryption-key", account: account)))
        let url = directory.appendingPathComponent("vault-v1.enc")
        let header = Data("OpenNoType.vault.1\n".utf8)
        let encrypted = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(header.count))
        let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
        try edit(&json)
        let next = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let sealed = try AES.GCM.seal(next, using: key, authenticating: header)
        try (header + XCTUnwrap(sealed.combined)).write(to: url)
    }
}
