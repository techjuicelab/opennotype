import Foundation
@preconcurrency import FluidAudio
@preconcurrency import WhisperKit

public struct SpeakerVoiceProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var embedding: [Float]
    public var modelIdentifier: String

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), embedding: [Float], modelIdentifier: String) {
        self.id = id; self.name = name; self.createdAt = createdAt
        self.embedding = embedding; self.modelIdentifier = modelIdentifier
    }
}

/// Implement with the application's encrypted store. Never persist enrollment audio here.
public protocol SpeakerProfileStoring: Sendable {
    func loadSpeakerProfile() async throws -> SpeakerVoiceProfile?
    func saveSpeakerProfile(_ profile: SpeakerVoiceProfile) async throws
    func deleteSpeakerProfile() async throws
}

public struct SpeakerFilterResult: Sendable {
    public let samples: [Float]
    public let acceptedDuration: Double
    public let discardedDuration: Double
    public let warning: String
}

/// Experimental neural speaker matching; this is not source separation or authentication.
public actor LocalSpeakerRecognizer {
    public static let modelIdentifier = "FluidAudio-0.12.6/pyannote_segmentation+wespeaker_v2"
    public static let limitation = "실험 기능: 등록된 목소리와 비슷한 단독 발화 구간만 남깁니다. 겹쳐 말하는 음성을 분리하지 않으며, TV·타인의 목소리가 남거나 내 말이 빠질 수 있습니다."
    public private(set) var state: LocalModelState = .notPrepared
    private let profileStore: any SpeakerProfileStoring
    private var diarizer: DiarizerManager?
    private var isWorking = false

    public init(profileStore: any SpeakerProfileStoring) { self.profileStore = profileStore }

    public func prepare(progress: (@Sendable (LocalModelState) -> Void)? = nil) async throws {
        if diarizer != nil { state = .ready; progress?(.ready); return }
        guard !isWorking else { throw LocalAudioError.busy }
        isWorking = true
        defer { isWorking = false }
        do {
            state = .downloading(0); progress?(state)
            let models = try await DiarizerModels.downloadIfNeeded(progressHandler: { value in
                progress?(.downloading(value.fractionCompleted))
            })
            try Task.checkCancellation()
            state = .loading; progress?(state)
            let manager = DiarizerManager(config: DiarizerConfig(
                clusteringThreshold: 0.65,
                minSpeechDuration: 0.7,
                minEmbeddingUpdateDuration: 2,
                debugMode: false,
                chunkDuration: 10,
                chunkOverlap: 0
            ))
            manager.initialize(models: models)
            diarizer = manager
            state = .ready; progress?(state)
        } catch {
            state = .failed("화자 모델 준비 실패: \(error.localizedDescription)")
            progress?(state)
            throw error
        }
    }

    public func hasProfile() async throws -> Bool {
        guard let profile = try await profileStore.loadSpeakerProfile() else { return false }
        return Self.isValid(profile)
    }

    public func deleteProfile() async throws { try await profileStore.deleteSpeakerProfile() }

    /// Consumes a dedicated, disposable enrollment file; removes it even when enrollment fails.
    /// The caller must not pass an existing personal recording that it intends to retain.
    public func enroll(consumingRecordingAt audioURL: URL, name: String = "내 목소리") async throws -> SpeakerVoiceProfile {
        do {
            let profile = try await makeProfile(audioURL: audioURL, name: name)
            try removeEnrollmentRecording(audioURL)
            try await profileStore.saveSpeakerProfile(profile)
            return profile
        } catch {
            try removeEnrollmentRecording(audioURL)
            throw error
        }
    }

    private func makeProfile(audioURL: URL, name: String) async throws -> SpeakerVoiceProfile {
        guard let diarizer else { throw LocalAudioError.notPrepared }
        guard !isWorking else { throw LocalAudioError.busy }
        isWorking = true
        defer { isWorking = false }
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        guard (80_000...480_000).contains(samples.count), samples.allSatisfy(\.isFinite) else {
            throw LocalAudioError.enrollmentDuration
        }
        try Task.checkCancellation()
        diarizer.speakerManager.reset()
        let analysis = try diarizer.performCompleteDiarization(samples)
        let segments = analysis.segments
        guard Set(segments.map(\.speakerId)).count == 1,
              segments.reduce(0.0, { $0 + Double($1.durationSeconds) }) >= 4 else {
            throw LocalAudioError.enrollmentNeedsSingleSpeaker
        }
        // Embed up to three separate ten-second windows instead of silently truncating a long clip.
        var embeddings = [[Float]]()
        for offset in stride(from: 0, to: samples.count, by: 160_000) {
            let end = min(offset + 160_000, samples.count)
            guard end - offset >= 80_000 else { continue }
            let embedding = try diarizer.extractSpeakerEmbedding(from: Array(samples[offset..<end]))
            if let normalized = Self.normalized(embedding) { embeddings.append(normalized) }
        }
        guard !embeddings.isEmpty else { throw LocalAudioError.invalidSpeakerProfile }
        var mean = [Float](repeating: 0, count: 256)
        for vector in embeddings { for index in 0..<256 { mean[index] += vector[index] } }
        guard let normalized = Self.normalized(mean) else { throw LocalAudioError.invalidSpeakerProfile }
        try Task.checkCancellation()
        return SpeakerVoiceProfile(name: name, embedding: normalized, modelIdentifier: Self.modelIdentifier)
    }

    public func filter(audioURL: URL) async throws -> SpeakerFilterResult {
        guard let diarizer else { throw LocalAudioError.notPrepared }
        guard !isWorking else { throw LocalAudioError.busy }
        isWorking = true
        defer { isWorking = false }
        guard let profile = try await profileStore.loadSpeakerProfile() else { throw LocalAudioError.missingSpeakerProfile }
        guard Self.isValid(profile) else { throw LocalAudioError.invalidSpeakerProfile }
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw LocalAudioError.emptyAudio }
        guard samples.count <= 16_000 * 540 else { throw LocalAudioError.tooLong }
        try Task.checkCancellation()
        diarizer.speakerManager.reset()
        let result = try diarizer.performCompleteDiarization(samples)
        let candidates = result.segments.map {
            SpeakerSegmentCandidate(speakerID: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), embedding: $0.embedding)
        }
        let accepted = Self.acceptedRanges(candidates, profile: profile, audioDuration: Double(samples.count) / 16_000)
        guard !accepted.isEmpty else { throw LocalAudioError.noMatchingSpeaker }
        var output = [Float]()
        var acceptedSamples = 0
        var previousUpper = 0
        for range in accepted {
            let lower = max(0, min(samples.count, Int(ceil(range.lowerBound * 16_000))))
            let upper = max(lower, min(samples.count, Int(floor(range.upperBound * 16_000))))
            guard upper > lower else { continue }
            if !output.isEmpty {
                output.append(contentsOf: repeatElement(0, count: min(3_200, max(0, lower - previousUpper))))
            }
            output.append(contentsOf: samples[lower..<upper])
            acceptedSamples += upper - lower
            previousUpper = upper
        }
        guard acceptedSamples >= 8_000 else { throw LocalAudioError.noMatchingSpeaker }
        try Task.checkCancellation()
        return SpeakerFilterResult(
            samples: output,
            acceptedDuration: Double(acceptedSamples) / 16_000,
            discardedDuration: Double(samples.count - acceptedSamples) / 16_000,
            warning: Self.limitation
        )
    }

    private func removeEnrollmentRecording(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) }
            catch { throw LocalAudioError.rawRecordingDeletionFailed }
        }
    }

    static func isValid(_ profile: SpeakerVoiceProfile) -> Bool {
        profile.modelIdentifier == modelIdentifier && normalized(profile.embedding) != nil
    }

    static func normalized(_ vector: [Float]) -> [Float]? {
        guard vector.count == 256, vector.allSatisfy(\.isFinite) else { return nil }
        let magnitude = sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard magnitude.isFinite, magnitude > 1e-8 else { return nil }
        return vector.map { Float(Double($0) / magnitude) }
    }

    /// Conservative policy: discard the entire candidate if another speaker overlaps it.
    /// The threshold is a provisional product setting, not a calibrated accuracy claim.
    static func acceptedRanges(_ segments: [SpeakerSegmentCandidate], profile: SpeakerVoiceProfile, audioDuration: Double) -> [Range<Double>] {
        guard let reference = normalized(profile.embedding), audioDuration.isFinite, audioDuration > 0 else { return [] }
        let valid = segments.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= audioDuration + 0.1 }
        let accepted = valid.filter { candidate in
            guard let vector = normalized(candidate.embedding) else { return false }
            let similarity = zip(reference, vector).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            guard similarity >= 0.65 else { return false }
            return !valid.contains { other in
                other.speakerID != candidate.speakerID && other.start < candidate.end && other.end > candidate.start
            }
        }.map { $0.start..<min($0.end, audioDuration) }.sorted { $0.lowerBound < $1.lowerBound }
        var merged = [Range<Double>]()
        for range in accepted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else { merged.append(range) }
        }
        return merged
    }
}

struct SpeakerSegmentCandidate: Sendable {
    var speakerID: String
    var start: Double
    var end: Double
    var embedding: [Float]
}
