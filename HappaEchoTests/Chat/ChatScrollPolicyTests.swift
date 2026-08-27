import XCTest
@testable import HappaEcho

final class ChatScrollPolicyTests: XCTestCase {
    func testStreamingUpdateDoesNotForceScrollAfterUserLeavesBottom() {
        XCTAssertFalse(ChatScrollPolicy.shouldScrollToBottom(
            after: .streamingUpdate,
            userIsAtBottom: false
        ))
    }

    func testNewMessageStillScrollsToBottom() {
        XCTAssertTrue(ChatScrollPolicy.shouldScrollToBottom(
            after: .newMessage,
            userIsAtBottom: false
        ))
    }
}
