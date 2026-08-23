import XCTest
@testable import HappaEcho

final class HappaEchoTests: XCTestCase {
    func testProductNameIsHappaEcho() {
        XCTAssertEqual(AppIdentity.name, "HappaEcho")
    }
}
