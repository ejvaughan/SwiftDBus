import XCTest
@testable import SwiftDbus

class SwiftDbusTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(DBusArray<DBusArray<UInt8>>.dbusTypeSignature, "aay")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
