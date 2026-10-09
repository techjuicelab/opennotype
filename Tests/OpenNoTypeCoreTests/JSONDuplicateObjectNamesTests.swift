import XCTest
@testable import OpenNoTypeCore

final class JSONDuplicateObjectNamesTests: XCTestCase {
    func testValidatedNestedObjectsAndArraysKeepSeparateNameScopes() throws {
        let nested = "{\"value\":" + String(repeating: "[", count: 510)
            + "{\"same\":1}" + String(repeating: "]", count: 510) + "}"
        let data = Data(nested.utf8)
        _ = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(JSONDuplicateObjectNames.areUnique(in: data))
        let duplicate = Data(nested.replacingOccurrences(of: "\"same\":1", with: "\"same\":1,\"same\":2").utf8)
        _ = try JSONSerialization.jsonObject(with: duplicate)
        XCTAssertFalse(JSONDuplicateObjectNames.areUnique(in: duplicate))
    }

    func testManyDistinctNamesAndLongQuotedValuesDoNotHideADuplicate() throws {
        let members = (0..<6_000).map { "\"name\($0)\":0" }.joined(separator: ",")
        let quoted = String(repeating: #"\"same\":1,\"same\":2 \\"#, count: 1_000)
        let unique = Data("{\(members),\"body\":\"\(quoted)\"}".utf8)
        _ = try JSONSerialization.jsonObject(with: unique)
        XCTAssertLessThanOrEqual(unique.count, DecisionClient.maximumResponseBytes)
        XCTAssertTrue(JSONDuplicateObjectNames.areUnique(in: unique))
        let duplicate = Data("{\(members),\"body\":\"\(quoted)\",\"name5999\":1}".utf8)
        _ = try JSONSerialization.jsonObject(with: duplicate)
        XCTAssertFalse(JSONDuplicateObjectNames.areUnique(in: duplicate))
    }
}
