import Foundation
import NaturalLanguage
@preconcurrency import WhisperKit

public enum LocalModelState: Equatable, Sendable {
    case notPrepared
    case downloading(Double)
    case loading
    case ready
    case failed(String)

    public var label: String {
        switch self {
        case .notPrepared: L("모델 준비 필요", "Model setup required")
        case .downloading(let fraction): L("모델 다운로드 \(Int(min(1, max(0, fraction)) * 100))%", "Downloading model \(Int(min(1, max(0, fraction)) * 100))%")
        case .loading: L("기기에 맞게 모델 준비 중", "Preparing model for this Mac")
        case .ready: L("사용 가능", "Ready")
        case .failed(let message): message
        }
    }
}

public enum LocalSpeechModel: String, Codable, CaseIterable, Identifiable, Sendable {
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
        case .largeV3: L("Whisper Large v3 · 약 627 MB", "Whisper Large v3 · About 627 MB")
        case .small: L("Whisper Small · 약 487 MB", "Whisper Small · About 487 MB")
        case .base: L("Whisper Base · 약 147 MB", "Whisper Base · About 147 MB")
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
    case unsafeModelCache
    case missingSpeakerProfile, invalidSpeakerProfile, enrollmentNeedsSingleSpeaker
    case enrollmentDuration, noMatchingSpeaker, rawRecordingDeletionFailed

    public var errorDescription: String? {
        switch self {
        case .notPrepared: L("설정에서 로컬 모델을 다운로드하고 준비해 주세요.", "Download and prepare the local model in Settings.")
        case .busy: L("로컬 음성 엔진이 처리 중입니다. 완료 후 다시 시도해 주세요.", "The local speech engine is busy. Try again when it finishes.")
        case .emptyAudio: L("녹음에 처리할 음성이 없습니다.", "The recording contains no audio to process.")
        case .tooLong: L("로컬 음성 인식은 최대 9분 녹음을 지원합니다.", "Local transcription supports recordings up to 9 minutes.")
        case .noSpeech: L("인식된 음성이 없습니다. 원음을 확인한 뒤 다시 시도해 주세요.", "No speech was recognized. Check the recording and try again.")
        case .unsafeModelCache: L("모델 저장 경로에 심볼릭 링크가 있어 삭제하지 않았습니다.", "The model cache contains a symbolic link and was not deleted.")
        case .missingSpeakerProfile: L("먼저 내 목소리를 등록해 주세요.", "Register your voice first.")
        case .invalidSpeakerProfile: L("저장된 목소리 특징이 현재 모델과 맞지 않습니다. 다시 등록해 주세요.", "The saved voice profile is incompatible with the current model. Register your voice again.")
        case .enrollmentNeedsSingleSpeaker: L("등록 녹음에서 한 사람의 충분한 음성을 확인하지 못했습니다. 조용한 곳에서 혼자 말해 주세요.", "The enrollment recording did not contain enough speech from one person. Record yourself alone in a quiet place.")
        case .enrollmentDuration: L("목소리 등록은 5초 이상 30초 이하로 녹음해 주세요.", "Record 5 to 30 seconds to register your voice.")
        case .noMatchingSpeaker: L("등록된 목소리와 충분히 일치하는 단독 발화 구간을 찾지 못했습니다. 필터를 끄거나 다시 녹음해 주세요.", "No solo speech segments matched your registered voice closely enough. Turn off the filter or record again.")
        case .rawRecordingDeletionFailed: L("등록 원음을 삭제하지 못했습니다. 로컬 저장소 상태를 확인해 주세요.", "The enrollment recording could not be deleted. Check local storage.")
        }
    }
}

