import XCTest

final class HappaEchoUITests: XCTestCase {
    func testLaunchShowsNewConversationAction() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["新建对话"].waitForExistence(timeout: 5))
    }
}
