import Darwin
import Foundation
import XCTest
@testable import OpenNoType

final class TemporaryAudioFilesTests: XCTestCase {
    private var container: URL!
    private var root: URL { container.appendingPathComponent("audio", isDirectory: true) }

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("OpenNoTypeTemporaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: container.path) { try FileManager.default.removeItem(at: container) }
    }

    private func sessionName(pid: Int32 = 42) -> String { "session-\(pid)-\(UUID().uuidString)" }

    private func makeCandidate(name: String? = nil, fileName: String? = nil) throws -> (directory: URL, audio: URL) {
        let directory = root.appendingPathComponent(name ?? sessionName(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let audio = directory.appendingPathComponent(fileName ?? UUID().uuidString + ".wav")
        try Data("synthetic temporary audio".utf8).write(to: audio)
        return (directory, audio)
    }

    func testReservedWAVAndSessionArePrivateAndUnique() throws {
        let subject = TemporaryAudioSession(rootDirectory: root)
        let first = try subject.makeURL()
        let second = try subject.makeURL()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
        XCTAssertTrue(first.deletingLastPathComponent().lastPathComponent.hasPrefix("session-\(getpid())-"))
        XCTAssertEqual(try Data(contentsOf: first).count, 0)
        for (path, mode) in [(root, 0o700), (first.deletingLastPathComponent(), 0o700), (first, 0o600)] {
            let actual = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(actual?.intValue, mode)
        }
    }

    func testDirectWritePreservesPrivateWAVWithoutAuxiliaryFilesAndAllowsDeadSessionCleanup() throws {
        let writer = TemporaryAudioSession(rootDirectory: root, processID: 42, processIsAlive: { _ in false })
        let audio = try writer.makeURL()
        let directory = audio.deletingLastPathComponent()
        let payload = Data(repeating: 0xA5, count: 256 * 1024)

        // Retry audio is written directly into its reserved file; atomic writes leave auxiliary files on a crash.
        try payload.write(to: audio)

        XCTAssertEqual(try Data(contentsOf: audio), payload)
        let permissions = try FileManager.default.attributesOfItem(atPath: audio.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [audio.lastPathComponent])

        let nextProcess = TemporaryAudioSession(rootDirectory: root, processID: 43, processIsAlive: { _ in false })
        try nextProcess.cleanupDeadSessions()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testDeadSessionIsCleanedButLiveAndCurrentSessionsRemain() throws {
        let dead = try makeCandidate(name: sessionName(pid: 42))
        let live = try makeCandidate(name: sessionName(pid: 43))
        let subject = TemporaryAudioSession(rootDirectory: root, processID: 44, processIsAlive: { $0 == 43 })
        let current = try subject.makeURL()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dead.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.audio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        try subject.cleanupDeadSessions()
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
    }

    func testRealCurrentPIDIsNeverTreatedAsDead() throws {
        let live = try makeCandidate(name: sessionName(pid: getpid()))
        let subject = TemporaryAudioSession(rootDirectory: root)
        _ = try subject.makeURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.audio.path))
    }

    func testCleanupCurrentSessionDoesNotRemoveOtherSessionsOrRootFiles() throws {
        let subject = TemporaryAudioSession(rootDirectory: root, processIsAlive: { _ in true })
        let current = try subject.makeURL()
        let other = try makeCandidate()
        let legacy = root.appendingPathComponent(UUID().uuidString + ".wav")
        try Data([1]).write(to: legacy)
        try subject.cleanupCurrentSession()
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.audio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        try subject.cleanupCurrentSession()
    }

    func testUnknownAndMalformedFoldersAreNeverDeleted() throws {
        let unrelated = try makeCandidate(name: "unrelated")
        let malformed = try makeCandidate(name: "session-42-not-a-uuid")
        let zeroPID = try makeCandidate(name: sessionName(pid: 0))
        let subject = TemporaryAudioSession(rootDirectory: root, processIsAlive: { _ in false })
        _ = try subject.makeURL()
        for url in [unrelated.audio, malformed.audio, zeroPID.audio] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testUnknownFilePreventsDeletingEntireDeadSession() throws {
        let candidate = try makeCandidate(fileName: "unrelated.txt")
        let audio = candidate.directory.appendingPathComponent(UUID().uuidString + ".wav")
        try Data([1, 2]).write(to: audio)
        let subject = TemporaryAudioSession(rootDirectory: root, processIsAlive: { _ in false })
        _ = try subject.makeURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.audio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testSymlinkRootIsRejectedWithoutTouchingDestination() throws {
        let outside = container.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
        let subject = TemporaryAudioSession(rootDirectory: root)
        XCTAssertThrowsError(try subject.makeURL()) { error in XCTAssertEqual(error as? TemporaryAudioError, .unsafePath) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testSymlinkSessionIsNotFollowedOrDeleted() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = container.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let audio = outside.appendingPathComponent(UUID().uuidString + ".wav")
        try Data([2, 4]).write(to: audio)
        let linked = root.appendingPathComponent(sessionName())
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        let subject = TemporaryAudioSession(rootDirectory: root, processIsAlive: { _ in false })
        _ = try subject.makeURL()
        XCTAssertEqual(try Data(contentsOf: audio), Data([2, 4]))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path), outside.path)
    }

    func testSymlinkAudioLeavesWholeSessionUntouched() throws {
        let candidate = try makeCandidate()
        let outside = container.appendingPathComponent("outside.txt")
        try Data([5, 6]).write(to: outside)
        let linked = candidate.directory.appendingPathComponent(UUID().uuidString + ".wav")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        let subject = TemporaryAudioSession(rootDirectory: root, processIsAlive: { _ in false })
        _ = try subject.makeURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.audio.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data([5, 6]))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path), outside.path)
    }

    func testCurrentSessionCleanupRefusesSymlinkAudio() throws {
        let subject = TemporaryAudioSession(rootDirectory: root)
        let current = try subject.makeURL()
        let outside = container.appendingPathComponent("outside.txt")
        try Data([3]).write(to: outside)
        let linked = current.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".wav")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        XCTAssertThrowsError(try subject.cleanupCurrentSession()) { error in XCTAssertEqual(error as? TemporaryAudioError, .unsafePath) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data([3]))
    }

    func testHardLinkedAudioIsNotDeleted() throws {
        let candidate = try makeCandidate()
        let outside = container.appendingPathComponent("outside.wav")
        try FileManager.default.linkItem(at: candidate.audio, to: outside)
        let subject = TemporaryAudioSession(rootDirectory: root, processIsAlive: { _ in false })
        _ = try subject.makeURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.audio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
