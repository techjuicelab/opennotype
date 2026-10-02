import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class ImprovementPreferencesTests: XCTestCase {
    func testAlternativeModelIsProviderScopedAndDefaultsToCurrentModel() throws {
        var settings = Preferences()
        settings.textProvider = .openRouter
        settings.textModels[AIProvider.openRouter.rawValue] = "current"
        XCTAssertEqual(settings.improvementModel, "current")
        settings.improvementModels[AIProvider.openRouter.rawValue] = "alternative"
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.improvementModel, "alternative")
        settings.textProvider = .groq
        XCTAssertEqual(settings.improvementModel, settings.textModel)
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(old.improvementModel, old.textModel)
        XCTAssertEqual(old.decisionReviewMode, .off)
    }
}
