import XCTest
@testable import HappaEcho

final class NotionBlockFormatterTests: XCTestCase {
    private let formatter = NotionBlockFormatter(maxRichTextCharacters: 2_000, maxBlocksPerBatch: 3)

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
        let blocks = formatter.blocks(for: Message(role: .user, content: text, sequence: 0), batchIndex: 0)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.plainText), ["happaecho-message:\(blocks[0].markerMessageID!.uuidString.lowercased()):batch:0", text])
        XCTAssertEqual(blocks[1].richText.map(\.content.count), [2_000, 1])
    }

    func testFormatsMarkdownDeterministically() {
        let message = Message(role: .assistant, content: "# Heading\n- first\n- second\n> quote\n```swift\nlet x = 1\n```", sequence: 0)
        let blocks = formatter.blocks(for: message, batchIndex: 2)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .heading(level: 1), .bulletedListItem, .bulletedListItem, .quote, .code(language: "swift")])
        XCTAssertEqual(blocks.dropFirst().map(\.plainText), ["Heading", "first", "second", "quote", "let x = 1"])
    }

    func testFallsBackToParagraphForUnclosedCodeFenceAndPreservesRawLatex() {
        let message = Message(role: .user, content: "$$\\frac{a}{b}$$\n```swift\nlet x", sequence: 0)
        let blocks = formatter.blocks(for: message, batchIndex: 0)
        XCTAssertEqual(blocks.dropFirst().map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(blocks.dropFirst().map(\.plainText), ["$$\\frac{a}{b}$$", "```swift\nlet x"])
    }

    func testSplitsBlocksIntoStableMarkedBatches() {
        let message = Message(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, role: .user, content: "one\ntwo\nthree\nfour", sequence: 0)
        let batches = formatter.batches(for: message)
        XCTAssertEqual(batches.map(\.index), [0, 1])
        XCTAssertEqual(batches.map(\.marker), [
            "happaecho-message:22222222-2222-2222-2222-222222222222:batch:0",
            "happaecho-message:22222222-2222-2222-2222-222222222222:batch:1",
        ])
        XCTAssertEqual(batches.map { $0.blocks.count }, [3, 3])
        XCTAssertEqual(batches.flatMap(\.blocks).filter { $0.markerMessageID != nil }.count, 2)
    }
}
