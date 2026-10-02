import AppKit
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class DecisionReviewFlowTests: XCTestCase {
    func testPreferencesDefaultAndUnknownModesNeverOptIn() throws {
        for json in ["{}", #"{"decisionReviewMode":"unknown","retentionDays":7}"#,
                     #"{"decisionReviewMode":true,"retentionDays":7}"#] {
            let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
            XCTAssertEqual(preferences.decisionReviewMode, .off)
        }
        for mode in DecisionReviewMode.allCases {
            var preferences = Preferences(); preferences.decisionReviewMode = mode
            let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(decoded.decisionReviewMode, mode)
        }
    }

    func testOffPreservesTheExistingPipelineWithoutADecisionRequest() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.99)
        let fixture = try fixture(mode: .off, evaluator: evaluator)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertNil(fixture.model.decisionReviewSummary)
    }

    func testProtectHoldsInputButKeepsOriginalAndResultForReview() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.95)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await recordAndWait(fixture)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertEqual(fixture.model.decisionOriginalText, DecisionAppURLProtocol.transcript)
        XCTAssertTrue(fixture.model.notice?.contains("자동 입력을 보류") == true)
        XCTAssertEqual(fixture.model.page, .home)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.last?.originalText, DecisionAppURLProtocol.transcript)
        XCTAssertEqual(history.last?.resultText, DecisionAppURLProtocol.output)
        let usage = try await fixture.store.usageRecords()
        XCTAssertEqual(usage.filter { $0.event.stage == .decisionReview }.count, 1)
        XCTAssertTrue(fixture.model.lastProcessingTimings?.contains("Jev 검토") == true)
    }

    func testLowRiskInsertsAndOnlyProposesKnownSpellingsWithoutLearning() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.1, proposeTerm: true)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertEqual(fixture.model.decisionTermSuggestions, ["오픈 라우터 → OpenRouter"])
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertTrue(fixture.model.dictionary.isEmpty)
        let stored = try await fixture.store.dictionary()
        XCTAssertTrue(stored.isEmpty)
        let calls = await evaluator.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.key, "synthetic-openRouter-key")
        XCTAssertEqual(call.request.transcript, DecisionAppURLProtocol.transcript)
        XCTAssertFalse(String(describing: call.request).contains("private surrounding context"))
    }

    func testUnavailableReviewFailsOpenWithoutReportingSuccess() async throws {
        for failure in [DecisionError.timedOut, .invalidResponse, .missingAPIKey] {
            let fixture = try fixture(mode: .protect, evaluator: DecisionAppEvaluator(failure: failure))
            await recordAndWait(fixture)
            XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
            XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("완료하지 못했습니다") == true)
            XCTAssertNil(fixture.model.decisionOriginalText)
            XCTAssertNil(fixture.model.error)
        }
    }

    func testObserveStartsAfterInputAndDoesNotKeepTheAppBusy() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Background review started"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .observe, evaluator: evaluator)
        await recordAndWait(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        await gate.release()
        await waitForReview(fixture.model)
        XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("문장 정리 결과는 변경하지 않았습니다") == true)
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertNil(fixture.model.decisionOriginalText)
        XCTAssertEqual(fixture.insertions.texts.count, 1)
    }

    func testObserveDiscardsLateResultsAfterCancelDisableHistoryOrDeletion() async throws {
        for action in 0..<4 {
            let gate = DecisionAppGate(entered: expectation(description: "Review started for action \(action)"))
            let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
            let fixture = try fixture(mode: .observe, evaluator: evaluator)
            await recordAndWait(fixture)
            await fulfillment(of: [gate.entered], timeout: 3)
            switch action {
            case 0: fixture.model.cancel()
            case 1: fixture.model.preferences.decisionReviewMode = .off
            case 2: fixture.model.preferences.historyEnabled = false
            default: await fixture.model.deleteHistory()
            }
            await gate.release()
            for _ in 0..<10 { await Task.yield() }
            XCTAssertNil(fixture.model.decisionReviewSummary)
            XCTAssertTrue(fixture.model.decisionTermSuggestions.isEmpty)
            XCTAssertEqual(fixture.insertions.texts.count, 1)
        }
    }

    func testProtectCancellationCannotHoldOrInsertAStaleResult() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Protection waits"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await startAndStop(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.cancel()
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertNil(fixture.model.decisionReviewSummary)
        XCTAssertNil(fixture.model.decisionOriginalText)
        XCTAssertFalse(fixture.model.isBusy)
    }

    func testRevokingReviewWhileProtectingContinuesNormalInput() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Protection can be revoked"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        let completed = watchCompletion(fixture.model)
        await startAndStop(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.preferences.decisionReviewMode = .off
        await gate.release()
        await fulfillment(of: [completed], timeout: 3)
        fixture.model.onPhaseChange = nil
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertNil(fixture.model.decisionReviewSummary)
        XCTAssertNil(fixture.model.decisionOriginalText)
    }

    func testRecordedReviewModeAndProviderRemainFrozen() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.95)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .recording)
        fixture.model.preferences.decisionReviewMode = .observe
        fixture.model.preferences.textProvider = .groq
        let completed = watchCompletion(fixture.model)
        fixture.model.elapsed = 1; fixture.model.stop()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        XCTAssertTrue(fixture.insertions.texts.isEmpty, "The recorded protection mode still applies")
        let calls = await evaluator.calls
        XCTAssertEqual(calls.map(\.key), ["synthetic-openRouter-key"])
    }

    func testReenablingReviewDoesNotResendARecordingWhoseConsentWasRevoked() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.99)
        let fixture = try fixture(mode: .protect, evaluator: evaluator)
        await fixture.model.toggle(.dictation)
        fixture.model.preferences.decisionReviewMode = .off
        fixture.model.preferences.decisionReviewMode = .protect
        let completed = watchCompletion(fixture.model)
        fixture.model.elapsed = 1; fixture.model.stop()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testANewRecordingDiscardsThePreviousBackgroundReview() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Previous background review started"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .observe, evaluator: evaluator)
        await recordAndWait(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .recording)
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(fixture.model.decisionReviewSummary)
        XCTAssertTrue(fixture.model.decisionTermSuggestions.isEmpty)
        XCTAssertTrue(fixture.model.phase == .recording, "Old completion must not stop the new recording")
    }

    func testUnsupportedModesAndProvidersDoNotSendExtraText() async throws {
        for input in [InputMode.translation, .rewrite] {
            let evaluator = DecisionAppEvaluator()
            let fixture = try fixture(mode: .protect, evaluator: evaluator)
            await recordAndWait(fixture, mode: input)
            let calls = await evaluator.calls
            XCTAssertTrue(calls.isEmpty)
        }
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, provider: .groq)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testExplicitReviewOptInDoesNotRequireTextHistory() async throws {
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, history: false)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        let history = try await fixture.store.history()
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testTermCandidatesAreBoundedRelevantAndFavorThePersonalDictionary() {
        let dictionary = [DictionaryEntry(spoken: "오픈 라우터", written: "PersonalSpelling"),
                          .init(spoken: "없는 단어", written: "UnusedTerm"),
                          .init(spoken: "일반 단어", written: "일반 표기")]
        let terms = AppModel.decisionTermCandidates(transcript: "오픈 라우터와 원 패스워드, 그록, 깃허브, 노션의 에이피아이", dictionary: dictionary)
        XCTAssertEqual(terms.count, 4)
        XCTAssertEqual(terms.first?.candidate, "PersonalSpelling")
        XCTAssertFalse(terms.contains { $0.candidate == "UnusedTerm" || $0.candidate == "일반 표기" })
        XCTAssertEqual(Set(terms.map(\.id)).count, terms.count)
    }

    func testSpellingSuggestionsCanPreserveHangulButNeverReverseSpokenLatin() {
        let terms = [DecisionTermCandidate(id: "term", original: "오픈 라우터", candidate: "OpenRouter")]
        let review = DecisionResult(meaningChanged: 0.1, contentAdded: 0.1, contentOmitted: 0.1,
            terms: [.init(id: "term", choice: .keepOriginal,
                          probabilities: [.keepOriginal: 0.9, .useCandidate: 0.05, .uncertain: 0.05], confidence: 0.9)])
        XCTAssertEqual(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: "'오픈 라우터'라고 적어", output: "'OpenRouter'라고 적어"), ["OpenRouter → 오픈 라우터 · 원문 표기 유지"])
        XCTAssertTrue(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: "오픈 라우터의 영문 표기는 OpenRouter", output: "OpenRouter의 영문 표기는 OpenRouter").isEmpty)
    }

    func testSpellingSuggestionsIgnoreTermsDiscardedBySelfCorrection() {
        let terms = [DecisionTermCandidate(id: "notes", original: "노션", candidate: "Notion"),
                     DecisionTermCandidate(id: "repo", original: "깃허브", candidate: "GitHub")]
        let review = DecisionResult(meaningChanged: 0.1, contentAdded: 0.1, contentOmitted: 0.1,
            terms: terms.map { .init(id: $0.id, choice: .useCandidate,
                                    probabilities: [.useCandidate: 0.9, .keepOriginal: 0.05, .uncertain: 0.05], confidence: 0.9) })
        let transcript = "노션에 아니 깃허브 이슈에 남겨 주세요"
        XCTAssertTrue(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: transcript, output: "GitHub 이슈에 남겨 주세요.").isEmpty)
        XCTAssertEqual(AppModel.decisionSuggestions(review: review, terms: terms,
            transcript: transcript, output: "깃허브 이슈에 남겨 주세요."), ["깃허브 → GitHub"])
    }


    func testDecisionProviderMigrationPreservesLegacyButDisablesUnknownDestinations() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"provider":"groq","decisionReviewMode":"protect"}"#.utf8))
        XCTAssertEqual(legacy.decisionProvider, .openRouter)
        XCTAssertEqual(legacy.decisionReviewMode, .protect)
        for raw in [#""future-provider""#, "42", "null"] {
            let document = "{\"provider\":\"groq\",\"decisionReviewMode\":\"protect\",\"decisionProvider\":\(raw)}"
            let restored = try JSONDecoder().decode(Preferences.self, from: Data(document.utf8))
            XCTAssertEqual(restored.provider, .groq)
            XCTAssertEqual(restored.decisionReviewMode, .off)
        }
        var direct = Preferences(); direct.decisionProvider = .typeSafe; direct.decisionReviewMode = .observe
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(direct))
        XCTAssertEqual(restored.decisionProvider, .typeSafe)
        XCTAssertEqual(restored.decisionReviewMode, .observe)
        XCTAssertFalse(AIProvider.allCases.contains { $0.rawValue == "typesafe" })
    }

    func testDirectTypeSafeUsesItsSavedKeyIndependentlyOfTextProvider() async throws {
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, provider: .groq, decisionProvider: .typeSafe)
        fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
        fixture.model.decisionAPIKeyDraft = "synthetic-unsaved-direct-key"
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.map(\.provider), [.typeSafe])
        XCTAssertEqual(calls.map(\.key), ["synthetic-typesafe-key"])
        XCTAssertTrue(fixture.model.decisionKeyDraftIsChanged)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        let records = try await fixture.store.usageRecords()
        let review = try XCTUnwrap(records.first { $0.event.stage == .decisionReview })
        XCTAssertEqual(review.event.providerID, "typesafe")
        XCTAssertFalse(review.event.isLocal)
        XCTAssertEqual(records.filter { $0.event.stage == .textProcessing }.map(\.event.provider), [.groq])
        XCTAssertTrue(fixture.keys.aiWrites.isEmpty)
    }

    func testMissingDirectKeySkipsOnlyJevAndDoesNotBlockDictation() async throws {
        let keys = DecisionAppKeyStorage(); keys.value = nil
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, provider: .groq, decisionProvider: .typeSafe, keyStore: keys)
        fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("TypeSafe API 키를 준비하지 못해") == true)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertNil(fixture.model.error)
    }

    func testDirectKeySaveFailurePreservesSavedKeyAndDeletionTouchesNoAIKeys() async throws {
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, decisionProvider: .typeSafe)
        fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
        fixture.keys.failWrite = true
        fixture.model.decisionAPIKeyDraft = "synthetic-new-direct-key"
        fixture.model.saveDecisionKey(); await waitForDecisionKey(fixture.model)
        XCTAssertTrue(fixture.model.decisionKeySaved)
        XCTAssertTrue(fixture.model.decisionKeyStatus?.contains("이전에 저장한 키를 유지") == true)
        await recordAndWait(fixture)
        var calls = await evaluator.calls
        XCTAssertEqual(calls.last?.key, "synthetic-typesafe-key")
        fixture.keys.failWrite = false
        fixture.model.saveDecisionKey(); await waitForDecisionKey(fixture.model)
        await recordAndWait(fixture)
        calls = await evaluator.calls
        XCTAssertEqual(calls.last?.key, "synthetic-new-direct-key")
        fixture.model.decisionAPIKeyDraft = ""
        fixture.model.saveDecisionKey(); await waitForDecisionKey(fixture.model)
        XCTAssertFalse(fixture.model.decisionKeySaved)
        XCTAssertNil(fixture.keys.value)
        XCTAssertTrue(fixture.keys.aiWrites.isEmpty)
        XCTAssertTrue(fixture.model.keySaved)
        XCTAssertTrue(fixture.model.textKeySaved)
    }

    func testLateDirectKeySavePreservesANewerUnsavedDraft() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Direct key save waits"))
        let keys = DecisionAppKeyStorage(); keys.saveGate = gate
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator, decisionProvider: .typeSafe, keyStore: keys)
        fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
        fixture.model.decisionAPIKeyDraft = "synthetic-saved-replacement"
        fixture.model.saveDecisionKey()
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.decisionAPIKeyDraft = "synthetic-newer-unsaved-draft"
        await gate.release(); await waitForDecisionKey(fixture.model)
        XCTAssertEqual(fixture.model.decisionAPIKeyDraft, "synthetic-newer-unsaved-draft")
        XCTAssertTrue(fixture.model.decisionKeyDraftIsChanged)
        XCTAssertTrue(fixture.model.decisionKeyStatus?.contains("아직 저장되지 않았습니다") == true)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.last?.key, "synthetic-saved-replacement")
    }

    func testOptionalDirectKeyReadCannotHoldStartupOrDiscardItsFailure() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Optional Keychain waits"))
        let keys = DecisionAppKeyStorage(); keys.readGate = gate; keys.failRead = true
        let fixture = try fixture(mode: .protect, evaluator: DecisionAppEvaluator(), decisionProvider: .typeSafe,
                                  keyStore: keys, cachedKeys: true)
        await fixture.model.prepareStartup()
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(fixture.model.startupState, .ready)
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertTrue(fixture.model.keySaved && fixture.model.textKeySaved)
        await gate.release(); await waitForDecisionKey(fixture.model)
        XCTAssertEqual(fixture.model.startupState, .ready)
        XCTAssertNil(fixture.model.error)
        XCTAssertNil(fixture.model.startupError)
        XCTAssertTrue(fixture.model.decisionKeyStatus?.contains("읽지 못했습니다") == true)
    }

    func testChangingDecisionProviderRevokesTheRecordingSnapshot() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.99)
        let fixture = try fixture(mode: .protect, evaluator: evaluator, decisionProvider: .typeSafe)
        fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
        await fixture.model.toggle(.dictation)
        fixture.model.preferences.decisionProvider = .openRouter
        let completed = watchCompletion(fixture.model)
        fixture.model.elapsed = 1; fixture.model.stop()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty, "A changed destination must not receive an older recording")
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testReplacingDirectKeyRevokesThePendingReview() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Direct reviewer waits"))
        let evaluator = DecisionAppEvaluator(risk: 0.99, gate: gate)
        let fixture = try fixture(mode: .protect, evaluator: evaluator, decisionProvider: .typeSafe)
        fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
        let completed = watchCompletion(fixture.model)
        await startAndStop(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.decisionAPIKeyDraft = "synthetic-replaced-key"
        fixture.model.saveDecisionKey(); await waitForDecisionKey(fixture.model)
        await gate.release()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        XCTAssertNil(fixture.model.decisionReviewSummary)
        XCTAssertNil(fixture.model.decisionOriginalText)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testLateDirectKeySaveOrReloadDoesNotRevokeANewerOpenRouterReview() async throws {
        for reload in [false, true] {
            let keyGate = DecisionAppGate(entered: expectation(description: "Optional key work waits"))
            let reviewGate = DecisionAppGate(entered: expectation(description: "New OpenRouter review waits"))
            let evaluator = DecisionAppEvaluator(risk: 0.99, gate: reviewGate)
            let fixture = try fixture(mode: .protect, evaluator: evaluator, decisionProvider: .typeSafe)
            fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
            if reload {
                fixture.keys.readGate = keyGate
                fixture.model.loadDecisionKey(force: true)
            } else {
                fixture.keys.saveGate = keyGate
                fixture.model.decisionAPIKeyDraft = "synthetic-replaced-key"
                fixture.model.saveDecisionKey()
            }
            await fulfillment(of: [keyGate.entered], timeout: 3)
            fixture.model.preferences.decisionProvider = .openRouter
            let completed = watchCompletion(fixture.model)
            await startAndStop(fixture)
            await fulfillment(of: [reviewGate.entered], timeout: 3)
            await keyGate.release(); await waitForDecisionKey(fixture.model)
            await reviewGate.release()
            await fulfillment(of: [completed], timeout: 5)
            fixture.model.onPhaseChange = nil
            let calls = await evaluator.calls
            XCTAssertEqual(calls.map(\.provider), [.openRouter])
            XCTAssertTrue(fixture.insertions.texts.isEmpty, "An unrelated key completion must not bypass protection")
            XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("자동 입력을 보류") == true)
        }
    }

    func testConnectionTestUsesSyntheticTextWithReviewOffAndOnlyRecordsUsage() async throws {
        for provider in DecisionProvider.allCases {
            let evaluator = DecisionAppEvaluator()
            let fixture = try fixture(mode: .off, evaluator: evaluator, decisionProvider: provider)
            if provider == .typeSafe { fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model) }
            fixture.model.result = "Existing user result"
            fixture.model.testDecisionConnection()
            await waitForDecisionConnectionTest(fixture.model)
            let calls = await evaluator.calls
            XCTAssertEqual(calls.map(\.provider), [provider])
            XCTAssertEqual(calls.first?.request.transcript, "내일 오후 세 시에 회의를 시작해 주세요.")
            XCTAssertEqual(fixture.model.preferences.decisionReviewMode, .off)
            XCTAssertTrue(fixture.model.decisionConnectionTestStatus?.contains("연결 확인 완료") == true)
            XCTAssertTrue(fixture.model.decisionConnectionTestStatus?.contains(provider.model) == true)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            XCTAssertEqual(fixture.model.result, "Existing user result")
            let history = try await fixture.store.history()
            XCTAssertTrue(history.isEmpty)
            let usage = try await fixture.store.usageRecords()
            XCTAssertEqual(usage.count, 1)
            XCTAssertEqual(usage.first?.event.decisionProvider, provider)
        }
    }

    func testConnectionTestFailureIsSafeAndProviderSwitchDiscardsLateSuccess() async throws {
        let failure = try fixture(mode: .off, evaluator: DecisionAppEvaluator(failure: .connectionFailed))
        failure.model.preferences.usageTrackingEnabled = false
        failure.model.testDecisionConnection(); await waitForDecisionConnectionTest(failure.model)
        XCTAssertTrue(failure.model.decisionConnectionTestStatus?.contains("확인하지 못했습니다") == true)
        let usage = try await failure.store.usageRecords()
        XCTAssertTrue(usage.isEmpty)
        let gate = DecisionAppGate(entered: expectation(description: "Connection test waits"))
        let waiting = try fixture(mode: .off, evaluator: DecisionAppEvaluator(gate: gate))
        waiting.model.testDecisionConnection()
        await fulfillment(of: [gate.entered], timeout: 3)
        waiting.model.preferences.decisionProvider = .typeSafe
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(waiting.model.decisionConnectionTestStatus)
        XCTAssertFalse(waiting.model.decisionConnectionTestInProgress)
    }

    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let insertions: DecisionAppInsertions
        let keys: DecisionAppKeyStorage
    }
    private func fixture(mode: DecisionReviewMode, evaluator: DecisionAppEvaluator,
                         provider: AIProvider = .openRouter, history: Bool = true,
                         decisionProvider: DecisionProvider = .openRouter,
                         keyStore: DecisionAppKeyStorage? = nil, cachedKeys: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-DecisionApp-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("store"), backend: DecisionAppSecrets())
        let audio = root.appendingPathComponent("synthetic.wav")
        try Data([82, 73, 70, 70, 1, 2, 3]).write(to: audio)
        let target = InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
                                originalValue: nil, range: nil, selectedText: "selected synthetic source", context: "private surrounding context")
        let insertions = DecisionAppInsertions()
        let keys = keyStore ?? DecisionAppKeyStorage()
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }; runtime.capture = { _ in target }
        runtime.accessibilityPermitted = { true }; runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("Unexpected microphone access"); return false }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.readKey = { "synthetic-\($0.rawValue)-key" }
        runtime.readStartupKey = { "synthetic-\($0.rawValue)-key" }
        runtime.saveStoredKey = { _, provider in keys.aiWrites.append(provider) }
        runtime.deleteStoredKey = { provider in keys.aiWrites.append(provider) }
        runtime.readDecisionKey = { provider in
            XCTAssertEqual(provider, .typeSafe); return try await keys.read()
        }
        runtime.saveDecisionKey = { value, provider in
            XCTAssertEqual(provider, .typeSafe); try await keys.write(value)
        }
        runtime.deleteDecisionKey = { provider in
            XCTAssertEqual(provider, .typeSafe); try await keys.write(nil)
        }
        runtime.startRecording = { _ in try Data([82, 73, 70, 70, 1, 2, 3]).write(to: audio) }
        runtime.stopRecording = { audio }; runtime.recordingPeakDB = { -12 }
        runtime.insertText = { text, _, _, cancelled in
            XCTAssertFalse(cancelled()); insertions.texts.append(text); return .confirmed(.paste)
        }
        var preferences = Preferences()
        preferences.provider = .groq; preferences.textProvider = provider
        preferences.decisionReviewMode = mode; preferences.automaticLearningEnabled = false
        preferences.decisionProvider = decisionProvider
        preferences.historyEnabled = history
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DecisionAppURLProtocol.self]
        let session = URLSession(configuration: config)
        let model = AppModel(store: store, runtime: runtime, client: ProviderClient(session: session),
                             decisionClient: evaluator, startServices: false, preferences: preferences, useCachedKeys: cachedKeys)
        addTeardownBlock { @MainActor in model.cancel(); session.invalidateAndCancel(); try? FileManager.default.removeItem(at: root) }
        return .init(model: model, store: store, insertions: insertions, keys: keys)
    }
    private func watchCompletion(_ model: AppModel) -> XCTestExpectation {
        let completed = expectation(description: "Dictation completes")
        var delivered = false
        model.onPhaseChange = { [weak model] in
            if model?.phase == .idle, !delivered { delivered = true; completed.fulfill() }
        }
        return completed
    }
    private func startAndStop(_ fixture: Fixture, mode: InputMode = .dictation) async {
        await fixture.model.toggle(mode)
        XCTAssertTrue(fixture.model.phase == .recording)
        fixture.model.elapsed = 1; fixture.model.stop()
    }
    private func recordAndWait(_ fixture: Fixture, mode: InputMode = .dictation) async {
        let completed = watchCompletion(fixture.model)
        await startAndStop(fixture, mode: mode)
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
    }
    private func waitForReview(_ model: AppModel) async {
        for _ in 0..<100 {
            if model.decisionReviewSummary?.contains("검토하고 있어요") == false { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The synthetic decision did not finish")
    }
    private func waitForDecisionKey(_ model: AppModel) async {
        for _ in 0..<200 {
            if !model.decisionKeyOperationInProgress { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("The synthetic decision key operation did not finish")
    }
    private func waitForDecisionConnectionTest(_ model: AppModel) async {
        for _ in 0..<200 {
            if !model.decisionConnectionTestInProgress { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("The synthetic connection test did not finish")
    }
}

@MainActor private final class DecisionAppInsertions { var texts: [String] = [] }
@MainActor private final class DecisionAppKeyStorage {
    var value: String? = "synthetic-typesafe-key"
    var aiWrites: [AIProvider] = []
    var writes: [String?] = []
    var failRead = false
    var failWrite = false
    var readGate: DecisionAppGate?
    var saveGate: DecisionAppGate?
    func read() async throws -> String? {
        if let readGate { await readGate.wait() }
        if failRead { throw SecretStorageError.keychain(-25293) }
        return value
    }
    func write(_ newValue: String?) async throws {
        if let saveGate { await saveGate.wait() }
        if failWrite { throw SecretStorageError.keychain(-25293) }
        writes.append(newValue); value = newValue
    }
}
private actor DecisionAppGate {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(entered: XCTestExpectation) { self.entered = entered }
    func wait() async {
        entered.fulfill()
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
private actor DecisionAppEvaluator: DecisionEvaluating {
    struct Call { let request: DecisionRequest; let key: String; let provider: DecisionProvider }
    private(set) var calls: [Call] = []
    let risk: Double
    let proposeTerm: Bool
    let failure: DecisionError?
    let gate: DecisionAppGate?
    init(risk: Double = 0.1, proposeTerm: Bool = false, failure: DecisionError? = nil, gate: DecisionAppGate? = nil) {
        self.risk = risk; self.proposeTerm = proposeTerm; self.failure = failure; self.gate = gate
    }
    func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        calls.append(.init(request: input, key: configuration.apiKey, provider: configuration.provider))
        if let gate { await gate.wait() }
        try Task.checkCancellation()
        if let failure { throw failure }
        let usage = ProviderUsage(provider: configuration.provider == .openRouter ? .openRouter : nil,
                                  decisionProvider: configuration.provider, model: configuration.provider.model, stage: .decisionReview)
        await onUsage?(usage)
        let terms: [DecisionTermResult] = proposeTerm ? input.termCandidates.map {
            .init(id: $0.id, choice: .useCandidate, probabilities: [.useCandidate: 0.8, .keepOriginal: 0.1, .uncertain: 0.1], confidence: 0.8)
        } : []
        return .init(meaningChanged: risk, contentAdded: 0.05, contentOmitted: 0.05, terms: terms,
                     reportedModel: configuration.provider.model)
    }
}
private final class DecisionAppSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = nil }
}
/// Intercepts every URL; these app tests cannot reach a live service.
private final class DecisionAppURLProtocol: URLProtocol {
    static let transcript = "오픈 라우터 연결을 확인해 주세요"
    static let output = "오픈 라우터 연결을 확인해 주세요."
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            let object: [String: Any]
            if url.path.hasSuffix("/audio/transcriptions") { object = ["text": Self.transcript] }
            else if url.path.hasSuffix("/chat/completions") {
                let encoded = try JSONSerialization.data(withJSONObject: ["text": Self.output])
                object = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": String(decoding: encoded, as: UTF8.self)]]]]
            } else { throw URLError(.unsupportedURL) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
