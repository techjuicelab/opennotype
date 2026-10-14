import Foundation

public enum LocalModelUnloadPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case never, afterFiveMinutes, afterFifteenMinutes, afterThirtyMinutes

    public var id: String { rawValue }
    public var interval: TimeInterval? {
        switch self {
        case .never: nil
        case .afterFiveMinutes: 300
        case .afterFifteenMinutes: 900
        case .afterThirtyMinutes: 1_800
        }
    }

    public var displayName: String {
        switch self {
        case .never: L("계속 메모리에 유지", "Keep in memory")
        case .afterFiveMinutes: L("5분 미사용 후 해제", "Unload after 5 idle minutes")
        case .afterFifteenMinutes: L("15분 미사용 후 해제", "Unload after 15 idle minutes")
        case .afterThirtyMinutes: L("30분 미사용 후 해제", "Unload after 30 idle minutes")
        }
    }

    func shouldUnload(lastUse: Date?, now: Date) -> Bool {
        guard let interval, let lastUse else { return false }
        return now.timeIntervalSince(lastUse) >= interval
    }
}

public struct LocalModelCacheStatus: Equatable, Sendable, Identifiable {
    public var id: String { model.id }
    public let model: LocalSpeechModel
    public let isDownloaded: Bool
    public let storedBytes: Int64
    public let isLoaded: Bool
}

/// Preview re-runs Whisper on a bounded recent window; it is not a streaming decoder.
/// It never becomes the final transcript, which always uses the complete recording.
public enum LocalPreviewPolicy {
    public static let sampleRate = 16_000
    public static let minimumSeconds = 2
    public static let maximumSeconds = 12
    public static let refreshInterval: TimeInterval = 3

    public static func recentWindow(_ samples: [Float]) -> [Float]? {
        guard samples.count >= sampleRate * minimumSeconds else { return nil }
        let window = samples.suffix(sampleRate * maximumSeconds)
        guard window.allSatisfy(\.isFinite) else { return nil }
        return Array(window)
    }
}

enum LocalModelCache {
    static func modelFolder(_ model: LocalSpeechModel, in directory: URL) -> URL {
        directory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.variant)")
    }

    static func tokenizerFolder(_ model: LocalSpeechModel, in directory: URL) -> URL {
        let name: String
        switch model {
        case .largeV3: name = "whisper-large-v3"
        case .small: name = "whisper-small"
        case .base: name = "whisper-base"
        }
        return directory.appendingPathComponent("models/openai/\(name)")
    }

    /// Never delete the cache root or legacy shared tokenizer files at that root.
    /// Every path component must remain inside the dedicated cache without symlinks.
    static func removableFolders(_ model: LocalSpeechModel, in directory: URL) throws -> [URL] {
        let root = directory.standardizedFileURL
        let rootValues = try? root.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootValues?.isSymbolicLink != true else { throw LocalAudioError.unsafeModelCache }
        let folders = [modelFolder(model, in: root), tokenizerFolder(model, in: root)]
        for folder in folders {
            var component = folder
            while component.path != root.path {
                guard component.path.hasPrefix(root.path + "/") else { throw LocalAudioError.unsafeModelCache }
                let values = try? component.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values?.isSymbolicLink != true else { throw LocalAudioError.unsafeModelCache }
                component.deleteLastPathComponent()
            }
        }
        return folders
    }

    static func storedBytes(_ model: LocalSpeechModel, in directory: URL) -> Int64 {
        guard let folders = try? removableFolders(model, in: directory) else { return 0 }
        return folders.reduce(0) { total, folder in
            guard let enumerator = FileManager.default.enumerator(at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return total }
            var bytes = total
            for case let file as URL in enumerator {
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            }
            return bytes
        }
    }
}