/// All audio inference happens on this device. Only public model files are downloaded.
public actor LocalTranscriber {
    public private(set) var model: LocalSpeechModel
    public private(set) var state: LocalModelState = .notPrepared
    private let cacheDirectory: URL
    private var engine: WhisperKit?
    private enum Work: Equatable { case preparation, inference, maintenance, preview(UUID) }
    private var work: Work?
    private var isWorking: Bool { work != nil }
    private var lastUse: Date?
    private var pendingFinalTranscriptions = 0
    private var previewTask: Task<String?, Error>?
    private var previewCancellation: LocalPreviewCancellation?

    public init(model: LocalSpeechModel = .largeV3, cacheDirectory: URL? = nil) {
        self.model = model
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory
    }

    /// Internal seam for deterministic engine arbitration tests without models or network.
    init(preparedEngine: WhisperKit, model: LocalSpeechModel = .largeV3, cacheDirectory: URL) {
        self.model = model
        self.cacheDirectory = cacheDirectory
        self.engine = preparedEngine
        self.state = .ready
        self.lastUse = Date()
    }

    public static var defaultCacheDirectory: URL {
        defaultCacheDirectory(for: .current)
    }

    static func defaultCacheDirectory(for identity: AppIdentity) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(identity.supportDirectoryName)/Models/WhisperKit", isDirectory: true)
    }

    /// Model selection never downloads. Preparation remains an explicit separate action.
    public func selectModel(_ selected: LocalSpeechModel) async throws {
        guard !isWorking, pendingFinalTranscriptions == 0 else { throw LocalAudioError.busy }
        guard model != selected else { return }
        work = .maintenance
        defer { work = nil }
        await engine?.unloadModels()
        engine = nil
        model = selected
        lastUse = nil
        state = .notPrepared
    }

    public func cacheStatuses() -> [LocalModelCacheStatus] {
        LocalSpeechModel.allCases.map { candidate in
            LocalModelCacheStatus(model: candidate,
                isDownloaded: Self.cachedFiles(for: candidate, in: cacheDirectory) != nil,
                storedBytes: LocalModelCache.storedBytes(candidate, in: cacheDirectory),
                isLoaded: candidate == model && engine != nil)
        }
    }

    /// Releases only in-memory Core ML models. Downloaded files and recordings remain intact.
    public func unloadModel() async throws {
        guard !isWorking, pendingFinalTranscriptions == 0 else { throw LocalAudioError.busy }
        work = .maintenance
        defer { work = nil }
        await engine?.unloadModels()
        engine = nil
        lastUse = nil
        state = .notPrepared
    }

    /// The app calls this on its idle timer. Active preparation, preview, and final inference
    /// are never interrupted to recover memory.
    @discardableResult
    public func unloadIfIdle(policy: LocalModelUnloadPolicy, now: Date = Date()) async throws -> Bool {
        guard engine != nil, policy.shouldUnload(lastUse: lastUse, now: now) else { return false }
        guard !isWorking, pendingFinalTranscriptions == 0 else { return false }
        try await unloadModel()
        return true
    }

    /// Deletes only the selected model's dedicated weights and tokenizer directories.
    /// Legacy shared tokenizer files, other models, and user recordings are preserved.
    public func deleteSelectedModelCache() async throws {
        guard !isWorking, pendingFinalTranscriptions == 0 else { throw LocalAudioError.busy }
        let folders = try LocalModelCache.removableFolders(model, in: cacheDirectory)
        work = .maintenance
        defer { work = nil }
        await engine?.unloadModels()
        engine = nil
        lastUse = nil
        state = .notPrepared
        for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Loads only an existing model and tokenizer. WhisperKit's `download: false` does
    /// not prevent its tokenizer loader from falling back to the Hub after a local error.
    /// Parse the tokenizer through the local-only API and inject it before loading models.
    public func prepareCached(progress: (@Sendable (LocalModelState) -> Void)? = nil) async throws -> Bool {
        guard !isWorking, pendingFinalTranscriptions == 0 else { throw LocalAudioError.busy }
        if engine != nil { state = .ready; lastUse = Date(); progress?(.ready); return true }
        try Task.checkCancellation()
        guard let files = Self.cachedFiles(for: model, in: cacheDirectory) else { return false }
        work = .preparation
        defer { work = nil }
        do {
            state = .loading; progress?(state)
            let tokenizer = try await CachedWhisperTokenizer.load(from: files.tokenizer)
            try Task.checkCancellation()
            let config = WhisperKitConfig(modelFolder: files.model.path, tokenizerFolder: files.tokenizer,
                verbose: false, logLevel: .error, prewarm: false, load: false, download: false)
            let loaded = try await WhisperKit(config)
            loaded.tokenizer = tokenizer
            // Every LocalSpeechModel in this app is multilingual. WhisperKit normally
            // sets this in its downloading tokenizer loader, which this path skips.
            loaded.textDecoder.isModelMultilingual = true
            try await loaded.prewarmModels()
            try Task.checkCancellation()
            try await loaded.loadModels()
            try Task.checkCancellation()
            engine = loaded
            lastUse = Date()
            state = .ready; progress?(state)
            return true
        } catch {
            state = error is CancellationError ? .notPrepared : .failed(L("저장된 로컬 모델 준비 실패: \(error.localizedDescription)", "Could not prepare the saved local model: \(error.localizedDescription)"))
            progress?(state)
            throw error
        }
    }

    static func cachedFiles(for model: LocalSpeechModel, in directory: URL) -> (model: URL, tokenizer: URL)? {
        // Hugging Face's localRepoLocation is downloadBase/models/<repository id>.
        let folder = LocalModelCache.modelFolder(model, in: directory)
        guard ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy({ name in
            FileManager.default.isReadableFile(atPath: folder.appendingPathComponent("\(name).mlmodelc/coremldata.bin").path)
                || FileManager.default.isReadableFile(atPath: folder.appendingPathComponent("\(name).mlpackage/Manifest.json").path)
        }) else { return nil }
        let tokenizerModel: String
        switch model { case .largeV3: tokenizerModel = "whisper-large-v3"; case .small: tokenizerModel = "whisper-small"; case .base: tokenizerModel = "whisper-base" }
        let tokenizerPaths = [directory.appendingPathComponent("models/openai/\(tokenizerModel)"), directory, folder,
            folder.appendingPathComponent("models/openai/\(tokenizerModel)")]
        guard let tokenizer = tokenizerPaths.first(where: { candidate in
            ["tokenizer.json", "tokenizer_config.json"].allSatisfy {
                FileManager.default.isReadableFile(atPath: candidate.appendingPathComponent($0).path)
            }
        }) else { return nil }
        return (folder, tokenizer)
    }

    /// Explicit user action: downloads weights/tokenizer when missing, then loads Core ML.
    public func prepare(progress: (@Sendable (LocalModelState) -> Void)? = nil) async throws {
        guard !isWorking, pendingFinalTranscriptions == 0 else { throw LocalAudioError.busy }
        if engine != nil { state = .ready; lastUse = Date(); progress?(.ready); return }
        work = .preparation
        defer { work = nil }
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
            lastUse = Date()
            state = .ready; progress?(state)
        } catch {
            state = error is CancellationError ? .notPrepared : .failed(L("로컬 모델 준비 실패: \(error.localizedDescription)", "Could not prepare the local model: \(error.localizedDescription)"))
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
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw LocalAudioError.emptyAudio }
        guard samples.count <= 16_000 * 540 else { throw LocalAudioError.tooLong }
        // Final inference takes priority over an in-flight speculative preview. Reserve
        // that priority across the await so another preview cannot jump ahead of it.
        pendingFinalTranscriptions += 1
        defer { pendingFinalTranscriptions -= 1 }
        if case .preview(let id) = work, let task = previewTask {
            previewCancellation?.cancel()
            task.cancel()
            _ = try? await task.value
            finishPreview(id)
        }
        guard !isWorking else { throw LocalAudioError.busy }
        guard let engine else { throw LocalAudioError.notPrepared }
        work = .inference
        defer { work = nil; lastUse = Date() }
        try Task.checkCancellation()
        let text = try await Self.infer(engine: engine, samples: samples, dictionary: dictionary, writingProfile: writingProfile)
        guard !text.isEmpty else { throw LocalAudioError.noSpeech }
        return text
    }

    /// Experimental progressive preview of the most recent 12 seconds of mono 16 kHz
    /// PCM. This does not download, load models, queue work, or replace final transcription.
    /// Busy engines and insufficient audio return nil so recording can continue normally.
    public func preview(samples: [Float], dictionary: [DictionaryEntry], writingProfile: WritingProfile = .init()) async throws -> String? {
        guard !isWorking, pendingFinalTranscriptions == 0, let engine,
              let window = LocalPreviewPolicy.recentWindow(samples) else { return nil }
        try Task.checkCancellation()
        let id = UUID()
        let cancellation = LocalPreviewCancellation()
        work = .preview(id)
        previewCancellation = cancellation
        let task = Task<String?, Error> {
            try Task.checkCancellation()
            let result = try await Self.infer(engine: engine, samples: window, dictionary: dictionary,
                writingProfile: writingProfile, cancellation: cancellation)
            try Task.checkCancellation()
            return result.isEmpty ? nil : result
        }
        previewTask = task
        defer { finishPreview(id) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            cancellation.cancel()
            task.cancel()
        }
    }

    private func finishPreview(_ id: UUID) {
        guard work == .preview(id) else { return }
        work = nil
        previewTask = nil
        previewCancellation = nil
        lastUse = Date()
    }

    private static func infer(engine: WhisperKit, samples: [Float], dictionary: [DictionaryEntry],
                              writingProfile: WritingProfile, cancellation: LocalPreviewCancellation? = nil) async throws -> String {
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
        let results: [TranscriptionResult] = try await engine.transcribe(audioArray: samples, decodeOptions: options,
            callback: { _ in cancellation?.isCancelled == true ? false : nil })
        try Task.checkCancellation()
        if cancellation?.isCancelled == true { throw CancellationError() }
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    /// Keep the vocabulary prompt free of Whisper control markers. SDK 1.1.0 also fixes
    /// premature EOT predictions during prompt prefill (upstream pull request #514).
    static func vocabularyTokens(_ tokens: [Int], specialTokenBegin: Int) -> [Int] {
        Array(tokens.filter { $0 >= 0 && $0 < specialTokenBegin }.prefix(192))
    }
}

