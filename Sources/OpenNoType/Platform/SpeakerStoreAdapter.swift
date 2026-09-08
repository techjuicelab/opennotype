import Foundation
import OpenNoTypeCore

actor SpeakerStoreAdapter: SpeakerProfileStoring {
    let store: SecureStore
    init(store: SecureStore) { self.store = store }
    func loadSpeakerProfile() async throws -> SpeakerVoiceProfile? {
        guard let data = try await store.speakerProfile() else { return nil }
        return try JSONDecoder().decode(SpeakerVoiceProfile.self, from: data)
    }
    func saveSpeakerProfile(_ profile: SpeakerVoiceProfile) async throws {
        try await store.saveSpeakerProfile(JSONEncoder().encode(profile))
    }
    func deleteSpeakerProfile() async throws { try await store.deleteSpeakerProfile() }
}
