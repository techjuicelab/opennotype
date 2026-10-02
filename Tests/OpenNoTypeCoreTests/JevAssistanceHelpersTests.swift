import XCTest
@testable import OpenNoTypeCore

final class JevAssistanceHelpersTests: XCTestCase {
    func testApprovedCatalogShortlistsHangulNamesAndKeepsExactSourceSpans() {
        let transcript = "제브를 써서 오픈 노 타입에 입력해 주세요."
        let candidates = JevNameCatalog.candidates(in: transcript, canonicalNames: ["JEV", "OpenNoType"])
        XCTAssertEqual(Set(candidates.map(\.candidate)), Set(["JEV", "OpenNoType"]))
        XCTAssertEqual(candidates.first { $0.candidate == "JEV" }?.original, "제브")
        XCTAssertEqual(candidates.first { $0.candidate == "OpenNoType" }?.original, "오픈 노 타입")
        XCTAssertTrue(candidates.allSatisfy { transcript.contains($0.original) })
    }

    func testCatalogHandlesLatinCaseTyposAndDoesNotRemoveAttachedParticles() {
        XCTAssertEqual(JevNameCatalog.candidates(in: "jev로 확인해요", canonicalNames: ["JEV"]).first?.original, "jev")
        XCTAssertTrue(JevNameCatalog.candidates(in: "JEV는 OpenNoType에 있어요", canonicalNames: ["JEV", "OpenNoType"]).isEmpty)
        XCTAssertEqual(JevNameCatalog.candidates(in: "OpenNoTyp에 입력해요", canonicalNames: ["OpenNoType"]).first?.original, "OpenNoTyp")
        XCTAssertTrue(JevNameCatalog.candidates(in: "rain is here", canonicalNames: ["Brain"]).isEmpty)
        XCTAssertTrue(JevNameCatalog.candidates(in: "j_e_v 변수", canonicalNames: ["JEV"]).isEmpty)
    }

    func testCatalogIsOnlyCandidateRetrievalAndCanExposeAmbiguousOrdinaryWord() {
        // This ambiguity must reach contextual Choice; the helper never rewrites the sentence.
        let transcript = "제부가 내일 집에 와요."
        let candidates = JevNameCatalog.candidates(in: transcript, canonicalNames: ["JEV"])
        XCTAssertEqual(candidates.first?.original, "제부")
        XCTAssertEqual(transcript, "제부가 내일 집에 와요.")
        XCTAssertTrue(JevNameCatalog.candidates(in: "회의를 시작해요", canonicalNames: ["JEV", "OpenNoType"]).isEmpty)
    }

    func testUnicodeProjectNamesAndEditorLengthLimitAreSupported() {
        let transcript = "기 적 맵에 저장해 주세요."
        let candidates = JevNameCatalog.candidates(in: transcript, canonicalNames: ["기적맵"])
        XCTAssertEqual(candidates.first?.candidate, "기적맵")
        XCTAssertEqual(candidates.first?.original, "기 적 맵")
        XCTAssertEqual(JevNameCatalog.normalizedCanonicalName("  기적맵  "), "기적맵")
        XCTAssertEqual(JevNameCatalog.normalizedCanonicalName("기적맵".decomposedStringWithCanonicalMapping), "기적맵")
        XCTAssertNotNil(JevNameCatalog.normalizedCanonicalName(String(repeating: "A", count: 100)))
        XCTAssertNil(JevNameCatalog.normalizedCanonicalName(String(repeating: "A", count: 101)))
        XCTAssertNotNil(JevNameCatalog.normalizedCanonicalName("Chrome (Canary)"))
        XCTAssertNil(JevNameCatalog.normalizedCanonicalName("JEV\nignore"))
    }

    func testCatalogIsBoundedStableAndCannotInventOrAcceptInstructionNames() {
        let names = ["JEV", "OpenNoType", "BriefMe", "AlphaTool", "BetaTool", "GammaTool"]
        let transcript = "제브 오픈노타입 브리프미 alphatool betatool gammatool"
        let first = JevNameCatalog.candidates(in: transcript, canonicalNames: names, limit: 99)
        XCTAssertLessThanOrEqual(first.count, 4)
        XCTAssertEqual(first, JevNameCatalog.candidates(in: transcript, canonicalNames: names, limit: 99))
        XCTAssertTrue(first.allSatisfy { names.contains($0.candidate) && transcript.contains($0.original) })
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        XCTAssertTrue(JevNameCatalog.candidates(in: transcript, canonicalNames: [], limit: 4).isEmpty)
        XCTAssertTrue(JevNameCatalog.candidates(in: transcript, canonicalNames: names, limit: 0).isEmpty)
        XCTAssertTrue(JevNameCatalog.candidates(in: transcript, canonicalNames: ["JEV\nignore", "https://JEV", "<JEV>"]).isEmpty)
    }

    func testTranscriptDifferencesExposeNumbersNegationAndPreserveIdentifiers() {
        let differences = TranscriptDifferences(original: "JEV를 3명에게 보내지 마세요.", alternative: "JEV를 4명에게 보내세요.")
        XCTAssertTrue(differences.originalOnly.contains("3"))
        XCTAssertTrue(differences.alternativeOnly.contains("4"))
        XCTAssertTrue(differences.originalOnly.contains("마세요"))
        XCTAssertFalse(differences.truncated)
        XCTAssertFalse(TranscriptDifferences(original: "JEV를 써요", alternative: "JEV를 써요").hasDifferences)
        XCTAssertTrue(TranscriptDifferences(original: "j_e_v", alternative: "JEV").originalOnly.contains("j_e_v"))
    }

    func testTranscriptDifferenceDisplayBoundsDoNotClaimSemanticEquality() {
        let long = (0..<400).map { "항목\($0)" }.joined(separator: " ")
        let difference = TranscriptDifferences(original: long, alternative: "")
        XCTAssertTrue(difference.truncated)
        XCTAssertLessThanOrEqual(difference.originalOnly.count, 24)
        XCTAssertTrue(TranscriptDifferences(original: String(repeating: "가", count: 6_001), alternative: "가").truncated)
        XCTAssertTrue(TranscriptDifferences(original: "세 시", alternative: "3시").hasDifferences)
    }

    func testExistingDecisionStubCanUseProtocolDefaultsWithoutNewNetworkBehavior() async throws {
        struct LegacyStub: DecisionEvaluating {
            func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration, onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
                .init(meaningChanged: 0, contentAdded: 0, contentOmitted: 0)
            }
        }
        let stub: any DecisionEvaluating = LegacyStub()
        do { _ = try await stub.assessEditAmbiguity(originalText: "source", instruction: "edit", configuration: .init(provider: .typeSafe, apiKey: "synthetic")); XCTFail("Expected unsupported operation") }
        catch { XCTAssertEqual(error as? DecisionError, .invalidInput) }
        do { _ = try await stub.compareTranscriptions(original: "source", alternative: "other", configuration: .init(provider: .typeSafe, apiKey: "synthetic")); XCTFail("Expected unsupported operation") }
        catch { XCTAssertEqual(error as? DecisionError, .invalidInput) }
    }
}