private final class LocalPreviewCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}

/// Local-only adapter for WhisperKit 1.1.0. Its public WhisperTokenizerWrapper has an
/// internal initializer, while ModelUtilities.loadTokenizer can start a network fallback.
/// Token mapping and word splitting follow Argmax's MIT-licensed WhisperTokenizerWrapper:
/// https://github.com/argmaxinc/WhisperKit/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Models.swift
/// Copyright 2024 Argmax, Inc. See THIRD_PARTY_NOTICES.md and the bundled MIT notice.
struct CachedWhisperTokenizer: WhisperTokenizer {
    private let tokenizer: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    static func load(from folder: URL) async throws -> CachedWhisperTokenizer {
        // This overload only reads local JSON; unlike from(pretrained:), it never snapshots a repository.
        let tokenizer = try await AutoTokenizerWrapper.from(modelFolder: folder)
        return try CachedWhisperTokenizer(tokenizer: tokenizer)
    }

    private init(tokenizer: TokenizerWrapper) throws {
        func required(_ name: String) throws -> Int {
            guard let value = tokenizer.convertTokenToId(name) else { throw LocalAudioError.notPrepared }
            return value
        }
        let end = try required("<|endoftext|>")
        self.tokenizer = tokenizer
        self.specialTokens = try SpecialTokens(
            endToken: end, englishToken: required("<|en|>"), noSpeechToken: required("<|nospeech|>"),
            noTimestampsToken: required("<|notimestamps|>"), specialTokenBegin: end,
            startOfPreviousToken: required("<|startofprev|>"), startOfTranscriptToken: required("<|startoftranscript|>"),
            timeTokenBegin: required("<|0.00|>"), transcribeToken: required("<|transcribe|>"),
            translateToken: required("<|translate|>"), whitespaceToken: tokenizer.convertTokenToId(" ") ?? 220)
        self.allLanguageTokens = Set(Constants.languages.values.compactMap {
            tokenizer.convertTokenToId("<|\($0)|>")
        }.filter { $0 > end })
    }

