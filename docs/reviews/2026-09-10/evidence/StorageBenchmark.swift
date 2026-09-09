import Foundation
final class BenchSecrets: SecretBackend, @unchecked Sendable {
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { values[service + account] = data }
    func delete(service: String, account: String) throws { values.removeValue(forKey: service + account) }
}
@main struct Benchmark {
    static func main() async throws {
        let count = Int(CommandLine.arguments[1])!
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SecureStore(directory: directory, backend: BenchSecrets())
        for _ in 0..<count {
            let start = ProcessInfo.processInfo.systemUptime
            try await store.saveFailure(FailedRecording(mode: .dictation, provider: .openAI, targetLanguage: "English"), audio: Data(repeating: 0xAA, count: 17_280_000))
            print(String(format: "save=%.6fs", ProcessInfo.processInfo.systemUptime - start))
        }
        for iteration in 1...3 {
            let started = ProcessInfo.processInfo.systemUptime
            let result = try await store.snapshot(retentionDays: 30)
            print(String(format: "failures=%d snapshot%d=%.6fs result=%d", count, iteration, ProcessInfo.processInfo.systemUptime - started, result.failedRecordings.count))
        }
        let vault = directory.appendingPathComponent("vault-v1.enc")
        if let size = try? FileManager.default.attributesOfItem(atPath: vault.path)[.size] { print("vaultBytes=\(size)") }
    }
}
