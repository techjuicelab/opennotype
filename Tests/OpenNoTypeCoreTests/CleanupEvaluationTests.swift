import CryptoKit
import Foundation
import XCTest
@testable import OpenNoTypeCore

/// These tests validate evaluation inputs and prompt boundaries, not live model quality.
final class CleanupEvaluationTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixtures() throws -> (Data, [[String: Any]]) {
        let data = try Data(contentsOf: repository.appendingPathComponent("docs/fixtures/faithful-cleanup.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(object["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        let ids = try cases.map { try XCTUnwrap($0["id"] as? String) }
        XCTAssertEqual(Set(ids).count, ids.count, "Every evaluation case needs a stable unique ID")
        return (data, cases)
    }

    private func request(_ fixture: [String: Any]) throws -> ProcessingRequest {
        let mode = try XCTUnwrap(InputMode(rawValue: XCTUnwrap(fixture["mode"] as? String)))
        let transcript = try XCTUnwrap(fixture["stt_input"] as? String)
        let profile = try XCTUnwrap(fixture["writing_profile"] as? [String: String])
        let kind = try XCTUnwrap(WritingProfileKind(rawValue: XCTUnwrap(profile["kind"])))
        let tone = try XCTUnwrap(WritingTone(rawValue: XCTUnwrap(profile["tone"])))
        let dictionary = try XCTUnwrap(fixture["dictionary"] as? [[String: String]]).map {
            DictionaryEntry(spoken: try XCTUnwrap($0["spoken"]), written: try XCTUnwrap($0["written"]))
        }
        return ProcessingRequest(mode: mode, transcript: transcript,
            selectedText: fixture["selected_text"] as? String,
            context: fixture["cursor_context"] as? String,
            dictionary: dictionary,
            targetLanguage: fixture["target_language"] as? String ?? "English (United States)",
            writingProfile: .init(kind: kind, tone: tone))
    }

    func testSyntheticFixtureUnicodeAndModeBoundaries() throws {
        for fixture in try fixtures().1 {
            let id = try XCTUnwrap(fixture["id"] as? String)
            let source = try request(fixture)
            let prompt = try ProcessingPrompt.build(source)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.input.utf8)) as? [String: Any])
            let field = source.mode == .rewrite ? "edit_instruction" : "spoken_text"
            XCTAssertEqual(Data(try XCTUnwrap(payload[field] as? String).utf8), Data(source.transcript.utf8), id)
            XCTAssertEqual(payload["mode"] as? String, source.mode.rawValue, id)
            XCTAssertNotNil(fixture["expected_text"] as? String, id)
            XCTAssertFalse(try XCTUnwrap(fixture["preservation_conditions"] as? [String]).isEmpty, id)
            XCTAssertFalse(try XCTUnwrap(fixture["forbidden_changes"] as? [String]).isEmpty, id)
            if source.mode == .rewrite {
                XCTAssertEqual(payload["original_text"] as? String, source.selectedText, id)
                XCTAssertNil(payload["spoken_text"], id)
                XCTAssertNil(payload["writing_profile"], id)
                XCTAssertNil(payload["target_language"], id)
            } else {
                XCTAssertEqual(payload["writing_profile"] as? [String: String],
                    ["kind": source.writingProfile.kind.rawValue, "tone": source.writingProfile.tone.rawValue], id)
                XCTAssertNil(payload["original_text"], id)
                XCTAssertNil(payload["edit_instruction"], id)
                if source.mode == .translation { XCTAssertNotNil(payload["target_language"] as? String, id) }
                else { XCTAssertNil(payload["target_language"], id) }
            }
            XCTAssertEqual(payload["cursor_context"] as? String,
                source.context.flatMap { $0.isEmpty ? nil : String($0.suffix(1_000)) }, id)
            let entries = try XCTUnwrap(payload["dictionary"] as? [[String: String]])
            XCTAssertEqual(entries.count, source.dictionary.count, id)
            for entry in entries {
                XCTAssertTrue(source.dictionary.contains {
                    entry == ["spoken": String($0.spoken.prefix(120)), "written": String($0.written.prefix(120))]
                }, id)
            }
            let clean = ProcessingRequest(mode: source.mode, transcript: "독립된 합성 검증 문장입니다.",
                selectedText: source.mode == .rewrite ? "선택한 합성 문장입니다." : nil,
                targetLanguage: source.targetLanguage, writingProfile: source.writingProfile)
            XCTAssertEqual(prompt.instructions, try ProcessingPrompt.build(clean).instructions,
                "\(id): fixture text, context and dictionary must remain data")
        }
    }

    func testEvaluationUsesProductionInputValidation() {
        for transcript in [" \n\t", String(repeating: "가", count: 80_001)] {
            for mode in InputMode.allCases {
                XCTAssertThrowsError(try ProcessingPrompt.build(.init(mode: mode, transcript: transcript, selectedText: "원문")))
            }
        }
        for selected in [nil, " \n", String(repeating: "나", count: 80_001)] as [String?] {
            XCTAssertThrowsError(try ProcessingPrompt.build(.init(mode: .rewrite, transcript: "오타만 고쳐 줘", selectedText: selected)))
        }
        XCTAssertThrowsError(try ProcessingPrompt.build(.init(mode: .translation, transcript: "합성 문장", targetLanguage: "unsupported")))
    }

    func testExportProductionPromptsWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["OPENNOTYPE_CLEANUP_EXPORT"] else { return }
        guard path.hasPrefix("/"), !path.hasSuffix("/") else {
            XCTFail("OPENNOTYPE_CLEANUP_EXPORT must be an absolute output file path")
            return
        }
        let (fixtureData, cases) = try fixtures()
        let exported: [[String: Any]] = try cases.map { fixture in
            let prompt = try ProcessingPrompt.build(request(fixture))
            return ["fixture": fixture, "instructions": prompt.instructions, "input": prompt.input,
                    "instructions_sha256": Self.sha256(Data(prompt.instructions.utf8))]
        }
        let source = try Data(contentsOf: repository.appendingPathComponent("Sources/OpenNoTypeCore/AI/ProcessingPrompt.swift"))
        var sourceHashes: [String: String] = [:]
        for path in ["Sources/OpenNoTypeCore/AI/ProcessingPrompt.swift", "Sources/OpenNoTypeCore/AI/DictationCleanupInstructions.swift"] {
            let file = repository.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: file.path) {
                sourceHashes[path] = Self.sha256(try Data(contentsOf: file))
            }
        }
        let export: [String: Any] = [
            "schema_version": 1,
            "status": "synthetic_fixture_prompts_not_live_model_results",
            "fixture_sha256": Self.sha256(fixtureData),
            "prompt_source_sha256": Self.sha256(source),
            "source_sha256": sourceHashes,
            "cases": exported
        ]
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: output, options: .atomic)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
