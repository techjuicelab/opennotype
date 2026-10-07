import AppKit
import AVFoundation
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class TranslationProtectionFlowTests: KoreanPresentationTestCase {
    func testRefinementRunsOnceAndOnlyFinalTranslationIsReviewedInsertedAndStored() async throws {
        for mode in [InputMode.dictation, .translation] {
            let final = "資料をご確認いただけると助かります。急ぎではありません。"
            let f = try fixture(refinement: true, refinedOutput: final)
            await record(f, mode: mode)
            XCTAssertEqual(f.http.requestCount, 3)
            XCTAssertEqual(f.http.refinementCount, 1)
            let calls = await f.reviewer.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.cleanedText, final)
            XCTAssertEqual(f.insertions.texts, [final])
            XCTAssertEqual(f.model.result, final)
            XCTAssertEqual(f.model.translationRefinement?.draft, f.http.output)
            XCTAssertEqual(f.model.translationRefinement?.output, final)
            XCTAssertFalse(f.model.translationRefinement?.held ?? true)
            let history = try await f.store.history()
            XCTAssertEqual(history.last?.resultText, final)
            let usage = try await f.store.usageRecords()
            XCTAssertEqual(usage.filter { $0.event.stage == .textProcessing }.count, 2)
            XCTAssertEqual(usage.filter { $0.event.stage == .decisionReview }.count, 1)
        }
    }

    func testRefinementIsIndependentOfJevAndNeverAppliesToSameLanguageDictation() async throws {
        let enabled = try fixture(enabled: false, refinement: true, refinedOutput: "資料を確認していただけると助かります。急ぎではありません。")
        await record(enabled)
        XCTAssertEqual(enabled.http.requestCount, 3)
        let calls = await enabled.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(enabled.insertions.texts, [enabled.http.refinedOutput!])
        let original = try fixture(output: .original, refinement: true)
        await record(original)
        XCTAssertEqual(original.http.refinementCount, 0)
        XCTAssertNil(original.model.translationRefinement)
    }

    func testRefinementHTTPFailureAndEmptyOutputHoldWithoutDraftInsertionOrJev() async throws {
        for httpFailure in [false, true] {
            let f = try fixture(refinement: true, refinedOutput: "", refinementHTTPFailure: httpFailure)
            await record(f)
            XCTAssertEqual(f.http.requestCount, 3, "Refinement may not retry HTTP 503")
            XCTAssertEqual(f.http.refinementCount, 1)
            let calls = await f.reviewer.calls
            XCTAssertTrue(calls.isEmpty)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertEqual(f.model.result, f.http.output)
            XCTAssertTrue(f.model.translationRefinement?.held == true)
            XCTAssertNotNil(f.model.error)
            let history = try await f.store.history()
            XCTAssertTrue(history.isEmpty)
            XCTAssertEqual(f.model.failures.count, 1)
        }
    }

    func testRefinementProtectedLiteralChangeHoldsAndKeepsDraftForManualReview() async throws {
        let f = try fixture(transcript: "`ONT-21` 확인을 부탁드립니다.", refinement: true,
            draftOutput: "`ONT-21` の確認をお願いします。", refinedOutput: "`ONT-22` の確認をお願いします。")
        await record(f)
        XCTAssertEqual(f.http.refinementCount, 1)
        XCTAssertTrue(f.insertions.texts.isEmpty)
        XCTAssertTrue(f.model.translationRefinement?.held == true)
        XCTAssertEqual(f.model.translationRefinement?.draft, f.http.output)
        XCTAssertNil(f.model.translationRefinement?.output)
        let usage = try await f.store.usageRecords()
        XCTAssertEqual(usage.filter { $0.event.stage == .textProcessing }.count, 2, "Rejected responses can be billable")
    }

    func testRefinementCapturesOptInLanguageAndToneAtRecordingStart() async throws {
        let f = try fixture(tone: .formal, refinement: true)
        await f.model.toggle(.dictation)
        f.model.preferences.dictationOutputLanguage = .english
        f.model.preferences.writingProfiles["test.translation.editor"] = .init(tone: .casual)
        f.model.stop(); await waitForIdle(f.model)
        let payload = try XCTUnwrap(f.http.refinementPayloads.first)
        XCTAssertEqual(payload["target_language"] as? String, "Japanese")
        XCTAssertEqual((payload["writing_profile"] as? [String: String])?["tone"], WritingTone.formal.rawValue)
        XCTAssertEqual(payload["translation_draft"] as? String, f.http.output)
        XCTAssertEqual(payload["spoken_text"] as? String, f.http.transcript)
        let off = try fixture(refinement: false)
        await off.model.toggle(.dictation)
        off.model.preferences.translationRefinementEnabled = true
        off.model.stop(); await waitForIdle(off.model)
        XCTAssertEqual(off.http.refinementCount, 0)
    }

    func testRefinementRevocationCancelAndHistoryDisableDiscardLateResponse() async throws {
        for action in 0..<4 {
            let gate = TranslationProtectionGate(entered: expectation(description: "Refinement waits \(action)"))
            let f = try fixture(refinement: true, refinedOutput: "資料の確認をお願いします。急ぎではありません。", refinementGate: gate)
            await f.model.toggle(.dictation); f.model.stop()
            await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertTrue(f.model.translationRefinement?.isProcessing == true)
            if action == 0 { f.model.cancel() }
            else if action == 1 { f.model.preferences.translationRefinementEnabled = false }
            else if action == 2 { f.model.preferences.historyEnabled = false }
            else { await f.model.deleteHistory() }
            await gate.release(); await waitForIdle(f.model)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertNil(f.model.translationRefinement)
            XCTAssertTrue(f.model.result.isEmpty, "A discarded draft must not be relabelled as a final result")
            let calls = await f.reviewer.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testRefinementRevocationWhileRecordingCannotBeUndoneByReenabling() async throws {
        let f = try fixture(refinement: true)
        await f.model.toggle(.dictation)
        f.model.preferences.translationRefinementEnabled = false
        f.model.preferences.translationRefinementEnabled = true
        f.model.stop(); await waitForIdle(f.model)
        XCTAssertEqual(f.http.refinementCount, 0)
        XCTAssertTrue(f.insertions.texts.isEmpty)
        XCTAssertTrue(f.model.result.isEmpty)
        XCTAssertNotNil(f.model.error)
    }

    func testPrivacyRevocationBeforeDraftArrivesDoesNotRepublishSourceOrDraft() async throws {
        for deleteAll in [false, true] {
            let gate = TranslationProtectionGate(entered: expectation(description: "Initial translation waits"))
            let f = try fixture(refinement: true, generationGate: gate)
            await f.model.toggle(.dictation); f.model.stop()
            await fulfillment(of: [gate.entered], timeout: 3)
            if deleteAll { await f.model.deleteHistory() }
            else { f.model.preferences.historyEnabled = false }
            await gate.release(); await waitForIdle(f.model)
            XCTAssertEqual(f.http.refinementCount, 0)
            XCTAssertTrue(f.model.result.isEmpty)
            XCTAssertNil(f.model.recentDecisionTarget)
            XCTAssertNil(f.model.translationRefinement)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertTrue(f.model.failures.isEmpty, "A revoked operation must not recreate recovery audio")
        }
    }

    func testHistoryRefinementStaysInItsPreviewAndReviewsOnlyFinalWithoutReplacingHistory() async throws {
        let final = "お時間のあるときに資料をご確認いただけると助かります。急ぎではありません。"
        let f = try fixture(refinement: true, refinedOutput: final)
        let entry = HistoryEntry(mode: .dictation, originalText: f.http.transcript, resultText: "saved result",
                                 sourceBundleID: "test.translation.editor", provider: .openRouter)
        _ = try await f.store.appendHistory(entry); await f.model.refreshData()
        f.model.reprocessHistory(entry); await waitForIdle(f.model)
        XCTAssertEqual(f.http.requestCount, 2)
        XCTAssertEqual(f.model.historyReprocessing?.result, final)
        XCTAssertEqual(f.model.historyReprocessing?.translationRefinement?.output, final)
        XCTAssertNil(f.model.translationRefinement)
        XCTAssertTrue(f.insertions.texts.isEmpty)
        let calls = await f.reviewer.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.cleanedText, final)
        let history = try await f.store.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.resultText, "saved result")
        f.model.dismissHistoryReprocessing()
        XCTAssertNil(f.model.historyReprocessing)
    }

    func testFinalRefinementCanStillBeHeldByIndependentJevReview() async throws {
        let final = "資料をご確認いただけると助かります。急ぎではありません。"
        let f = try fixture(risk: 0.9, refinement: true, refinedOutput: final)
        await record(f)
        let calls = await f.reviewer.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.cleanedText, final)
        XCTAssertTrue(f.insertions.texts.isEmpty)
        XCTAssertEqual(f.model.result, final)
        XCTAssertFalse(f.model.translationRefinement?.held ?? true, "Refinement completion and Jev approval are separate")
        XCTAssertTrue(f.model.notice?.contains("보류") == true)
    }

    func testRecoveryUsesCurrentRefinementPreferenceWithoutRepeatingFailedExtraCall() async throws {
        let f = try fixture(refinement: true, refinementHTTPFailure: true)
        await record(f)
        let failure = try XCTUnwrap(f.model.failures.first)
        f.model.preferences.translationRefinementEnabled = false
        f.model.retry(failure, useCurrentSettings: true)
        await waitForIdle(f.model)
        XCTAssertEqual(f.http.requestCount, 5, "Retry uses one STT and one translation, without disabled refinement")
        XCTAssertEqual(f.http.refinementCount, 1)
        XCTAssertTrue(f.insertions.texts.isEmpty, "Recovery prepares a preview without automatic typing")
        XCTAssertEqual(f.model.result, f.http.output)
        XCTAssertTrue(f.model.failures.isEmpty)
        let history = try await f.store.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.resultText, f.http.output)
    }

    func testOptOutAndOtherReviewModesKeepTranslationAtTwoProviderRequests() async throws {
        for (enabled, mode) in [(false, DecisionReviewMode.protect), (true, .off), (true, .observe), (true, .repair)] {
            let f = try fixture(enabled: enabled, mode: mode)
            await record(f)
            XCTAssertEqual(f.http.requestCount, 2)
            let calls = await f.reviewer.calls
            XCTAssertTrue(calls.isEmpty)
            XCTAssertEqual(f.insertions.texts, [f.http.output])
        }
    }

    func testNativeAndExplicitTranslationReviewCapturedLanguageAndToneBeforeTyping() async throws {
        for (mode, output, language) in [(InputMode.dictation, DictationOutputLanguage.english, "English (United States)"),
                                        (.dictation, .japanese, "Japanese"), (.dictation, .korean, "Korean"),
                                        (.translation, .original, "Japanese")] {
            let f = try fixture(output: output, tone: .formal, detailed: true)
            await record(f, mode: mode)
            let calls = await f.reviewer.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.purpose, .translation(targetLanguage: language))
            XCTAssertEqual(calls.first?.translationTone, .formal)
            XCTAssertTrue(calls.first?.termCandidates.isEmpty == true)
            XCTAssertEqual(Set(calls.first?.detailAxes ?? []), Set(DecisionDetailAxis.allCases))
            XCTAssertEqual(f.insertions.texts, [f.http.output])
            XCTAssertEqual(f.http.requestCount, 2, "Review cannot trigger regeneration or another STT request")
            let history = try await f.store.history()
            XCTAssertEqual(history.last?.targetLanguage, language)
            let usage = try await f.store.usageRecords()
            XCTAssertEqual(usage.filter { $0.event.stage == .decisionReview }.count, 1)
        }
    }

    func testInconclusiveHighRiskAndMalformedReviewsNeverInsert() async throws {
        for risk in [0.1001, 0.5, 0.9, Double.nan, -0.1, 1.1] {
            let f = try fixture(risk: risk)
            await record(f)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertEqual(f.model.result, f.http.output)
            XCTAssertEqual(f.http.requestCount, 2)
            let calls = await f.reviewer.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertTrue(f.model.notice?.contains("보류") == true)
        }
    }

    func testUnavailableReviewAndMissingConnectionHoldWithoutFallbackOrRegeneration() async throws {
        let failed = try fixture(failure: .timedOut)
        await record(failed)
        XCTAssertTrue(failed.insertions.texts.isEmpty)
        XCTAssertEqual(failed.model.result, failed.http.output)
        XCTAssertEqual(failed.http.requestCount, 2)
        let missing = try fixture(decisionProvider: .typeSafe)
        await record(missing)
        XCTAssertTrue(missing.insertions.texts.isEmpty)
        XCTAssertEqual(missing.http.requestCount, 2)
        let calls = await missing.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testOversizedTranslationReviewHoldsBeforeCallingReviewer() async throws {
        let f = try fixture(transcript: String(repeating: "한", count: 8_001))
        await record(f)
        let calls = await f.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(f.insertions.texts.isEmpty)
        XCTAssertEqual(f.http.requestCount, 2)
        XCTAssertEqual(f.model.result, f.http.output)
    }

    func testRecordingKeepsCapturedTargetAndToneWhenSettingsChange() async throws {
        let f = try fixture(tone: .formal)
        await f.model.toggle(.dictation)
        XCTAssertEqual(f.model.phase, .recording)
        f.model.preferences.dictationOutputLanguage = .english
        f.model.preferences.writingProfiles["test.translation.editor"] = .init(tone: .casual)
        f.model.stop()
        await waitForIdle(f.model)
        let calls = await f.reviewer.calls
        XCTAssertEqual(calls.first?.purpose, .translation(targetLanguage: "Japanese"))
        XCTAssertEqual(calls.first?.translationTone, .formal)
        XCTAssertEqual(f.insertions.texts, [f.http.output])
    }

    func testEnablingProtectionAfterRecordingStartsDoesNotAddReviewToCapturedOptOut() async throws {
        let f = try fixture(enabled: false)
        await f.model.toggle(.dictation)
        f.model.preferences.translationProtectionEnabled = true
        f.model.stop()
        await waitForIdle(f.model)
        let calls = await f.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(f.http.requestCount, 2)
        XCTAssertEqual(f.insertions.texts, [f.http.output])
    }

    func testProtectionRevocationOrCancellationDiscardsLateReviewBeforeTyping() async throws {
        for cancel in [false, true] {
            let gate = TranslationProtectionGate(entered: expectation(description: "Translation review waits"))
            let f = try fixture(gate: gate)
            await f.model.toggle(.dictation)
            f.model.stop()
            await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            if cancel { f.model.cancel() }
            else { f.model.preferences.translationProtectionEnabled = false }
            await gate.release()
            await waitForIdle(f.model)
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertEqual(f.http.requestCount, 2)
        }
    }

    func testTranslationToggleDoesNotRevokeSameLanguageDictationReview() async throws {
        let gate = TranslationProtectionGate(entered: expectation(description: "Same-language review waits"))
        let f = try fixture(output: .original, gate: gate)
        await f.model.toggle(.dictation)
        f.model.stop()
        await fulfillment(of: [gate.entered], timeout: 3)
        f.model.preferences.translationProtectionEnabled = false
        await gate.release()
        await waitForIdle(f.model)
        let calls = await f.reviewer.calls
        XCTAssertEqual(calls.first?.purpose, .dictation)
        XCTAssertEqual(f.insertions.texts, [f.http.output])
        XCTAssertEqual(f.http.requestCount, 2)
    }

    func testHistoryReprocessingCapturesProtectionAndLanguageWithoutInsertionOrHistoryReplacement() async throws {
        for enabled in [false, true] {
            let f = try fixture(enabled: enabled, tone: .polite)
            let entry = HistoryEntry(mode: .dictation, originalText: f.http.transcript, resultText: "saved result",
                sourceBundleID: "test.translation.editor", provider: .openRouter)
            _ = try await f.store.appendHistory(entry)
            await f.model.refreshData()
            f.model.reprocessHistory(entry)
            f.model.preferences.dictationOutputLanguage = .english
            f.model.preferences.writingProfiles["test.translation.editor"] = .init(tone: .casual)
            if !enabled { f.model.preferences.translationProtectionEnabled = true }
            await waitForIdle(f.model)
            let calls = await f.reviewer.calls
            XCTAssertEqual(calls.count, enabled ? 1 : 0)
            if enabled {
                XCTAssertEqual(calls.first?.purpose, .translation(targetLanguage: "Japanese"))
                XCTAssertEqual(calls.first?.translationTone, .polite)
            }
            XCTAssertNil(f.model.historyReprocessing?.error, "A current preview must not cancel its review while recording usage")
            let usage = try await f.store.usageRecords()
            XCTAssertEqual(usage.filter { $0.event.stage == .decisionReview }.count, enabled ? 1 : 0)
            XCTAssertEqual(f.model.historyReprocessing?.reviewTarget?.purpose, .translation(targetLanguage: "Japanese"))
            XCTAssertTrue(f.insertions.texts.isEmpty)
            XCTAssertEqual(f.http.requestCount, 1)
            let history = try await f.store.history()
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(history.first?.resultText, "saved result")
        }
    }

    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let reviewer: TranslationProtectionReviewer
        let http: TranslationProtectionHTTP
        let insertions: TranslationProtectionInsertions
    }

    private func fixture(enabled: Bool = true, mode: DecisionReviewMode = .protect,
                         output: DictationOutputLanguage = .japanese, tone: WritingTone = .preserve,
                         detailed: Bool = false, risk: Double = 0.01, failure: DecisionError? = nil,
                         gate: TranslationProtectionGate? = nil, decisionProvider: DecisionProvider = .openRouter,
                         transcript: String = "急ぎではありません。資料を確認していただけますか。",
                         refinement: Bool = false, draftOutput: String? = nil, refinedOutput: String? = nil,
                         refinementHTTPFailure: Bool = false, refinementGate: TranslationProtectionGate? = nil,
                         generationGate: TranslationProtectionGate? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-TranslationProtection-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("store"), backend: TranslationProtectionSecrets())
        let audio = root.appendingPathComponent("synthetic.wav")
        let target = InputTarget(pid: 41009, bundleID: "test.translation.editor", element: nil,
                                 originalValue: nil, range: nil, selectedText: nil, context: nil)
        let insertions = TranslationProtectionInsertions()
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }; runtime.capture = { _ in target }
        runtime.accessibilityPermitted = { true }; runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("Unexpected microphone request"); return false }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.readKey = { _ in "synthetic-provider-key" }; runtime.readStartupKey = { _ in "synthetic-provider-key" }
        runtime.readDecisionKey = { _ in nil }
        runtime.startRecording = { _ in try Data([82, 73, 70, 70, 1, 2, 3]).write(to: audio) }
        runtime.stopRecording = { audio }; runtime.recordingElapsed = { 1 }; runtime.recordingPeakDB = { -20 }
        runtime.insertText = { text, _, _, isCancelled in
            XCTAssertFalse(isCancelled()); insertions.texts.append(text); return .confirmed(.paste)
        }
        var preferences = Preferences.koreanForTesting
        preferences.provider = .groq; preferences.textProvider = .openRouter
        preferences.decisionReviewMode = mode; preferences.translationProtectionEnabled = enabled
        preferences.translationRefinementEnabled = refinement
        preferences.dictationOutputLanguage = output; preferences.targetLanguage = "Japanese"
        preferences.writingProfiles["test.translation.editor"] = .init(tone: tone)
        preferences.automaticLearningEnabled = false; preferences.jevDetailedReviewEnabled = detailed
        preferences.decisionProvider = decisionProvider
        let translated: String
        switch output {
        case .english: translated = "Could you review the materials? It is not urgent."
        case .korean: translated = "급한 건 아니에요. 자료를 확인해 주실 수 있나요?"
        default: translated = "急ぎではありません。資料を確認していただけますか。"
        }
        let http = TranslationProtectionHTTP(transcript: transcript, output: draftOutput ?? translated,
            refinedOutput: refinedOutput, refinementHTTPFailure: refinementHTTPFailure,
            refinementGate: refinementGate, generationGate: generationGate)
        let reviewer = TranslationProtectionReviewer(risk: risk, failure: failure, gate: gate)
        let model = AppModel(store: store, runtime: runtime, client: http.client, decisionClient: reviewer,
                             startServices: false, preferences: preferences)
        addTeardownBlock { @MainActor in model.cancel(); http.close(); try? FileManager.default.removeItem(at: root) }
        return .init(model: model, store: store, reviewer: reviewer, http: http, insertions: insertions)
    }

    private func record(_ f: Fixture, mode: InputMode = .dictation) async {
        await f.model.toggle(mode)
        XCTAssertEqual(f.model.phase, .recording)
        f.model.stop()
        await waitForIdle(f.model)
    }
    private func waitForIdle(_ model: AppModel) async {
        for _ in 0..<400 {
            if model.phase == .idle { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Synthetic translation protection did not finish")
    }
}

@MainActor private final class TranslationProtectionInsertions { var texts: [String] = [] }
private actor TranslationProtectionGate {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(entered: XCTestExpectation) { self.entered = entered }
    func wait() async {
        entered.fulfill()
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
private actor TranslationProtectionReviewer: DecisionEvaluating {
    private(set) var calls: [DecisionRequest] = []
    let risk: Double
    let failure: DecisionError?
    let gate: TranslationProtectionGate?
    init(risk: Double, failure: DecisionError?, gate: TranslationProtectionGate?) {
        self.risk = risk; self.failure = failure; self.gate = gate
    }
    func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        calls.append(input)
        if let gate { await gate.wait() }
        try Task.checkCancellation()
        if let failure { throw failure }
        let usage = ProviderUsage(provider: .openRouter, decisionProvider: configuration.provider,
            model: configuration.provider.model, stage: .decisionReview, inputTokens: 100, outputTokens: 10)
        await onUsage?(usage)
        return .init(meaningChanged: risk, contentAdded: 0.01, contentOmitted: 0.01,
            detailRisks: Dictionary(uniqueKeysWithValues: input.detailAxes.map { ($0, 0.01) }))
    }
}
private final class TranslationProtectionSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = nil }
}
private final class TranslationProtectionHTTP: @unchecked Sendable {
    static let registryLock = NSLock()
    static var registry: [String: TranslationProtectionHTTP] = [:]
    let id = UUID().uuidString
    let transcript: String
    let output: String
    let refinedOutput: String?
    let refinementHTTPFailure: Bool
    let refinementGate: TranslationProtectionGate?
    let generationGate: TranslationProtectionGate?
    private let lock = NSLock()
    private var count = 0
    private var refinementRequests: [[String: Any]] = []
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    var refinementCount: Int { lock.lock(); defer { lock.unlock() }; return refinementRequests.count }
    var refinementPayloads: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return refinementRequests }
    private(set) var session: URLSession!
    lazy var client = ProviderClient(session: session)
    init(transcript: String, output: String, refinedOutput: String? = nil,
         refinementHTTPFailure: Bool = false, refinementGate: TranslationProtectionGate? = nil,
         generationGate: TranslationProtectionGate? = nil) {
        self.transcript = transcript; self.output = output
        self.refinedOutput = refinedOutput; self.refinementHTTPFailure = refinementHTTPFailure; self.refinementGate = refinementGate
        self.generationGate = generationGate
        Self.registryLock.lock(); Self.registry[id] = self; Self.registryLock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationProtectionURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Synthetic-Translation-Test": id]
        session = URLSession(configuration: config)
    }
    func close() {
        session.invalidateAndCancel()
        Self.registryLock.lock(); Self.registry[id] = nil; Self.registryLock.unlock()
    }
    private func register(_ payload: [String: Any]?) {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if let payload { refinementRequests.append(payload) }
    }
    func response(for request: URLRequest) async throws -> (Data, Int) {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n))
            }
            body = data
        }
        let requestObject = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let messages = requestObject?["messages"] as? [[String: Any]]
        let input = (messages?.last?["content"] as? String).flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let refining = input?["translation_draft"] != nil
        register(refining ? input : nil)
        if refining, let refinementGate { await refinementGate.wait() }
        if !refining, request.url?.path.hasSuffix("/audio/transcriptions") != true,
           let generationGate { await generationGate.wait() }
        try Task.checkCancellation()
        if refining, refinementHTTPFailure { return (Data("{}".utf8), 503) }
        let object: [String: Any]
        if request.url?.path.hasSuffix("/audio/transcriptions") == true { object = ["text": transcript] }
        else {
            let text = try JSONSerialization.data(withJSONObject: ["text": refining ? refinedOutput ?? output : output])
            object = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": String(decoding: text, as: UTF8.self)]]],
                      "usage": ["prompt_tokens": 100, "completion_tokens": 20]]
        }
        return (try JSONSerialization.data(withJSONObject: object), 200)
    }
}
/// Handles every network request locally; no synthetic regression can contact a live provider.
private final class TranslationProtectionURLProtocol: URLProtocol {
    private var loadTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        loadTask = Task {
        do {
            guard let id = request.value(forHTTPHeaderField: "X-Synthetic-Translation-Test"), let url = request.url else { throw URLError(.badURL) }
            TranslationProtectionHTTP.registryLock.lock()
            let state = TranslationProtectionHTTP.registry[id]
            TranslationProtectionHTTP.registryLock.unlock()
            guard let state else { throw URLError(.resourceUnavailable) }
            let (bytes, status) = try await state.response(for: request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                               headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { loadTask?.cancel() }
}
