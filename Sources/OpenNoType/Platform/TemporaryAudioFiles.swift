import Darwin
import Foundation

enum TemporaryAudioFiles {
    private static let current = TemporaryAudioSession(
        rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("OpenNoType", isDirectory: true)
    )

    /// Reserves an empty owner-only WAV in this process's private temporary session.
    static func makeURL() throws -> URL { try current.makeURL() }

    /// May also run at application startup without requesting microphone access or creating a WAV.
    static func cleanupDeadSessions() throws { try current.cleanupDeadSessions() }

    /// Call from the application's normal termination hook after stopping audio work.
    static func cleanupCurrentSession() throws { try current.cleanupCurrentSession() }
}

enum TemporaryAudioError: Error, LocalizedError, Equatable {
    case unsafePath
    case fileSystem(Int32)
    var errorDescription: String? {
        switch self {
        case .unsafePath: "안전하지 않은 임시 녹음 경로입니다. 파일을 변경하지 않았습니다."
        case .fileSystem(let code): "임시 녹음 파일을 준비하거나 정리하지 못했습니다 (\(code))."
        }
    }
}

/// Isolated instances let tests exercise cleanup without accessing a user's real temporary files.
final class TemporaryAudioSession: @unchecked Sendable {
    private let lock = NSLock()
    let rootDirectory: URL
    let sessionName: String
    private let processIsAlive: @Sendable (pid_t) -> Bool

    init(rootDirectory: URL, processID: pid_t = getpid(), sessionID: UUID = UUID(),
         processIsAlive: @escaping @Sendable (pid_t) -> Bool = { TemporaryAudioSession.isProcessAlive($0) }) {
        let standardized = rootDirectory.standardizedFileURL
        self.rootDirectory = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(standardized.lastPathComponent, isDirectory: true)
        self.sessionName = "session-\(processID)-\(sessionID.uuidString)"
        self.processIsAlive = processIsAlive
    }

