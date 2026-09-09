import Foundation

final class ProbeSecrets: SecretBackend, @unchecked Sendable {
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { values[service + account] = data }
    func delete(service: String, account: String) throws { values.removeValue(forKey: service + account) }
}

@main struct Probe {
    static func main() async throws {
        for pair in [("Send this.", "Sell this."), ("Cat is here.", "Car is here."), ("사과를 먹어요", "banana를 먹어요")] {
            let value = CorrectionLearner.suggestion(original: pair.0, edited: pair.1)
            print("learning", pair.0, "->", pair.1, "=", value.map { $0.spoken + " -> " + $0.written } ?? "review")
        }
        let location = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoTypeCoreReview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: location) }
        let backend = ProbeSecrets()
        let store = try SecureStore(directory: location, backend: backend)
        for count in 0...3 {
            if count > 0 {
                let started = ProcessInfo.processInfo.systemUptime
                try await store.saveFailure(FailedRecording(mode: .dictation, provider: .openAI, targetLanguage: "English"), audio: Data(repeating: 0xAA, count: 17_280_000))
                print(String(format: "failures=%d save=%.3fs", count, ProcessInfo.processInfo.systemUptime - started))
            }
            if count == 0 || count == 1 || count == 3 {
                for iteration in 1...3 {
                    let started = ProcessInfo.processInfo.systemUptime
                    let snapshot = try await store.snapshot(retentionDays: 30)
                    print(String(format: "failures=%d snapshot%d=%.3fs result=%d", count, iteration, ProcessInfo.processInfo.systemUptime - started, snapshot.failedRecordings.count))
                }
            }
        }
        let committed = location.appendingPathComponent("vault-v1.enc")
        let before = try Data(contentsOf: committed)
        try Data([0, 1, 2]).write(to: location.appendingPathComponent(".vault-interrupted.tmp"))
        do { _ = try await store.snapshot(retentionDays: 30); print("staged-corruption unexpected success") }
        catch { print("staged-corruption normal-vault-read", String(describing: error)) }
        print("committed-preserved", try Data(contentsOf: committed) == before)
        print("vault-bytes", before.count)
    }
}
