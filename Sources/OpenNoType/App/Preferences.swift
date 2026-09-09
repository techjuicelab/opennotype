import Foundation
import OpenNoTypeCore

struct Preferences: Codable {
    var provider: AIProvider = .openAI
    var transcriptionModels: [String: String] = [:]
    var textModels: [String: String] = [:]
    var targetLanguage = "English (United States)"
    var useLocalTranscription = false
    var allowedContextApps: Set<String> = []
    var writingProfiles: [String: WritingProfile] = [:]
    var retentionDays = 30
    var historyEnabled = true
    var automaticLearningEnabled = true
    var speakerFilterEnabled = false
    var hotkeys = HotkeyBinding.defaults
    var launchAtLogin = false
    var appearance = "system"

    private enum CodingKeys: String, CodingKey {
        case provider, transcriptionModels, textModels, targetLanguage, useLocalTranscription
        case allowedContextApps, writingProfiles, retentionDays, historyEnabled, speakerFilterEnabled
        case hotkeys, launchAtLogin, appearance, automaticLearningEnabled
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
        provider = read(.provider, provider)
        transcriptionModels = read(.transcriptionModels, transcriptionModels)
        textModels = read(.textModels, textModels)
        targetLanguage = read(.targetLanguage, targetLanguage)
        useLocalTranscription = read(.useLocalTranscription, useLocalTranscription)
        allowedContextApps = read(.allowedContextApps, allowedContextApps)
        writingProfiles = read(.writingProfiles, writingProfiles)
        retentionDays = read(.retentionDays, retentionDays)
        historyEnabled = read(.historyEnabled, historyEnabled)
        automaticLearningEnabled = read(.automaticLearningEnabled, automaticLearningEnabled)
        speakerFilterEnabled = read(.speakerFilterEnabled, speakerFilterEnabled)
        let storedHotkeys: [HotkeyBinding] = read(.hotkeys, hotkeys)
        if Self.validHotkeys(storedHotkeys) { hotkeys = storedHotkeys }
        launchAtLogin = read(.launchAtLogin, launchAtLogin)
        appearance = read(.appearance, appearance)
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

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: "preferences.v1"),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return decoded
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "preferences.v1")
    }
    /// A cleared custom model field means "use the default", not "send an empty model id".
    var transcriptionModel: String {
        Self.nonBlank(transcriptionModels[provider.rawValue]) ?? ProviderDefaults.forProvider(provider).transcriptionModel
    }
    var textModel: String {
        Self.nonBlank(textModels[provider.rawValue]) ?? ProviderDefaults.forProvider(provider).textModel
    }
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
    case home, history, dictionary, recovery, voice, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .home: "시작하기"; case .history: "기록"; case .dictionary: "개인 사전"; case .recovery: "다시 처리"; case .voice: "음성 모델"; case .settings: "설정" }
    }
    var icon: String {
        switch self { case .home: "waveform"; case .history: "clock"; case .dictionary: "character.book.closed"; case .recovery: "arrow.clockwise"; case .voice: "person.wave.2"; case .settings: "slider.horizontal.3" }
    }
}
