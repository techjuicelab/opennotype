import Foundation
import OpenNoTypeCore

enum DecisionReviewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, observe, protect, repair
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: L("사용 안 함", "Off")
        case .observe: L("입력 후 검토·학습", "Review & learn after typing")
        case .protect: L("입력 전 보호", "Protect before typing")
        case .repair: L("입력 전 교정", "Repair before typing")
        }
    }
}

struct Preferences: Codable {
    var interfaceLanguage: AppLanguage = .english
    var provider: AIProvider = .openAI
    var textProvider: AIProvider? = nil
    var transcriptionModels: [String: String] = [:]
    var textModels: [String: String] = [:]
    var targetLanguage = "English (United States)"
    var useLocalTranscription = false
    var allowedContextApps: Set<String> = []
    var writingProfiles: [String: WritingProfile] = [:]
    var retentionDays = 30
    var historyEnabled = true
    var automaticLearningEnabled = true
    var usageTrackingEnabled = true
    var usageAccountingIncomplete = false
    var decisionReviewMode: DecisionReviewMode = .off
    var decisionProvider: DecisionProvider = .openRouter
    var jevDetailedReviewEnabled = false
    var jevEconomyEnabled = false
    var jevAutomaticImprovementEnabled = false
    var jevClarifyEditsEnabled = false
    var jevReRecognitionEnabled = false
    var jevFeedbackLearningEnabled = false
    var jevNameCatalog: [String] = [] {
        didSet { jevNameCatalog = Self.normalizedJevCatalogNames(jevNameCatalog) }
    }
    /// Empty means reuse the current text model; only explicit alternatives use this setting.
    var improvementModels: [String: String] = [:]
    var speakerFilterEnabled = false
    var hotkeys = HotkeyBinding.defaults
    var launchAtLogin = false
    var appearance = "system"

    private enum CodingKeys: String, CodingKey {
        case interfaceLanguage, improvementModels
        case jevDetailedReviewEnabled, jevEconomyEnabled, jevAutomaticImprovementEnabled
        case jevClarifyEditsEnabled, jevReRecognitionEnabled, jevFeedbackLearningEnabled, jevNameCatalog
        case provider, textProvider, transcriptionModels, textModels, targetLanguage, useLocalTranscription
        case allowedContextApps, writingProfiles, retentionDays, historyEnabled, speakerFilterEnabled
        case hotkeys, launchAtLogin, appearance, automaticLearningEnabled, usageTrackingEnabled, usageAccountingIncomplete, decisionReviewMode, decisionProvider
    }

    init() {}

