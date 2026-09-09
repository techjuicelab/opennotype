import Darwin
import Foundation

/// Small POSIX boundary shared by the vault and its audio blobs. Never follows the final symlink.
enum SecureStorageFiles {
    static func information(_ url: URL) throws -> stat? {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw SecureStoreError.fileSystem(errno)
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw SecureStoreError.unsafeStoragePath }
        return info
    }

    static func read(_ url: URL, prefix: Int? = nil) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ELOOP { throw SecureStoreError.unsafeStoragePath }
            throw SecureStoreError.fileSystem(errno)
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw SecureStoreError.fileSystem(errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw SecureStoreError.unsafeStoragePath }
        if let prefix { return try handle.read(upToCount: prefix) ?? Data() }
        return try handle.readToEnd() ?? Data()
    }

    static func remove(_ url: URL) throws {
        guard try information(url) != nil else { return }
        guard unlink(url.path) == 0 else { throw SecureStoreError.fileSystem(errno) }
        try sync(url.deletingLastPathComponent())
    }

    static func quarantine(_ url: URL, now: Date) throws {
        guard try information(url) != nil else { return }
        let deadline = Int64(ceil(now.addingTimeInterval(86_400).timeIntervalSince1970))
        let destination = url.deletingLastPathComponent().appendingPathComponent(".recovery-\(deadline)-\(UUID().uuidString).enc")
        guard rename(url.path, destination.path) == 0 else { throw SecureStoreError.fileSystem(errno) }
        try sync(url.deletingLastPathComponent())
    }

    static func cleanupRecovery(directory: URL, now: Date) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            guard name.hasPrefix(".recovery-"), name.hasSuffix(".enc") else { continue }
            let remainder = String(name.dropFirst(10).dropLast(4))
            guard let separator = remainder.firstIndex(of: "-"),
                  let deadline = Double(remainder[..<separator]),
                  UUID(uuidString: String(remainder[remainder.index(after: separator)...])) != nil else { continue }
            if deadline <= now.timeIntervalSince1970 { try remove(directory.appendingPathComponent(name)) }
        }
    }

    static func writeAtomically(_ data: Data, to destination: URL, stagingPrefix: String,
                                beforeCommit: (@Sendable () throws -> Void)? = nil,
                                validate: (Data) throws -> Void) throws {
        // Reject a replaced destination instead of quietly overwriting a symlink.
        _ = try information(destination)
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(stagingPrefix + UUID().uuidString + ".tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SecureStoreError.fileSystem(errno) }
        defer { close(fd); try? remove(temporary) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SecureStoreError.fileSystem(errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw SecureStoreError.fileSystem(errno) }
        let staged = try read(temporary)
        guard staged == data else { throw SecureStoreError.corruptedStorage }
        try validate(staged)
        try beforeCommit?()
        guard rename(temporary.path, destination.path) == 0 else { throw SecureStoreError.fileSystem(errno) }
        try sync(directory)
    }

    static func sync(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw SecureStoreError.fileSystem(errno) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw SecureStoreError.fileSystem(errno) }
    }
}
