import AppKit
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class DecisionReviewFlowTests: KoreanPresentationTestCase {
    func testExpressionIsCapturedForGenerationReviewAndSavedHistoryDespiteSettingChanges() async throws {
        let chosen = DictationExpression(style: .summary, strength: 75)
        let evaluator = DecisionAppEvaluator(risk: 0.1)
        let fixture = try fixture(mode: .protect, evaluator: evaluator) { $0.dictationExpression = chosen }
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .recording)
        fixture.model.preferences.dictationExpression = .init(style: .expanded, strength: 25)
        let completed = watchCompletion(fixture.model)
        fixture.model.elapsed = 1; fixture.model.stop()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        let input = try generationPayload(try XCTUnwrap(fixture.responses.generationBodies.first))
        let expression = try XCTUnwrap(input["dictation_expression"] as? [String: Any])
        XCTAssertEqual(expression["style"] as? String, "summary")
        XCTAssertEqual(expression["strength"] as? Int, 75)
        let initialCalls = await evaluator.calls
        XCTAssertEqual(initialCalls.first?.request.expression, chosen)
        let history = try await fixture.store.history()
        let entry = try XCTUnwrap(history.last)
        XCTAssertEqual(entry.writingProfile?.expression, chosen)
        XCTAssertEqual(fixture.responses.generationCount, 1)
        XCTAssertEqual(fixture.insertions.texts.count, 1)
        fixture.model.reviewHistory(entry)
        for _ in 0..<200 where fixture.model.manualDecisionReviewInProgress {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let allCalls = await evaluator.calls
        XCTAssertEqual(allCalls.count, 2)
        XCTAssertEqual(allCalls.last?.request.expression, chosen, "Saved review uses the captured intent, not today's setting")
    }

    func testExpressionSurvivesOneRepairGenerationAndRecheck() async throws {
        let chosen = DictationExpression(style: .clear, strength: 60)
        let source = "내일 회의를 시작하지 마세요"
        let corrected = "내일 회의를 시작하지 마세요."
        let responses = DecisionAppResponses(transcripts: [source], outputs: ["내일 회의를 시작해 주세요.", corrected])
        let evaluator = DecisionAppEvaluator(riskSequence: [0.95, 0.1])
        let fixture = try fixture(mode: .repair, evaluator: evaluator, responses: responses) { $0.dictationExpression = chosen }
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [corrected])
        let calls = await evaluator.calls
        XCTAssertEqual(calls.map(\.request.expression), [chosen, chosen])
        XCTAssertEqual(responses.generationCount, 2)
        for body in responses.generationBodies {
            let payload = try generationPayload(body)
            XCTAssertEqual((payload["dictation_expression"] as? [String: Any])?["style"] as? String, "clear")
        }
    }

    func testPreferencesDefaultAndUnknownModesNeverOptIn() throws {
        for json in ["{}", #"{"decisionReviewMode":"unknown","retentionDays":7}"#,
                     #"{"decisionReviewMode":true,"retentionDays":7}"#] {
            let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
            XCTAssertEqual(preferences.decisionReviewMode, .off)
        }
        for mode in DecisionReviewMode.allCases {
            var preferences = Preferences.koreanForTesting; preferences.decisionReviewMode = mode
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
        let editCalls = await evaluator.editCalls, comparisonCalls = await evaluator.comparisonCalls
        XCTAssertTrue(editCalls.isEmpty)
        XCTAssertTrue(comparisonCalls.isEmpty)
        XCTAssertEqual(fixture.responses.transcriptionHosts.count, 1)
        XCTAssertEqual(fixture.responses.generationCount, 1)
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
        var direct = Preferences.koreanForTesting; direct.decisionProvider = .typeSafe; direct.decisionReviewMode = .observe
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

    func testEconomySkipsOnlyExactNonemptyTextWithoutSpellingCandidates() async throws {
        let text = "내일 회의는 세 시입니다."
        let evaluator = DecisionAppEvaluator(risk: 0.99)
        let responses = DecisionAppResponses(transcripts: [text], outputs: [text])
        let fixture = try fixture(mode: .protect, evaluator: evaluator, responses: responses) {
            $0.jevEconomyEnabled = true
        }
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.insertions.texts, [text])
        XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("생략") == true)
        XCTAssertTrue(fixture.model.decisionRiskSignals.isEmpty)
    }

    func testEconomyStillReviewsChangedTextAndExactTextWithSpellingCandidates() async throws {
        for (transcript, output) in [("내일 회의는 세 시입니다", "내일 회의는 세 시입니다."),
                                     (DecisionAppURLProtocol.transcript, DecisionAppURLProtocol.transcript)] {
            let evaluator = DecisionAppEvaluator(risk: 0.99)
            let fixture = try fixture(mode: .protect, evaluator: evaluator,
                                      responses: .init(transcripts: [transcript], outputs: [output])) {
                $0.jevEconomyEnabled = true
            }
            await recordAndWait(fixture)
            let calls = await evaluator.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
        }
    }

    func testDetailedReviewSendsOnlyExplicitlyEnabledAxes() async throws {
        for enabled in [false, true] {
            let evaluator = DecisionAppEvaluator()
            let fixture = try fixture(mode: .protect, evaluator: evaluator) {
                $0.jevDetailedReviewEnabled = enabled
            }
            await recordAndWait(fixture)
            let calls = await evaluator.calls
            XCTAssertEqual(calls.first?.request.detailAxes, enabled ? DecisionDetailAxis.allCases : [])
        }
    }

    func testAmbiguousOrUnavailableEditHoldsBeforePaidGeneration() async throws {
        for unavailable in [false, true] {
            let evaluator = DecisionAppEvaluator(editChoice: .ambiguous,
                editFailure: unavailable ? .connectionFailed : nil)
            let fixture = try fixture(mode: .off, evaluator: evaluator) { $0.jevClarifyEditsEnabled = true }
            await recordAndWait(fixture, mode: .rewrite)
            let calls = await evaluator.editCalls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.original, "selected synthetic source")
            XCTAssertEqual(calls.first?.instruction, DecisionAppURLProtocol.transcript)
            XCTAssertEqual(fixture.responses.generationCount, 0)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            XCTAssertEqual(fixture.model.jevEditClarification?.instruction, DecisionAppURLProtocol.transcript)
            XCTAssertNil(fixture.model.jevEditClarification?.output)
            XCTAssertEqual(fixture.model.preferences.decisionReviewMode, .off)
            let history = try await fixture.store.history()
            XCTAssertTrue(history.isEmpty)
        }
    }

    func testClearEditContinuesExistingGenerationAndInsertion() async throws {
        let evaluator = DecisionAppEvaluator(editChoice: .clear)
        let fixture = try fixture(mode: .off, evaluator: evaluator) { $0.jevClarifyEditsEnabled = true }
        await recordAndWait(fixture, mode: .rewrite)
        let calls = await evaluator.editCalls, regularCalls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(regularCalls.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 1)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertNil(fixture.model.jevEditClarification)
    }

    func testRevokingEditClarificationDiscardsItsPendingAssessment() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Edit assessment waits"))
        let evaluator = DecisionAppEvaluator(editChoice: .ambiguous, editGate: gate)
        let fixture = try fixture(mode: .off, evaluator: evaluator) { $0.jevClarifyEditsEnabled = true }
        let completed = watchCompletion(fixture.model)
        await startAndStop(fixture, mode: .rewrite)
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.preferences.jevClarifyEditsEnabled = false
        await gate.release()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        XCTAssertNil(fixture.model.jevEditClarification, "An opted-out assessment cannot publish a late clarification")
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testRevokingDetailedReviewDuringRecordingDoesNotSendCapturedExtraQuestions() async throws {
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .protect, evaluator: evaluator) { $0.jevDetailedReviewEnabled = true }
        await fixture.model.toggle(.dictation)
        fixture.model.preferences.jevDetailedReviewEnabled = false
        let completed = watchCompletion(fixture.model)
        fixture.model.elapsed = 1; fixture.model.stop()
        await fulfillment(of: [completed], timeout: 5)
        fixture.model.onPhaseChange = nil
        let calls = await evaluator.calls
        XCTAssertTrue(calls.allSatisfy { $0.request.detailAxes.isEmpty })
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
    }

    func testReRecognitionUsesOneAlternativeOnTheSameProviderAndHoldsChangedText() async throws {
        let alternative = "OpenRouter 연결을 취소해 주세요."
        let evaluator = DecisionAppEvaluator(transcriptChoice: .meaningfulDifference)
        let fixture = try fixture(mode: .off, evaluator: evaluator,
                                  responses: .init(transcripts: [DecisionAppURLProtocol.transcript, alternative])) {
            $0.jevReRecognitionEnabled = true
        }
        await recordAndWait(fixture)
        let calls = await evaluator.comparisonCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.original, DecisionAppURLProtocol.transcript)
        XCTAssertEqual(calls.first?.alternative, alternative)
        XCTAssertEqual(fixture.responses.transcriptionHosts, ["api.groq.com", "api.groq.com"])
        XCTAssertEqual(fixture.responses.generationCount, 1)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertEqual(fixture.model.jevReRecognition?.alternative, alternative)
        XCTAssertFalse(fixture.model.jevReRecognition?.isProcessing ?? true)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.last?.originalText, DecisionAppURLProtocol.transcript)
        XCTAssertEqual(history.last?.resultText, DecisionAppURLProtocol.output)
    }

    func testEquivalentReRecognitionInsertsOnlyTheFirstCleanedResult() async throws {
        let evaluator = DecisionAppEvaluator(transcriptChoice: .equivalent)
        let fixture = try fixture(mode: .off, evaluator: evaluator,
                                  responses: .init(transcripts: [DecisionAppURLProtocol.transcript, "OpenRouter 연결을 확인해 주세요."])) {
            $0.jevReRecognitionEnabled = true
        }
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
        XCTAssertEqual(fixture.responses.generationCount, 1)
        XCTAssertEqual(fixture.responses.transcriptionHosts.count, 2)
        XCTAssertNil(fixture.model.jevReRecognition?.output)
    }

    func testCancelledReRecognitionDiscardsLateComparisonWithoutTyping() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Transcript comparison waits"))
        let evaluator = DecisionAppEvaluator(transcriptChoice: .equivalent, comparisonGate: gate)
        let fixture = try fixture(mode: .off, evaluator: evaluator) { $0.jevReRecognitionEnabled = true }
        await startAndStop(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.model.cancel()
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(fixture.model.jevReRecognition)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertFalse(fixture.model.isBusy)
    }

    func testDismissingReRecognitionCardImmediatelyCancelsThePendingAudioJob() async throws {
        try await assertPendingReRecognitionStopsImmediately(revokeOption: false)
    }

    func testRevokingReRecognitionImmediatelyCancelsThePendingAudioJob() async throws {
        try await assertPendingReRecognitionStopsImmediately(revokeOption: true)
    }

    private func assertPendingReRecognitionStopsImmediately(revokeOption: Bool) async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Initial transcript comparison waits"))
        let evaluator = DecisionAppEvaluator(transcriptChoice: .equivalent, comparisonGate: gate)
        let fixture = try fixture(mode: .off, evaluator: evaluator) { $0.jevReRecognitionEnabled = true }
        await startAndStop(fixture)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertTrue(fixture.model.phase == .processing)
        XCTAssertTrue(fixture.model.jevReRecognition?.isProcessing == true)
        if revokeOption { fixture.model.preferences.jevReRecognitionEnabled = false }
        else { fixture.model.dismissJevReRecognition() }
        // Assert before releasing the service response: the UI must stop immediately.
        XCTAssertTrue(fixture.model.phase == .idle)
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertNil(fixture.model.jevReRecognition)
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(fixture.model.phase == .idle)
        XCTAssertNil(fixture.model.jevReRecognition)
        XCTAssertTrue(fixture.insertions.texts.isEmpty, "A late equivalent result must not resume automatic typing")
        XCTAssertEqual(fixture.responses.transcriptionHosts.count, 2)
        XCTAssertEqual(fixture.responses.generationCount, 1)
        let history = try await fixture.store.history()
        XCTAssertTrue(history.isEmpty)
    }

    func testAutomaticImprovementCreatesAtMostOneCopyOnlyAlternative() async throws {
        let alternative = "OpenRouter 연결을 확인해 주세요."
        let evaluator = DecisionAppEvaluator(risk: 0.99)
        let fixture = try fixture(mode: .protect, evaluator: evaluator,
                                  responses: .init(outputs: [DecisionAppURLProtocol.output, alternative])) {
            $0.jevAutomaticImprovementEnabled = true
        }
        await recordAndWait(fixture)
        for _ in 0..<300 {
            if fixture.model.jevImprovement?.isProcessing == false { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(fixture.model.jevImprovement?.output, alternative)
        XCTAssertFalse(fixture.model.jevImprovement?.isProcessing ?? true)
        XCTAssertEqual(fixture.responses.generationCount, 2)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 2, "The alternative is reviewed once and must not recursively improve itself")
        XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.last?.resultText, DecisionAppURLProtocol.output)
    }

    func testComparisonPreparationCannotSendChangedUnconfirmedCasesModelsOrBudget() async throws {
        for changedField in 0..<3 {
            let gate = DecisionAppGate(entered: expectation(description: "Comparison connection waits"))
            let keys = DecisionAppKeyStorage(); keys.readGate = gate
            let evaluator = DecisionAppEvaluator()
            let fixture = try fixture(mode: .off, evaluator: evaluator, decisionProvider: .typeSafe, keyStore: keys)
            let comparison = fixture.model.jevModelComparison
            comparison.cases = [.init(transcript: "내일 회의를 시작해 주세요", approvedText: "내일 회의를 시작해 주세요.")]
            comparison.selectedModels = ["qwen/qwen3.7-flash", "openai/gpt-6-luna"]
            comparison.budgetUSD = 0.20
            fixture.model.runJevModelComparison()
            await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertTrue(fixture.model.jevModelComparisonPreparing)
            switch changedField {
            case 0: comparison.cases[0].transcript = "이 새 문장은 전송 승인을 받지 않았습니다"
            case 1: comparison.selectedModels.reverse()
            default: comparison.budgetUSD = 0.10
            }
            await gate.release()
            for _ in 0..<200 {
                if !fixture.model.jevModelComparisonPreparing { break }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertFalse(fixture.model.jevModelComparisonPreparing)
            XCTAssertFalse(comparison.isRunning)
            XCTAssertEqual(fixture.responses.generationCount, 0)
            let calls = await evaluator.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testRepairRechecksBeforeTypingAndLearnsOnlyResolvedCategoriesForTheNextRequest() async throws {
        let source = "내일 회의를 시작하지 마세요"
        let incorrect = "내일 회의를 시작해 주세요."
        let corrected = "내일 회의를 시작하지 마세요."
        let responses = DecisionAppResponses(transcripts: [source], outputs: [incorrect, corrected, corrected])
        let evaluator = DecisionAppEvaluator(riskSequence: [0.95, 0.1, 0.1])
        let fixture = try fixture(mode: .repair, evaluator: evaluator, responses: responses) {
            $0.jevFeedbackLearningEnabled = true
            $0.jevAutomaticImprovementEnabled = true
        }
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [corrected])
        XCTAssertEqual(fixture.model.result, corrected)
        XCTAssertEqual(fixture.responses.generationCount, 2)
        let firstCalls = await evaluator.calls
        XCTAssertEqual(firstCalls.map(\.request.cleanedText), [incorrect, corrected])
        let history = try await fixture.store.history()
        XCTAssertEqual(history.last?.originalText, source)
        XCTAssertEqual(history.last?.resultText, corrected)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertEqual(lessons, [.meaning])
        XCTAssertTrue(fixture.model.dictionary.isEmpty)
        let initialPayload = try generationPayload(fixture.responses.generationBodies[0])
        let repairPayload = try generationPayload(fixture.responses.generationBodies[1])
        XCTAssertNil(initialPayload["review_lessons"])
        XCTAssertEqual(repairPayload["previous_output"] as? String, incorrect)
        XCTAssertEqual(repairPayload["repair_issues"] as? [String], ["meaning"])
        XCTAssertNil(repairPayload["cursor_context"], "Repair cannot reinterpret private surrounding app text as evidence")

        await recordAndWait(fixture)
        XCTAssertEqual(fixture.responses.generationCount, 3)
        let nextPayload = try generationPayload(fixture.responses.generationBodies[2])
        XCTAssertEqual(nextPayload["review_lessons"] as? [String], ["meaning"])
        XCTAssertNil(nextPayload["previous_output"], "A previous sentence must not become the next generation's facts")
        XCTAssertNil(nextPayload["repair_issues"])
        XCTAssertEqual(fixture.insertions.texts, [corrected, corrected])
    }

    func testCleanRepairModeUsesOneGenerationOneReviewAndCreatesNoLesson() async throws {
        let source = "내일 회의를 취소해 주세요"
        let output = "내일 회의를 취소해 주세요."
        let evaluator = DecisionAppEvaluator(risk: 0.1)
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
            responses: .init(transcripts: [source], outputs: [output])) { $0.jevFeedbackLearningEnabled = true }
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [output])
        XCTAssertEqual(fixture.responses.generationCount, 1)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertTrue(lessons.isEmpty)
    }

    func testUnresolvedRepairIsHeldWithoutAThirdGenerationOrFeedbackLesson() async throws {
        let evaluator = DecisionAppEvaluator(riskSequence: [0.95, 0.7])
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
            responses: .init(transcripts: ["내일 회의를 시작하지 마세요"],
                             outputs: ["내일 회의를 시작해 주세요.", "내일 회의를 시작하지 마세요."])) {
            $0.jevFeedbackLearningEnabled = true
        }
        await recordAndWait(fixture)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 2)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(fixture.model.notice?.contains("자동 입력을 보류") == true)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertTrue(lessons.isEmpty)
    }

    func testRecheckFailureDoesNotLearnOrTypeTheCandidate() async throws {
        let evaluator = DecisionAppEvaluator(failure: .timedOut, failureOnCall: 2, riskSequence: [0.95, 0.1])
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
            responses: .init(transcripts: ["내일 회의를 시작하지 마세요"],
                             outputs: ["내일 회의를 시작해 주세요.", "내일 회의를 시작하지 마세요."])) {
            $0.jevFeedbackLearningEnabled = true
        }
        await recordAndWait(fixture)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 2)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertTrue(lessons.isEmpty)
        XCTAssertTrue(fixture.model.jevLearningSummary?.contains("완료하지 못했습니다") == true)
    }

    func testUnavailableInitialRepairReviewFailsClosedWithoutAnAuxiliaryCall() async throws {
        for error in [DecisionError.timedOut, .invalidResponse, .missingAPIKey] {
            let evaluator = DecisionAppEvaluator(failure: error)
            let fixture = try fixture(mode: .repair, evaluator: evaluator,
                responses: .init(transcripts: ["내일 회의를 취소해 주세요"], outputs: ["내일 회의를 취소해 주세요."])) {
                $0.jevFeedbackLearningEnabled = true
            }
            await recordAndWait(fixture)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            XCTAssertEqual(fixture.responses.generationCount, 1)
            let calls = await evaluator.calls
            XCTAssertEqual(calls.count, 1)
            let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
            XCTAssertTrue(lessons.isEmpty)
        }
    }

    func testMissingStoredDirectRepairKeyHoldsInputBeforeAnyJevRequest() async throws {
        let keys = DecisionAppKeyStorage(); keys.value = nil
        let evaluator = DecisionAppEvaluator(risk: 0.95)
        let fixture = try fixture(mode: .repair, evaluator: evaluator, decisionProvider: .typeSafe,
            keyStore: keys, responses: .init(transcripts: ["내일 회의를 취소해 주세요"], outputs: ["내일 회의를 취소해 주세요."]))
        fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
        XCTAssertEqual(fixture.model.requiredJevIssue, .keyMissing)
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .idle)
        XCTAssertTrue(fixture.model.error?.contains("유료 처리는 시작하지 않았습니다") == true)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 0)
        XCTAssertTrue(fixture.responses.transcriptionHosts.isEmpty)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testRequiredDirectKeyWaitBlocksBeforeRecordingOrPaidCalls() async throws {
        let gate = DecisionAppGate(entered: expectation(description: "Required Jev key waits"))
        let keys = DecisionAppKeyStorage(); keys.readGate = gate
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .repair, evaluator: evaluator, decisionProvider: .typeSafe, keyStore: keys)
        fixture.model.loadDecisionKey()
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(fixture.model.requiredJevIssue, .keyLoading)
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .idle)
        XCTAssertTrue(fixture.responses.transcriptionHosts.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 0)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        await gate.release(); await waitForDecisionKey(fixture.model)
        XCTAssertTrue(fixture.model.requiredJevReady)
    }

    func testIncompatibleReuseRepairBlocksRecordingAndRecoveryBeforePaidCalls() async throws {
        let fixture = try fixture(mode: .repair, evaluator: DecisionAppEvaluator(), provider: .groq)
        XCTAssertEqual(fixture.model.requiredJevIssue, .incompatibleTextProvider)
        await fixture.model.toggle(.dictation)
        XCTAssertTrue(fixture.model.phase == .idle)
        let item = FailedRecording(mode: .dictation, provider: .groq, textProvider: .groq,
                                   targetLanguage: "English")
        try await fixture.store.saveFailure(item, audio: Data([1, 2, 3]))
        fixture.model.retry(item)
        XCTAssertTrue(fixture.model.phase == .idle)
        XCTAssertTrue(fixture.responses.transcriptionHosts.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 0)
        let failures = try await fixture.store.failures()
        XCTAssertEqual(failures.map(\.id), [item.id])
    }

    func testMissingOptionalDirectKeyDoesNotBlockOffOrObserve() async throws {
        for mode in [DecisionReviewMode.off, .observe] {
            let keys = DecisionAppKeyStorage(); keys.value = nil
            let fixture = try fixture(mode: mode, evaluator: DecisionAppEvaluator(), decisionProvider: .typeSafe,
                                      keyStore: keys)
            fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
            XCTAssertTrue(fixture.model.requiredJevReady)
            await recordAndWait(fixture)
            XCTAssertEqual(fixture.insertions.texts, [DecisionAppURLProtocol.output])
            XCTAssertEqual(fixture.responses.generationCount, 1)
        }
    }

    func testOversizedSourceStopsBeforeGenerationAndPreservesTranscriptionAndRecovery() async throws {
        for source in [String(repeating: "a", count: 24_001), String(repeating: "가", count: 8_001)] {
            let evaluator = DecisionAppEvaluator()
            let fixture = try fixture(mode: .repair, evaluator: evaluator,
                                      responses: .init(transcripts: [source], outputs: [source]))
            await recordAndWait(fixture)
            XCTAssertEqual(fixture.responses.transcriptionHosts.count, 1)
            XCTAssertEqual(fixture.responses.generationCount, 0)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            XCTAssertEqual(fixture.model.result, source)
            XCTAssertEqual(fixture.model.decisionOriginalText, source)
            XCTAssertEqual(fixture.model.decisionReviewFailure, .lengthLimit)
            let calls = await evaluator.calls
            XCTAssertTrue(calls.isEmpty)
            let failures = try await fixture.store.failures()
            XCTAssertEqual(failures.count, 1)
            XCTAssertEqual(fixture.model.jevQualityMetrics.rows.first?.pipelineHeldCount, 1)
        }
    }

    func testOversizedResultIsNotSentToJevAndRepairKeepsTheManualResult() async throws {
        let source = String(repeating: "가", count: 4_001)
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
                                  responses: .init(transcripts: [source], outputs: [source]))
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.responses.generationCount, 1)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.model.result, source)
        XCTAssertEqual(fixture.model.decisionReviewFailure, .lengthLimit)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.model.jevQualityMetrics.rows.first?.reviewFailureCount, 1)
        XCTAssertEqual(fixture.model.jevQualityMetrics.rows.first?.pipelineHeldCount, 1)
    }

    func testReviewDiagnosticsPreserveAuthLimitTimeoutConnectionAndResponseCauses() async throws {
        let cases: [(DecisionError, JevReviewFailure)] = [(.httpStatus(401), .authentication),
            (.httpStatus(429), .rateLimit), (.timedOut, .timeout), (.connectionFailed, .connection),
            (.invalidResponse, .malformed)]
        for (error, reason) in cases {
            let fixture = try fixture(mode: .repair, evaluator: DecisionAppEvaluator(failure: error))
            await recordAndWait(fixture)
            XCTAssertEqual(fixture.model.decisionReviewFailure, reason)
            XCTAssertTrue(fixture.model.decisionReviewSummary?.contains(reason.message) == true)
            XCTAssertEqual(fixture.model.result, DecisionAppURLProtocol.output)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            let metric = try XCTUnwrap(fixture.model.jevQualityMetrics.rows.first)
            XCTAssertEqual(metric.reviewAttemptCount, 1)
            XCTAssertEqual(metric.reviewFailureCount, 1)
            XCTAssertEqual(metric.reviewCount, 0)
            XCTAssertEqual(metric.pipelineHeldCount, 1)
            XCTAssertNotNil(metric.p95PipelineDuration)
        }
    }

    func testObserveReRecognitionCommunicatesItsPreTypingWait() throws {
        let fixture = try fixture(mode: .observe, evaluator: DecisionAppEvaluator())
        XCTAssertFalse(fixture.model.jevReviewMayDelayInput)
        fixture.model.preferences.jevReRecognitionEnabled = true
        XCTAssertTrue(fixture.model.jevReviewMayDelayInput)
        fixture.model.preferences.decisionReviewMode = .off
        XCTAssertFalse(fixture.model.jevReviewMayDelayInput)
    }

    func testUnknownRepairPriceCannotStartAnExtraGeneration() async throws {
        let evaluator = DecisionAppEvaluator(risk: 0.95)
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
            responses: .init(transcripts: ["내일 회의를 취소해 주세요"], outputs: ["내일 회의를 시작해 주세요."])) {
            $0.textModels["openRouter"] = "synthetic-unknown-price-model"
            $0.jevFeedbackLearningEnabled = true
        }
        await recordAndWait(fixture)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 1)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(fixture.model.jevLearningSummary?.contains("US$0.05") == true)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertTrue(lessons.isEmpty)
    }

    func testIncompleteNameReviewCannotAuthorizeRepairModeTyping() async throws {
        let evaluator = DecisionAppEvaluator(omitTerms: true)
        let fixture = try fixture(mode: .repair, evaluator: evaluator)
        await recordAndWait(fixture)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(calls.first?.request.termCandidates.isEmpty ?? true)
        XCTAssertTrue(fixture.insertions.texts.isEmpty)
        XCTAssertEqual(fixture.responses.generationCount, 1)
    }

    func testLocalLiteralGuardRepairsAChangedNumberEvenWhenInitialJevMissesIt() async throws {
        let source = "내일 오후 3시에 회의를 시작해 주세요"
        let wrong = "내일 오후 4시에 회의를 시작해 주세요."
        let correct = "내일 오후 3시에 회의를 시작해 주세요."
        let evaluator = DecisionAppEvaluator(risk: 0.1)
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
            responses: .init(transcripts: [source], outputs: [wrong, correct])) {
            $0.jevFeedbackLearningEnabled = true
        }
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [correct])
        XCTAssertEqual(fixture.responses.generationCount, 2)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 2)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertFalse(lessons.isEmpty)
    }

    func testRepairModeTypesSupportedLargerKoreanQuantityWithoutAnUnnecessaryRepair() async throws {
        for (source, output) in [("백 명을 초대해 주세요", "100명을 초대해 주세요."),
                                 ("천 원을 보내 주세요", "1000원을 보내 주세요."),
                                 ("만 개를 준비해 주세요", "10000개를 준비해 주세요.")] {
            let evaluator = DecisionAppEvaluator(risk: 0.1)
            let fixture = try fixture(mode: .repair, evaluator: evaluator,
                responses: .init(transcripts: [source], outputs: [output]))
            await recordAndWait(fixture)
            XCTAssertEqual(fixture.insertions.texts, [output], source)
            XCTAssertEqual(fixture.responses.generationCount, 1, source)
            let reviews = await evaluator.calls
            XCTAssertEqual(reviews.count, 1, source)
            XCTAssertFalse(fixture.model.jevRepairInProgress)
        }
    }

    func testCancelledOrRevokedRepairCannotTypeOrLearnAfterItsRecheckReturns() async throws {
        for action in 0..<3 {
            let gate = DecisionAppGate(entered: expectation(description: "Repair recheck waits \(action)"))
            let evaluator = DecisionAppEvaluator(riskSequence: [0.95, 0.1], gate: gate, gateOnCall: 2)
            let fixture = try fixture(mode: .repair, evaluator: evaluator, decisionProvider: .typeSafe,
                responses: .init(transcripts: ["내일 회의를 시작하지 마세요"],
                                 outputs: ["내일 회의를 시작해 주세요.", "내일 회의를 시작하지 마세요."])) {
                $0.jevFeedbackLearningEnabled = true
            }
            fixture.model.loadDecisionKey(); await waitForDecisionKey(fixture.model)
            let completed = watchCompletion(fixture.model)
            await startAndStop(fixture)
            await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            switch action {
            case 0: fixture.model.cancel()
            case 1: fixture.model.preferences.decisionReviewMode = .off
            default:
                fixture.model.decisionAPIKeyDraft = "synthetic-replaced-repair-key"
                fixture.model.saveDecisionKey(); await waitForDecisionKey(fixture.model)
            }
            await gate.release()
            await fulfillment(of: [completed], timeout: 3)
            fixture.model.onPhaseChange = nil
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            XCTAssertFalse(fixture.model.jevRepairInProgress)
            let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
            XCTAssertTrue(lessons.isEmpty)
            XCTAssertNil(fixture.model.jevImprovement)
        }
    }

    func testObserveRepairsAndLearnsInTheBackgroundWithoutReplacingTypedTextOrHistory() async throws {
        let source = "내일 회의를 시작하지 마세요"
        let wrong = "내일 회의를 시작해 주세요."
        let correct = "내일 회의를 시작하지 마세요."
        let evaluator = DecisionAppEvaluator(riskSequence: [0.95, 0.1])
        let fixture = try fixture(mode: .observe, evaluator: evaluator,
            responses: .init(transcripts: [source], outputs: [wrong, correct])) { $0.jevFeedbackLearningEnabled = true }
        await recordAndWait(fixture)
        await waitForRepairWork(fixture.model)
        XCTAssertEqual(fixture.insertions.texts, [wrong])
        XCTAssertEqual(fixture.model.result, wrong)
        XCTAssertEqual(fixture.responses.generationCount, 2)
        XCTAssertEqual(fixture.model.jevImprovement?.output, correct)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.last?.resultText, wrong)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertEqual(lessons, [.meaning])
    }

    func testFailedNewObservationCannotReuseThePreviousJobsValidReview() async throws {
        let evaluator = DecisionAppEvaluator(failure: .invalidResponse, failureOnCall: 3, riskSequence: [0.95, 0.1, 0.95])
        let fixture = try fixture(mode: .observe, evaluator: evaluator,
            responses: .init(transcripts: ["내일 회의를 시작하지 마세요"],
                             outputs: ["내일 회의를 시작해 주세요.", "내일 회의를 시작하지 마세요.", "내일 회의를 시작해 주세요."])) {
            $0.jevFeedbackLearningEnabled = true
        }
        await recordAndWait(fixture); await waitForRepairWork(fixture.model)
        XCTAssertNotNil(fixture.model.jevImprovement)
        await recordAndWait(fixture); await waitForReview(fixture.model)
        XCTAssertEqual(fixture.responses.generationCount, 3)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertNil(fixture.model.jevImprovement)
        XCTAssertEqual(fixture.insertions.texts.count, 2)
        XCTAssertTrue(fixture.model.decisionReviewSummary?.contains("완료하지 못했습니다") == true)
    }

    func testRepairStillRunsWithFeedbackLearningOffButStoresNoCategories() async throws {
        let evaluator = DecisionAppEvaluator(riskSequence: [0.95, 0.1])
        let corrected = "내일 회의를 시작하지 마세요."
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
            responses: .init(transcripts: ["내일 회의를 시작하지 마세요"], outputs: ["내일 회의를 시작해 주세요.", corrected]))
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [corrected])
        XCTAssertEqual(fixture.responses.generationCount, 2)
        let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
        XCTAssertTrue(lessons.isEmpty)
        XCTAssertTrue(fixture.model.jevLearningSummary?.contains("꺼져") == true)
    }

    func testEconomyCannotSkipTheRequiredReviewInRepairMode() async throws {
        let text = "내일 회의를 취소해 주세요"
        let evaluator = DecisionAppEvaluator()
        let fixture = try fixture(mode: .repair, evaluator: evaluator,
            responses: .init(transcripts: [text], outputs: [text])) { $0.jevEconomyEnabled = true }
        await recordAndWait(fixture)
        XCTAssertEqual(fixture.insertions.texts, [text])
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(fixture.responses.generationCount, 1)
        XCTAssertFalse(fixture.model.decisionReviewSummary?.contains("생략") == true)
    }

    func testHistoryRevocationAndFullDeletionClearLessonsAndDiscardLateRepairLearning() async throws {
        for deletesHistory in [false, true] {
            let gate = DecisionAppGate(entered: expectation(description: "Learning reset while recheck waits"))
            let evaluator = DecisionAppEvaluator(riskSequence: [0.95, 0.1], gate: gate, gateOnCall: 2)
            let fixture = try fixture(mode: .repair, evaluator: evaluator,
                responses: .init(transcripts: ["내일 회의를 시작하지 마세요"],
                                 outputs: ["내일 회의를 시작해 주세요.", "내일 회의를 시작하지 마세요."])) {
                $0.jevFeedbackLearningEnabled = true
            }
            try await fixture.store.recordJevRepairLesson(provider: .openRouter, model: fixture.model.preferences.textModel, issues: [.numbers])
            let completed = watchCompletion(fixture.model)
            await startAndStop(fixture)
            await fulfillment(of: [gate.entered], timeout: 3)
            if deletesHistory { await fixture.model.deleteHistory() }
            else { fixture.model.preferences.historyEnabled = false }
            await gate.release()
            await fulfillment(of: [completed], timeout: 3)
            fixture.model.onPhaseChange = nil
            for _ in 0..<20 { await Task.yield() }
            let lessons = try await fixture.store.jevRepairLessons(provider: .openRouter, model: fixture.model.preferences.textModel)
            XCTAssertTrue(lessons.isEmpty)
            XCTAssertTrue(fixture.model.jevLearnedIssues.isEmpty)
            XCTAssertTrue(fixture.insertions.texts.isEmpty)
            XCTAssertNil(fixture.model.jevImprovement)
            let history = try await fixture.store.history()
            XCTAssertTrue(history.isEmpty, "Revoked pending repair must not resurrect a cleared history record")
        }
    }

    func testSavedFeedbackDoesNotCrossModelOrProviderScopeAndIsOmittedWhenLearningIsOff() async throws {
        for learning in [false, true] {
            let evaluator = DecisionAppEvaluator()
            let fixture = try fixture(mode: .repair, evaluator: evaluator,
                responses: .init(transcripts: ["내일 회의를 취소해 주세요"], outputs: ["내일 회의를 취소해 주세요."])) {
                $0.jevFeedbackLearningEnabled = learning
            }
            let model = fixture.model.preferences.textModel
            try await fixture.store.recordJevRepairLesson(provider: .groq, model: model, issues: [.numbers])
            try await fixture.store.recordJevRepairLesson(provider: .openRouter, model: "different-model", issues: [.conditions])
            if !learning { try await fixture.store.recordJevRepairLesson(provider: .openRouter, model: model, issues: [.negation]) }
            await recordAndWait(fixture)
            let payload = try generationPayload(fixture.responses.generationBodies[0])
            XCTAssertNil(payload["review_lessons"])
            XCTAssertEqual(fixture.insertions.texts, ["내일 회의를 취소해 주세요."])
        }
    }

    private func generationPayload(_ body: Data) throws -> [String: Any] {
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(envelope["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.first { $0["role"] as? String == "user" })
        let content = try XCTUnwrap(user["content"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
    }

    private func waitForRepairWork(_ model: AppModel) async {
        for _ in 0..<500 {
            if !model.jevRepairInProgress, let summary = model.jevLearningSummary,
               !summary.contains("있어요") { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("The synthetic repair did not finish")
    }

    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let insertions: DecisionAppInsertions
        let keys: DecisionAppKeyStorage
        let responses: DecisionAppResponses
    }
    private func fixture(mode: DecisionReviewMode, evaluator: DecisionAppEvaluator,
                         provider: AIProvider = .openRouter, history: Bool = true,
                         decisionProvider: DecisionProvider = .openRouter,
                         keyStore: DecisionAppKeyStorage? = nil, cachedKeys: Bool = false,
                         responses: DecisionAppResponses = .init(),
                         configure: (inout Preferences) -> Void = { _ in }) throws -> Fixture {
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
        runtime.stopRecording = { audio }; runtime.recordingElapsed = { 1 }; runtime.recordingPeakDB = { -12 }
        runtime.insertText = { text, _, _, cancelled in
            XCTAssertFalse(cancelled()); insertions.texts.append(text); return .confirmed(.paste)
        }
        var preferences = Preferences.koreanForTesting
        preferences.provider = .groq; preferences.textProvider = provider
        preferences.decisionReviewMode = mode; preferences.automaticLearningEnabled = false
        preferences.decisionProvider = decisionProvider
        preferences.historyEnabled = history
        configure(&preferences)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DecisionAppURLProtocol.self]
        let responseID = UUID().uuidString
        DecisionAppURLProtocol.responses.register(responses, id: responseID)
        config.httpAdditionalHeaders = ["X-OpenNoType-Synthetic-Fixture": responseID]
        let session = URLSession(configuration: config)
        let model = AppModel(store: store, runtime: runtime, client: ProviderClient(session: session),
                             decisionClient: evaluator, startServices: false, preferences: preferences, useCachedKeys: cachedKeys)
        addTeardownBlock { @MainActor in
            model.cancel(); session.invalidateAndCancel()
            DecisionAppURLProtocol.responses.unregister(id: responseID)
            try? FileManager.default.removeItem(at: root)
        }
        return .init(model: model, store: store, insertions: insertions, keys: keys, responses: responses)
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
    struct EditCall { let original: String; let instruction: String }
    struct ComparisonCall { let original: String; let alternative: String }
    private(set) var calls: [Call] = []
    private(set) var editCalls: [EditCall] = []
    private(set) var comparisonCalls: [ComparisonCall] = []
    let risk: Double
    let proposeTerm: Bool
    let omitTerms: Bool
    let failure: DecisionError?
    let failureOnCall: Int?
    let riskSequence: [Double]?
    let gate: DecisionAppGate?
    let gateOnCall: Int
    let editChoice: DecisionEditChoice
    let editFailure: DecisionError?
    let editGate: DecisionAppGate?
    let transcriptChoice: DecisionTranscriptChoice
    let comparisonGate: DecisionAppGate?
    init(risk: Double = 0.1, proposeTerm: Bool = false, omitTerms: Bool = false, failure: DecisionError? = nil,
         failureOnCall: Int? = nil, riskSequence: [Double]? = nil,
         gate: DecisionAppGate? = nil, gateOnCall: Int = 1,
         editChoice: DecisionEditChoice = .clear, editFailure: DecisionError? = nil, editGate: DecisionAppGate? = nil,
         transcriptChoice: DecisionTranscriptChoice = .equivalent, comparisonGate: DecisionAppGate? = nil) {
        self.risk = risk; self.proposeTerm = proposeTerm; self.failure = failure; self.gate = gate
        self.omitTerms = omitTerms
        self.failureOnCall = failureOnCall; self.riskSequence = riskSequence; self.gateOnCall = gateOnCall
        self.editChoice = editChoice; self.editFailure = editFailure; self.editGate = editGate
        self.transcriptChoice = transcriptChoice; self.comparisonGate = comparisonGate
    }
    func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        calls.append(.init(request: input, key: configuration.apiKey, provider: configuration.provider))
        let callNumber = calls.count
        if let gate, callNumber == gateOnCall { await gate.wait() }
        try Task.checkCancellation()
        if let failure, failureOnCall == nil || failureOnCall == callNumber { throw failure }
        let usage = ProviderUsage(provider: configuration.provider == .openRouter ? .openRouter : nil,
                                  decisionProvider: configuration.provider, model: configuration.provider.model, stage: .decisionReview)
        await onUsage?(usage)
        let terms: [DecisionTermResult] = omitTerms ? [] : input.termCandidates.map {
            proposeTerm
                ? .init(id: $0.id, choice: .useCandidate, probabilities: [.useCandidate: 0.8, .keepOriginal: 0.1, .uncertain: 0.1], confidence: 0.8)
                : .init(id: $0.id, choice: .keepOriginal, probabilities: [.useCandidate: 0.05, .keepOriginal: 0.9, .uncertain: 0.05], confidence: 0.9)
        }
        let callRisk = riskSequence.flatMap { $0.isEmpty ? nil : $0[min(callNumber - 1, $0.count - 1)] } ?? risk
        return .init(meaningChanged: callRisk, contentAdded: 0.05, contentOmitted: 0.05, terms: terms,
                     reportedModel: configuration.provider.model)
    }
    func assessEditAmbiguity(originalText: String, instruction: String, configuration: DecisionConfiguration,
                             onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionEditAssessment {
        editCalls.append(.init(original: originalText, instruction: instruction))
        if let editGate { await editGate.wait() }
        try Task.checkCancellation()
        if let editFailure { throw editFailure }
        let probabilities = Dictionary(uniqueKeysWithValues: DecisionEditChoice.allCases.map {
            ($0, $0 == editChoice ? 0.9 : 0.05)
        })
        return .init(choice: editChoice, probabilities: probabilities, confidence: 0.9,
                     reportedModel: configuration.provider.model)
    }
    func compareTranscriptions(original: String, alternative: String, configuration: DecisionConfiguration,
                               onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionTranscriptAssessment {
        comparisonCalls.append(.init(original: original, alternative: alternative))
        if let comparisonGate { await comparisonGate.wait() }
        try Task.checkCancellation()
        let probabilities = Dictionary(uniqueKeysWithValues: DecisionTranscriptChoice.allCases.map {
            ($0, $0 == transcriptChoice ? 0.9 : 0.05)
        })
        return .init(choice: transcriptChoice, probabilities: probabilities, confidence: 0.9,
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
    static let responses = DecisionAppResponseRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            guard let id = request.value(forHTTPHeaderField: "X-OpenNoType-Synthetic-Fixture"),
                  let fixture = Self.responses.value(id: id) else { throw URLError(.resourceUnavailable) }
            let object: [String: Any]
            if url.path.hasSuffix("/audio/transcriptions") { object = ["text": fixture.transcript(host: url.host ?? "")] }
            else if url.path.hasSuffix("/chat/completions") {
                let encoded = try JSONSerialization.data(withJSONObject: ["text": fixture.output(body: try Self.bodyData(request))])
                object = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": String(decoding: encoded, as: UTF8.self)]]]]
            } else { throw URLError(.unsupportedURL) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    private static func bodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var body = Data(), buffer = [UInt8](repeating: 0, count: 8_192)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            body.append(contentsOf: buffer.prefix(count))
            if body.count > 2_000_000 { throw URLError(.dataLengthExceedsMaximum) }
        }
        return body
    }
}

/// Session-scoped fixtures avoid shared response ordering when unrelated tests run concurrently.
private final class DecisionAppResponses: @unchecked Sendable {
    private let lock = NSLock()
    private let transcripts: [String]
    private let outputs: [String]
    private var hosts: [String] = []
    private var generations = 0
    private var bodies: [Data] = []
    init(transcripts: [String] = [DecisionAppURLProtocol.transcript],
         outputs: [String] = [DecisionAppURLProtocol.output]) {
        precondition(!transcripts.isEmpty && !outputs.isEmpty)
        self.transcripts = transcripts; self.outputs = outputs
    }
    var transcriptionHosts: [String] { lock.lock(); defer { lock.unlock() }; return hosts }
    var generationCount: Int { lock.lock(); defer { lock.unlock() }; return generations }
    var generationBodies: [Data] { lock.lock(); defer { lock.unlock() }; return bodies }
    func transcript(host: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let value = transcripts[min(hosts.count, transcripts.count - 1)]
        hosts.append(host); return value
    }
    func output(body: Data) -> String {
        lock.lock(); defer { lock.unlock() }
        let value = outputs[min(generations, outputs.count - 1)]
        generations += 1; bodies.append(body); return value
    }
}
private final class DecisionAppResponseRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: DecisionAppResponses] = [:]
    func register(_ value: DecisionAppResponses, id: String) { lock.lock(); defer { lock.unlock() }; values[id] = value }
    func unregister(id: String) { lock.lock(); defer { lock.unlock() }; values[id] = nil }
    func value(id: String) -> DecisionAppResponses? { lock.lock(); defer { lock.unlock() }; return values[id] }
}
