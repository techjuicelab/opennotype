import Foundation
import XCTest
@testable import OpenNoTypeCore

private final class ReviewedDictionarySecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var pendingGate: ReviewedDictionaryReadGate?
    func read(service: String, account: String) throws -> Data? {
        lock.lock()
        let value = values[service + ":" + account]
        let gate = pendingGate
        pendingGate = nil
        lock.unlock()
        try gate?.pause()
        return value
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + ":" + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: service + ":" + account)
    }
    func pauseNextRead(_ gate: ReviewedDictionaryReadGate) {
        lock.lock(); defer { lock.unlock() }; pendingGate = gate
    }
}

private final class ReviewedDictionaryReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var entered = false
    var hasEntered: Bool { lock.lock(); defer { lock.unlock() }; return entered }
    private enum GateError: Error { case timedOut }
    func pause() throws {
        lock.lock(); entered = true; lock.unlock()
        guard releaseSignal.wait(timeout: .now() + 5) == .success else { throw GateError.timedOut }
    }
    func release() { releaseSignal.signal() }
}

final class ReviewedDictionaryTests: XCTestCase {
    private var directory: URL!
    private var backend: ReviewedDictionarySecrets!
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-ReviewedDictionary-\(UUID().uuidString)", isDirectory: true)
        backend = ReviewedDictionarySecrets()
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func store() throws -> SecureStore {
        let current = date
        return try SecureStore(directory: directory, backend: backend, now: { current })
    }
    private func entry(_ spoken: String = "term", _ written: String = "Term", id: UUID = UUID(), learned: Bool = false) -> DictionaryEntry {
        .init(id: id, spoken: spoken, written: written, createdAt: date, learned: learned)
    }
    private var vaultURL: URL { directory.appendingPathComponent("vault-v1.enc") }
    private enum TestError: Error { case notSaved }
    private func saved(_ result: ReviewedDictionarySaveResult) throws -> (applied: DictionaryEntry, previous: DictionaryEntry?) {
        guard case .saved(let applied, let previous) = result else {
            XCTFail("Expected a saved change, got \(result)"); throw TestError.notSaved
        }
        return (applied, previous)
    }
    private func assertDictionary(_ subject: SecureStore, _ entries: [DictionaryEntry]) async throws {
        let actual = try await subject.dictionary()
        XCTAssertEqual(actual, entries)
    }

    func testNewEntryNormalizesAndReturnsExactUndoValues() async throws {
        let subject = try store()
        let requested = entry("  오픈 라우터\n", " OpenRouter ")
        let change = try saved(await subject.applyReviewedDictionaryEntry(requested, expectedPrevious: nil))
        XCTAssertEqual(change.applied.id, requested.id)
        XCTAssertEqual(change.applied.spoken, "오픈 라우터")
        XCTAssertEqual(change.applied.written, "OpenRouter")
        XCTAssertEqual(change.applied.createdAt, requested.createdAt)
        XCTAssertFalse(change.applied.learned)
        XCTAssertNil(change.previous)
        try await assertDictionary(subject, [change.applied])
        let undone = try await subject.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertTrue(undone)
        try await assertDictionary(subject, [])
    }

    func testConfirmedReplacementReturnsActualPreviousAndRestoresItExactly() async throws {
        let subject = try store()
        let previous = entry("TERM", "Old", learned: true)
        let unrelated = entry("other", "Other")
        try await subject.saveDictionary([previous, unrelated])
        let requested = entry(" term ", "New")
        let change = try saved(await subject.applyReviewedDictionaryEntry(requested, expectedPrevious: previous))
        XCTAssertEqual(change.previous, previous)
        try await assertDictionary(subject, [unrelated, change.applied])
        let undone = try await subject.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertTrue(undone)
        try await assertDictionary(subject, [unrelated, previous])
    }

