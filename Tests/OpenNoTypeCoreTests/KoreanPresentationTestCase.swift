import XCTest
import OpenNoTypeCore

/// These existing presentation contracts describe the Korean interface explicitly.
/// English and language migration have separate bilingual tests.
class KoreanPresentationTestCase: XCTestCase {
    private var previousLanguage: AppLanguage = .english
    override func setUp() {
        super.setUp()
        previousLanguage = AppLocalization.shared.language
        AppLocalization.shared.language = .korean
    }
    override func tearDown() {
        AppLocalization.shared.language = previousLanguage
        super.tearDown()
    }
}
