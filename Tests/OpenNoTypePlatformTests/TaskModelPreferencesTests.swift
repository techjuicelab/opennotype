import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class TaskModelPreferencesTests: XCTestCase {
    func testTasksFollowCleanupUntilTheyHaveTheirOwnModel() {
        var settings = Preferences()
        settings.textProvider = .openRouter
        settings.textModels[AIProvider.openRouter.rawValue] = "cleanup"
        for task in TextTask.allCases {
            XCTAssertEqual(settings.textModel(forTask: task), "cleanup", "\(task)")
            XCTAssertFalse(settings.hasOwnModel(task))
        }
        settings.taskModels[AIProvider.openRouter.rawValue] = ["translation": "translator", "prompt": "writer"]
        XCTAssertEqual(settings.textModel(forTask: .translation), "translator")
        XCTAssertEqual(settings.textModel(forTask: .refinement), "translator", "Refinement follows translation")
        XCTAssertEqual(settings.textModel(forTask: .prompt), "writer")
        XCTAssertEqual(settings.textModel(forTask: .rewrite), "cleanup")
        XCTAssertTrue(settings.hasOwnModel(.translation))
    }

    func testModesMapToTheirTaskAndTranslatedDictationUsesTranslation() {
        var settings = Preferences()
        settings.textProvider = .openRouter
        settings.textModels[AIProvider.openRouter.rawValue] = "cleanup"
        settings.taskModels[AIProvider.openRouter.rawValue] = ["translation": "translator", "rewrite": "editor", "prompt": "writer"]
        XCTAssertEqual(settings.textModel(for: .dictation), "cleanup")
        XCTAssertEqual(settings.textModel(for: .translation), "translator")
        XCTAssertEqual(settings.textModel(for: .rewrite), "editor")
        XCTAssertEqual(settings.textModel(for: .prompt), "writer")
        settings.dictationOutputLanguage = DictationOutputLanguage.allCases.first { $0.isTranslation }!
        XCTAssertEqual(settings.textModel(for: .dictation), "translator")
    }

    func testTaskModelsAreScopedToTheTextProviderAndBlankMeansFollow() {
        var settings = Preferences()
        settings.textProvider = .openRouter
        settings.taskModels[AIProvider.openRouter.rawValue] = ["translation": "router-translator"]
        settings.textProvider = .groq
        XCTAssertEqual(settings.textModel(forTask: .translation), settings.textModel)
        settings.taskModels[AIProvider.groq.rawValue] = ["translation": "   "]
        XCTAssertEqual(settings.textModel(forTask: .translation), settings.textModel, "A blank override is not sent as a model id")
        XCTAssertFalse(settings.hasOwnModel(.translation))
    }

    func testTaskModelsSurviveEncodingAndOlderSettingsDecodeUnchanged() throws {
        var settings = Preferences()
        settings.textProvider = .openAI
        settings.taskModels[AIProvider.openAI.rawValue] = ["rewrite": "editor"]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.textModel(forTask: .rewrite), "editor")
        XCTAssertEqual(decoded.recoveryState, .loaded)
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"provider":"openAI"}"#.utf8))
        XCTAssertTrue(old.taskModels.isEmpty)
        XCTAssertEqual(old.textModel(forTask: .prompt), old.textModel)
    }
}