    /// Every field falls back to its default on its own, so one unreadable value (for example a provider
    /// or profile added by a newer build) never discards the rest of the user's settings.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        // Older versions had a Korean-only interface. A fresh install uses English;
        // an existing preferences record keeps its previous Korean presentation.
        interfaceLanguage = values.contains(.interfaceLanguage)
            ? read(.interfaceLanguage, .english) : .korean
        provider = read(.provider, provider)
        if let raw = try? values.decodeIfPresent(String.self, forKey: .textProvider) {
            textProvider = AIProvider(rawValue: raw)
        }
        transcriptionModels = read(.transcriptionModels, transcriptionModels)
        textModels = read(.textModels, textModels)
        targetLanguage = read(.targetLanguage, targetLanguage)
        useLocalTranscription = read(.useLocalTranscription, useLocalTranscription)
        allowedContextApps = read(.allowedContextApps, allowedContextApps)
        writingProfiles = read(.writingProfiles, writingProfiles)
        retentionDays = read(.retentionDays, retentionDays)
        historyEnabled = read(.historyEnabled, historyEnabled)
        automaticLearningEnabled = read(.automaticLearningEnabled, automaticLearningEnabled)
        usageTrackingEnabled = read(.usageTrackingEnabled, usageTrackingEnabled)
        usageAccountingIncomplete = read(.usageAccountingIncomplete, usageAccountingIncomplete)
        decisionReviewMode = read(.decisionReviewMode, decisionReviewMode)
        improvementModels = read(.improvementModels, improvementModels)
        jevDetailedReviewEnabled = read(.jevDetailedReviewEnabled, false)
        jevEconomyEnabled = read(.jevEconomyEnabled, false)
        jevAutomaticImprovementEnabled = read(.jevAutomaticImprovementEnabled, false)
        jevClarifyEditsEnabled = read(.jevClarifyEditsEnabled, false)
        jevReRecognitionEnabled = read(.jevReRecognitionEnabled, false)
        jevFeedbackLearningEnabled = read(.jevFeedbackLearningEnabled, false)
        jevNameCatalog = Self.normalizedJevCatalogNames(read(.jevNameCatalog, []))
        if values.contains(.decisionProvider) {
            if let raw = try? values.decode(String.self, forKey: .decisionProvider),
               let restored = DecisionProvider(rawValue: raw) {
                decisionProvider = restored
            } else {
                // An unknown destination must not silently send opted-in text to OpenRouter.
                decisionReviewMode = .off
                jevDetailedReviewEnabled = false
                jevEconomyEnabled = false
                jevAutomaticImprovementEnabled = false
                jevClarifyEditsEnabled = false
                jevReRecognitionEnabled = false
                jevFeedbackLearningEnabled = false
            }
        }
        speakerFilterEnabled = read(.speakerFilterEnabled, speakerFilterEnabled)
        let storedHotkeys: [HotkeyBinding] = read(.hotkeys, hotkeys)
        if Self.validHotkeys(storedHotkeys) { hotkeys = storedHotkeys }
        launchAtLogin = read(.launchAtLogin, launchAtLogin)
        appearance = read(.appearance, appearance)
    }

    /// Keep only explicitly supplied names; app discovery never populates this list automatically.
    static func normalizedJevCatalogNames(_ names: [String]) -> [String] {
        var result: [String] = []
        for raw in names {
            guard let name = JevNameCatalog.normalizedCanonicalName(raw),
                  !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            result.append(name)
            if result.count == 64 { break }
        }
        return result
    }

    private static func validHotkeys(_ bindings: [HotkeyBinding]) -> Bool {
        // Carbon modifier flags: Command, Shift, Option, Control. A bare or Shift-only
        // binding could capture ordinary typing, so restore only this invalid field.
        let allowedModifiers: UInt32 = 256 | 512 | 2048 | 4096
        let requiredModifier: UInt32 = 256 | 2048 | 4096
        return bindings.count == HotkeyBinding.defaults.count
            && Set(bindings.map { "\($0.keyCode):\($0.modifiers)" }).count == bindings.count
            && bindings.allSatisfy {
                $0.keyCode <= 127 && $0.modifiers & requiredModifier != 0
                    && $0.modifiers & ~allowedModifiers == 0
            }
    }

    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: "preferences.v1"),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return decoded
    }
    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "preferences.v1")
    }
    /// A cleared custom model field means "use the default", not "send an empty model id".
    var transcriptionModel: String {
        Self.nonBlank(transcriptionModels[provider.rawValue]) ?? ProviderDefaults.forProvider(provider).transcriptionModel
    }
    var textModel: String {
        Self.nonBlank(textModels[effectiveTextProvider.rawValue]) ?? ProviderDefaults.forProvider(effectiveTextProvider).textModel
    }
    var effectiveTextProvider: AIProvider { textProvider ?? provider }
    var improvementModel: String { Self.nonBlank(improvementModels[effectiveTextProvider.rawValue]) ?? textModel }
    private static func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    var needsLocal: Bool { provider == .anthropic || useLocalTranscription }

    func writingProfile(for bundleID: String?) -> WritingProfile {
        if let bundleID, let selected = writingProfiles[bundleID] { return selected }
        return WritingProfile.defaultForApp(bundleID: bundleID)
    }
}

enum AppPage: String, CaseIterable, Identifiable {
    case home, history, dictionary, recovery, usage, voice, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .home: L("시작하기", "Get started"); case .history: L("기록", "History"); case .dictionary: L("개인 사전", "Dictionary"); case .recovery: L("다시 처리", "Recovery"); case .voice: L("음성 모델", "Voice models"); case .usage: L("사용량", "Usage"); case .settings: L("설정", "Settings") }
    }
    var icon: String {
        switch self { case .home: "waveform"; case .history: "clock"; case .dictionary: "character.book.closed"; case .recovery: "arrow.clockwise"; case .voice: "person.wave.2"; case .usage: "chart.bar.xaxis"; case .settings: "slider.horizontal.3" }
    }
}
