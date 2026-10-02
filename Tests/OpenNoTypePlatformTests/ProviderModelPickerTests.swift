import SwiftUI
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class ProviderModelPickerTests: XCTestCase {
    func testMenuRetainsSmallPricePrecisionAndNamesInputBeforeOutput() throws {
        let gemma = try XCTUnwrap(OpenRouterModelChoices.text.first { $0.id == "google/gemma-4-26b-a4b-it" })
        XCTAssertEqual(gemma.menuTitle, "Gemma 4 26B A4B · $0.0765 / $0.255")
        XCTAssertTrue(gemma.accessibilityTitle.contains("100만 토큰당 입력 $0.0765, 출력 $0.255"))
        let solar = try XCTUnwrap(OpenRouterModelChoices.text.first { $0.id == "upstage/solar-mini4" })
        XCTAssertEqual(solar.menuTitle, "Solar Mini 4 · $0.05 / $0.20")
    }

    func testOnlyTheExistingProviderDefaultGetsTheDefaultMarker() {
        XCTAssertEqual(OpenRouterModelChoices.text.filter { $0.title.contains("기본") }.map(\.id),
                       [ProviderDefaults.forProvider(.openRouter).textModel])
        XCTAssertEqual(GroqModelChoices.text.filter { $0.title.contains("기본") }.map(\.id),
                       [ProviderDefaults.forProvider(.groq).textModel])
        XCTAssertEqual(OpenRouterModelChoices.text.map(\.id), TextModelCatalog.entries(for: .openRouter).map(\.id))
    }

    func testTranscriptionMenuDoesNotMislabelAudioAsTokenPricing() {
        XCTAssertTrue(GroqModelChoices.transcription.allSatisfy { $0.price == nil })
        XCTAssertTrue(GroqModelChoices.transcription.allSatisfy { $0.menuTitle == $0.title })
        XCTAssertTrue(GroqModelChoices.transcription.allSatisfy { !$0.accessibilityTitle.contains("토큰") })
    }

    func testConstructingThePickerNeverReplacesASavedOrCustomModel() {
        for stored in ["my-provider/private-model", "qwen/qwen3-30b-a3b-instruct-2507", "openai/gpt-4.1-mini"] {
            var modelID = stored
            var writes = 0
            let binding = Binding(get: { modelID }, set: { modelID = $0; writes += 1 })
            _ = ProviderModelPicker("문장 정리 모델", selection: binding, choices: OpenRouterModelChoices.text)
            XCTAssertEqual(modelID, stored)
            XCTAssertEqual(writes, 0)
        }
    }
}
