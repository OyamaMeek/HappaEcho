import XCTest
@testable import HappaEcho

final class NotionBlockFormatterTests: XCTestCase {
    private let formatter = NotionBlockFormatter(maxRichTextCharacters: 2_000, maxBlocksPerBatch: 5)

    func testPagePropertiesContainConversationMetadata() {
        let conversation = Conversation(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "A chat",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            modelID: "gpt-test"
        )
        conversation.messages = [
            Message(role: .user, content: "One", sequence: 0, syncState: .synced),
            Message(role: .assistant, content: "Two", sequence: 1, syncState: .synced),
        ]

        XCTAssertEqual(formatter.pageProperties(for: conversation), [
            "Title": .title("A chat"),
            "Created": .date(Date(timeIntervalSince1970: 100)),
            "Updated": .date(Date(timeIntervalSince1970: 200)),
            "Model": .richText("gpt-test"),
            "MessageCount": .number(2),
            "Status": .select("success"),
        ])
    }

    func testPagePropertiesUseEmptyModelAndNoneStatusWhenNotSynced() {
        let conversation = Conversation(title: "Empty", modelID: nil)
        XCTAssertEqual(formatter.pageProperties(for: conversation)["Model"], .richText(""))
        XCTAssertEqual(formatter.pageProperties(for: conversation)["Status"], .select("none"))
    }

    func testFormatsLongParagraphIntoTwoThousandCharacterRichTextSegments() {
        let text = String(repeating: "a", count: 2_001)
        let message = Message(role: .user, content: text, createdAt: Date(timeIntervalSince1970: 0), sequence: 0)
        let blocks = formatter.blocks(for: message, batchIndex: 0)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks.map(\.plainText), ["happaecho-message:\(blocks[0].markerMessageID!.uuidString.lowercased()):batch:0", "User", "1970-01-01T00:00:00Z", text])
        XCTAssertEqual(blocks[3].richText.map(\.content.count), [2_000, 1])
    }

    func testFormatsMarkdownDeterministicallyWithRoleAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let message = Message(role: .assistant, content: "# Heading\n- first\n- second\n> quote\n```swift\nlet x = 1\n```", createdAt: timestamp, sequence: 0)
        let blocks = formatter.blocks(for: message, batchIndex: 2)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .paragraph, .paragraph, .heading(level: 1), .bulletedListItem, .bulletedListItem, .quote, .code(language: "swift")])
        XCTAssertEqual(blocks.map(\.plainText), [
            "happaecho-message:\(message.id.uuidString.lowercased()):batch:2",
            "Assistant",
            "2023-11-14T22:13:20Z",
            "Heading", "first", "second", "quote", "let x = 1",
        ])
    }

    func testPreservesOrdinaryMultilineParagraphInOneBlock() {
        let message = Message(role: .user, content: "first line\nsecond line\nthird line", sequence: 0)
        let blocks = formatter.blocks(for: message, batchIndex: 0)
        XCTAssertEqual(blocks.dropFirst(3).map(\.plainText), ["first line\nsecond line\nthird line"])
    }

    func testFallsBackToParagraphForUnclosedCodeFenceAndPreservesRawLatex() {
        let message = Message(role: .user, content: "$$\\frac{a}{b}$$\n```swift\nlet x", sequence: 0)
        let blocks = formatter.blocks(for: message, batchIndex: 0)
        XCTAssertEqual(blocks.dropFirst(3).map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(blocks.dropFirst(3).map(\.plainText), ["$$\\frac{a}{b}$$", "```swift\nlet x"])
    }

    func testSplitsBlocksIntoStableMarkedBatches() throws {
        let message = Message(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, role: .user, content: "# one\n# two\n# three\n# four", sequence: 0)
        let batches = try formatter.batches(for: message)
        XCTAssertEqual(batches.map(\.index), [0, 1])
        XCTAssertEqual(batches.map(\.marker), [
            "happaecho-message:22222222-2222-2222-2222-222222222222:batch:0",
            "happaecho-message:22222222-2222-2222-2222-222222222222:batch:1",
        ])
        XCTAssertEqual(batches.map { $0.blocks.count }, [5, 2])
        XCTAssertEqual(batches.flatMap(\.blocks).filter { $0.markerMessageID != nil }.count, 2)
    }
    func testRejectsBatchLimitsThatCannotHoldMessageContent() {
        let message = Message(role: .user, content: "content", sequence: 0)
        for limit in [0, 1] {
            let formatter = NotionBlockFormatter(maxBlocksPerBatch: limit)
            XCTAssertThrowsError(try formatter.batches(for: message)) { error in
                XCTAssertEqual(error as? NotionBlockFormatterError, .invalidBatchLimit(limit))
            }
        }
    }

    func testNeverExceedsConfiguredBatchLimitBelowMetadataCount() throws {
        let formatter = NotionBlockFormatter(maxBlocksPerBatch: 2)
        let message = Message(role: .user, content: "# one\n# two", sequence: 0)
        let batches = try formatter.batches(for: message)
        XCTAssertTrue(batches.allSatisfy { $0.blocks.count <= 2 })
        XCTAssertEqual(batches.flatMap(\.blocks).filter { $0.markerMessageID == message.id }.count, batches.count)
    }
}