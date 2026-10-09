import AppKit
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class PromptCompositionFlowTests: KoreanPresentationTestCase {
    func testMalformedFirstGenerationPreservesTranscriptWithoutClaimingAReviewHold() async throws {
        let fixture = try fixture(malformedGeneration: 1)
        await reprocessAndWait(fixture)

        let composition = try XCTUnwrap(fixture.model.promptComposition)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(fixture.http.bodies.count, 1)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(composition.interruption, .generationFailed)
        XCTAssertEqual(composition.title, "프롬프트 생성 실패")
        XCTAssertEqual(composition.interruptionDescription, "초안을 만들지 못했습니다. Jev 검토는 시작되지 않았습니다.")
        XCTAssertEqual(composition.transcript, fixture.entry.originalText)
        XCTAssertNil(composition.draft)
        XCTAssertNil(composition.finalCandidate)
        XCTAssertNil(composition.draftReview)
        XCTAssertNil(composition.finalReview)
        XCTAssertNil(composition.output)
        XCTAssertTrue(composition.held)
        XCTAssertFalse(composition.isProcessing)
        XCTAssertFalse(composition.inspectionDescription.contains("후보"))
        XCTAssertFalse(composition.inspectionDescription.contains("검토 항목"))
        XCTAssertNil(fixture.model.historyReprocessing?.result)
        XCTAssertNotNil(fixture.model.historyReprocessing?.error)
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertEqual(fixture.boundaries.captures, 0)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
    }

    func testMalformedPolishingResponsePreservesDraftAndReviewWithoutClaimingFinalReview() async throws {
        let fixture = try fixture(rejectDraft: true, malformedGeneration: 2)
        await reprocessAndWait(fixture)

        let composition = try XCTUnwrap(fixture.model.promptComposition)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(fixture.http.bodies.count, 2)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(composition.interruption, .generationFailed)
        XCTAssertEqual(composition.title, "프롬프트 다듬기 실패")
        XCTAssertEqual(composition.interruptionDescription, "초안 검토 후 다듬기를 완료하지 못했습니다. 최종 검토는 시작되지 않았습니다.")
        XCTAssertEqual(composition.draft, PromptFlowHTTP.draft)
        XCTAssertFalse(composition.draftReview?.accepted == true)
        XCTAssertNil(composition.finalCandidate)
        XCTAssertNil(composition.finalReview)
        XCTAssertNil(composition.output)
        XCTAssertTrue(composition.held)
        XCTAssertFalse(composition.isProcessing)
        XCTAssertTrue(composition.inspectionDescription.contains("초안 검토 항목"))
        XCTAssertFalse(composition.inspectionDescription.contains("최종 검토"))
        XCTAssertNil(fixture.model.historyReprocessing?.result)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
    }

    func testReviewResponseFailureIsDistinctFromContentHeldVerdict() async throws {
        for failedReview in [1, 2] {
            let fixture = try fixture(failedReview: failedReview)
            await reprocessAndWait(fixture)

            let composition = try XCTUnwrap(fixture.model.promptComposition)
            let calls = await fixture.reviewer.calls
            XCTAssertEqual(calls.count, failedReview)
            XCTAssertEqual(fixture.http.bodies.count, 1)
            XCTAssertEqual(composition.interruption, .reviewFailed)
            XCTAssertEqual(composition.title, "프롬프트 검토 실패")
            XCTAssertEqual(composition.stage, failedReview == 1 ? .reviewingDraft : .reviewingFinal)
            XCTAssertEqual(composition.draft, PromptFlowHTTP.draft)
            XCTAssertNil(composition.finalReview)
            XCTAssertNil(composition.output)
            XCTAssertTrue(composition.held)
            XCTAssertFalse(composition.isProcessing)
            XCTAssertNil(fixture.model.historyReprocessing?.result)
            XCTAssertEqual(fixture.boundaries.insertions, 0)
            if failedReview == 1 {
                XCTAssertNil(composition.draftReview)
                XCTAssertNil(composition.finalCandidate)
                XCTAssertFalse(composition.inspectionDescription.contains("검토 항목"))
            } else {
                XCTAssertTrue(composition.draftReview?.accepted == true)
                XCTAssertEqual(composition.finalCandidate, PromptFlowHTTP.draft)
                XCTAssertTrue(composition.inspectionDescription.contains("초안 검토 항목"))
                XCTAssertFalse(composition.inspectionDescription.contains("최종 검토 항목"))
            }
            let saved = try await fixture.store.history()
            XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
        }
    }

    func testAcceptedPromptHistorySkipsUnnecessaryPolishingAndKeepsTwoReviewsWithoutTyping() async throws {
        let fixture = try fixture(malformedGeneration: 2)
        await fixture.model.refreshData()
        await reprocessAndWait(fixture)

        XCTAssertEqual(fixture.http.bodies.count, 1, "A malformed unused polishing response must not fail an accepted draft")
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.map(\.transcript), [fixture.entry.originalText, fixture.entry.originalText])
        XCTAssertEqual(calls.map(\.prompt), [PromptFlowHTTP.draft, PromptFlowHTTP.draft])
        XCTAssertEqual(fixture.model.promptComposition?.output, PromptFlowHTTP.draft)
        XCTAssertEqual(fixture.model.historyReprocessing?.result, PromptFlowHTTP.draft)
        XCTAssertEqual(fixture.model.historyReprocessing?.reviewTarget?.purpose, .promptComposition)
        XCTAssertNil(fixture.model.historyReprocessing?.error)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertEqual(fixture.boundaries.captures, 0)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
        let first = try userInput(fixture.http.bodies[0])
        XCTAssertEqual(first["mode"] as? String, "prompt")
        XCTAssertEqual(first["spoken_text"] as? String, fixture.entry.originalText)
        XCTAssertNil(first["prompt_draft"])
        XCTAssertNil(first["writing_profile"])
        XCTAssertNil(first["target_language"])
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
        XCTAssertEqual(saved.first?.mode, .prompt)
    }

    func testUncertainFinalReviewHoldsPromptAndNeverPublishesHistoryPreviewResult() async throws {
        let fixture = try fixture(uncertainFinal: true)
        await fixture.model.refreshData()
        await reprocessAndWait(fixture)

        XCTAssertEqual(fixture.http.bodies.count, 1)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(fixture.model.promptComposition?.held == true)
        XCTAssertEqual(fixture.model.promptComposition?.interruption, .reviewHeld)
        XCTAssertEqual(fixture.model.promptComposition?.title, "기존 지침 관련 검토 보류")
        XCTAssertEqual(fixture.model.promptComposition?.deliveryDisposition, .blocked)
        XCTAssertEqual(fixture.model.promptComposition?.draft, PromptFlowHTTP.draft)
        XCTAssertEqual(fixture.model.promptComposition?.transcript, fixture.entry.originalText)
        XCTAssertEqual(fixture.model.promptComposition?.finalCandidate, calls.last?.prompt)
        XCTAssertTrue(fixture.model.promptComposition?.draftReview?.accepted == true)
        XCTAssertEqual(fixture.model.promptComposition?.finalReview?.issues, PromptCompositionIssue.allCases)
        XCTAssertNil(fixture.model.promptComposition?.output)
        XCTAssertNil(fixture.model.historyReprocessing?.result)
        XCTAssertNotNil(fixture.model.historyReprocessing?.error)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertFalse(fixture.model.isBusy)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
    }

    func testRejectedDraftKeepsTheExactPolishedCandidateAndSeparateReviewsWhenFinalIsHeld() async throws {
        let fixture = try fixture(uncertainFinal: true, rejectDraft: true)
        fixture.model.preferences.usageTrackingEnabled = true
        await reprocessAndWait(fixture)

        let calls = await fixture.reviewer.calls
        XCTAssertEqual(fixture.http.bodies.count, 2)
        let polishingInput = try userInput(fixture.http.bodies[1])
        XCTAssertNil(polishingInput["prompt_draft"])
        XCTAssertEqual(polishingInput["repair_mode"] as? String, "source_reconstruction")
        XCTAssertEqual(polishingInput["spoken_text"] as? String, fixture.entry.originalText)
        XCTAssertEqual(polishingInput["review_issues"] as? [String], PromptCompositionIssue.allCases.map(\.rawValue))
        XCTAssertEqual(calls.map(\.prompt), [PromptFlowHTTP.draft, PromptFlowHTTP.final])
        let composition = try XCTUnwrap(fixture.model.promptComposition)
        XCTAssertEqual(composition.draft, PromptFlowHTTP.draft)
        XCTAssertEqual(composition.finalCandidate, PromptFlowHTTP.final)
        XCTAssertEqual(composition.draftReview?.assessments[.intent]?.choice, .fail)
        XCTAssertEqual(composition.finalReview?.assessments[.intent]?.choice, .uncertain)
        XCTAssertTrue(composition.held)
        XCTAssertFalse(composition.isProcessing)
        XCTAssertNil(composition.output)
        XCTAssertNil(fixture.model.historyReprocessing?.result)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        let failures = try await fixture.store.failures()
        let history = try await fixture.store.history()
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(history.first?.resultText, fixture.entry.resultText)
        let usage = try await fixture.store.usageRecords()
        XCTAssertEqual(usage.count, 4, "Both generations and both reviews remain accounted for when repair is needed")
        fixture.model.page = .recovery
        XCTAssertEqual(fixture.model.promptComposition, composition, "Changing pages must not discard held evidence")
    }

    func testMissingReviewKeyBlocksHistoryReprocessingBeforePaidGeneration() async throws {
        let fixture = try fixture(hasKey: false)
        try await fixture.store.saveHistory([fixture.entry])
        await fixture.model.refreshData()
        XCTAssertNotNil(fixture.model.promptCompositionIssue)
        XCTAssertNotNil(fixture.model.historyReprocessingUnavailableReason(for: fixture.entry))
        fixture.model.reprocessHistory(fixture.entry)

        XCTAssertTrue(fixture.http.bodies.isEmpty)
        let calls = await fixture.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(fixture.model.historyReprocessing)
        XCTAssertNil(fixture.model.promptComposition)
        XCTAssertFalse(fixture.model.isBusy)
    }

    func testPromptRecordingStartsInOwnAppWithoutAccessibilityOrInputTargetCapture() async throws {
        let fixture = try fixture()
        XCTAssertFalse(fixture.model.accessibilityAllowed)
        await fixture.model.toggle(.prompt)

        XCTAssertTrue(fixture.model.phase == .recording)
        XCTAssertEqual(fixture.model.mode, .prompt)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 1)
        XCTAssertEqual(fixture.boundaries.captures, 0)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertTrue(fixture.http.bodies.isEmpty)
        fixture.model.cancel()
        XCTAssertFalse(fixture.model.isBusy)
    }

    func testPromptHistorySettingsChangeBeforeItsFirstSuspensionCancelsBeforePaidGeneration() async throws {
        for changeProvider in [false, true] {
            let fixture = try fixture()
            try await fixture.store.saveHistory([fixture.entry])
            await fixture.model.refreshData()
            XCTAssertEqual(fixture.model.mode, .dictation, "The last recording mode does not identify a history job")
            fixture.model.reprocessHistory(fixture.entry)
            XCTAssertNil(fixture.model.promptComposition, "The task has not yet reached composePrompt")
            if changeProvider { fixture.model.preferences.textProvider = .groq }
            else { fixture.model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/changed-prompt" }

            XCTAssertFalse(fixture.model.isBusy)
            XCTAssertNil(fixture.model.historyReprocessing)
            let latePhase = expectation(description: "Cancelled prompt history must not resume")
            latePhase.isInverted = true
            fixture.model.onPhaseChange = { latePhase.fulfill() }
            await fulfillment(of: [latePhase], timeout: 0.1)
            fixture.model.onPhaseChange = nil
            XCTAssertTrue(fixture.http.bodies.isEmpty)
            let calls = await fixture.reviewer.calls
            XCTAssertTrue(calls.isEmpty)
            XCTAssertNil(fixture.model.promptComposition)
        }
    }

    func testOrdinaryHistoryKeepsCapturedSettingsAfterTheLastRecordingWasPromptMode() async throws {
        let fixture = try fixture()
        var entry = fixture.entry
        entry.mode = .dictation
        try await fixture.store.saveHistory([entry])
        await fixture.model.refreshData()
        fixture.model.mode = .prompt
        fixture.model.preferences.dictationOutputLanguage = .original
        let finished = expectation(description: "Ordinary history retains its captured provider model")
        var delivered = false
        fixture.model.onPhaseChange = { [weak model = fixture.model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        fixture.model.reprocessHistory(entry)
        fixture.model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/changed-after-capture"
        await fulfillment(of: [finished], timeout: 5)
        fixture.model.onPhaseChange = nil

        XCTAssertEqual(fixture.http.bodies.count, 1)
        let body = try XCTUnwrap(fixture.http.bodies.first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "test/prompt-flow")
        XCTAssertEqual(fixture.model.historyReprocessing?.result, PromptFlowHTTP.draft)
        XCTAssertNil(fixture.model.historyReprocessing?.error)
        XCTAssertNil(fixture.model.promptComposition)
        let calls = await fixture.reviewer.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testCorrectedPromptRegenerationUsesCurrentSettingsAndAccountsForThreeTextOnlyRequests() async throws {
        let fixture = try fixture()
        let failure = FailedRecording(mode: .prompt, provider: .groq, targetLanguage: "English")
        let audio = Data("synthetic retained audio evidence".utf8)
        try await fixture.store.saveFailure(failure, audio: audio)
        await reprocessAndWait(fixture)
        let source = try XCTUnwrap(fixture.model.promptComposition)
        let previousPreview = fixture.model.historyReprocessing
        fixture.model.preferences.usageTrackingEnabled = true
        fixture.model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/current-prompt"
        let corrected = "독후감 앱을 개선해 줘. 실제로 하지 않은 감상을 만들어 넣지 말고, 알림은 아직 정하지 않았어."

        await regenerateAndWait(fixture, source: source, correctedTranscript: corrected)

        let composition = try XCTUnwrap(fixture.model.promptComposition)
        XCTAssertNotEqual(composition.id, source.id)
        XCTAssertEqual(composition.originalTranscript, fixture.entry.originalText)
        XCTAssertEqual(composition.recognizedTranscript, fixture.entry.originalText)
        XCTAssertEqual(composition.transcript, corrected)
        XCTAssertNotNil(composition.output)
        XCTAssertFalse(composition.isProcessing)
        XCTAssertFalse(composition.held)
        XCTAssertEqual(fixture.model.mode, .prompt)
        XCTAssertEqual(fixture.model.result, "", "Only the reviewed prompt panel publishes this text-only result")
        XCTAssertEqual(fixture.http.bodies.count, 2)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(Array(calls.suffix(2)).map(\.transcript), [corrected, corrected])
        XCTAssertEqual(composition.finalCandidate, calls.last?.prompt)
        for body in fixture.http.bodies.suffix(1) {
            let outer = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(outer["model"] as? String, "test/current-prompt")
            let input = try userInput(body)
            XCTAssertEqual(input["mode"] as? String, "prompt")
            XCTAssertEqual(input["spoken_text"] as? String, corrected)
            XCTAssertNil(input["writing_profile"])
            XCTAssertNil(input["target_language"])
            XCTAssertNil(input["selected_text"])
        }
        let usage = try await fixture.store.usageRecords()
        XCTAssertEqual(usage.count, 3)
        XCTAssertEqual(usage.filter { $0.event.stage == .textProcessing }.count, 1)
        XCTAssertEqual(usage.filter { $0.event.stage == .decisionReview }.count, 2)
        XCTAssertFalse(usage.contains { $0.event.stage == .transcription })
        XCTAssertEqual(Set(usage.map(\.jobID)).count, 1)
        XCTAssertTrue(usage.allSatisfy { $0.mode == .prompt && !$0.isRecovery })
        let history = try await fixture.store.history()
        let failures = try await fixture.store.failures()
        let retainedAudio = try await fixture.store.failureAudio(id: failure.id)
        XCTAssertEqual(history.map(\.id), [fixture.entry.id])
        XCTAssertEqual(history.first?.originalText, fixture.entry.originalText)
        XCTAssertEqual(history.first?.resultText, fixture.entry.resultText)
        XCTAssertEqual(failures.map(\.id), [failure.id])
        XCTAssertEqual(retainedAudio, audio)
        XCTAssertEqual(fixture.model.historyReprocessing?.id, previousPreview?.id)
        XCTAssertEqual(fixture.model.historyReprocessing?.result, previousPreview?.result)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertEqual(fixture.boundaries.captures, 0)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
    }

    func testSameTranscriptCanExplicitlyRetryAfterGenerationFailureWithoutTranscription() async throws {
        let fixture = try fixture(malformedGeneration: 1)
        await reprocessAndWait(fixture)
        let source = try XCTUnwrap(fixture.model.promptComposition)
        XCTAssertEqual(source.interruption, .generationFailed)

        await regenerateAndWait(fixture, source: source, correctedTranscript: source.transcript)

        let composition = try XCTUnwrap(fixture.model.promptComposition)
        XCTAssertEqual(fixture.http.bodies.count, 2)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.map(\.transcript), [source.transcript, source.transcript])
        XCTAssertEqual(composition.transcript, source.transcript)
        XCTAssertEqual(composition.recognizedTranscript, source.transcript)
        XCTAssertNotNil(composition.output)
        XCTAssertNil(composition.interruption)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
    }

    func testRepeatedCorrectionKeepsTheFirstRecognizedTranscript() async throws {
        let fixture = try fixture()
        await reprocessAndWait(fixture)
        let first = try XCTUnwrap(fixture.model.promptComposition)
        await regenerateAndWait(fixture, source: first, correctedTranscript: "첫 번째로 수정한 독후감 앱 요청입니다.")
        let second = try XCTUnwrap(fixture.model.promptComposition)
        await regenerateAndWait(fixture, source: second, correctedTranscript: "두 번째로 수정한 독후감 앱 요청입니다.")

        let final = try XCTUnwrap(fixture.model.promptComposition)
        XCTAssertEqual(final.originalTranscript, first.transcript)
        XCTAssertEqual(final.recognizedTranscript, first.transcript)
        XCTAssertEqual(final.transcript, "두 번째로 수정한 독후감 앱 요청입니다.")
        XCTAssertEqual(fixture.http.bodies.count, 3)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 6)
        XCTAssertEqual(Array(calls.suffix(2)).map(\.transcript), [final.transcript, final.transcript])
        XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
    }

    func testCorrectedPromptWithUncertainFinalReviewKeepsItsExactSourceAndCandidateWithoutOutput() async throws {
        let fixture = try fixture()
        await reprocessAndWait(fixture)
        let source = try XCTUnwrap(fixture.model.promptComposition)
        await fixture.reviewer.holdReview(number: 4)
        let corrected = "실제로 말하지 않은 감상을 추가하지 말아 주세요."
        await regenerateAndWait(fixture, source: source, correctedTranscript: corrected)

        let composition = try XCTUnwrap(fixture.model.promptComposition)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(composition.transcript, corrected)
        XCTAssertEqual(composition.recognizedTranscript, source.transcript)
        XCTAssertEqual(composition.finalCandidate, calls.last?.prompt)
        XCTAssertEqual(calls.last?.transcript, corrected)
        XCTAssertEqual(composition.interruption, .reviewHeld)
        XCTAssertTrue(composition.held)
        XCTAssertFalse(composition.isProcessing)
        XCTAssertNil(composition.output)
        XCTAssertEqual(fixture.model.result, "")
        XCTAssertEqual(fixture.http.bodies.count, 2)
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        let history = try await fixture.store.history()
        XCTAssertEqual(history.first?.resultText, fixture.entry.resultText)
    }

    func testPromptRegenerationRejectsStaleSourceInvalidInputAndBusyClicksBeforePaidGeneration() async throws {
        let fixture = try fixture()
        await reprocessAndWait(fixture)
        let source = try XCTUnwrap(fixture.model.promptComposition)
        fixture.model.regeneratePrompt(sourceID: UUID(), sourceTranscript: source.transcript, correctedTranscript: "수정한 요청")
        fixture.model.regeneratePrompt(sourceID: source.id, sourceTranscript: "오래된 원문", correctedTranscript: "수정한 요청")
        for invalid in [" \n\t", "금지된\u{0000}제어 문자", String(repeating: "가", count: 4_001)] {
            fixture.model.regeneratePrompt(sourceID: source.id, sourceTranscript: source.transcript, correctedTranscript: invalid)
        }
        XCTAssertEqual(fixture.model.promptComposition, source)
        XCTAssertEqual(fixture.http.bodies.count, 1)
        XCTAssertFalse(fixture.model.isBusy)

        fixture.model.regeneratePrompt(sourceID: source.id, sourceTranscript: source.transcript, correctedTranscript: "사용자가 명시한 새 요청입니다.")
        XCTAssertTrue(fixture.model.isBusy)
        fixture.model.regeneratePrompt(sourceID: source.id, sourceTranscript: source.transcript, correctedTranscript: "두 번 눌러도 보내지 마세요.")
        fixture.model.cancel()
        await Task.yield()
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertNil(fixture.model.promptComposition)
        XCTAssertEqual(fixture.http.bodies.count, 1)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 2)
    }

    func testPromptRegenerationSettingsRevocationBeforeItsFirstSuspensionStopsAllPaidCalls() async throws {
        for changeReviewSettings in [false, true] {
            let fixture = try fixture()
            await reprocessAndWait(fixture)
            let source = try XCTUnwrap(fixture.model.promptComposition)
            let finished = expectation(description: "Revoked text-only regeneration returns to idle")
            var delivered = false
            fixture.model.onPhaseChange = { [weak model = fixture.model] in
                if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
            }
            fixture.model.regeneratePrompt(sourceID: source.id, sourceTranscript: source.transcript,
                correctedTranscript: "현재 원문으로 새 프롬프트를 만들어 주세요.")
            if changeReviewSettings { fixture.model.preferences.decisionReviewMode = .observe }
            else { fixture.model.preferences.textModels[AIProvider.openRouter.rawValue] = "test/revoked" }
            await fulfillment(of: [finished], timeout: 5)
            fixture.model.onPhaseChange = nil
            XCTAssertFalse(fixture.model.isBusy)
            XCTAssertNil(fixture.model.promptComposition)
            XCTAssertEqual(fixture.http.bodies.count, 1)
            let calls = await fixture.reviewer.calls
            XCTAssertEqual(calls.count, 2)
        }
    }

    func testCancellingPromptRegenerationWhileReviewIsPendingDiscardsTheLateCandidate() async throws {
        let fixture = try fixture()
        let failure = FailedRecording(mode: .prompt, provider: .groq, targetLanguage: "English")
        let audio = Data("synthetic failed audio retained through cancellation".utf8)
        try await fixture.store.saveFailure(failure, audio: audio)
        await reprocessAndWait(fixture)
        let source = try XCTUnwrap(fixture.model.promptComposition)
        let paused = expectation(description: "Synthetic draft review is pending")
        let returned = expectation(description: "Cancelled synthetic review returns a late verdict")
        await fixture.reviewer.pauseReview(number: 3, onPause: { paused.fulfill() }, onReturn: { returned.fulfill() })
        fixture.model.regeneratePrompt(sourceID: source.id, sourceTranscript: source.transcript,
            correctedTranscript: "검토를 기다리는 중 취소할 새 요청입니다.")
        await fulfillment(of: [paused], timeout: 5)
        XCTAssertTrue(fixture.model.isBusy)
        fixture.model.cancel()
        XCTAssertEqual(fixture.model.notice, "취소했습니다.")
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertNil(fixture.model.promptComposition)
        await fixture.reviewer.resumeReview()
        await fulfillment(of: [returned], timeout: 5)
        let latePublication = expectation(description: "Cancelled prompt must not publish a late stage or result")
        latePublication.isInverted = true
        fixture.model.onPhaseChange = { latePublication.fulfill() }
        await fulfillment(of: [latePublication], timeout: 0.1)
        fixture.model.onPhaseChange = nil
        XCTAssertEqual(fixture.http.bodies.count, 2, "Cancellation must prevent every generation after the pending review")
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertNil(fixture.model.promptComposition)
        XCTAssertEqual(fixture.model.result, "")
        XCTAssertEqual(fixture.model.notice, "취소했습니다.")
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
        let failures = try await fixture.store.failures()
        let retainedAudio = try await fixture.store.failureAudio(id: failure.id)
        XCTAssertEqual(failures.map(\.id), [failure.id])
        XCTAssertEqual(retainedAudio, audio)
    }

    func testSemanticWarningProvidesCopyablePromptAndPreviewWithoutTypingOrApproval() async throws {
        let fixture = try fixture(qualityWarningFinal: true)
        await reprocessAndWait(fixture)

        let composition = try XCTUnwrap(fixture.model.promptComposition)
        XCTAssertEqual(composition.output, PromptFlowHTTP.draft)
        XCTAssertEqual(composition.deliveryDisposition, .needsReview)
        XCTAssertEqual(composition.warningIssues, [.intent, .unsupportedAdditions, .omissions])
        XCTAssertFalse(composition.held)
        XCTAssertFalse(composition.isProcessing)
        XCTAssertTrue(composition.canCopyOutput)
        XCTAssertNil(composition.interruption)
        XCTAssertEqual(composition.title, "만든 프롬프트")
        XCTAssertEqual(composition.status, PromptCompositionPresentation.qualityReviewNotice)
        XCTAssertFalse(composition.finalReview?.accepted == true)
        XCTAssertEqual(fixture.model.historyReprocessing?.result, composition.output)
        XCTAssertEqual(fixture.model.historyReprocessing?.promptReviewSummary,
            .init(deliveryDisposition: .needsReview, warningIssues: composition.warningIssues))
        XCTAssertNil(fixture.model.historyReprocessing?.error)
        XCTAssertNil(fixture.model.error)
        XCTAssertEqual(fixture.model.result, "")
        XCTAssertEqual(fixture.http.bodies.count, 1)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
        XCTAssertNil(saved.first?.promptReviewSummary, "A preview does not relabel the saved result")
        let failures = try await fixture.store.failures()
        XCTAssertTrue(failures.isEmpty)
    }

    func testWarnedTextRegenerationPreservesOriginalHistoryAndFailedAudio() async throws {
        let fixture = try fixture()
        await reprocessAndWait(fixture)
        let source = try XCTUnwrap(fixture.model.promptComposition)
        let failure = FailedRecording(mode: .prompt, provider: .groq, targetLanguage: "English")
        let audio = Data("original failed audio must survive text-only regeneration".utf8)
        try await fixture.store.saveFailure(failure, audio: audio)
        await fixture.reviewer.warnReview(number: 4)
        let corrected = "알림 기능이 있으면 좋겠지만 넣을지는 아직 미정입니다."
        await regenerateAndWait(fixture, source: source, correctedTranscript: corrected)

        let composition = try XCTUnwrap(fixture.model.promptComposition)
        XCTAssertEqual(composition.transcript, corrected)
        XCTAssertEqual(composition.recognizedTranscript, source.transcript)
        XCTAssertEqual(composition.deliveryDisposition, .needsReview)
        XCTAssertTrue(composition.canCopyOutput)
        XCTAssertFalse(composition.held)
        XCTAssertNotNil(composition.output)
        XCTAssertNil(fixture.model.error)
        XCTAssertEqual(fixture.model.result, "")
        XCTAssertEqual(fixture.http.bodies.count, 2)
        XCTAssertEqual(fixture.http.transcriptions, 0)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(calls.last?.transcript, corrected)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
        let saved = try await fixture.store.history()
        XCTAssertEqual(saved.first?.resultText, fixture.entry.resultText)
        XCTAssertNil(saved.first?.promptReviewSummary)
        let failures = try await fixture.store.failures()
        XCTAssertEqual(failures.map(\.id), [failure.id])
        let retained = try await fixture.store.failureAudio(id: failure.id)
        XCTAssertEqual(retained, audio)
    }

    func testRecoverySavesCapturedPromptReviewStateAndDoesNotTreatWarningsAsFailedAudio() async throws {
        for warning in [false, true] {
            let fixture = try fixture(qualityWarningFinal: warning)
            let failure = FailedRecording(mode: .prompt, provider: .groq, textProvider: .openRouter,
                targetLanguage: "English", transcriptionModel: "whisper-large-v3-turbo",
                textModel: "test/prompt-flow", usedLocalTranscription: false, usedSpeakerFilter: false)
            try await fixture.store.saveFailure(failure, audio: Data("synthetic audio".utf8))
            await fixture.model.refreshData()
            await retryAndWait(fixture, failure: failure)

            let saved = try await fixture.store.history()
            XCTAssertEqual(saved.count, 1)
            XCTAssertEqual(saved.first?.mode, .prompt)
            XCTAssertEqual(saved.first?.originalText, PromptFlowHTTP.transcript)
            XCTAssertEqual(saved.first?.resultText, PromptFlowHTTP.draft)
            XCTAssertEqual(saved.first?.promptReviewSummary?.deliveryDisposition, warning ? .needsReview : .ready)
            XCTAssertEqual(saved.first?.promptReviewSummary?.warningIssues,
                warning ? [.intent, .unsupportedAdditions, .omissions] : [])
            let failures = try await fixture.store.failures()
            XCTAssertTrue(failures.isEmpty)
            XCTAssertNil(fixture.model.error)
            XCTAssertEqual(fixture.model.result, "")
            XCTAssertTrue(fixture.model.promptComposition?.canCopyOutput == true)
            XCTAssertEqual(fixture.http.transcriptions, 1)
            XCTAssertEqual(fixture.http.bodies.count, 1)
            let calls = await fixture.reviewer.calls
            XCTAssertEqual(calls.count, 2)
            XCTAssertEqual(fixture.boundaries.insertions, 0)
            XCTAssertEqual(fixture.boundaries.recordingStarts, 0)
        }
    }

    func testBoundaryBlockedRecoveryKeepsAudioWithoutSavingAProvidedResult() async throws {
        let fixture = try fixture(uncertainFinal: true)
        let failure = FailedRecording(mode: .prompt, provider: .groq, textProvider: .openRouter,
            targetLanguage: "English", transcriptionModel: "whisper-large-v3-turbo",
            textModel: "test/prompt-flow", usedLocalTranscription: false, usedSpeakerFilter: false)
        let audio = Data("synthetic boundary-blocked audio".utf8)
        try await fixture.store.saveFailure(failure, audio: audio)
        await fixture.model.refreshData()
        await retryAndWait(fixture, failure: failure)

        XCTAssertEqual(fixture.model.promptComposition?.deliveryDisposition, .blocked)
        XCTAssertFalse(fixture.model.promptComposition?.canCopyOutput == true)
        XCTAssertNil(fixture.model.promptComposition?.output)
        XCTAssertNotNil(fixture.model.error)
        let saved = try await fixture.store.history()
        XCTAssertTrue(saved.isEmpty)
        let failures = try await fixture.store.failures()
        XCTAssertEqual(failures.map(\.id), [failure.id])
        let retained = try await fixture.store.failureAudio(id: failure.id)
        XCTAssertEqual(retained, audio)
        XCTAssertEqual(fixture.http.transcriptions, 1)
        XCTAssertEqual(fixture.http.bodies.count, 1)
        let calls = await fixture.reviewer.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(fixture.boundaries.insertions, 0)
    }

    private struct Fixture {
        let model: AppModel
        let store: SecureStore
        let entry: HistoryEntry
        let http: PromptFlowHTTP
        let reviewer: PromptFlowReviewer
        let boundaries: PromptFlowBoundaries
    }

    private func fixture(hasKey: Bool = true, uncertainFinal: Bool = false, qualityWarningFinal: Bool = false, rejectDraft: Bool = false,
                         malformedGeneration: Int? = nil, failedReview: Int? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-PromptFlow-\(UUID().uuidString)", isDirectory: true)
        let store = try SecureStore(directory: root.appendingPathComponent("vault"), backend: PromptFlowSecrets())
        let entry = HistoryEntry(mode: .prompt,
            originalText: PromptFlowHTTP.transcript,
            resultText: "이전에 보관한 프롬프트", provider: .groq)
        let http = PromptFlowHTTP(malformedGeneration: malformedGeneration)
        let reviewer = PromptFlowReviewer(uncertainFinal: uncertainFinal, qualityWarningFinal: qualityWarningFinal,
            rejectDraft: rejectDraft, failedReview: failedReview)
        let boundaries = PromptFlowBoundaries()
        var runtime = AppRuntime()
        runtime.frontmostApplication = { .current }
        runtime.capture = { _ in boundaries.captures += 1; XCTFail("Prompt composition must not capture another app"); return nil }
        runtime.accessibilityPermitted = { false }
        runtime.secureInputActive = { true }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { XCTFail("Unexpected microphone permission request"); return false }
        runtime.readKey = { _ in hasKey ? "synthetic-prompt-flow-key" : nil }
        runtime.readDecisionKey = { _ in XCTFail("OpenRouter review must use its existing connection"); return nil }
        runtime.startRecording = { _ in boundaries.recordingStarts += 1 }
        runtime.stopRecording = { nil }
        runtime.recordingElapsed = { 1 }
        runtime.recordingPeakDB = { -12 }
        runtime.insertText = { _, _, _, _ in boundaries.insertions += 1; XCTFail("Prompt composition must not type into another app"); return .confirmed(.paste) }
        var preferences = Preferences.koreanForTesting
        preferences.provider = .openRouter
        preferences.useLocalTranscription = false
        preferences.speakerFilterEnabled = false
        preferences.usageTrackingEnabled = false
        preferences.automaticLearningEnabled = false
        preferences.decisionProvider = .openRouter
        preferences.decisionReviewMode = .off
        preferences.dictationOutputLanguage = .japanese
        preferences.dictationExpression = .init(style: .creative, strength: 100)
        preferences.textModels[AIProvider.openRouter.rawValue] = "test/prompt-flow"
        let model = AppModel(store: store, runtime: runtime, client: http.client, decisionClient: reviewer,
                             startServices: false, preferences: preferences)
        addTeardownBlock { @MainActor in
            model.cancel(); http.close()
            try? FileManager.default.removeItem(at: root)
        }
        return .init(model: model, store: store, entry: entry, http: http, reviewer: reviewer, boundaries: boundaries)
    }

    private func reprocessAndWait(_ fixture: Fixture) async {
        do { try await fixture.store.saveHistory([fixture.entry]); await fixture.model.refreshData() }
        catch { XCTFail("Synthetic history setup failed: \(error)"); return }
        let finished = expectation(description: "Prompt history pipeline completes")
        var delivered = false
        fixture.model.onPhaseChange = { [weak model = fixture.model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        fixture.model.reprocessHistory(fixture.entry)
        await fulfillment(of: [finished], timeout: 5)
        fixture.model.onPhaseChange = nil
    }

    private func regenerateAndWait(_ fixture: Fixture, source: PromptCompositionPresentation, correctedTranscript: String) async {
        let finished = expectation(description: "Explicit text-only prompt regeneration completes")
        var delivered = false
        fixture.model.onPhaseChange = { [weak model = fixture.model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        fixture.model.regeneratePrompt(sourceID: source.id, sourceTranscript: source.transcript, correctedTranscript: correctedTranscript)
        await fulfillment(of: [finished], timeout: 5)
        fixture.model.onPhaseChange = nil
    }

    private func retryAndWait(_ fixture: Fixture, failure: FailedRecording) async {
        let finished = expectation(description: "Prompt recovery reaches its terminal state")
        var delivered = false
        fixture.model.onPhaseChange = { [weak model = fixture.model] in
            if model?.phase == .idle, !delivered { delivered = true; finished.fulfill() }
        }
        fixture.model.retry(failure)
        await fulfillment(of: [finished], timeout: 5)
        fixture.model.onPhaseChange = nil
    }

    private func userInput(_ data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
        let content = try XCTUnwrap(messages.first(where: { $0["role"] == "user" })?["content"])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
    }
}

@MainActor private final class PromptFlowBoundaries {
    var captures = 0
    var insertions = 0
    var recordingStarts = 0
}

private actor PromptFlowReviewer: DecisionEvaluating {
    let uncertainFinal: Bool
    let qualityWarningFinal: Bool
    let rejectDraft: Bool
    let failedReview: Int?
    private(set) var calls: [PromptCompositionReviewRequest] = []
    private var heldReview: Int?
    private var warnedReview: Int?
    private var pausedReview: Int?
    private var pendingReview: CheckedContinuation<Void, Never>?
    private var onPause: (@Sendable () -> Void)?
    private var onReturn: (@Sendable () -> Void)?
    init(uncertainFinal: Bool, qualityWarningFinal: Bool, rejectDraft: Bool, failedReview: Int?) {
        self.uncertainFinal = uncertainFinal; self.qualityWarningFinal = qualityWarningFinal
        self.rejectDraft = rejectDraft; self.failedReview = failedReview
    }
    func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        throw DecisionError.invalidInput
    }
    func holdReview(number: Int) { heldReview = number }
    func warnReview(number: Int) { warnedReview = number }
    func pauseReview(number: Int, onPause: @escaping @Sendable () -> Void, onReturn: @escaping @Sendable () -> Void) {
        pausedReview = number; self.onPause = onPause; self.onReturn = onReturn
    }
    func resumeReview() { pendingReview?.resume(); pendingReview = nil }
    func reviewPromptComposition(_ input: PromptCompositionReviewRequest, configuration: DecisionConfiguration,
                                 onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> PromptCompositionReviewResult {
        calls.append(input)
        if calls.count == failedReview { throw DecisionError.invalidResponse }
        if calls.count == pausedReview {
            await withCheckedContinuation { continuation in
                pendingReview = continuation
                onPause?()
            }
            onReturn?()
        }
        await onUsage?(.init(provider: .openRouter, decisionProvider: .openRouter, model: configuration.provider.model,
            stage: .decisionReview, httpStatus: 200, inputTokens: 5, outputTokens: 3, providerCostUSD: 0.000001))
        let choice: PromptCompositionReviewChoice = calls.count == 1 && rejectDraft ? .fail
            : uncertainFinal && calls.count == 2 || calls.count == heldReview ? .uncertain : .pass
        var probabilities: [PromptCompositionReviewChoice: Double] = [.pass: 0.03, .fail: 0.03, .uncertain: 0.03]
        probabilities[choice] = 0.94
        let assessment = PromptCompositionReviewAssessment(choice: choice, probabilities: probabilities, confidence: 0.9)
        var assessments = Dictionary(uniqueKeysWithValues: PromptCompositionIssue.allCases.map { ($0, assessment) })
        if qualityWarningFinal && calls.count == 2 || calls.count == warnedReview {
            let warning = PromptCompositionReviewAssessment(choice: .uncertain,
                probabilities: [.pass: 0.03, .fail: 0.03, .uncertain: 0.94], confidence: 0.9)
            for issue in [PromptCompositionIssue.intent, .unsupportedAdditions, .omissions] { assessments[issue] = warning }
        }
        return .init(assessments: assessments)
    }
}

private final class PromptFlowSecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[service + account] }
    func save(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[service + account] = nil }
}

private final class PromptFlowHTTP: @unchecked Sendable {
    static let transcript = "OpenNoType에서 말한 아이디어를 Codex용 짧은 작업 요청으로 정리해 줘. 코드나 설계는 넣지 마."
    static let draft = "OpenNoType의 아이디어를 Codex용 짧은 작업 요청으로 정리해 주세요."
    static let final = "OpenNoType의 아이디어를 Codex용 짧은 작업 요청으로 정리해 주세요. 코드와 직접 설계는 포함하지 마세요."
    let id = UUID().uuidString
    let session: URLSession
    let client: ProviderClient
    var bodies: [Data] { PromptFlowURLProtocol.bodies(for: id) }
    var transcriptions: Int { PromptFlowURLProtocol.transcriptions(for: id) }
    init(malformedGeneration: Int? = nil) {
        PromptFlowURLProtocol.register(id, malformedGeneration: malformedGeneration)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PromptFlowURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-OpenNoType-PromptFlow": id]
        session = URLSession(configuration: configuration)
        client = ProviderClient(session: session)
    }
    func close() { session.invalidateAndCancel(); PromptFlowURLProtocol.remove(id) }
}

/// Every URL is intercepted; no live service, microphone or real credential is used.
private final class PromptFlowURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var logs: [String: [Data]] = [:]
    private static var malformedGenerations: [String: Int] = [:]
    private static var transcriptionCounts: [String: Int] = [:]
    static func register(_ id: String, malformedGeneration: Int?) {
        lock.lock(); defer { lock.unlock() }
        logs[id] = []; malformedGenerations[id] = malformedGeneration; transcriptionCounts[id] = 0
    }
    static func remove(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        logs[id] = nil; malformedGenerations[id] = nil; transcriptionCounts[id] = nil
    }
    static func bodies(for id: String) -> [Data] { lock.lock(); defer { lock.unlock() }; return logs[id] ?? [] }
    static func transcriptions(for id: String) -> Int { lock.lock(); defer { lock.unlock() }; return transcriptionCounts[id] ?? 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url,
                  let id = request.value(forHTTPHeaderField: "X-OpenNoType-PromptFlow") else { throw URLError(.unsupportedURL) }
            if url.path.hasSuffix("/audio/transcriptions") {
                Self.lock.lock(); Self.transcriptionCounts[id, default: 0] += 1; Self.lock.unlock()
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: ["text": PromptFlowHTTP.transcript]))
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            guard url.path.hasSuffix("/chat/completions") else { throw URLError(.unsupportedURL) }
            let body = try Self.body(request)
            Self.lock.lock()
            guard let count = Self.logs[id]?.count else { Self.lock.unlock(); throw URLError(.resourceUnavailable) }
            Self.logs[id]?.append(body)
            let malformed = Self.malformedGenerations[id] == count + 1
            Self.lock.unlock()
            let output = count == 0 ? PromptFlowHTTP.draft : PromptFlowHTTP.final
            let result: [String: Any] = malformed ? ["unexpected": output] : try Self.result(output, for: body)
            let content = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
            let object: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": content]]],
                "model": "test/prompt-flow", "usage": ["prompt_tokens": 5, "completion_tokens": 3, "cost": 0.000001]]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    private static func result(_ output: String, for data: Data) throws -> [String: Any] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let format = body["response_format"] as? [String: Any]
        let jsonSchema = format?["json_schema"] as? [String: Any]
        let schema = jsonSchema?["schema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        guard properties?["segments"] != nil else { return ["text": output] }
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first { $0["role"] as? String == "user" }?["content"] as? String)
        let input = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        let segments = try XCTUnwrap(input["source_segments"] as? [[String: String]])
        // These fixtures exercise transport and UI evidence, not semantic segment coverage.
        return ["segments": try segments.enumerated().map { index, segment in
            ["id": try XCTUnwrap(segment["id"]), "text": index == 0 ? output : ""]
        }]
    }
    private static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