    func testLegacyWhitespaceKeyIsComparedNormalizedButUndoRestoresExactValue() async throws {
        let subject = try store()
        let previous = entry(" TERM \n", "Old", learned: true)
        try await subject.saveDictionary([previous])
        let change = try saved(await subject.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: previous))
        XCTAssertEqual(change.previous, previous)
        let undone = try await subject.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertTrue(undone)
        try await assertDictionary(subject, [previous])
    }

    func testSameSpokenAndWrittenIsNoOpWithoutChangingIdentityOrMetadata() async throws {
        let subject = try store()
        let previous = entry("TERM", "Term", learned: true)
        try await subject.saveDictionary([previous])
        let before = try Data(contentsOf: vaultURL)
        let result = try await subject.applyReviewedDictionaryEntry(entry(" term ", " Term "), expectedPrevious: nil)
        XCTAssertEqual(result, .alreadyExists(previous))
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        try await assertDictionary(subject, [previous])
    }

    func testNewSpokenCollisionAfterConfirmationReturnsStaleWithoutWriting() async throws {
        let first = try store(), second = try store()
        let newer = entry("TERM", "Manual")
        _ = try await second.upsertDictionaryEntries([newer])
        let before = try Data(contentsOf: vaultURL)
        let result = try await first.applyReviewedDictionaryEntry(entry("term", "Suggested"), expectedPrevious: nil)
        XCTAssertEqual(result, .stale)
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        try await assertDictionary(first, [newer])
    }

    func testLaterEditFromAnotherStoreInvalidatesReviewedSnapshot() async throws {
        let first = try store(), second = try store()
        let previous = entry("term", "Old")
        _ = try await first.upsertDictionaryEntries([previous])
        _ = try await second.updateDictionaryEntry(id: previous.id, spoken: "term", written: "Manual")
        let result = try await first.applyReviewedDictionaryEntry(entry("term", "Suggested"), expectedPrevious: previous)
        XCTAssertEqual(result, .stale)
        let current = try await first.dictionary()
        XCTAssertEqual(current.first?.written, "Manual")
        XCTAssertEqual(current.first?.id, previous.id)
    }

    func testReplacementWithNewIdentityInvalidatesReviewedSnapshot() async throws {
        let subject = try store()
        let previous = entry("term", "Old"), replacement = entry("term", "Old")
        _ = try await subject.upsertDictionaryEntries([replacement])
        let result = try await subject.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: previous)
        XCTAssertEqual(result, .stale)
        try await assertDictionary(subject, [replacement])
    }

    func testMetadataChangesAlsoInvalidateReviewedSnapshot() async throws {
        let subject = try store()
        let previous = entry("term", "Old")
        var changed = previous
        changed.learned = true
        changed.createdAt = date.addingTimeInterval(1)
        try await subject.saveDictionary([changed])
        let result = try await subject.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: previous)
        XCTAssertEqual(result, .stale)
        try await assertDictionary(subject, [changed])
    }

    func testDeletedReviewedEntryIsNotResurrected() async throws {
        let subject = try store()
        let previous = entry("term", "Old")
        _ = try await subject.upsertDictionaryEntries([previous])
        _ = try await subject.deleteDictionaryEntry(id: previous.id)
        let result = try await subject.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: previous)
        XCTAssertEqual(result, .stale)
        try await assertDictionary(subject, [])
    }

    func testNewIDCollisionNeverDeletesAnUnrelatedEntry() async throws {
        let subject = try store()
        let existing = entry("other", "Other")
        _ = try await subject.upsertDictionaryEntries([existing])
        let result = try await subject.applyReviewedDictionaryEntry(entry("term", "Term", id: existing.id), expectedPrevious: nil)
        XCTAssertEqual(result, .conflict)
        try await assertDictionary(subject, [existing])
    }

    func testIDCollisionIsCheckedBeforeAlreadyExistsNoOp() async throws {
        let subject = try store()
        let target = entry(), other = entry("other", "Other")
        try await subject.saveDictionary([target, other])
        let result = try await subject.applyReviewedDictionaryEntry(entry(id: other.id), expectedPrevious: target)
        XCTAssertEqual(result, .conflict)
        try await assertDictionary(subject, [target, other])
    }

    func testMatchingExistingIDCanBeReplacedWhenSnapshotIsExact() async throws {
        let subject = try store()
        let previous = entry("term", "Old")
        _ = try await subject.upsertDictionaryEntries([previous])
        let requested = entry("term", "New", id: previous.id)
        let change = try saved(await subject.applyReviewedDictionaryEntry(requested, expectedPrevious: previous))
        XCTAssertEqual(change.applied, requested)
        XCTAssertEqual(change.previous, previous)
        let undone = try await subject.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertTrue(undone)
        try await assertDictionary(subject, [previous])
    }

    func testAmbiguousSpokenDuplicatesAreRejectedIncludingLegacyWhitespace() async throws {
        let subject = try store()
        let one = entry("term", "One"), two = entry(" TERM ", "Two")
        try await subject.saveDictionary([one, two])
        let result = try await subject.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: one)
        XCTAssertEqual(result, .conflict)
        try await assertDictionary(subject, [one, two])
    }

    func testExpectedSnapshotForDifferentSpokenKeyIsRejected() async throws {
        let subject = try store()
        let other = entry("other", "Other")
        _ = try await subject.upsertDictionaryEntries([other])
        let result = try await subject.applyReviewedDictionaryEntry(entry(), expectedPrevious: other)
        XCTAssertEqual(result, .conflict)
        try await assertDictionary(subject, [other])
    }

    func testAmbiguousPreviousIdentityCannotBeReplacedWithFreshID() async throws {
        let subject = try store()
        let target = entry("term", "Old")
        let other = entry("other", "Other", id: target.id)
        try await subject.saveDictionary([target, other])
        let result = try await subject.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: target)
        XCTAssertEqual(result, .conflict)
        try await assertDictionary(subject, [target, other])
    }

    func testConcurrentStoresCreateOneEntryAndReturnOneStaleResult() async throws {
        let first = try store(), second = try store()
        let one = entry("term", "One"), two = entry("TERM", "Two")
        async let a = first.applyReviewedDictionaryEntry(one, expectedPrevious: nil)
        async let b = second.applyReviewedDictionaryEntry(two, expectedPrevious: nil)
        let results = try await [a, b]
        XCTAssertEqual(results.filter { if case .saved = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(results.filter { $0 == .stale }.count, 1)
        let current = try await first.dictionary()
        XCTAssertEqual(current.count, 1)
        XCTAssertTrue(current.first == one || current.first == two)
    }

    func testConcurrentNewEntriesWithSameIDReturnOneConflict() async throws {
        let first = try store(), second = try store()
        let sharedID = UUID()
        let one = entry("one", "One", id: sharedID), two = entry("two", "Two", id: sharedID)
        async let a = first.applyReviewedDictionaryEntry(one, expectedPrevious: nil)
        async let b = second.applyReviewedDictionaryEntry(two, expectedPrevious: nil)
        let results = try await [a, b]
        XCTAssertEqual(results.filter { if case .saved = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(results.filter { $0 == .conflict }.count, 1)
        let current = try await first.dictionary()
        XCTAssertEqual(current.count, 1)
        XCTAssertTrue(current.first == one || current.first == two)
    }

    func testUnrelatedConcurrentEditIsPreservedAndDoesNotBlockReplacement() async throws {
        let first = try store(), second = try store()
        let previous = entry("term", "Old"), other = entry("other", "Other")
        try await first.saveDictionary([previous, other])
        _ = try await second.updateDictionaryEntry(id: other.id, spoken: "other", written: "Manual")
        let change = try saved(await first.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: previous))
        let current = try await second.dictionary()
        XCTAssertEqual(current.count, 2)
        XCTAssertEqual(current.first?.written, "Manual")
        XCTAssertEqual(current.last, change.applied)
    }

    func testUndoRespectsLaterManualEditFromAnotherStore() async throws {
        let first = try store(), second = try store()
        let change = try saved(await first.applyReviewedDictionaryEntry(entry(), expectedPrevious: nil))
        _ = try await second.updateDictionaryEntry(id: change.applied.id, spoken: "term", written: "Manual")
        let undone = try await first.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertFalse(undone)
        let current = try await first.dictionary()
        XCTAssertEqual(current.first?.written, "Manual")
    }

    func testUndoDoesNotRestorePreviousIDOverAnUnrelatedNewEntry() async throws {
        let subject = try store()
        let previous = entry("term", "Old")
        _ = try await subject.upsertDictionaryEntries([previous])
        let change = try saved(await subject.applyReviewedDictionaryEntry(entry("term", "New"), expectedPrevious: previous))
        let other = entry("other", "Other", id: previous.id)
        _ = try await subject.upsertDictionaryEntries([other])
        let undone = try await subject.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertFalse(undone)
        try await assertDictionary(subject, [change.applied, other])
    }

    func testUndoRejectsLaterWhitespaceKeyCollisionAndDuplicateIdentity() async throws {
        let subject = try store()
        let change = try saved(await subject.applyReviewedDictionaryEntry(entry(), expectedPrevious: nil))
        let sameSpoken = entry(" TERM ", "Later")
        try await subject.saveDictionary([change.applied, sameSpoken])
        let rejectedSpoken = try await subject.undoDictionaryChange(applied: change.applied, previous: nil)
        XCTAssertFalse(rejectedSpoken)
        let sameID = entry("other", "Other", id: change.applied.id)
        try await subject.saveDictionary([change.applied, sameID])
        let rejectedIdentity = try await subject.undoDictionaryChange(applied: change.applied, previous: nil)
        XCTAssertFalse(rejectedIdentity)
        try await assertDictionary(subject, [change.applied, sameID])
    }

    func testInvalidReviewedValuesNeverModifyVault() async throws {
        let subject = try store()
        let prior = entry()
        _ = try await subject.upsertDictionaryEntries([prior])
        let before = try Data(contentsOf: vaultURL)
        for invalid in [entry(" \n", "Valid"), entry("valid", "\t"), entry(String(repeating: "가", count: 101), "Valid"), entry("valid", String(repeating: "a", count: 101))] {
            do { _ = try await subject.applyReviewedDictionaryEntry(invalid, expectedPrevious: nil); XCTFail("Invalid entry committed") }
            catch { XCTAssertEqual(error as? SecureStoreError, .invalidDictionaryEntry) }
        }
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        try await assertDictionary(subject, [prior])
    }

    func testCancelledReviewedWriteDoesNotCommit() async throws {
        let subject = try store()
        let previous = entry("term", "Old")
        _ = try await subject.upsertDictionaryEntries([previous])
        let before = try Data(contentsOf: vaultURL)
        let proposed = entry("term", "New")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await subject.applyReviewedDictionaryEntry(proposed, expectedPrevious: previous)
        }
        do { _ = try await task.value; XCTFail("Canceled entry committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        try await assertDictionary(subject, [previous])
    }

    func testCancellationWhileTransactionIsBlockedIsCheckedBeforeMutation() async throws {
        let subject = try store()
        let previous = entry("term", "Old")
        _ = try await subject.upsertDictionaryEntries([previous])
        let before = try Data(contentsOf: vaultURL)
        let proposed = entry("term", "New")
        let gate = ReviewedDictionaryReadGate()
        backend.pauseNextRead(gate)
        defer { gate.release() }
        let task = Task { try await subject.applyReviewedDictionaryEntry(proposed, expectedPrevious: previous) }
        let deadline = Date().addingTimeInterval(3)
        while !gate.hasEntered, Date() < deadline { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(gate.hasEntered, "The write must pass its initial cancellation check and enter the transaction")
        task.cancel()
        gate.release()
        do { _ = try await task.value; XCTFail("Canceled transaction committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        try await assertDictionary(subject, [previous])
    }

    private func learningCandidate(id: UUID = UUID(), age: TimeInterval = 0) -> LearningCandidate {
        .init(id: id, originalText: "오픈 라우터에서 확인해요", editedText: "OpenRouter에서 확인해요",
              createdAt: date.addingTimeInterval(-age))
    }

    func testDismissingCandidatePreservesOtherStoresNewerCandidate() async throws {
        let first = try store(), second = try store()
        let visible = learningCandidate(), newer = learningCandidate()
        try await first.saveLearningCandidates([visible])
        try await second.saveLearningCandidates([newer, visible])
        let remaining = try await first.dismissLearningCandidate(id: visible.id)
        XCTAssertEqual(remaining, [newer])
        let fromOtherStore = try await second.learningCandidates()
        XCTAssertEqual(fromOtherStore, [newer])
        let dismissedAgain = try await first.dismissLearningCandidate(id: visible.id)
        XCTAssertEqual(dismissedAgain, [newer], "A stale dismiss must not erase the replacement")
    }

    func testReviewedLearningConsumesOnlyExactCandidateAndSupportsUndo() async throws {
        let subject = try store()
        let candidate = learningCandidate(), other = learningCandidate()
        try await subject.saveLearningCandidates([candidate, other])
        let change = try saved(await subject.applyReviewedLearningCandidate(candidate,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: 30))
        XCTAssertFalse(change.applied.learned)
        let remaining = try await subject.learningCandidates()
        XCTAssertEqual(remaining, [other])
        try await assertDictionary(subject, [change.applied])
        let undone = try await subject.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertTrue(undone)
        try await assertDictionary(subject, [])
        let afterUndo = try await subject.learningCandidates()
        XCTAssertEqual(afterUndo, [other], "Undo does not restore discarded source text")
    }

    func testReviewedLearningReplacementRestoresExactPreviousOnUndo() async throws {
        let subject = try store()
        let candidate = learningCandidate()
        let previous = entry("오픈 라우터", "OldRouter", learned: true)
        try await subject.saveDictionary([previous])
        try await subject.saveLearningCandidates([candidate])
        let change = try saved(await subject.applyReviewedLearningCandidate(candidate,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: previous, retentionDays: 30))
        XCTAssertEqual(change.previous, previous)
        let undone = try await subject.undoDictionaryChange(applied: change.applied, previous: change.previous)
        XCTAssertTrue(undone)
        try await assertDictionary(subject, [previous])
    }

    func testAlreadyRegisteredReviewedLearningConsumesCandidateWithoutReplacingMetadata() async throws {
        let subject = try store()
        let candidate = learningCandidate()
        let previous = entry("오픈 라우터", "OpenRouter", learned: true)
        try await subject.saveDictionary([previous])
        try await subject.saveLearningCandidates([candidate])
        let result = try await subject.applyReviewedLearningCandidate(candidate,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: 30)
        XCTAssertEqual(result, .alreadyExists(previous))
        try await assertDictionary(subject, [previous])
        let remaining = try await subject.learningCandidates()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeletedLearningCandidateCannotBeSavedFromStaleInstance() async throws {
        let first = try store(), second = try store()
        let candidate = learningCandidate(), replacement = learningCandidate()
        try await first.saveLearningCandidates([candidate])
        try await second.deleteAllHistory()
        try await second.saveLearningCandidates([replacement])
        let result = try await first.applyReviewedLearningCandidate(candidate,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: 30)
        XCTAssertEqual(result, .stale)
        try await assertDictionary(first, [])
        let remaining = try await first.learningCandidates()
        XCTAssertEqual(remaining, [replacement])
    }

    func testEditedCandidateWithSameIDDoesNotMatchReviewedSnapshot() async throws {
        let subject = try store()
        let candidate = learningCandidate()
        var newer = candidate
        newer.editedText = "OtherRouter에서 확인해요"
        try await subject.saveLearningCandidates([newer])
        let result = try await subject.applyReviewedLearningCandidate(candidate,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: 30)
        XCTAssertEqual(result, .stale)
        let remaining = try await subject.learningCandidates()
        XCTAssertEqual(remaining, [newer])
    }

    func testDuplicateLearningCandidateIdentityIsConflict() async throws {
        let subject = try store()
        let candidate = learningCandidate()
        try await subject.saveLearningCandidates([candidate, candidate])
        let result = try await subject.applyReviewedLearningCandidate(candidate,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: 30)
        XCTAssertEqual(result, .conflict)
        try await assertDictionary(subject, [])
        let remaining = try await subject.learningCandidates()
        XCTAssertEqual(remaining.count, 2)
    }

    func testExpiredLearningCandidateIsPrunedBeforeReviewedWrite() async throws {
        let subject = try store()
        let old = learningCandidate(age: 2 * 86_400), recent = learningCandidate()
        try await subject.saveLearningCandidates([old, recent])
        let result = try await subject.applyReviewedLearningCandidate(old,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: 1)
        XCTAssertEqual(result, .stale)
        try await assertDictionary(subject, [])
        let remaining = try await subject.learningCandidates()
        XCTAssertEqual(remaining, [recent])
    }

    func testZeroRetentionCannotSaveCandidateAndForeverRetentionCan() async throws {
        let subject = try store()
        let current = learningCandidate()
        try await subject.saveLearningCandidates([current])
        let zero = try await subject.applyReviewedLearningCandidate(current,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: 0)
        XCTAssertEqual(zero, .stale)
        _ = try await subject.snapshot(retentionDays: -1)
        let old = learningCandidate(age: 365 * 86_400)
        try await subject.saveLearningCandidates([old])
        let change = try saved(await subject.applyReviewedLearningCandidate(old,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: -1))
        try await assertDictionary(subject, [change.applied])
    }

    func testDictionaryChangedDuringLearningReviewPreservesCandidateAndNewEntry() async throws {
        let first = try store(), second = try store()
        let candidate = learningCandidate(), previous = entry("오픈 라우터", "Old")
        try await first.saveLearningCandidates([candidate])
        try await first.saveDictionary([previous])
        _ = try await second.updateDictionaryEntry(id: previous.id, spoken: previous.spoken, written: "Manual")
        let result = try await first.applyReviewedLearningCandidate(candidate,
            entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: previous, retentionDays: 30)
        XCTAssertEqual(result, .stale)
        let remaining = try await first.learningCandidates(), dictionary = try await first.dictionary()
        XCTAssertEqual(remaining, [candidate])
        XCTAssertEqual(dictionary.first?.written, "Manual")
    }

    func testReviewedLearningCannotWriteUnrelatedOrAutomaticAlias() async throws {
        let subject = try store()
        let candidate = learningCandidate()
        try await subject.saveLearningCandidates([candidate])
        for invalid in [entry("오픈 라우터", "Unrelated"), entry("다른 말", "OpenRouter"), entry("오픈 라우터", "OpenRouter", learned: true)] {
            do {
                _ = try await subject.applyReviewedLearningCandidate(candidate, entry: invalid, expectedPrevious: nil, retentionDays: 30)
                XCTFail("An unreviewed alias was committed")
            } catch { XCTAssertEqual(error as? SecureStoreError, .invalidDictionaryEntry) }
        }
        do {
            _ = try await subject.applyReviewedLearningCandidate(candidate, entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: nil, retentionDays: -2)
            XCTFail("Invalid retention accepted")
        } catch { XCTAssertEqual(error as? SecureStoreError, .invalidRetention) }
        let remaining = try await subject.learningCandidates()
        XCTAssertEqual(remaining, [candidate])
        try await assertDictionary(subject, [])
    }

    func testConcurrentReviewedLearningConsumesCandidateOnlyOnce() async throws {
        let first = try store(), second = try store()
        let candidate = learningCandidate(), one = entry("오픈 라우터", "OpenRouter"), two = entry("오픈 라우터", "OpenRouter")
        try await first.saveLearningCandidates([candidate])
        async let a = first.applyReviewedLearningCandidate(candidate, entry: one, expectedPrevious: nil, retentionDays: 30)
        async let b = second.applyReviewedLearningCandidate(candidate, entry: two, expectedPrevious: nil, retentionDays: 30)
        let results = try await [a, b]
        XCTAssertEqual(results.filter { if case .saved = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(results.filter { $0 == .stale }.count, 1)
        let remaining = try await first.learningCandidates(), dictionary = try await first.dictionary()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(dictionary.count, 1)
    }

    func testCancellationDuringLearningTransactionDoesNotConsumeCandidate() async throws {
        let subject = try store()
        let candidate = learningCandidate(), proposed = entry("오픈 라우터", "OpenRouter")
        try await subject.saveLearningCandidates([candidate])
        let before = try Data(contentsOf: vaultURL)
        let gate = ReviewedDictionaryReadGate()
        backend.pauseNextRead(gate)
        defer { gate.release() }
        let task = Task { try await subject.applyReviewedLearningCandidate(candidate, entry: proposed, expectedPrevious: nil, retentionDays: 30) }
        let deadline = Date().addingTimeInterval(3)
        while !gate.hasEntered, Date() < deadline { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(gate.hasEntered)
        task.cancel(); gate.release()
        do { _ = try await task.value; XCTFail("Cancelled learning transaction committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        let remaining = try await subject.learningCandidates()
        XCTAssertEqual(remaining, [candidate])
        try await assertDictionary(subject, [])
    }

    func testFailedLearningCommitPreservesBothCandidateAndDictionary() async throws {
        let subject = try store()
        let candidate = learningCandidate(), previous = entry("오픈 라우터", "Old")
        try await subject.saveLearningCandidates([candidate])
        try await subject.saveDictionary([previous])
        let before = try Data(contentsOf: vaultURL), current = date
        let failing = try SecureStore(directory: directory, backend: backend, now: { current },
                                      beforeVaultCommit: { throw TestError.notSaved })
        do {
            _ = try await failing.applyReviewedLearningCandidate(candidate,
                entry: entry("오픈 라우터", "OpenRouter"), expectedPrevious: previous, retentionDays: 30)
            XCTFail("Expected write failure")
        } catch { XCTAssertTrue(error is TestError) }
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        let remaining = try await subject.learningCandidates()
        XCTAssertEqual(remaining, [candidate])
        try await assertDictionary(subject, [previous])
    }
}