    func makeURL() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let rootFD = try prepareRoot()
        defer { close(rootFD) }
        try cleanupDeadSessions(rootFD: rootFD)
        if mkdirat(rootFD, sessionName, 0o700) != 0 && errno != EEXIST { throw TemporaryAudioError.fileSystem(errno) }
        let sessionFD = try openOwnedDirectory(parentFD: rootFD, name: sessionName)
        defer { close(sessionFD) }
        guard fchmod(sessionFD, 0o700) == 0 else { throw TemporaryAudioError.fileSystem(errno) }
        let name = UUID().uuidString + ".wav"
        let fd = openat(sessionFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw TemporaryAudioError.fileSystem(errno) }
        defer { close(fd) }
        guard fchmod(fd, 0o600) == 0 else {
            let failure = errno
            _ = unlinkat(sessionFD, name, 0)
            throw TemporaryAudioError.fileSystem(failure)
        }
        return rootDirectory.appendingPathComponent(sessionName, isDirectory: true).appendingPathComponent(name)
    }

    func cleanupCurrentSession() throws {
        lock.lock(); defer { lock.unlock() }
        let rootFD = try openExistingRoot()
        guard rootFD >= 0 else { return }
        defer { close(rootFD) }
        var info = stat()
        if fstatat(rootFD, sessionName, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return }
            throw TemporaryAudioError.fileSystem(errno)
        }
        try removeSession(parentFD: rootFD, name: sessionName)
    }

    func cleanupDeadSessions() throws {
        lock.lock(); defer { lock.unlock() }
        let rootFD = try openExistingRoot()
        guard rootFD >= 0 else { return }
        defer { close(rootFD) }
        try cleanupDeadSessions(rootFD: rootFD)
    }

    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return true }
        if kill(pid, 0) == 0 { return true }
        // Permission errors and unknown states are not proof that a process has exited.
        return errno != ESRCH
    }

    private func prepareRoot() throws -> Int32 {
        let existing = try openExistingRoot()
        if existing >= 0 { return existing }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = try openExistingRoot()
        guard fd >= 0 else { throw TemporaryAudioError.unsafePath }
        return fd
    }

    private func openExistingRoot() throws -> Int32 {
        var info = stat()
        if lstat(rootDirectory.path, &info) != 0 {
            if errno == ENOENT { return -1 }
            throw TemporaryAudioError.fileSystem(errno)
        }
        guard Self.ownedDirectory(info) else { throw TemporaryAudioError.unsafePath }
        let fd = open(rootDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw TemporaryAudioError.fileSystem(errno) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, Self.ownedDirectory(opened), opened.st_ino == info.st_ino, opened.st_dev == info.st_dev else {
            close(fd); throw TemporaryAudioError.unsafePath
        }
        guard fchmod(fd, 0o700) == 0 else { let failure = errno; close(fd); throw TemporaryAudioError.fileSystem(failure) }
        return fd
    }

    private func cleanupDeadSessions(rootFD: Int32) throws {
        for name in try names(in: rootFD) {
            guard name != sessionName, let pid = Self.processID(from: name), !processIsAlive(pid) else { continue }
            // Preserve unknown files, links, and malformed sessions rather than recursively deleting them.
            do { try removeSession(parentFD: rootFD, name: name) }
            catch TemporaryAudioError.unsafePath { continue }
            catch TemporaryAudioError.fileSystem(let code) where code == ENOENT { continue }
        }
    }

    private func removeSession(parentFD: Int32, name: String) throws {
        let fd = try openOwnedDirectory(parentFD: parentFD, name: name)
        defer { close(fd) }
        let files = try names(in: fd)
        for file in files {
            guard file.hasSuffix(".wav"), UUID(uuidString: String(file.dropLast(4))) != nil else { throw TemporaryAudioError.unsafePath }
            var info = stat()
            guard fstatat(fd, file, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw TemporaryAudioError.fileSystem(errno) }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1 else { throw TemporaryAudioError.unsafePath }
        }
        // unlinkat removes a directory entry without following a symlink even if it changes after validation.
        for file in files {
            if unlinkat(fd, file, 0) != 0 && errno != ENOENT { throw TemporaryAudioError.fileSystem(errno) }
        }
        var opened = stat(), current = stat()
        guard fstat(fd, &opened) == 0, fstatat(parentFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              Self.ownedDirectory(current), opened.st_ino == current.st_ino, opened.st_dev == current.st_dev else {
            throw TemporaryAudioError.unsafePath
        }
        guard unlinkat(parentFD, name, AT_REMOVEDIR) == 0 else { throw TemporaryAudioError.fileSystem(errno) }
    }

    private func openOwnedDirectory(parentFD: Int32, name: String) throws -> Int32 {
        var info = stat()
        guard fstatat(parentFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw TemporaryAudioError.fileSystem(errno) }
        guard Self.ownedDirectory(info) else { throw TemporaryAudioError.unsafePath }
        let fd = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw TemporaryAudioError.fileSystem(errno) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, Self.ownedDirectory(opened), opened.st_ino == info.st_ino, opened.st_dev == info.st_dev else {
            close(fd); throw TemporaryAudioError.unsafePath
        }
        return fd
    }

    private static func ownedDirectory(_ info: stat) -> Bool { info.st_mode & S_IFMT == S_IFDIR && info.st_uid == geteuid() }

    private static func processID(from name: String) -> pid_t? {
        guard name.hasPrefix("session-") else { return nil }
        let parts = name.dropFirst(8).split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let pid = pid_t(parts[0]), pid > 0, String(pid) == parts[0], UUID(uuidString: String(parts[1])) != nil else { return nil }
        return pid
    }

    private func names(in fd: Int32) throws -> [String] {
        let copy = dup(fd)
        guard copy >= 0 else { throw TemporaryAudioError.fileSystem(errno) }
        guard let stream = fdopendir(copy) else { let failure = errno; close(copy); throw TemporaryAudioError.fileSystem(failure) }
        defer { closedir(stream) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw TemporaryAudioError.fileSystem(errno) }
                return result
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name != "." && name != ".." { result.append(name) }
        }
    }
}
