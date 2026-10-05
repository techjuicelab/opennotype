import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class DictationTranslationPreviewTests: KoreanPresentationTestCase {
    func testEveryPreviewPreservesTheDeadlineCountAndApprovalRestrictionInTheAuthoredExample() {
        XCTAssertTrue(DictationTranslationExamples.source.contains("오늘 안"))
        XCTAssertTrue(DictationTranslationExamples.source.contains("12개"))
        for language in DictationOutputLanguage.allCases {
            let text = DictationTranslationExamples.result(for: language)
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(text.contains("12"))
            switch language {
            case .original, .korean:
                XCTAssertTrue(text.contains("오늘 안"))
                XCTAssertTrue(text.contains("승인 전에는 공유하지"))
            case .english:
                XCTAssertTrue(text.contains("by the end of today"))
                XCTAssertTrue(text.contains("don't share it until it's approved"))
            case .japanese:
                XCTAssertTrue(text.contains("今日中"))
                XCTAssertTrue(text.contains("承認が出るまでは共有しない"))
                XCTAssertTrue(text.contains("いただけますか"))
            }
        }
    }

    func testInterfaceLanguageDoesNotTranslateTheSourceOrChangeTheOutputExample() {
        let source = DictationTranslationExamples.source
        let outputs = DictationOutputLanguage.allCases.map(DictationTranslationExamples.result)
        AppLocalization.shared.language = .english
        XCTAssertEqual(DictationTranslationExamples.source, source)
        XCTAssertEqual(DictationOutputLanguage.allCases.map(DictationTranslationExamples.result), outputs)
    }
}
