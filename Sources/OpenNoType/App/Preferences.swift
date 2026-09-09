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
    var speakerFilterEnabled = false
    var hotkeys = HotkeyBinding.defaults
    var launchAtLogin = false
    var appearance = "system"

    private enum CodingKeys: String, CodingKey {
        case provider, transcriptionModels, textModels, targetLanguage, useLocalTranscription
        case allowedContextApps, writingProfiles, retentionDays, historyEnabled, speakerFilterEnabled
        case hotkeys, launchAtLogin, appearance
    }

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? provider
        transcriptionModels = try values.decodeIfPresent([String: String].self, forKey: .transcriptionModels) ?? transcriptionModels
        textModels = try values.decodeIfPresent([String: String].self, forKey: .textModels) ?? textModels
        targetLanguage = try values.decodeIfPresent(String.self, forKey: .targetLanguage) ?? targetLanguage
        useLocalTranscription = try values.decodeIfPresent(Bool.self, forKey: .useLocalTranscription) ?? useLocalTranscription
        allowedContextApps = try values.decodeIfPresent(Set<String>.self, forKey: .allowedContextApps) ?? allowedContextApps
        writingProfiles = try values.decodeIfPresent([String: WritingProfile].self, forKey: .writingProfiles) ?? writingProfiles
        retentionDays = try values.decodeIfPresent(Int.self, forKey: .retentionDays) ?? retentionDays
        historyEnabled = try values.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? historyEnabled
        speakerFilterEnabled = try values.decodeIfPresent(Bool.self, forKey: .speakerFilterEnabled) ?? speakerFilterEnabled
        hotkeys = try values.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys) ?? hotkeys
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? appearance
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
    var transcriptionModel: String { transcriptionModels[provider.rawValue] ?? ProviderDefaults.forProvider(provider).transcriptionModel }
    var textModel: String { textModels[provider.rawValue] ?? ProviderDefaults.forProvider(provider).textModel }
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
