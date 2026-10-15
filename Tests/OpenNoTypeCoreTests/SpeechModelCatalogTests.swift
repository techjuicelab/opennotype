import Foundation
import XCTest
@testable import OpenNoTypeCore

final class SpeechModelCatalogTests: KoreanPresentationTestCase {
    func testSpeechCatalogPreservesProviderDefaultsAndEndpointSpecificIDs() {
        let expected: [AIProvider: Set<String>] = [
            .openAI: ["gpt-transcribe", "gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"],
            .groq: ["whisper-large-v3-turbo", "whisper-large-v3"],
            .openRouter: ["openai/gpt-transcribe", "openai/gpt-4o-mini-transcribe", "openai/gpt-4o-transcribe",
                          "openai/whisper-1", "openai/whisper-large-v3", "openai/whisper-large-v3-turbo"]
        ]
        for (provider, ids) in expected {
            let entries = SpeechModelCatalog.entries(for: provider)
            XCTAssertEqual(Set(entries.map(\.id)), ids, provider.rawValue)
            XCTAssertEqual(entries.count, ids.count, "No duplicate entries")
            XCTAssertEqual(entries.first?.id, ProviderDefaults.forProvider(provider).transcriptionModel,
                           "Keep the existing default first; do not change stored preferences")
        }
        XCTAssertTrue(SpeechModelCatalog.entries(for: .anthropic).isEmpty)
        XCTAssertTrue(ProviderDefaults.forProvider(.anthropic).requiresLocalTranscription)
    }

    func testSpeechMetadataHasDatedPrimarySourcesAndDistinguishesShutdownScope() throws {
        for provider in AIProvider.allCases {
            for entry in SpeechModelCatalog.entries(for: provider) {
                XCTAssertFalse(entry.title.isEmpty)
                XCTAssertEqual(entry.asOf, "2026-10-15")
                XCTAssertEqual(entry.sourceURL.scheme, "https")
            }
        }
        let direct = try XCTUnwrap(SpeechModelCatalog.entries(for: .openAI).first { $0.id == "whisper-1" })
        XCTAssertTrue(direct.note?.contains("2027-02-26") == true)
        let routed = try XCTUnwrap(SpeechModelCatalog.entries(for: .openRouter).first { $0.id == "openai/whisper-1" })
        XCTAssertTrue(routed.note?.contains("별도로 확인") == true)
        XCTAssertEqual(URLComponents(url: routed.sourceURL, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "output_modalities", value: "transcription")])
    }

    func testSpeechChoicesExcludeUnsupportedRealtimeAndDiarizationContracts() {
        for provider in AIProvider.allCases {
            for entry in SpeechModelCatalog.entries(for: provider) {
                XCTAssertFalse(entry.id.contains("realtime") || entry.id.contains("live") || entry.id.contains("diarize"))
                XCTAssertNil(TextModelCatalog.entry(id: entry.id, provider: provider),
                             "A speech choice must not accidentally appear as a text-generation choice")
            }
        }
    }
}
