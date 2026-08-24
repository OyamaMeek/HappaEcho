import XCTest
@testable import HappaEcho

final class ServerSentEventParserTests: XCTestCase {
    // MARK: - Basic event parsing

    func testSingleDataLineProducesEvent() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("data: hello\n\n".utf8))
        XCTAssertEqual(events.map(\.data), ["hello"])
    }

    func testMultipleDataLinesJoinWithNewline() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("data: first\ndata: second\n\n".utf8))
        XCTAssertEqual(events.map(\.data), ["first\nsecond"])
    }

    func testEventsResetAfterBlankLine() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("data: one\n\ndata: two\n\n".utf8))
        XCTAssertEqual(events.map(\.data), ["one", "two"])
    }

    // MARK: - Line endings

    func testCRLFLineEndings() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("data: hello\r\ndata: world\r\n\r\n".utf8))
        XCTAssertEqual(events.map(\.data), ["hello\nworld"])
    }

    // MARK: - Field syntax

    func testLeadingSingleSpaceAfterColonIsStripped() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("data: spaced\n\n".utf8))
        XCTAssertEqual(events.map(\.data), ["spaced"])
    }

    func testExtraSpacesAfterColonAreKeptExceptTheFirst() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("data:   three\n\n".utf8))
        XCTAssertEqual(events.map(\.data), ["  three"])
    }

    func testEventTypeIsPreserved() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("event: custom\ndata: value\n\n".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].eventType, "custom")
        XCTAssertEqual(events[0].data, "value")
    }

    func testCommentLinesAreIgnored() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data(": heartbeat\ndata: ok\n\n".utf8))
        XCTAssertEqual(events.map(\.data), ["ok"])
    }

    // MARK: - Boundaries and no-data

    func testBlankLineWithoutDataDoesNotDispatch() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("event: ping\n\n\n\n".utf8))
        XCTAssertTrue(events.isEmpty)
    }

    func testEmptyChunkProducesNoEvents() {
        var parser = ServerSentEventParser()
        XCTAssertTrue(parser.append(Data()).isEmpty)
        XCTAssertTrue(parser.finish().isEmpty)
    }

    // MARK: - Byte fragmentation

    func testSplitUTF8CodePointAcrossChunks() {
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []

        // "data: 你好\n\n" where 你 = E4 BD A0 and 好 = E5 A5 BD, with the
        // first code point split across chunk boundaries.
        events += parser.append(Data("data: ".utf8) + Data([0xE4, 0xBD]))
        events += parser.append(Data([0xA0, 0xE5, 0xA5]))
        events += parser.append(Data([0xBD]) + Data("\n\n".utf8))

        XCTAssertEqual(events.map(\.data), ["你好"])
    }

    func testByteAtATimeFragmentation() {
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []
        for byte in Data("data: alpha\n\ndata: beta\n\n".utf8) {
            events += parser.append(Data([byte]))
        }
        XCTAssertEqual(events.map(\.data), ["alpha", "beta"])
    }

    // MARK: - Terminal [DONE]

    func testDoneMarkerIsPreserved() {
        var parser = ServerSentEventParser()
        let events = parser.append(Data("data: [DONE]\n\n".utf8))
        XCTAssertEqual(events.map(\.data), ["[DONE]"])
    }

    func testFinishFlushesUnterminatedEvent() {
        var parser = ServerSentEventParser()
        // No trailing blank line before the end of the stream.
        _ = parser.append(Data("data: first\ndata: second".utf8))
        let events = parser.finish()
        XCTAssertEqual(events.map(\.data), ["first\nsecond"])
    }

    func testFinishDispatchesUnterminatedDone() {
        var parser = ServerSentEventParser()
        _ = parser.append(Data("data: [DONE]".utf8))
        let events = parser.finish()
        XCTAssertEqual(events.map(\.data), ["[DONE]"])
    }
}
