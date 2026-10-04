import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class DecisionReviewActionsTests: KoreanPresentationTestCase {
    func testManualDirectReviewWithModeOffUsesSavedKeyAndDoesNotChangeTextHistoryOrInput() async throws {
        let evaluator = DecisionActionEvaluator(risk: 0.96, proposeTerm: true)
        let f = try fixture(mode: .off, evaluator: evaluator, provider: .groq, decisionProvider: .typeSafe)
        let entry = try await addHistory(f)
        f.model.result = "Unrelated current text"
        f.model.decisionAPIKeyDraft = "unsaved-key"
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.key, "synthetic-typesafe-key")
        XCTAssertEqual(calls.first?.provider, .typeSafe)
        XCTAssertEqual(f.model.preferences.decisionReviewMode, .off)
        XCTAssertEqual(f.model.result, "Unrelated current text")
        XCTAssertEqual(f.model.decisionReviewTarget?.id, entry.id)
        XCTAssertEqual(f.model.decisionReviewTarget?.kind, .history)
        XCTAssertEqual(f.model.decisionRiskSignals.map(\.isHigh), [true, false, false])
        XCTAssertTrue(f.insertions.texts.isEmpty)
        let history = try await f.store.history()
        XCTAssertEqual(history.map(\.resultText), [entry.resultText])
        let usage = try await f.store.usageRecords()
        XCTAssertEqual(usage.map(\.event.stage), [.decisionReview])
    }

    func testRecentResultCanBeReviewedWithoutEnablingAutomaticReview() async throws {
        let evaluator = DecisionActionEvaluator(proposeTerm: true)
        let f = try fixture(mode: .off, evaluator: evaluator)
        await recordAndWait(f)
        let before = f.model.result, targetID = f.model.recentDecisionTarget?.id
        f.model.reviewRecentResult(); await waitForManualReview(f.model)
        XCTAssertEqual(f.model.decisionReviewTarget?.id, targetID)
        XCTAssertEqual(f.model.decisionReviewTarget?.kind, .recent)
        XCTAssertEqual(f.model.result, before)
        XCTAssertEqual(f.insertions.texts.count, 1, "Manual review must not insert again")
        XCTAssertEqual(f.model.preferences.decisionReviewMode, .off)
    }

    func testManualHistoryRequestUsesCanonicalStoredTextForTheID() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        let entry = try await addHistory(f)
        var forged = entry; forged.originalText = "Unrelated caller text"; forged.resultText = "Different result"
        f.model.reviewHistory(forged); await waitForManualReview(f.model)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.first?.request.transcript, entry.originalText)
        XCTAssertEqual(calls.first?.request.cleanedText, entry.resultText)
    }

    func testCompletedReprocessingPreviewHasItsOwnReviewTargetAndIsNotOverwritten() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        let entry = try await addHistory(f)
        f.model.reprocessHistory(entry); await waitForPreview(f.model)
        let preview = try XCTUnwrap(f.model.historyReprocessing)
        f.model.reviewHistoryPreview(); await waitForManualReview(f.model)
        XCTAssertEqual(f.model.decisionReviewTarget?.kind, .reprocessed)
        XCTAssertEqual(f.model.decisionReviewTarget?.id, preview.id)
        XCTAssertEqual(f.model.decisionReviewTarget?.previewID, preview.id)
        XCTAssertEqual(f.model.decisionReviewTarget?.sourceHistoryID, entry.id)
        XCTAssertEqual(f.model.historyReprocessing?.result, preview.result)
        XCTAssertTrue(f.insertions.texts.isEmpty)
    }

    func testManualReviewRejectsOversizedEmptyOrUnsupportedHistoryBeforeRequest() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        for (mode, text) in [(InputMode.dictation, String(repeating: "한", count: 8_001)), (.dictation, " "), (.translation, "source"), (.rewrite, "source")] {
            let entry = try await addHistory(f, mode: mode, transcript: text)
            f.model.reviewHistory(entry); await waitForManualReview(f.model)
        }
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(f.insertions.texts.isEmpty)
    }

    func testManualReviewFailureNeverPublishesSuccessOrChangesResult() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(failure: .timedOut))
        let entry = try await addHistory(f)
        f.model.result = "Keep this"
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        XCTAssertTrue(f.model.manualDecisionReviewStatus?.contains("완료하지 못했습니다") == true)
        XCTAssertNil(f.model.decisionReviewSummary)
        XCTAssertTrue(f.model.decisionProposals.isEmpty)
        XCTAssertEqual(f.model.result, "Keep this")
    }

    func testManualLateResultsAreDiscardedAfterCancelProviderKeyOrHistoryChanges() async throws {
        for action in 0..<5 {
            let gate = DecisionActionGate(entered: expectation(description: "Manual review waits"))
            let evaluator = DecisionActionEvaluator(risk: 0.99, proposeTerm: true, gate: gate)
            let f = try fixture(mode: .off, evaluator: evaluator, decisionProvider: .typeSafe)
            let entry = try await addHistory(f)
            f.model.reviewHistory(entry)
            await fulfillment(of: [gate.entered], timeout: 3)
            switch action {
            case 0: f.model.cancelManualDecisionReview()
            case 1: f.model.preferences.decisionProvider = .openRouter
            case 2:
                f.model.decisionAPIKeyDraft = "replacement"
                f.model.saveDecisionKey(); await waitForDecisionKey(f.model)
            case 3: await f.model.deleteHistory(entry)
            default: f.model.preferences.historyEnabled = false
            }
            await gate.release()
            for _ in 0..<20 { await Task.yield() }
            XCTAssertNil(f.model.decisionReviewTarget)
            XCTAssertNil(f.model.decisionReviewSummary)
            XCTAssertTrue(f.model.decisionProposals.isEmpty)
            XCTAssertFalse(f.model.manualDecisionReviewInProgress)
            XCTAssertTrue(f.insertions.texts.isEmpty)
        }
    }

    func testPreviewDismissalDiscardsItsLateManualReview() async throws {
        let gate = DecisionActionGate(entered: expectation(description: "Preview review waits"))
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(gate: gate))
        let entry = try await addHistory(f)
        f.model.reprocessHistory(entry); await waitForPreview(f.model)
        f.model.reviewHistoryPreview(); await fulfillment(of: [gate.entered], timeout: 3)
        f.model.dismissHistoryReprocessing()
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(f.model.historyReprocessing)
        XCTAssertNil(f.model.decisionReviewTarget)
        XCTAssertFalse(f.model.manualDecisionReviewInProgress)
    }

    func testNewRecordingCancelsManualReviewWithoutBlockingRecording() async throws {
        let gate = DecisionActionGate(entered: expectation(description: "Manual background review waits"))
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(gate: gate))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertFalse(f.model.isBusy)
        await f.model.toggle(.dictation)
        XCTAssertTrue(f.model.isRecording)
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(f.model.decisionReviewTarget)
        XCTAssertTrue(f.model.isRecording)
    }

    func testKeyLoadingCancelledBeforeCompletionNeverSendsTheTarget() async throws {
        let gate = DecisionActionGate(entered: expectation(description: "Key read waits"))
        let keys = DecisionActionKeyStorage(); keys.readGate = gate
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator, decisionProvider: .typeSafe, keyStore: keys)
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await fulfillment(of: [gate.entered], timeout: 3)
        f.model.cancelManualDecisionReview()
        await gate.release(); await waitForDecisionKey(f.model)
        for _ in 0..<20 { await Task.yield() }
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(f.model.decisionReviewTarget)
    }

    func testDeletedPersistedHistoryIsRecheckedBeforeSending() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        let entry = try await addHistory(f)
        _ = try await f.store.deleteHistory(id: entry.id)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(f.model.decisionReviewTarget)
    }

    func testConfirmedProposalAddsDictionaryEntryWithSeparateUndoWithoutChangingText() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        XCTAssertTrue(f.model.canSaveDecisionProposal(proposal))
        await f.model.saveDecisionProposal(proposal, replacing: nil)
        XCTAssertEqual(f.model.dictionary.map(\.written), ["OpenRouter"])
        XCTAssertTrue(f.model.canUndoDecisionDictionarySave)
        XCTAssertFalse(f.model.canUndoLastLearning)
        XCTAssertEqual(f.model.result, "")
        XCTAssertTrue(f.insertions.texts.isEmpty)
        await f.model.undoDecisionDictionarySave()
        XCTAssertTrue(f.model.dictionary.isEmpty)
        XCTAssertFalse(f.model.canUndoDecisionDictionarySave)
    }

    func testRepeatedSaveIsANoopAndPreservesTheUndoForTheActualWrite() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        await f.model.saveDecisionProposal(proposal, replacing: nil)
        let saved = try XCTUnwrap(f.model.dictionary.first)
        await f.model.saveDecisionProposal(proposal, replacing: saved)
        XCTAssertEqual(f.model.dictionary, [saved])
        XCTAssertTrue(f.model.decisionProposalStatus?.contains("이미 사전에") == true)
        await f.model.undoDecisionDictionarySave()
        XCTAssertTrue(f.model.dictionary.isEmpty)
    }

    func testDictionaryChangeDuringConfirmationDoesNotOverwriteTheNewValue() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        let newer = DictionaryEntry(spoken: proposal.original, written: "New manual spelling")
        _ = try await f.store.upsertDictionaryEntries([newer])
        await f.model.saveDecisionProposal(proposal, replacing: nil)
        XCTAssertEqual(f.model.dictionary, [newer])
        XCTAssertFalse(f.model.canUndoDecisionDictionarySave)
        XCTAssertTrue(f.model.decisionProposalStatus?.contains("사전이 바뀌었거나") == true)
    }

    func testDeletedHistoryDuringConfirmationClearsProposalAndExplainsWhyNothingWasSaved() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        _ = try await f.store.deleteHistory(id: entry.id)
        await f.model.saveDecisionProposal(proposal, replacing: nil)
        XCTAssertTrue(f.model.dictionary.isEmpty)
        XCTAssertTrue(f.model.history.isEmpty)
        XCTAssertFalse(f.model.canUndoDecisionDictionarySave)
        XCTAssertNil(f.model.decisionReviewTarget)
        XCTAssertTrue(f.model.decisionProposals.isEmpty)
        XCTAssertTrue(f.model.decisionProposalStatus?.contains("삭제되었거나 만료") == true)
        XCTAssertEqual(f.model.notice, f.model.decisionProposalStatus)
    }

    func testProposalFromPreviousReviewCannotBeSavedAfterTargetChanges() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true))
        let first = try await addHistory(f)
        f.model.reviewHistory(first); await waitForManualReview(f.model)
        let old = try XCTUnwrap(f.model.decisionProposals.first)
        let second = try await addHistory(f)
        f.model.reviewHistory(second); await waitForManualReview(f.model)
        XCTAssertFalse(f.model.canSaveDecisionProposal(old))
        await f.model.saveDecisionProposal(old, replacing: nil)
        XCTAssertTrue(f.model.dictionary.isEmpty)
        XCTAssertEqual(f.model.decisionReviewTarget?.id, second.id)
    }

    func testKeepOriginalProposalCannotCreateAGlobalDictionaryMapping() async throws {
        let evaluator = DecisionActionEvaluator(proposeTerm: true, termChoice: .keepOriginal)
        let f = try fixture(mode: .off, evaluator: evaluator)
        let entry = try await addHistory(f, transcript: "'오픈 라우터'라고 적어 주세요", output: "'OpenRouter'라고 적어 주세요.")
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        XCTAssertFalse(proposal.canSave)
        XCTAssertFalse(f.model.canSaveDecisionProposal(proposal))
        await f.model.saveDecisionProposal(proposal, replacing: nil)
        XCTAssertTrue(f.model.dictionary.isEmpty)
    }

    func testUndoDoesNotOverwriteLaterManualDictionaryEdits() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        await f.model.saveDecisionProposal(proposal, replacing: nil)
        let saved = try XCTUnwrap(f.model.dictionary.first)
        _ = try await f.store.updateDictionaryEntry(id: saved.id, spoken: saved.spoken, written: "LaterEdit")
        await f.model.undoDecisionDictionarySave()
        XCTAssertEqual(f.model.dictionary.first?.written, "LaterEdit")
        XCTAssertFalse(f.model.canUndoDecisionDictionarySave)
    }

    func testExplicitReplacementAndUndoRestoreTheConfirmedPreviousMapping() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        let previous = DictionaryEntry(spoken: proposal.original, written: "Previous")
        _ = try await f.store.upsertDictionaryEntries([previous]); await f.model.refreshData()
        await f.model.saveDecisionProposal(proposal, replacing: previous)
        XCTAssertEqual(f.model.dictionary.first?.written, "OpenRouter")
        await f.model.undoDecisionDictionarySave()
        XCTAssertEqual(f.model.dictionary, [previous])
    }

    func testCaseInsensitiveSpokenLatinNeverGetsAHangulReversalSuggestion() {
        let terms = [DecisionTermCandidate(id: "term", original: "오픈 라우터", candidate: "OpenRouter")]
        let result = DecisionResult(meaningChanged: 0.1, contentAdded: 0.1, contentOmitted: 0.1,
            terms: [.init(id: "term", choice: .keepOriginal,
                probabilities: [.keepOriginal: 0.9, .useCandidate: 0.05, .uncertain: 0.05], confidence: 0.9)])
        for latin in ["OPENROUTER", "openrouter", "OpenRouter"] {
            XCTAssertTrue(AppModel.decisionSuggestions(review: result, terms: terms,
                transcript: "오픈 라우터의 영문 표기는 \(latin)", output: "OpenRouter의 영문 표기는 OpenRouter").isEmpty)
        }
    }

    func testDeletingHistoryAlsoClearsRecentTranscriptButKeepsTheVisibleResult() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        await recordAndWait(f)
        XCTAssertNotNil(f.model.recentDecisionTarget)
        let before = f.model.result
        await f.model.deleteHistory()
        XCTAssertNil(f.model.recentDecisionTarget)
        XCTAssertEqual(f.model.result, before)
        f.model.reviewRecentResult(); await waitForManualReview(f.model)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testDisablingHistoryClearsOldTranscriptButNewDictationStillAllowsExplicitReview() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        await recordAndWait(f)
        f.model.preferences.historyEnabled = false
        XCTAssertNil(f.model.recentDecisionTarget)
        await recordAndWait(f)
        XCTAssertNotNil(f.model.recentDecisionTarget)
        f.model.reviewRecentResult(); await waitForManualReview(f.model)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(f.model.preferences.decisionReviewMode, .off)
    }

    func testRecentTranslationAndRewriteReviewUsesCapturedPurposeWithoutAutomaticRequests() async throws {
        for mode in [InputMode.translation, .rewrite] {
            let evaluator = DecisionActionEvaluator()
            let f = try fixture(mode: .observe, evaluator: evaluator)
            await recordAndWait(f, mode: mode)
            let before = await evaluator.calls
            XCTAssertTrue(before.isEmpty)
            let target = try XCTUnwrap(f.model.recentDecisionTarget)
            f.model.preferences.targetLanguage = "Japanese"
            f.model.reviewRecentResult(); await waitForManualReview(f.model)
            let calls = await evaluator.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].request.purpose, mode == .translation
                ? .translation(targetLanguage: "English (United States)") : .rewrite(originalText: "selected synthetic source"))
            XCTAssertTrue(calls[0].request.termCandidates.isEmpty)
            XCTAssertEqual(target.mode, mode)
            let usage = try await f.store.usageRecords()
            XCTAssertEqual(usage.last?.mode, mode)
            XCTAssertEqual(f.insertions.texts.count, 1)
        }
    }

    func testTranslationPreviewReviewRetainsItsTargetLanguage() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        let entry = try await addHistory(f, mode: .translation)
        f.model.preferences.targetLanguage = "Korean"
        f.model.reprocessHistory(entry); await waitForPreview(f.model)
        f.model.preferences.targetLanguage = "Japanese"
        f.model.reviewHistoryPreview(); await waitForManualReview(f.model)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.first?.request.purpose, .translation(targetLanguage: "Korean"))
    }

    func testUncertainSpellingIsVisibleButCannotBeSaved() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true, termChoice: .uncertain))
        let entry = try await addHistory(f)
        f.model.reviewHistory(entry); await waitForManualReview(f.model)
        let proposal = try XCTUnwrap(f.model.decisionProposals.first)
        XCTAssertEqual(proposal.choice, .uncertain)
        XCTAssertFalse(f.model.canSaveDecisionProposal(proposal))
        await f.model.saveDecisionProposal(proposal, replacing: nil)
        XCTAssertTrue(f.model.dictionary.isEmpty)
    }

    func testExplicitImprovementGeneratesOnePreviewAndOneReviewWithoutInsertionOrHistoryChange() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator)
        await recordAndWait(f)
        let target = try XCTUnwrap(f.model.recentDecisionTarget)
        let before = try await f.store.history()
        f.model.preferences.improvementModels[AIProvider.openRouter.rawValue] = "synthetic-alternative"
        f.model.createJevImprovement(for: target)
        await waitForWorkflow(f.model)
        let preview = try XCTUnwrap(f.model.jevImprovement)
        XCTAssertEqual(preview.output, DecisionActionURLProtocol.output)
        XCTAssertEqual(preview.model, "synthetic-alternative")
        XCTAssertNotNil(preview.review)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.request.transcript, target.transcript)
        XCTAssertEqual(f.insertions.texts.count, 1)
        XCTAssertEqual(f.model.result, target.output)
        let after = try await f.store.history()
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(f.model.jevQualityMetrics.rows.first { $0.id.model == "synthetic-alternative" }?.improvementOfferedCount, 1)
        f.model.preferences.usageTrackingEnabled = false
        XCTAssertTrue(f.model.jevQualityMetrics.isEmpty)
    }

    func testImprovementFailureShowsUnreviewedPreviewAndDoesNotReplaceResult() async throws {
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(failure: .timedOut))
        await recordAndWait(f)
        let target = try XCTUnwrap(f.model.recentDecisionTarget)
        f.model.createJevImprovement(for: target); await waitForWorkflow(f.model)
        XCTAssertNotNil(f.model.jevImprovement?.output)
        XCTAssertNil(f.model.jevImprovement?.review)
        XCTAssertTrue(f.model.jevImprovement?.status?.contains("완료하지 못했습니다") == true)
        XCTAssertEqual(f.model.result, target.output)
        XCTAssertEqual(f.insertions.texts.count, 1)
    }

    func testImprovementLateReviewIsDiscardedAfterCancellation() async throws {
        let gate = DecisionActionGate(entered: expectation(description: "Alternative review waiting"))
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(gate: gate))
        await recordAndWait(f)
        f.model.createJevImprovement(for: try XCTUnwrap(f.model.recentDecisionTarget))
        await fulfillment(of: [gate.entered], timeout: 3)
        f.model.cancelJevWorkflow()
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(f.model.jevImprovement)
        XCTAssertEqual(f.insertions.texts.count, 1)
    }

    func testPhraseCorrectionIsReviewedThenExplicitlySavedAndUndoable() async throws {
        let evaluator = DecisionActionEvaluator(proposeTerm: true)
        let f = try fixture(mode: .off, evaluator: evaluator)
        let candidate = LearningCandidate(originalText: "오픈 라우터에 연결해 주세요", editedText: "OpenRouter에 연결해 주세요")
        try await f.store.saveLearningCandidates([candidate]); await f.model.refreshData()
        f.model.reviewLearningCandidate(candidate); await waitForWorkflow(f.model)
        let review = try XCTUnwrap(f.model.jevCorrectionReview)
        XCTAssertTrue(review.canSave)
        XCTAssertTrue(f.model.dictionary.isEmpty)
        let calls = await evaluator.calls
        XCTAssertEqual(calls.first?.request.termCandidates.first?.original, "오픈 라우터")
        XCTAssertEqual(calls.first?.request.termCandidates.first?.candidate, "OpenRouter")
        await f.model.saveReviewedCorrection(review.id, replacing: nil)
        XCTAssertEqual(f.model.dictionary.first?.written, "OpenRouter")
        XCTAssertNil(f.model.learningCandidate)
        await f.model.undoDecisionDictionarySave()
        XCTAssertTrue(f.model.dictionary.isEmpty)
        XCTAssertTrue(f.insertions.texts.isEmpty)
    }

    func testCorrectionCannotBeSavedAfterCandidateDeletionOrUncertainReview() async throws {
        for choice in [DecisionTermChoice.useCandidate, .uncertain] {
            let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(proposeTerm: true, termChoice: choice))
            let candidate = LearningCandidate(originalText: "오픈 라우터 사용", editedText: "OpenRouter 사용")
            try await f.store.saveLearningCandidates([candidate]); await f.model.refreshData()
            f.model.reviewLearningCandidate(candidate); await waitForWorkflow(f.model)
            let review = try XCTUnwrap(f.model.jevCorrectionReview)
            try await f.store.saveLearningCandidates([])
            await f.model.saveReviewedCorrection(review.id, replacing: nil)
            XCTAssertTrue(f.model.dictionary.isEmpty)
        }
    }

    func testOversizedSelectedSourceRejectsReviewAndAlternativeBeforeExtraRequests() async throws {
        let evaluator = DecisionActionEvaluator()
        let f = try fixture(mode: .off, evaluator: evaluator, selectedText: String(repeating: "한", count: 8_001))
        await recordAndWait(f, mode: .rewrite)
        let target = try XCTUnwrap(f.model.recentDecisionTarget)
        let before = try await f.store.usageRecords()
        f.model.reviewRecentResult(); await waitForManualReview(f.model)
        f.model.createJevImprovement(for: target); await waitForWorkflow(f.model)
        let calls = await evaluator.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(f.model.jevImprovement)
        let after = try await f.store.usageRecords()
        XCTAssertEqual(after.count, before.count)
        XCTAssertTrue(f.model.manualDecisionReviewStatus?.contains("24 KB") == true)
    }

    func testDismissingAnUnreviewedCorrectionDoesNotCancelAlternative() async throws {
        let gate = DecisionActionGate(entered: expectation(description: "Alternative waiting while correction is dismissed"))
        let f = try fixture(mode: .off, evaluator: DecisionActionEvaluator(gate: gate))
        let candidate = LearningCandidate(originalText: "오픈 라우터 사용", editedText: "OpenRouter 사용")
        try await f.store.saveLearningCandidates([candidate]); await f.model.refreshData()
        await recordAndWait(f)
        f.model.createJevImprovement(for: try XCTUnwrap(f.model.recentDecisionTarget))
        await fulfillment(of: [gate.entered], timeout: 3)
        await f.model.dismissLearningCandidate()
        XCTAssertNotNil(f.model.jevImprovement)
        await gate.release(); await waitForWorkflow(f.model)
        XCTAssertNotNil(f.model.jevImprovement?.review)
        XCTAssertNil(f.model.learningCandidate)
    }

    private func waitForWorkflow(_ model: AppModel) async {
        for _ in 0..<300 {
            if !model.jevWorkflowInProgress { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Jev workflow did not finish")
    }

    private func addHistory(_ f: Fixture, mode: InputMode = .dictation,
                            transcript: String = DecisionActionURLProtocol.transcript,
                            output: String = DecisionActionURLProtocol.output) async throws -> HistoryEntry {
        let entry = HistoryEntry(mode: mode, originalText: transcript, resultText: output, provider: .openRouter)
        _ = try await f.store.appendHistory(entry)
        await f.model.refreshData()
        return entry
    }
    private func waitForManualReview(_ model: AppModel) async {
        for _ in 0..<300 {
            if !model.manualDecisionReviewInProgress { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Manual synthetic review did not finish")
    }
    private func waitForPreview(_ model: AppModel) async {
        for _ in 0..<300 {
            if model.historyReprocessing?.isProcessing == false { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Synthetic preview did not finish")
    }
    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let insertions: DecisionActionInsertions
        let keys: DecisionActionKeyStorage
    }
    private func fixture(mode: DecisionReviewMode, evaluator: DecisionActionEvaluator,
                         provider: AIProvider = .openRouter, history: Bool = true,
                         decisionProvider: DecisionProvider = .openRouter,
                         keyStore: DecisionActionKeyStorage? = nil, cachedKeys: Bool = false,
                         selectedText: String = "selected synthetic source") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-DecisionAction-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("store"), backend: DecisionActionSecrets())
        let audio = root.appendingPathComponent("synthetic.wav")
        try Data([82, 73, 70, 70, 1, 2, 3]).write(to: audio)
        let target = InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
                                originalValue: nil, range: nil, selectedText: selectedText, context: "private surrounding context")
        let insertions = DecisionActionInsertions()
        let keys = keyStore ?? DecisionActionKeyStorage()
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
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DecisionActionURLProtocol.self]
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

@MainActor private final class DecisionActionInsertions { var texts: [String] = [] }
@MainActor private final class DecisionActionKeyStorage {
    var value: String? = "synthetic-typesafe-key"
    var aiWrites: [AIProvider] = []
    var writes: [String?] = []
    var failRead = false
    var failWrite = false
    var readGate: DecisionActionGate?
    var saveGate: DecisionActionGate?
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
private actor DecisionActionGate {
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
private actor DecisionActionEvaluator: DecisionEvaluating {
    struct Call { let request: DecisionRequest; let key: String; let provider: DecisionProvider }
    private(set) var calls: [Call] = []
    let risk: Double
    let proposeTerm: Bool
    let termChoice: DecisionTermChoice
    let failure: DecisionError?
    let gate: DecisionActionGate?
    init(risk: Double = 0.1, proposeTerm: Bool = false, failure: DecisionError? = nil, gate: DecisionActionGate? = nil, termChoice: DecisionTermChoice = .useCandidate) {
        self.risk = risk; self.proposeTerm = proposeTerm; self.termChoice = termChoice; self.failure = failure; self.gate = gate
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
            .init(id: $0.id, choice: termChoice, probabilities: [.useCandidate: 0.8, .keepOriginal: 0.1, .uncertain: 0.1], confidence: 0.8)
        } : []
        return .init(meaningChanged: risk, contentAdded: 0.05, contentOmitted: 0.05, terms: terms,
                     reportedModel: configuration.provider.model)
    }
}
private final class DecisionActionSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = nil }
}
/// Intercepts every URL; these app tests cannot reach a live service.
private final class DecisionActionURLProtocol: URLProtocol {
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
