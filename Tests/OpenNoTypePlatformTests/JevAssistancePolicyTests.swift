import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class JevAssistancePolicyTests: XCTestCase {
    func testEconomyRequiresNonemptyExactEqualityAndNoCandidate() {
        XCTAssertTrue(JevAssistancePolicy.canSkipReview(transcript: "회의는 3시입니다.", output: "회의는 3시입니다.", terms: []))
        XCTAssertFalse(JevAssistancePolicy.canSkipReview(transcript: " ", output: " ", terms: []))
        XCTAssertFalse(JevAssistancePolicy.canSkipReview(transcript: "3시 입니다", output: "3시입니다", terms: []))
        XCTAssertFalse(JevAssistancePolicy.canSkipReview(transcript: "제브", output: "제브", terms: [.init(id: "name", original: "제브", candidate: "JEV")]))
    }

    func testAmbiguityGateRejectsLowConfidenceOrMissingEvidence() {
        XCTAssertFalse(JevAssistancePolicy.editIsClear(nil))
        XCTAssertFalse(JevAssistancePolicy.editIsClear(.init(choice: .clear)))
        XCTAssertFalse(JevAssistancePolicy.editIsClear(.init(choice: .clear, probabilities: [.clear: 0.9], confidence: 0.2)))
        XCTAssertFalse(JevAssistancePolicy.editIsClear(.init(choice: .ambiguous, probabilities: [.ambiguous: 0.9], confidence: 0.9)))
        XCTAssertTrue(JevAssistancePolicy.editIsClear(.init(choice: .clear, probabilities: [.clear: 0.9], confidence: 0.8)))
    }

    func testTranscriptGateDoesNotPickTheCorrectAudioHypothesis() {
        XCTAssertTrue(JevAssistancePolicy.transcriptsEquivalent(.init(choice: .equivalent, probabilities: [.equivalent: 0.9], confidence: 0.8)))
        XCTAssertFalse(JevAssistancePolicy.transcriptsEquivalent(.init(choice: .equivalent)))
        for choice in [DecisionTranscriptChoice.meaningfulDifference, .uncertain] {
            XCTAssertFalse(JevAssistancePolicy.transcriptsEquivalent(.init(choice: choice, probabilities: [choice: 0.99], confidence: 0.99)))
        }
    }

    func testRetranscriptionKeepsProviderAndStoredKeyAndRejectsUnknownModels() throws {
        let source = ProviderConfiguration(provider: .groq, apiKey: "synthetic", transcriptionModel: "whisper-large-v3-turbo", textModel: "untouched")
        let alternate = try XCTUnwrap(JevAssistancePolicy.alternativeTranscriptionConfiguration(source))
        XCTAssertEqual(alternate.provider, source.provider)
        XCTAssertEqual(alternate.apiKey, source.apiKey)
        XCTAssertEqual(alternate.textModel, source.textModel)
        XCTAssertEqual(alternate.transcriptionModel, "whisper-large-v3")
        for provider in AIProvider.allCases {
            let unknown = ProviderConfiguration(provider: provider, apiKey: "synthetic", transcriptionModel: "custom-private-model", textModel: "unchanged")
            XCTAssertNil(JevAssistancePolicy.alternativeTranscriptionConfiguration(unknown))
        }
    }

    func testResolvedCandidateDoesNotTriggerExtraSpeechRequest() {
        let terms = [DecisionTermCandidate(id: "name", original: "제브", candidate: "JEV")]
        XCTAssertTrue(JevAssistancePolicy.needsNameRecheck(output: "제브로 개선해요", terms: terms))
        XCTAssertFalse(JevAssistancePolicy.needsNameRecheck(output: "JEV로 개선해요", terms: terms))
        XCTAssertFalse(JevAssistancePolicy.needsNameRecheck(output: "다른 말", terms: terms))
    }

    func testAutomaticReservationUsesActualPromptAndRefusesUnknownPrice() throws {
        let simple = ProcessingRequest(mode: .dictation, transcript: "제브로 개선해요")
        let withHints = ProcessingRequest(mode: .dictation, transcript: "제브로 개선해요", dictionary: [.init(spoken: "제브", written: "JEV")], previousOutput: "제브로 개선해요")
        let bytes = try ProviderClient.processingInputBytes(simple)
        XCTAssertGreaterThan(bytes, simple.transcript.utf8.count)
        XCTAssertGreaterThan(try ProviderClient.processingInputBytes(withHints), bytes)
        XCTAssertTrue(JevAssistancePolicy.automaticImprovementFitsBudget(model: "inclusionai/ling-3.0-flash", provider: .openRouter, promptBytes: bytes))
        XCTAssertFalse(JevAssistancePolicy.automaticImprovementFitsBudget(model: "unknown", provider: .openRouter, promptBytes: bytes))
        XCTAssertFalse(JevAssistancePolicy.automaticImprovementFitsBudget(model: "inclusionai/ling-3.0-flash", provider: .openRouter, promptBytes: 100_001))
    }
}
