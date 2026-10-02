import XCTest
import OpenNoTypeCore
@testable import OpenNoType

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

extension Preferences {
    static var koreanForTesting: Preferences {
        var preferences = Preferences()
        preferences.interfaceLanguage = .korean
        return preferences
    }
}
