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

enum PreferencesRecoveryState: Equatable {
    case fresh, loaded, partiallyRecovered([String]), corrupted

    var requiresRecovery: Bool {
        switch self { case .partiallyRecovered, .corrupted: true; case .fresh, .loaded: false }
    }
    var invalidFields: [String] {
        if case .partiallyRecovered(let fields) = self { return fields }
        return []
    }
}

struct Preferences: Codable {
    /// Recovery metadata is deliberately absent from CodingKeys and never becomes a user setting.
    private(set) var recoveryState: PreferencesRecoveryState = .fresh
    private var recoverySource: Data?
    var interfaceLanguage: AppLanguage = .english
    var provider: AIProvider = .openAI
    var textProvider: AIProvider? = nil
    var transcriptionModels: [String: String] = [:]
    var textModels: [String: String] = [:]
    var targetLanguage = "English (United States)"
    var dictationOutputLanguage: DictationOutputLanguage = .original
    var useLocalTranscription = false
    var allowedContextApps: Set<String> = []
    var writingProfiles: [String: WritingProfile] = [:]
    var dictationExpression = DictationExpression()
    var retentionDays = 30
    var historyEnabled = true
    var automaticLearningEnabled = true
    var usageTrackingEnabled = true
    var usageAccountingIncomplete = false
    var decisionReviewMode: DecisionReviewMode = .off
    var translationProtectionEnabled = false
    var translationRefinementEnabled = false
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
        case allowedContextApps, writingProfiles, dictationExpression, dictationOutputLanguage, retentionDays, historyEnabled, speakerFilterEnabled
        case hotkeys, launchAtLogin, appearance, automaticLearningEnabled, usageTrackingEnabled, usageAccountingIncomplete, decisionReviewMode, translationProtectionEnabled, translationRefinementEnabled, decisionProvider
    }

    init() {}

    /// Every field falls back to its default on its own, so one unreadable value (for example a provider
    /// or profile added by a newer build) never discards the rest of the user's settings.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var invalidFields: Set<String> = []
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard values.contains(key) else { return fallback }
            do { return try values.decode(T.self, forKey: key) }
            catch { invalidFields.insert(key.rawValue); return fallback }
        }
        // Older versions had a Korean-only interface. A fresh install uses English;
        // an existing preferences record keeps its previous Korean presentation.
        interfaceLanguage = values.contains(.interfaceLanguage)
            ? read(.interfaceLanguage, .english) : .korean
        if values.contains(.provider) {
            if let raw = try? values.decode(String.self, forKey: .provider), let restored = AIProvider(rawValue: raw) {
                provider = restored
            } else { invalidFields.insert(CodingKeys.provider.rawValue) }
        }
        if values.contains(.textProvider), (try? values.decodeNil(forKey: .textProvider)) != true {
            if let raw = try? values.decode(String.self, forKey: .textProvider), let restored = AIProvider(rawValue: raw) {
                textProvider = restored
            } else { invalidFields.insert(CodingKeys.textProvider.rawValue) }
        }
        transcriptionModels = read(.transcriptionModels, transcriptionModels)
        textModels = read(.textModels, textModels)
        targetLanguage = read(.targetLanguage, targetLanguage)
        if values.contains(.dictationOutputLanguage) {
            if let raw = try? values.decode(String.self, forKey: .dictationOutputLanguage),
               let restored = DictationOutputLanguage(rawValue: raw) {
                dictationOutputLanguage = restored
            } else { invalidFields.insert(CodingKeys.dictationOutputLanguage.rawValue) }
        }
        useLocalTranscription = read(.useLocalTranscription, useLocalTranscription)
        allowedContextApps = read(.allowedContextApps, allowedContextApps)
        writingProfiles = read(.writingProfiles, writingProfiles)
        dictationExpression = read(.dictationExpression, .init())
        retentionDays = read(.retentionDays, retentionDays)
        if retentionDays < -1 || invalidFields.contains(CodingKeys.retentionDays.rawValue) {
            invalidFields.insert(CodingKeys.retentionDays.rawValue)
            // An unreadable retention policy must never become the default 30-day deletion policy.
            retentionDays = -1
        }
        historyEnabled = read(.historyEnabled, historyEnabled)
        automaticLearningEnabled = read(.automaticLearningEnabled, automaticLearningEnabled)
        usageTrackingEnabled = read(.usageTrackingEnabled, usageTrackingEnabled)
        usageAccountingIncomplete = read(.usageAccountingIncomplete, usageAccountingIncomplete)
        decisionReviewMode = read(.decisionReviewMode, decisionReviewMode)
        translationProtectionEnabled = read(.translationProtectionEnabled, false)
        translationRefinementEnabled = read(.translationRefinementEnabled, false)
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
                invalidFields.insert(CodingKeys.decisionProvider.rawValue)
                // An unknown destination must not silently send opted-in text to OpenRouter.
                decisionReviewMode = .off
                translationProtectionEnabled = false
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
        else { invalidFields.insert(CodingKeys.hotkeys.rawValue) }
        launchAtLogin = read(.launchAtLogin, launchAtLogin)
        appearance = read(.appearance, appearance)
        recoveryState = invalidFields.isEmpty ? .loaded : .partiallyRecovered(invalidFields.sorted())
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

    static let lastKnownGoodKey = "preferences.v1.last-known-good"
    static let recoveryOriginalKey = "preferences.v1.recovery-original"
    private static let storageKey = "preferences.v1"

    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        let raw = defaults.object(forKey: storageKey)
        guard raw != nil || defaults.object(forKey: lastKnownGoodKey) != nil
                || defaults.object(forKey: recoveryOriginalKey) != nil else { return .init() }
        var restored: Preferences
        if let data = raw as? Data, let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            restored = decoded
        } else {
            restored = .init()
            restored.recoveryState = .corrupted
            restored.retentionDays = -1
        }
        if restored.recoveryState.requiresRecovery {
            // Keep the active blob untouched. Repeated launches preserve the same recovery source.
            if let raw { defaults.set(raw, forKey: recoveryOriginalKey) }
            restored.recoverySource = storedObjectFingerprint(raw)
        } else if let data = raw as? Data {
            defaults.set(data, forKey: lastKnownGoodKey)
        }
        return restored
    }

    /// Automatic setting changes cannot acknowledge recovery or overwrite an unreadable source.
    @discardableResult func save(to defaults: UserDefaults = .standard) -> Bool {
        guard !recoveryState.requiresRecovery, !Self.load(from: defaults).recoveryState.requiresRecovery,
              let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(data, forKey: Self.lastKnownGoodKey)
        return true
    }

    static func canRestoreLastKnownGood(from defaults: UserDefaults = .standard) -> Bool {
        lastKnownGood(from: defaults) != nil
    }

    /// Called only after the user explicitly chooses the validated previous settings.
    static func restoreLastKnownGood(from defaults: UserDefaults = .standard) -> Preferences? {
        guard load(from: defaults).recoveryState.requiresRecovery,
              let restored = lastKnownGood(from: defaults) else { return nil }
        return restored.writeResolvedRecovery(to: defaults)
    }

    /// The user accepts recovered fields or creates new settings; the original remains backed up.
    func acceptRecovery(to defaults: UserDefaults = .standard) -> Preferences? {
        guard recoveryState.requiresRecovery,
              Self.load(from: defaults).recoveryState.requiresRecovery,
              recoverySource == Self.storedObjectFingerprint(defaults.object(forKey: Self.storageKey)) else { return nil }
        return writeResolvedRecovery(to: defaults)
    }

    private static func lastKnownGood(from defaults: UserDefaults) -> Preferences? {
        guard let data = defaults.data(forKey: lastKnownGoodKey),
              let restored = try? JSONDecoder().decode(Self.self, from: data),
              !restored.recoveryState.requiresRecovery else { return nil }
        return restored
    }

    private func writeResolvedRecovery(to defaults: UserDefaults) -> Preferences? {
        var restored = self
        restored.recoveryState = .loaded
        restored.recoverySource = nil
        guard let data = try? JSONEncoder().encode(restored),
              let validated = try? JSONDecoder().decode(Self.self, from: data),
              !validated.recoveryState.requiresRecovery else { return nil }
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(data, forKey: Self.lastKnownGoodKey)
        return restored
    }

    private static func storedObjectFingerprint(_ raw: Any?) -> Data? {
        guard let raw else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: ["source": raw], format: .binary, options: 0)
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
        var profile = bundleID.flatMap { writingProfiles[$0] } ?? WritingProfile.defaultForApp(bundleID: bundleID)
        profile.expression = dictationExpression
        return profile
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
