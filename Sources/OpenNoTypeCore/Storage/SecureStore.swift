import CryptoKit
import Darwin
import Foundation

public enum SecureStoreError: Error, LocalizedError, Equatable {
    case missingEncryptionKey
    case invalidEncryptionKey
    case corruptedStorage
    case unsafeStoragePath
    case invalidRetention
    case recordingExpired
    case recordingNotFound
    case recordingTooLarge
    case recordingStorageFull
    case invalidDictionaryEntry
    case fileSystem(Int32)

    public var errorDescription: String? {
        switch self {
        case .missingEncryptionKey: "암호화된 기록은 있지만 복호화 키가 없습니다. 기존 기록을 보호하기 위해 저장을 중단했습니다."
        case .invalidEncryptionKey: "저장소 암호화 키가 올바르지 않습니다. 기존 기록은 변경하지 않았습니다."
        case .corruptedStorage: "기록을 복호화하거나 검증할 수 없습니다. 기존 기록은 변경하지 않았습니다."
        case .unsafeStoragePath: "안전하지 않은 저장소 경로입니다."
        case .invalidRetention: "보관 기간은 계속 보관(-1) 또는 0일 이상이어야 합니다."
        case .recordingExpired: "실패한 녹음의 보관 기간이 만료되었습니다."
        case .recordingNotFound: "보관 중인 실패 녹음이 없습니다."
        case .recordingTooLarge: "실패 녹음 한 개는 25 MB 이하로 보관할 수 있습니다."
        case .recordingStorageFull: "실패 녹음 저장 공간이 가득 찼습니다. 기존 복구 녹음은 보존했습니다. 필요 없는 녹음을 삭제한 뒤 다시 시도해 주세요."
        case .invalidDictionaryEntry: "사전 항목은 비어 있지 않은 100자 이하의 표기여야 합니다."
        case .fileSystem(let code): "로컬 저장소에 접근할 수 없습니다 (\(code))."
        }
    }
}

/// A consistent view of one authenticated vault revision, without raw audio or speaker embeddings.
public struct StoreSnapshot: Sendable {
    public let history: [HistoryEntry]
    public let dictionary: [DictionaryEntry]
    public let failedRecordings: [FailedRecording]
    public let learningCandidates: [LearningCandidate]
    public let hasVoiceProfile: Bool
    public let usageRecords: [UsageRecord]
    public let usageTrackingStartedAt: Date?
    public let usageDiscardedCount: Int

    public init(history: [HistoryEntry], dictionary: [DictionaryEntry], failedRecordings: [FailedRecording],
                learningCandidates: [LearningCandidate], hasVoiceProfile: Bool,
                usageRecords: [UsageRecord] = [], usageTrackingStartedAt: Date? = nil, usageDiscardedCount: Int = 0) {
        self.history = history
        self.dictionary = dictionary
        self.failedRecordings = failedRecordings
        self.learningCandidates = learningCandidates
        self.hasVoiceProfile = hasVoiceProfile
        self.usageRecords = usageRecords
        self.usageTrackingStartedAt = usageTrackingStartedAt
        self.usageDiscardedCount = usageDiscardedCount
    }
}

