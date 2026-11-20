import Foundation
import XCTest
@testable import OpenNoTypeCore
@testable import OpenNoType

private final class DictionaryUndoTestSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[service + ":" + account]
    }

    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[service + ":" + account] = data
    }

    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: service + ":" + account)
    }
}

@MainActor
final class DictionaryUndoTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-DictUndo-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeModel(directory: URL, backend: DictionaryUndoTestSecrets) throws -> AppModel {
        let store = try SecureStore(directory: directory, backend: backend)
        var runtime = AppRuntime()
        runtime.readKey = { _ in nil }
        runtime.readDecisionKey = { _ in nil }
        runtime.accessibilityPermitted = { false }
        runtime.microphonePermission = { .notDetermined }
        runtime.hotkeyConflictWarnings = { _ in [] }
        return AppModel(store: store, runtime: runtime, startServices: false, preferences: Preferences())
    }

    func testUndoBannerClearsAutomaticallyWhenSameSpokenReappears() {
        let deleted = DictionaryEntry(spoken: "OpenAI", written: "OpenAI", learned: true)
        XCTAssertFalse(DictionaryView.shouldClearUndoBanner(deleted: nil, dictionary: []))
        XCTAssertFalse(DictionaryView.shouldClearUndoBanner(deleted: deleted, dictionary: [
            DictionaryEntry(spoken: "Claude", written: "Claude")
        ]))
        XCTAssertTrue(DictionaryView.shouldClearUndoBanner(deleted: deleted, dictionary: [
            DictionaryEntry(spoken: " openai ", written: "OpenAI Inc.")
        ]))
        XCTAssertTrue(DictionaryView.shouldClearUndoBanner(deleted: deleted, dictionary: [
            DictionaryEntry(id: deleted.id, spoken: "different", written: "Different")
        ]))
    }

    func testRestoreDeletedDictionaryEntryRestoresWhenAbsentAndWarnsOnConflict() async throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = DictionaryUndoTestSecrets()
        let model = try makeModel(directory: dir, backend: backend)
        XCTAssertEqual(model.startupState, .ready)

        let original = DictionaryEntry(spoken: "오픈 노타입", written: "OpenNoType", learned: true)
        let importedOriginal = await model.importDictionary([original])
        XCTAssertTrue(importedOriginal)
        await model.deleteDictionaryEntry(original)
        XCTAssertTrue(model.dictionary.isEmpty)

        // Restore when absent succeeds and preserves learned provenance with success notice.
        let restoredOutcome = await model.restoreDeletedDictionaryEntry(original)
        XCTAssertEqual(restoredOutcome, .restored(original))
        XCTAssertEqual(model.dictionary, [original])
        XCTAssertEqual(model.noticeKind, .success)

        // Delete again, then register a new entry with the same spoken spelling.
        await model.deleteDictionaryEntry(original)
        let newer = DictionaryEntry(spoken: "오픈 노타입", written: "OpenNoType Pro", learned: false)
        let importedNewer = await model.importDictionary([newer])
        XCTAssertTrue(importedNewer)

        // Attempting to restore the older deleted entry must NOT overwrite `newer` and must warn.
        let conflictOutcome = await model.restoreDeletedDictionaryEntry(original)
        XCTAssertEqual(conflictOutcome, .conflict(existing: newer))
        XCTAssertEqual(model.dictionary, [newer])
        XCTAssertEqual(model.noticeKind, .warning)
        XCTAssertFalse(model.noticeKind.autoDismisses)
        XCTAssertTrue(model.notice?.contains("OpenNoType Pro") == true)
    }
}
