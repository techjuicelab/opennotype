import SwiftUI
import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class ProviderModelPickerLocalizationTests: XCTestCase {
    func testModelMenusUpdateTheirLanguageWithoutChangingIDsOrPrices() {
        let original = AppLocalization.shared.language
        defer { AppLocalization.shared.language = original }
        AppLocalization.shared.language = .english
        let originalIDs = OpenRouterModelChoices.text.map(\.id)
        let originalPrices = OpenRouterModelChoices.text.map(\.price)

        for language in [AppLanguage.english, .korean, .english] {
            AppLocalization.shared.language = language
            let marker = language == .english ? " · Default" : " · 기본"
            XCTAssertTrue(GroqModelChoices.transcription[0].title.hasSuffix(marker))
            XCTAssertEqual(GroqModelChoices.text.filter { $0.title.hasSuffix(marker) }.map(\.id),
                           [ProviderDefaults.forProvider(.groq).textModel])
            XCTAssertEqual(OpenRouterModelChoices.text.filter { $0.title.hasSuffix(marker) }.map(\.id),
                           [ProviderDefaults.forProvider(.openRouter).textModel])
            XCTAssertEqual(OpenRouterModelChoices.text.map(\.id), originalIDs)
            XCTAssertEqual(OpenRouterModelChoices.text.map(\.price), originalPrices)
        }
    }

    func testPriceAccessibilityLabelsFollowLanguageAndKeepDollarPrecision() throws {
        let original = AppLocalization.shared.language
        defer { AppLocalization.shared.language = original }
        let choice = try XCTUnwrap(OpenRouterModelChoices.text.first { $0.id == "google/gemma-4-26b-a4b-it" })
        AppLocalization.shared.language = .english
        XCTAssertEqual(choice.menuTitle, "Gemma 4 26B A4B · $0.0765 / $0.255")
        XCTAssertTrue(choice.accessibilityTitle.contains("per million tokens: input $0.0765, output $0.255"))
        AppLocalization.shared.language = .korean
        XCTAssertEqual(choice.menuTitle, "Gemma 4 26B A4B · $0.0765 / $0.255")
        XCTAssertTrue(choice.accessibilityTitle.contains("100만 토큰당 입력 $0.0765, 출력 $0.255"))
    }

    func testLanguageSwitchKeepsAManuallyEnteredModel() {
        let original = AppLocalization.shared.language
        defer { AppLocalization.shared.language = original }
        var savedID = "my-provider/private-model"
        var writes = 0
        let binding = Binding(get: { savedID }, set: { savedID = $0; writes += 1 })
        for language in [AppLanguage.english, .korean, .english] {
            AppLocalization.shared.language = language
            _ = ProviderModelPicker(L("문장 정리 모델", "Text cleanup model"), selection: binding,
                                    choices: OpenRouterModelChoices.text)
        }
        XCTAssertEqual(savedID, "my-provider/private-model")
        XCTAssertEqual(writes, 0)
    }
}
