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
        case .fileSystem(let code): "로컬 저장소에 접근할 수 없습니다 (\(code))."
        }
    }
}

public actor SecureStore {
    private struct FailurePayload: Codable {
        var item: FailedRecording
        var audio: Data
    }

    private struct Vault: Codable {
        var version = 1
        var retentionDays = 30
        var history: [HistoryEntry] = []
        var dictionary: [DictionaryEntry] = []
        var failures: [FailurePayload] = []
        var speakerProfile: Data?
        var learningCandidates: [LearningCandidate]?
    }

    private static let vaultName = "vault-v1.enc"
    private static let keyService = "app.opennotype.encryption-key"
    private static let header = Data("OpenNoType.vault.1\n".utf8)
    private let directory: URL
    private let key: SymmetricKey
    private let backend: any SecretBackend
    private let now: @Sendable () -> Date

    public init(directory: URL? = nil) throws {
        let location = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("OpenNoType/Data", isDirectory: true)
        try self.init(directory: location, backend: SystemKeychainBackend(), now: { Date() })
    }

    init(directory: URL, backend: any SecretBackend, now: @escaping @Sendable () -> Date = { Date() }) throws {
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
            var vault = try Self.readVault(directory: location, key: result)
            try Self.cleanupStagedFiles(directory: location, key: result)
            if Self.prune(&vault, at: now()) {
                try Self.writeVault(vault, directory: location, key: result)
            }
            return result
        }
        self.directory = location
        self.key = loadedKey
        self.backend = backend
        self.now = now
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

    public func deleteAllHistory() throws {
        try transaction { vault, _ in vault.history.removeAll(); vault.learningCandidates = nil }
    }

    public func dictionary() throws -> [DictionaryEntry] {
        try transaction { vault, _ in vault.dictionary }
    }

    public func saveDictionary(_ entries: [DictionaryEntry]) throws {
        try transaction { vault, _ in vault.dictionary = entries }
    }

    public func failures() throws -> [FailedRecording] {
        try transaction { vault, _ in vault.failures.map(\.item) }
    }

    public func saveFailure(_ item: FailedRecording, audio: Data) throws {
        try transaction { vault, current in
            var bounded = item
            bounded.expiresAt = min(item.expiresAt, item.createdAt.addingTimeInterval(86_400), current.addingTimeInterval(86_400))
            guard bounded.expiresAt > current, bounded.createdAt <= current else {
                throw SecureStoreError.recordingExpired
            }
            vault.failures.removeAll { $0.item.id == item.id }
            vault.failures.append(FailurePayload(item: bounded, audio: audio))
        }
    }

    public func failureAudio(id: UUID) throws -> Data {
        let result: Data? = try transaction { vault, _ in vault.failures.first { $0.item.id == id }?.audio }
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

    private func transaction<T>(_ operation: (inout Vault, Date) throws -> T) throws -> T {
        try Self.withLock(directory: directory) {
            guard let currentKey = try backend.read(service: Self.keyService, account: Self.keyAccount(for: directory)) else {
                throw SecureStoreError.missingEncryptionKey
            }
            guard currentKey == key.withUnsafeBytes({ Data($0) }) else { throw SecureStoreError.invalidEncryptionKey }
            var vault = try Self.readVault(directory: directory, key: key)
            try Self.cleanupStagedFiles(directory: directory, key: key)
            let before = try Self.encodeVault(vault)
            let current = now()
            _ = Self.prune(&vault, at: current)
            let result = try operation(&vault, current)
            let after = try Self.encodeVault(vault)
            // Pruning must also persist on read-only calls, including failed-audio lookups.
            if before != after {
                try Self.writeVault(vault, directory: directory, key: key)
            }
            return result
        }
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
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SecureStoreError.unsafeStoragePath }
        return try decodeVault(Data(contentsOf: url), key: key)
    }

    private static func encodeVault(_ vault: Vault) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(vault)
    }

    private static func cleanupStagedFiles(directory: URL, key: SymmetricKey) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let staged = names.filter { $0.hasPrefix(".vault-") && $0.hasSuffix(".tmp") }
        guard !staged.isEmpty else { return }
        // Without a committed vault, preserve any interrupted write for explicit recovery.
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(vaultName).path) else {
            throw SecureStoreError.corruptedStorage
        }
        let urls = staged.map { directory.appendingPathComponent($0) }
        for url in urls {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SecureStoreError.unsafeStoragePath }
            _ = try decodeVault(Data(contentsOf: url), key: key)
        }
        for url in urls { try FileManager.default.removeItem(at: url) }
    }

    private static func decodeVault(_ encrypted: Data, key: SymmetricKey) throws -> Vault {
        do {
            guard encrypted.starts(with: header) else { throw SecureStoreError.corruptedStorage }
            let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(header.count))
            let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
            let result = try JSONDecoder().decode(Vault.self, from: plaintext)
            guard result.version == 1, result.retentionDays >= -1 else { throw SecureStoreError.corruptedStorage }
            return result
        } catch { throw SecureStoreError.corruptedStorage }
    }

    private static func writeVault(_ vault: Vault, directory: URL, key: SymmetricKey) throws {
        let plaintext = try encodeVault(vault)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let combined = box.combined else { throw SecureStoreError.corruptedStorage }
        let encrypted = header + combined
        let temporary = directory.appendingPathComponent(".vault-\(UUID().uuidString).tmp")
        let destination = directory.appendingPathComponent(vaultName)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SecureStoreError.fileSystem(errno) }
        defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
        try encrypted.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SecureStoreError.fileSystem(errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw SecureStoreError.fileSystem(errno) }
        let staged = try Data(contentsOf: temporary)
        _ = try decodeVault(staged, key: key)
        guard staged == encrypted else { throw SecureStoreError.corruptedStorage }
        guard rename(temporary.path, destination.path) == 0 else { throw SecureStoreError.fileSystem(errno) }
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
    }
}
