import CryptoKit
import Foundation

/// Metadata and audio have separate authenticated envelopes. Orphan expiry can be checked by
/// reading at most 4 KiB; normal vault snapshots never decode or read the audio ciphertext.
enum FailureAudioFiles {
    struct Reference: Codable, Equatable {
        var id: UUID
        var byteCount: Int
    }
    private struct Metadata: Codable {
        var id: UUID
        var recordingID: UUID
        var expiresAt: Date
        var byteCount: Int
    }
    private static let header = Data("OpenNoType.audio.1\n".utf8)
    private static let maximumMetadataBytes = 4_096

    static func url(_ reference: Reference, directory: URL) -> URL {
        directory.appendingPathComponent("audio-\(reference.id.uuidString).enc")
    }

    static func referenceID(_ name: String) -> UUID? {
        guard name.hasPrefix("audio-"), name.hasSuffix(".enc") else { return nil }
        return UUID(uuidString: String(name.dropFirst(6).dropLast(4)))
    }

    static func migrationID(audio: Data, item: FailedRecording) -> UUID {
        var hash = SHA256()
        hash.update(data: Data("OpenNoType.migrate-audio.1\n\(item.id.uuidString)\n\(item.expiresAt.timeIntervalSinceReferenceDate.bitPattern)\n".utf8))
        hash.update(data: audio)
        let bytes = Array(hash.finalize().prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func write(_ audio: Data, item: FailedRecording, directory: URL, key: SymmetricKey,
                      migrationID: UUID? = nil, now: Date = Date()) throws -> Reference {
        let reference = Reference(id: migrationID ?? UUID(), byteCount: audio.count)
        if migrationID != nil, try SecureStorageFiles.information(url(reference, directory: directory)) != nil {
            do {
                let previous = try read(reference, item: item, directory: directory, key: key)
                guard previous == audio else { throw SecureStoreError.corruptedStorage }
                return reference
            } catch {
                // The authenticated legacy vault remains authoritative. Preserve a broken
                // intermediate copy, then rebuild it from that source without blocking recovery.
                try SecureStorageFiles.quarantine(url(reference, directory: directory), now: now)
            }
        }
        let metadata = Metadata(id: reference.id, recordingID: item.id, expiresAt: item.expiresAt, byteCount: audio.count)
        let encoded = try JSONEncoder().encode(metadata)
        let sealedMetadata = try AES.GCM.seal(encoded, using: key, authenticating: header).combined!
        let audioBox = try AES.GCM.seal(audio, using: key, authenticating: header + sealedMetadata).combined!
        let length = UInt32(sealedMetadata.count)
        let lengthBytes = Data([UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
        let encrypted = header + lengthBytes + sealedMetadata + audioBox
        try SecureStorageFiles.writeAtomically(encrypted, to: url(reference, directory: directory), stagingPrefix: ".audio-") { staged in
            let decoded = try decode(staged, key: key, expected: reference, item: item)
            guard decoded == audio else { throw SecureStoreError.corruptedStorage }
        }
        return reference
    }

    static func read(_ reference: Reference, item: FailedRecording, directory: URL, key: SymmetricKey) throws -> Data {
        try decode(SecureStorageFiles.read(url(reference, directory: directory)), key: key, expected: reference, item: item)
    }

    private static func metadata(_ data: Data, key: SymmetricKey) throws -> (Metadata, Data, Int) {
        do {
            guard data.starts(with: header), data.count >= header.count + 4 else { throw SecureStoreError.corruptedStorage }
            let length = data[header.count..<header.count + 4].reduce(0) { ($0 << 8) | Int($1) }
            let offset = header.count + 4
            guard length >= 28, length <= maximumMetadataBytes, data.count >= offset + length else { throw SecureStoreError.corruptedStorage }
            let sealed = Data(data[offset..<offset + length])
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: header)
            let metadata = try JSONDecoder().decode(Metadata.self, from: plaintext)
            guard metadata.byteCount >= 0, metadata.expiresAt.timeIntervalSince1970.isFinite else { throw SecureStoreError.corruptedStorage }
            return (metadata, sealed, offset + length)
        } catch { throw SecureStoreError.corruptedStorage }
    }

    private static func decode(_ data: Data, key: SymmetricKey, expected: Reference, item: FailedRecording) throws -> Data {
        do {
            let (metadata, sealed, offset) = try metadata(data, key: key)
            guard metadata.id == expected.id, metadata.recordingID == item.id,
                  metadata.byteCount == expected.byteCount, metadata.expiresAt == item.expiresAt else {
                throw SecureStoreError.corruptedStorage
            }
            let audio = try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(offset)), using: key, authenticating: header + sealed)
            guard audio.count == expected.byteCount else { throw SecureStoreError.corruptedStorage }
            return audio
        } catch { throw SecureStoreError.corruptedStorage }
    }

    static func remove(_ reference: Reference, directory: URL) throws {
        try SecureStorageFiles.remove(url(reference, directory: directory))
    }

    /// Uncommitted blobs stay recoverable until their authenticated expiry. Referenced audio is
    /// deleted only after the vault commit which removes it, so a failed commit never loses audio.
    static func cleanupOrphans(directory: URL, referenced: Set<UUID>, key: SymmetricKey, now: Date) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            guard let id = referenceID(name), !referenced.contains(id) else { continue }
            let url = directory.appendingPathComponent(name)
            let prefix = try SecureStorageFiles.read(url, prefix: header.count + 4 + maximumMetadataBytes)
            let metadata: Metadata
            do {
                (metadata, _, _) = try self.metadata(prefix, key: key)
                guard metadata.id == id else { throw SecureStoreError.corruptedStorage }
            }
            catch {
                // An interrupted/unreferenced blob cannot invalidate an authenticated vault.
                try SecureStorageFiles.quarantine(url, now: now)
                continue
            }
            if metadata.expiresAt <= now { try SecureStorageFiles.remove(url) }
        }
    }

    /// Includes still-recoverable orphan files in the quota. Using ciphertext sizes also budgets
    /// encryption overhead conservatively; replacement may reclaim its old committed blob.
    static func storedBytes(directory: URL, excluding: UUID?) throws -> Int {
        var total = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            let id = referenceID(name)
            guard (id != nil && id != excluding) || name.hasPrefix(".recovery-") else { continue }
            guard let info = try SecureStorageFiles.information(directory.appendingPathComponent(name)) else { continue }
            let (sum, overflow) = total.addingReportingOverflow(Int(info.st_size))
            guard !overflow else { throw SecureStoreError.recordingStorageFull }
            total = sum
        }
        return total
    }
}
