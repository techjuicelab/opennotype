import CryptoKit
import Darwin
import Foundation
import WhisperKit

/// A public model repository at one fixed commit.
struct LocalModelPin: Equatable, Sendable {
    let repository: String
    let revision: String
}

/// One pinned file, relative to its repository root.
struct LocalModelFile: Equatable, Sendable {
    let path: String
    let size: Int64
    let sha256: String

    init(_ path: String, _ size: Int64, _ sha256: String) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}

extension LocalModelManifest {
    /// Tokenizer files read by WhisperKit's local tokenizer loader; tokenizer.json is required.
    static let tokenizerFileNames = ["config.json", "tokenizer.json", "tokenizer_config.json"]
    static let speakerFolders = ["pyannote_segmentation.mlmodelc", "wespeaker_v2.mlmodelc"]
}

/// Downloads the files of one pinned repository commit into `downloadBase/models/<repository>`.
protocol LocalModelDownloading: Sendable {
    func download(_ pin: LocalModelPin, matching globs: [String], into downloadBase: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws
}

/// Hugging Face Hub download at the pinned commit, never a moving branch such as main.
struct HubModelDownloader: LocalModelDownloading {
    func download(_ pin: LocalModelPin, matching globs: [String], into downloadBase: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let hub = HubApiWrapper(downloadBase: downloadBase)
        _ = try await hub.snapshot(from: HubApiWrapper.Repo(id: pin.repository), revision: pin.revision,
                                   matching: globs) { value in progress(value.fractionCompleted) }
    }
}

enum LocalModelIntegrity {
    /// The local root of a pinned repository, in the Hub client's layout.
    static func repositoryFolder(_ pin: LocalModelPin, in downloadBase: URL) -> URL {
        downloadBase.appendingPathComponent("models/\(pin.repository)", isDirectory: true)
    }

    /// Checks every pinned file below `root` by size and SHA-256. A file that does not match is
    /// removed when `removingMismatches` is set, so the next preparation downloads it again.
    /// Symbolic links are never followed, removed or accepted.
    static func verify(_ files: [LocalModelFile], in root: URL, removingMismatches: Bool = true) throws {
        var mismatch = false
        for file in files {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(file.path)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { mismatch = true; continue }
            guard info.st_mode & S_IFMT == S_IFREG else { throw LocalAudioError.unsafeModelCache }
            if Int64(info.st_size) == file.size, try sha256(of: url) == file.sha256 { continue }
            mismatch = true
            if removingMismatches { try FileManager.default.removeItem(at: url) }
        }
        if mismatch { throw LocalAudioError.modelIntegrityFailed }
    }

    static func sha256(of url: URL) throws -> String {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw LocalAudioError.modelIntegrityFailed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
