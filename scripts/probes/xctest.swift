import XCTest

final class XCTestAvailabilityProbe: XCTestCase {
    func testCompilerCanImportXCTest() { XCTAssertEqual(1, 1) }
}
