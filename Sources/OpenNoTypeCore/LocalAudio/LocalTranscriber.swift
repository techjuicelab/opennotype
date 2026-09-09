import Foundation
@preconcurrency import WhisperKit

public enum LocalModelState: Equatable, Sendable {
    case notPrepared
    case downloading(Double)
    case loading
    case ready
    case failed(String)

    public var label: String {
        switch self {
        case .notPrepared: "모델 준비 필요"
        case .downloading(let fraction): "모델 다운로드 \(Int(min(1, max(0, fraction)) * 100))%"
        case .loading: "기기에 맞게 모델 준비 중"
        case .ready: "사용 가능"
        case .failed(let message): message
        }
    }
}

public enum LocalSpeechModel: String, CaseIterable, Identifiable, Sendable {
    case largeV3, small, base
    public var id: String { rawValue }
    public var variant: String {
        switch self {
        case .largeV3: "openai_whisper-large-v3-v20240930_626MB"
        case .small: "openai_whisper-small"
        case .base: "openai_whisper-base"
        }
    }
    public var displayName: String {
        switch self {
        case .largeV3: "Whisper Large v3 · 약 627 MB"
        case .small: "Whisper Small · 약 487 MB"
        case .base: "Whisper Base · 약 147 MB"
        }
    }
    /// Model weights only. Tokenizer and Core ML caches require additional space.
    public var downloadBytes: Int64 {
        switch self {
        case .largeV3: 626_718_238
        case .small: 486_487_465
        case .base: 146_719_453
        }
    }
}

public enum LocalAudioError: LocalizedError, Sendable {
    case notPrepared, busy, emptyAudio, tooLong, noSpeech
    case missingSpeakerProfile, invalidSpeakerProfile, enrollmentNeedsSingleSpeaker
    case enrollmentDuration, noMatchingSpeaker, rawRecordingDeletionFailed

    public var errorDescription: String? {
        switch self {
        case .notPrepared: "설정에서 로컬 모델을 다운로드하고 준비해 주세요."
        case .busy: "로컬 음성 엔진이 처리 중입니다. 완료 후 다시 시도해 주세요."
        case .emptyAudio: "녹음에 처리할 음성이 없습니다."
        case .tooLong: "로컬 음성 인식은 최대 9분 녹음을 지원합니다."
        case .noSpeech: "인식된 음성이 없습니다. 원음을 확인한 뒤 다시 시도해 주세요."
        case .missingSpeakerProfile: "먼저 내 목소리를 등록해 주세요."
        case .invalidSpeakerProfile: "저장된 목소리 특징이 현재 모델과 맞지 않습니다. 다시 등록해 주세요."
        case .enrollmentNeedsSingleSpeaker: "등록 녹음에서 한 사람의 충분한 음성을 확인하지 못했습니다. 조용한 곳에서 혼자 말해 주세요."
        case .enrollmentDuration: "목소리 등록은 5초 이상 30초 이하로 녹음해 주세요."
        case .noMatchingSpeaker: "등록된 목소리와 충분히 일치하는 단독 발화 구간을 찾지 못했습니다. 필터를 끄거나 다시 녹음해 주세요."
        case .rawRecordingDeletionFailed: "등록 원음을 삭제하지 못했습니다. 로컬 저장소 상태를 확인해 주세요."
        }
    }
}

/// All audio inference happens on this device. Only public model files are downloaded.
public actor LocalTranscriber {
    public let model: LocalSpeechModel
    public private(set) var state: LocalModelState = .notPrepared
    private let cacheDirectory: URL
    private var engine: WhisperKit?
    private var isWorking = false

    public init(model: LocalSpeechModel = .largeV3, cacheDirectory: URL? = nil) {
        self.model = model
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory
    }

    public static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenNoType/Models/WhisperKit", isDirectory: true)
    }

    /// Explicit user action: downloads weights/tokenizer when missing, then loads Core ML.
    public func prepare(progress: (@Sendable (LocalModelState) -> Void)? = nil) async throws {
        if engine != nil { state = .ready; progress?(.ready); return }
        guard !isWorking else { throw LocalAudioError.busy }
        isWorking = true
        defer { isWorking = false }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            state = .downloading(0); progress?(state)
            let folder = try await WhisperKit.download(
                variant: model.variant,
                downloadBase: cacheDirectory,
                progressCallback: { value in progress?(.downloading(value.fractionCompleted)) }
            )
            try Task.checkCancellation()
            state = .loading; progress?(state)
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: cacheDirectory,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let loaded = try await WhisperKit(config)
            try Task.checkCancellation()
            engine = loaded
            state = .ready; progress?(state)
        } catch {
            state = .failed("로컬 모델 준비 실패: \(error.localizedDescription)")
            progress?(state)
            throw error
        }
    }

    public func transcribe(audioURL: URL, dictionary: [DictionaryEntry], writingProfile: WritingProfile = .init()) async throws -> String {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        return try await transcribe(samples: samples, dictionary: dictionary, writingProfile: writingProfile)
    }

    /// Accepts mono 16 kHz PCM, including output from the optional speaker filter.
    public func transcribe(samples: [Float], dictionary: [DictionaryEntry], writingProfile: WritingProfile = .init()) async throws -> String {
        guard let engine else { throw LocalAudioError.notPrepared }
        guard !isWorking else { throw LocalAudioError.busy }
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw LocalAudioError.emptyAudio }
        guard samples.count <= 16_000 * 540 else { throw LocalAudioError.tooLong }
        isWorking = true
        defer { isWorking = false }
        try Task.checkCancellation()
        let hint = TranscriptionHints.make(dictionary: dictionary, profile: writingProfile).localPrompt
        let prompt = hint.isEmpty ? nil : engine.tokenizer.map {
            Self.vocabularyTokens($0.encode(text: hint), specialTokenBegin: $0.specialTokens.specialTokenBegin)
        }
        let options = DecodingOptions(
            task: .transcribe,
            language: nil,
            temperature: 0,
            detectLanguage: true,
            skipSpecialTokens: true,
            promptTokens: prompt,
            suppressBlank: true,
            concurrentWorkerCount: 2
        )
        let results: [TranscriptionResult] = try await engine.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalAudioError.noSpeech }
        return text
    }

    /// Keep the vocabulary prompt free of Whisper control markers. SDK 1.1.0 also fixes
    /// premature EOT predictions during prompt prefill (upstream pull request #514).
    static func vocabularyTokens(_ tokens: [Int], specialTokenBegin: Int) -> [Int] {
        Array(tokens.filter { $0 >= 0 && $0 < specialTokenBegin }.prefix(192))
    }
}