public actor SecureStore {
    private struct UsageCursor: Codable {
        var createdAt: Date
        var id: UUID
        init(_ record: UsageRecord) { createdAt = record.event.createdAt; id = record.id }
        func includes(_ record: UsageRecord) -> Bool {
            record.event.createdAt < createdAt || (record.event.createdAt == createdAt && record.id.uuidString <= id.uuidString)
        }
    }
    private struct FailurePayload: Codable {
        var item: FailedRecording
        var audio: Data?
        var blob: FailureAudioFiles.Reference?
    }

    private struct Vault: Codable {
        var version = 2
        var retentionDays = 30
        var history: [HistoryEntry] = []
        var dictionary: [DictionaryEntry] = []
        var failures: [FailurePayload] = []
        var pendingAudioDeletions: [FailureAudioFiles.Reference]?
        var speakerProfile: Data?
        var learningCandidates: [LearningCandidate]?
        // Optional fields preserve v1/v2 vault compatibility. Usage has independent retention.
        var usageRecords: [UsageRecord]?
        var usageTrackingStartedAt: Date?
        var usageResetAt: Date?
        var usageDiscardedCount: Int?
        var usageDiscardedThrough: UsageCursor?
    }

    public static let maximumFailedRecordingBytes = 100_000_000
    public static let maximumUsageRecords = 10_000
    private static let maximumAudioBytes = 25_000_000
    private static let vaultName = "vault-v1.enc"
    private static let keyService = "app.opennotype.encryption-key"
    private static let header = Data("OpenNoType.vault.1\n".utf8)
    private let directory: URL
    private let key: SymmetricKey
    private let backend: any SecretBackend
    private let now: @Sendable () -> Date
    private let audioLimitBytes: Int
    private let beforeVaultCommit: (@Sendable () throws -> Void)?

    public init(directory: URL? = nil) throws {
        let location = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("OpenNoType/Data", isDirectory: true)
        try self.init(directory: location, backend: SystemKeychainBackend(), now: { Date() })
    }

    init(directory: URL, backend: any SecretBackend, now: @escaping @Sendable () -> Date = { Date() },
         audioLimitBytes: Int = SecureStore.maximumFailedRecordingBytes,
         beforeVaultCommit: (@Sendable () throws -> Void)? = nil) throws {
        let standardized = directory.standardizedFileURL
        let location = standardized.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(standardized.lastPathComponent, isDirectory: true)
        try Self.prepareDirectory(location)
        let loadedKey: SymmetricKey = try Self.withLock(directory: location) {
            let account = Self.keyAccount(for: location)
            let data: Data
            if let stored = try backend.read(service: Self.keyService, account: account) {
                data = stored
            } else {
                let existing = try FileManager.default.contentsOfDirectory(atPath: location.path).filter { $0 != ".lock" }
                guard existing.isEmpty else { throw SecureStoreError.missingEncryptionKey }
                let generated = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                try backend.save(generated, service: Self.keyService, account: account)
                guard try backend.read(service: Self.keyService, account: account) == generated else {
                    throw SecureStoreError.invalidEncryptionKey
                }
                data = generated
            }
            guard data.count == 32 else { throw SecureStoreError.invalidEncryptionKey }
            let result = SymmetricKey(data: data)
            _ = try Self.prepareVault(directory: location, key: result, now: now(), beforeCommit: beforeVaultCommit)
            return result
        }
        self.directory = location
        self.key = loadedKey
        self.backend = backend
        self.now = now
        self.audioLimitBytes = max(0, audioLimitBytes)
        self.beforeVaultCommit = beforeVaultCommit
    }

    /// Preserves the existing retention and storage-order contracts while reading every domain once.
    public func snapshot(retentionDays: Int) throws -> StoreSnapshot {
        guard retentionDays >= -1 else { throw SecureStoreError.invalidRetention }
        return try transaction { vault, current in
            vault.retentionDays = retentionDays
            _ = Self.prune(&vault, at: current)
            return StoreSnapshot(history: vault.history, dictionary: vault.dictionary,
                                 failedRecordings: vault.failures.map(\.item),
                                 learningCandidates: vault.learningCandidates ?? [],
                                 hasVoiceProfile: vault.speakerProfile != nil,
                                 usageRecords: vault.usageRecords ?? [],
                                 usageTrackingStartedAt: vault.usageTrackingStartedAt,
                                 usageDiscardedCount: vault.usageDiscardedCount ?? 0)
        }
    }

    public func history(retentionDays: Int = 30) throws -> [HistoryEntry] {
        guard retentionDays >= -1 else { throw SecureStoreError.invalidRetention }
        return try transaction { vault, current in
            vault.retentionDays = retentionDays
            _ = Self.prune(&vault, at: current)
            return vault.history
        }
    }

    public func saveHistory(_ entries: [HistoryEntry]) throws {
        try transaction { vault, current in
            vault.history = entries
            _ = Self.prune(&vault, at: current)
        }
    }

    @discardableResult
    public func appendHistory(_ entry: HistoryEntry) throws -> [HistoryEntry] {
        try transaction { vault, current in
            vault.history.removeAll { $0.id == entry.id }
            vault.history.insert(entry, at: 0)
            _ = Self.prune(&vault, at: current)
            return vault.history
        }
    }

    @discardableResult
    public func deleteHistory(id: UUID) throws -> [HistoryEntry] {
        try transaction { vault, _ in
            vault.history.removeAll { $0.id == id }
            return vault.history
        }
    }

    public func deleteAllHistory() throws {
        try transaction { vault, _ in vault.history.removeAll(); vault.learningCandidates = nil }
    }

    /// Idempotent per request UUID, including updates that add late reported cost data.
    /// A cancelled request may still have incurred cost, so its accounting commit is not cancelled.
    public func appendUsage(_ record: UsageRecord) throws {
        try transaction(checkingCancellation: false) { vault, _ in
            guard vault.usageResetAt.map({ record.event.createdAt >= $0 }) ?? true,
                  !(vault.usageDiscardedThrough?.includes(record) ?? false) else { return }
            var records = vault.usageRecords ?? []
            records.removeAll { $0.id == record.id }
            records.append(record)
            records.sort {
                if $0.event.createdAt != $1.event.createdAt { return $0.event.createdAt > $1.event.createdAt }
                return $0.id.uuidString > $1.id.uuidString
            }
            if records.count > Self.maximumUsageRecords {
                let discarded = records.count - Self.maximumUsageRecords
                vault.usageDiscardedThrough = UsageCursor(records[Self.maximumUsageRecords])
                vault.usageDiscardedCount = (vault.usageDiscardedCount ?? 0) + discarded
                records.removeLast(discarded)
            }
            vault.usageRecords = records
            vault.usageTrackingStartedAt = min(vault.usageTrackingStartedAt ?? record.event.createdAt, record.event.createdAt)
        }
    }

    public func usageRecords() throws -> [UsageRecord] {
        try transaction { vault, _ in vault.usageRecords ?? [] }
    }

    /// Starts a fresh accounting period; text history, recovery audio and dictionary are untouched.
    public func clearUsage() throws {
        try transaction { vault, current in
            vault.usageRecords = []
            vault.usageTrackingStartedAt = current
            vault.usageResetAt = current
            vault.usageDiscardedCount = 0
            vault.usageDiscardedThrough = nil
        }
    }

    public func dictionary() throws -> [DictionaryEntry] {
        try transaction { vault, _ in vault.dictionary }
    }

    public func saveDictionary(_ entries: [DictionaryEntry]) throws {
        try transaction { vault, _ in vault.dictionary = entries }
    }

    /// Read, merge and commit under the same interprocess lock. Callers never overwrite a
    /// concurrently learned or manually edited entry using a stale UI snapshot.
    @discardableResult
    public func upsertDictionaryEntries(_ entries: [DictionaryEntry]) throws -> [DictionaryEntry] {
        try transaction { vault, _ in
            for entry in entries.prefix(10_000) {
                guard let (spoken, written) = Self.normalizedEntry(spoken: entry.spoken, written: entry.written) else { continue }
                vault.dictionary.removeAll { $0.id == entry.id || $0.spoken.caseInsensitiveCompare(spoken) == .orderedSame }
                vault.dictionary.append(.init(id: entry.id, spoken: spoken, written: written,
                                              createdAt: entry.createdAt, learned: entry.learned))
            }
            return vault.dictionary
        }
    }

    /// Return the actual previous value from the same revision as the learned write. Undo must
    /// never restore an older UI snapshot over a manual edit that preceded this transaction.
    public func applyLearnedDictionaryEntry(_ entry: DictionaryEntry) throws -> (applied: DictionaryEntry, previous: DictionaryEntry?) {
        try Task.checkCancellation()
        guard let (spoken, written) = Self.normalizedEntry(spoken: entry.spoken, written: entry.written) else {
            throw SecureStoreError.invalidDictionaryEntry
        }
        let applied = DictionaryEntry(id: entry.id, spoken: spoken, written: written, createdAt: entry.createdAt, learned: entry.learned)
        return try transaction { vault, _ in
            let previous = vault.dictionary.last { $0.spoken.caseInsensitiveCompare(spoken) == .orderedSame }
            vault.dictionary.removeAll { $0.id == entry.id || $0.spoken.caseInsensitiveCompare(spoken) == .orderedSame }
            vault.dictionary.append(applied)
            return (applied, previous)
        }
    }

    @discardableResult
    public func updateDictionaryEntry(id: UUID, spoken: String, written: String) throws -> [DictionaryEntry] {
        guard let (spoken, written) = Self.normalizedEntry(spoken: spoken, written: written) else {
            throw SecureStoreError.invalidDictionaryEntry
        }
        return try transaction { vault, _ in
            guard var existing = vault.dictionary.first(where: { $0.id == id }) else { return vault.dictionary }
            existing.spoken = spoken; existing.written = written
            vault.dictionary.removeAll { $0.id == id || $0.spoken.caseInsensitiveCompare(spoken) == .orderedSame }
            vault.dictionary.append(existing)
            return vault.dictionary
        }
    }

    @discardableResult
    public func deleteDictionaryEntry(id: UUID) throws -> [DictionaryEntry] {
        try transaction { vault, _ in
            vault.dictionary.removeAll { $0.id == id }
            return vault.dictionary
        }
    }

    /// Undo only the exact committed value: later manual edits always win.
    @discardableResult
    public func undoDictionaryChange(applied: DictionaryEntry, previous: DictionaryEntry?) throws -> Bool {
        try transaction { vault, _ in
            guard let index = vault.dictionary.firstIndex(where: { $0.id == applied.id }),
                  vault.dictionary[index] == applied,
                  !vault.dictionary.contains(where: { $0.id != applied.id && $0.spoken.caseInsensitiveCompare(applied.spoken) == .orderedSame }) else {
                return false
            }
            if let previous {
                guard previous.spoken.caseInsensitiveCompare(applied.spoken) == .orderedSame,
                      !vault.dictionary.contains(where: { $0.id != applied.id && $0.id == previous.id }) else { return false }
            }
            vault.dictionary.remove(at: index)
            if let previous { vault.dictionary.insert(previous, at: index) }
            return true
        }
    }

    private static func normalizedEntry(spoken: String, written: String) -> (String, String)? {
        let from = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from.count <= 100, to.count <= 100 else { return nil }
        return (from, to)
    }

    public func failures() throws -> [FailedRecording] {
        try transaction { vault, _ in vault.failures.map(\.item) }
    }

    public func saveFailure(_ item: FailedRecording, audio: Data) throws {
        guard audio.count <= Self.maximumAudioBytes else { throw SecureStoreError.recordingTooLarge }
        try transaction { vault, current in
            var bounded = item
            bounded.expiresAt = min(item.expiresAt, item.createdAt.addingTimeInterval(86_400), current.addingTimeInterval(86_400))
            guard bounded.expiresAt > current, bounded.createdAt <= current else { throw SecureStoreError.recordingExpired }
            let replacing = vault.failures.first { $0.item.id == item.id }?.blob?.id
            let existingBytes = try FailureAudioFiles.storedBytes(directory: directory, excluding: replacing)
            // Reserve the small encrypted metadata envelope as well as the raw audio.
            guard audio.count <= audioLimitBytes, existingBytes <= audioLimitBytes - audio.count,
                  audioLimitBytes - audio.count - existingBytes >= 4_096 else { throw SecureStoreError.recordingStorageFull }
            let blob = try FailureAudioFiles.write(audio, item: bounded, directory: directory, key: key)
            vault.failures.removeAll { $0.item.id == item.id }
            vault.failures.append(FailurePayload(item: bounded, audio: nil, blob: blob))
        }
    }

    public func failureAudio(id: UUID) throws -> Data {
        // The lookup and read stay inside the lock, so concurrent delete/replacement cannot
        // remove this blob in between. A missing lookup returns nil to persist expiry first.
        let result: Data? = try transaction { vault, _ in
            guard let payload = vault.failures.first(where: { $0.item.id == id }), let blob = payload.blob else { return nil }
            return try FailureAudioFiles.read(blob, item: payload.item, directory: directory, key: key)
        }
        guard let result else { throw SecureStoreError.recordingNotFound }
        return result
    }

    public func deleteFailure(id: UUID) throws {
        try transaction { vault, _ in vault.failures.removeAll { $0.item.id == id } }
    }

    public func saveSpeakerProfile(_ data: Data) throws {
        try transaction { vault, _ in vault.speakerProfile = data }
    }

    public func speakerProfile() throws -> Data? {
        try transaction { vault, _ in vault.speakerProfile }
    }

    public func deleteSpeakerProfile() throws {
        try transaction { vault, _ in vault.speakerProfile = nil }
    }

    public func learningCandidates() throws -> [LearningCandidate] {
        try transaction { vault, _ in vault.learningCandidates ?? [] }
    }

    public func saveLearningCandidates(_ entries: [LearningCandidate]) throws {
        try transaction { vault, current in
            vault.learningCandidates = entries
            _ = Self.prune(&vault, at: current)
        }
    }

    private func transaction<T>(checkingCancellation: Bool = true, _ operation: (inout Vault, Date) throws -> T) throws -> T {
        try Self.withLock(directory: directory) {
            guard let currentKey = try backend.read(service: Self.keyService, account: Self.keyAccount(for: directory)) else {
                throw SecureStoreError.missingEncryptionKey
            }
            guard currentKey == key.withUnsafeBytes({ Data($0) }) else { throw SecureStoreError.invalidEncryptionKey }
            let current = now()
            var vault = try Self.prepareVault(directory: directory, key: key, now: current, beforeCommit: beforeVaultCommit)
            let previousBlobs = vault.failures.compactMap(\.blob)
            let before = try Self.encodeVault(vault)
            let result = try operation(&vault, current)
            Self.queueObsoleteBlobs(previousBlobs, in: &vault)
            let after = try Self.encodeVault(vault)
            if before != after {
                // Cancellation is checked only before the atomic commit. Once its rename starts,
                // complete persistence and cleanup instead of leaving a partly accepted mutation.
                if checkingCancellation { try Task.checkCancellation() }
                try Self.writeVault(vault, directory: directory, key: key, beforeCommit: beforeVaultCommit)
                try Self.removePendingBlobs(vault, directory: directory)
            }
            return result
        }
    }

    /// A v1 vault remains the committed source until every live audio blob has been sealed,
    /// reread and validated. If any step fails, retry can safely restart from that old vault.
    private static func prepareVault(directory: URL, key: SymmetricKey, now: Date,
                                     beforeCommit: (@Sendable () throws -> Void)?) throws -> Vault {
        var vault = try readVault(directory: directory, key: key)
        try cleanupStagedFiles(directory: directory, now: now)
        let clearedDeletions = !(vault.pendingAudioDeletions ?? []).isEmpty
        try removePendingBlobs(vault, directory: directory)
        vault.pendingAudioDeletions = nil
        let previousBlobs = vault.failures.compactMap(\.blob)
        let migration = vault.version == 1
        let pruned = prune(&vault, at: now)
        if migration {
            for index in vault.failures.indices {
                guard let audio = vault.failures[index].audio else { throw SecureStoreError.corruptedStorage }
                var item = vault.failures[index].item
                item.expiresAt = min(item.expiresAt, item.createdAt.addingTimeInterval(86_400))
                let blob = try FailureAudioFiles.write(audio, item: item, directory: directory, key: key,
                                                      migrationID: FailureAudioFiles.migrationID(audio: audio, item: item), now: now)
                vault.failures[index] = FailurePayload(item: item, audio: nil, blob: blob)
            }
            vault.version = 2
        }
        queueObsoleteBlobs(previousBlobs, in: &vault)
        if migration || pruned || clearedDeletions {
            try writeVault(vault, directory: directory, key: key, beforeCommit: beforeCommit)
            try removePendingBlobs(vault, directory: directory)
        }
        try FailureAudioFiles.cleanupOrphans(directory: directory, referenced: Set(vault.failures.compactMap { $0.blob?.id }), key: key, now: now)
        return vault
    }

    private static func queueObsoleteBlobs(_ previous: [FailureAudioFiles.Reference], in vault: inout Vault) {
        let kept = Set(vault.failures.compactMap { $0.blob?.id })
        var pending = vault.pendingAudioDeletions ?? []
        for blob in previous where !kept.contains(blob.id) && !pending.contains(where: { $0.id == blob.id }) { pending.append(blob) }
        vault.pendingAudioDeletions = pending.isEmpty ? nil : pending
    }

    private static func removePendingBlobs(_ vault: Vault, directory: URL) throws {
        for blob in vault.pendingAudioDeletions ?? [] { try FailureAudioFiles.remove(blob, directory: directory) }
    }

    private static func prune(_ vault: inout Vault, at current: Date) -> Bool {
        let historyCount = vault.history.count
        let failureCount = vault.failures.count
        let candidateCount = vault.learningCandidates?.count ?? 0
        let cutoff = current.addingTimeInterval(-Double(vault.retentionDays) * 86_400)
        if vault.retentionDays >= 0 {
            vault.history.removeAll { vault.retentionDays == 0 || $0.createdAt <= cutoff }
            vault.learningCandidates?.removeAll { vault.retentionDays == 0 || $0.createdAt <= cutoff }
        }
        vault.failures.removeAll { min($0.item.expiresAt, $0.item.createdAt.addingTimeInterval(86_400)) <= current }
        return historyCount != vault.history.count || failureCount != vault.failures.count || candidateCount != (vault.learningCandidates?.count ?? 0)
    }

    private static func keyAccount(for directory: URL) -> String {
        SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func prepareDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              directory.resolvingSymlinksInPath().path == directory.path else {
            throw SecureStoreError.unsafeStoragePath
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func withLock<T>(directory: URL, operation: () throws -> T) throws -> T {
        // Revalidate for every operation; a directory replaced after initialization must not
        // redirect this instance to another path, including through a parent symlink.
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw SecureStoreError.unsafeStoragePath }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw SecureStoreError.unsafeStoragePath }
        let fd = open(directory.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SecureStoreError.fileSystem(errno) }
        defer { close(fd) }
        guard fchmod(fd, 0o600) == 0, flock(fd, LOCK_EX) == 0 else { throw SecureStoreError.fileSystem(errno) }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }

    private static func readVault(directory: URL, key: SymmetricKey) throws -> Vault {
        let url = directory.appendingPathComponent(vaultName)
        var fileInfo = stat()
        if lstat(url.path, &fileInfo) != 0 {
            if errno == ENOENT { return Vault() }
            throw SecureStoreError.fileSystem(errno)
        }
        return try decodeVault(SecureStorageFiles.read(url), key: key)
    }

    private static func encodeVault(_ vault: Vault) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(vault)
    }

    private static func cleanupStagedFiles(directory: URL, now: Date) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let staged = names.filter { ($0.hasPrefix(".vault-") || $0.hasPrefix(".audio-")) && $0.hasSuffix(".tmp") }
        if !staged.isEmpty {
            // readVault has already authenticated the committed version. Without one, preserve
            // the interrupted first write for explicit recovery instead of creating an empty vault.
            guard try SecureStorageFiles.information(directory.appendingPathComponent(vaultName)) != nil else {
                throw SecureStoreError.corruptedStorage
            }
            for name in staged { try SecureStorageFiles.quarantine(directory.appendingPathComponent(name), now: now) }
        }
        try SecureStorageFiles.cleanupRecovery(directory: directory, now: now)
    }

    private static func decodeVault(_ encrypted: Data, key: SymmetricKey) throws -> Vault {
        do {
            guard encrypted.starts(with: header) else { throw SecureStoreError.corruptedStorage }
            let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(header.count))
            let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
            let result = try JSONDecoder().decode(Vault.self, from: plaintext)
            guard (1...2).contains(result.version), result.retentionDays >= -1,
                  Set(result.failures.map { $0.item.id }).count == result.failures.count else { throw SecureStoreError.corruptedStorage }
            for failure in result.failures {
                if result.version == 1 {
                    guard failure.audio != nil else { throw SecureStoreError.corruptedStorage }
                } else {
                    guard failure.audio == nil, let blob = failure.blob, blob.byteCount >= 0 else { throw SecureStoreError.corruptedStorage }
                }
            }
            guard Set(result.failures.compactMap { $0.blob?.id }).count == result.failures.filter({ $0.blob != nil }).count else {
                throw SecureStoreError.corruptedStorage
            }
            guard Set(result.pendingAudioDeletions?.map(\.id) ?? []).isDisjoint(with: result.failures.compactMap { $0.blob?.id }) else {
                throw SecureStoreError.corruptedStorage
            }
            return result
        } catch { throw SecureStoreError.corruptedStorage }
    }

    private static func writeVault(_ vault: Vault, directory: URL, key: SymmetricKey,
                                   beforeCommit: (@Sendable () throws -> Void)? = nil) throws {
        let plaintext = try encodeVault(vault)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let combined = box.combined else { throw SecureStoreError.corruptedStorage }
        try SecureStorageFiles.writeAtomically(header + combined, to: directory.appendingPathComponent(vaultName),
                                              stagingPrefix: ".vault-", beforeCommit: beforeCommit) { staged in
            _ = try decodeVault(staged, key: key)
        }
    }
}
