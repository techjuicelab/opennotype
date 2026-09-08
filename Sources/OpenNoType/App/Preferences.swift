import Foundation
import OpenNoTypeCore

struct Preferences: Codable {
    var provider: AIProvider = .openAI
    var transcriptionModels: [String: String] = [:]
    var textModels: [String: String] = [:]
    var targetLanguage = "English (United States)"
    var useLocalTranscription = false
    var allowedContextApps: Set<String> = []
    var retentionDays = 30
    var historyEnabled = true
    var speakerFilterEnabled = false
    var hotkeys = HotkeyBinding.defaults
    var launchAtLogin = false
    var appearance = "system"
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
