import Foundation

final class ReviewMemorySecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[service + account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + account] = nil
    }
}

@main struct StoreConcurrencyReview {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoTypeConcurrencyReview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SecureStore(directory: directory, backend: ReviewMemorySecrets())
        let base = DictionaryEntry(spoken: "기본", written: "Base")
        try await store.saveDictionary([base])
        // Two AppModel operations can both capture this same array before either await returns.
        let firstSnapshot = try await store.dictionary()
        let secondSnapshot = firstSnapshot
        let manualEntry = DictionaryEntry(spoken: "수동", written: "Manual")
        let learnedEntry = DictionaryEntry(spoken: "학습", written: "Learned", learned: true)
        try await store.saveDictionary(firstSnapshot + [manualEntry])
        try await store.saveDictionary(secondSnapshot + [learnedEntry])
        let actual = try await store.dictionary()
        print("dictionary after two stale merges: expected=3 actual=\(actual.count) manualEntryPreserved=\(actual.contains { $0.id == manualEntry.id })")
        precondition(actual.count == 2 && !actual.contains { $0.id == manualEntry.id })

        let old = HistoryEntry(mode: .dictation, originalText: "old", resultText: "old", provider: .groq)
        try await store.saveHistory([old])
        let historySnapshot = try await store.history()
        try await store.deleteAllHistory()
        let new = HistoryEntry(mode: .dictation, originalText: "new", resultText: "new", provider: .groq)
        try await store.saveHistory([new] + historySnapshot)
        let remaining = try await store.history()
        print("history stale append after delete: deletedEntryResurrected=\(remaining.contains { $0.id == old.id })")
        precondition(remaining.contains { $0.id == old.id })
    }
}