    func encode(text: String) -> [Int] { tokenizer.encode(text: text) }
    func decode(tokens: [Int]) -> String { tokenizer.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { tokenizer.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { tokenizer.convertIdToToken(id) }

    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let fullText = decode(tokens: tokenIds)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(decode(tokens: tokenIds.filter { $0 < specialTokens.specialTokenBegin }))
        let languageCode = recognizer.dominantLanguage.flatMap { Locale(identifier: $0.rawValue).language.languageCode?.identifier }
        let usesSpaces = !["zh", "ja", "th", "lo", "my", "yue"].contains(languageCode)
        var words: [String] = [], grouped: [[Int]] = [], pending: [Int] = []
        var decodedOffset = 0
        for token in tokenIds {
            pending.append(token)
            let piece = decode(tokens: pending)
            // A UTF-8 character may span several tokens. Retain its tokens together.
            if piece.contains("\u{fffd}"), !String(fullText.dropFirst(decodedOffset)).hasPrefix(piece) { continue }
            let punctuation = !piece.trimmingCharacters(in: .whitespaces).isEmpty
                && piece.trimmingCharacters(in: .whitespaces).unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
            let startsWord = !usesSpaces || words.isEmpty || (pending.first ?? 0) >= specialTokens.specialTokenBegin
                || piece.hasPrefix(" ") || punctuation
            if startsWord { words.append(piece); grouped.append(pending) }
            else { words[words.count - 1] += piece; grouped[grouped.count - 1].append(contentsOf: pending) }
            decodedOffset += piece.count
            pending = []
        }
        if !pending.isEmpty { words.append(decode(tokens: pending)); grouped.append(pending) }
        return (words, grouped)
    }
}
