import Foundation

/// A single parsed Server-Sent Event.
///
/// The OpenAI-compatible protocol only needs the `data` payload, but the event
/// type is preserved so callers can branch on provider-specific event names.
struct ServerSentEvent: Equatable, Sendable {
    var eventType: String
    var data: String
}

/// Incrementally parses an SSE byte stream that arrives in arbitrary chunks.
///
/// Feed every received chunk through `append(_:)`, then call `finish()` once
/// the stream ends so the final unterminated event is dispatched. The parser
/// only decodes complete lines: a multi-byte UTF-8 code point split across
/// chunks is buffered until its terminating newline arrives, so it is never
/// split mid-sequence. Both LF and CRLF line endings are accepted, multiple
/// `data:` lines join with `\n`, and a blank line dispatches the event.
struct ServerSentEventParser {
    /// Bytes received but not yet containing a complete line.
    private var pending = Data()

    private var eventType = ""
    private var dataLines: [String] = []

    /// Consumes a chunk of raw bytes and returns any complete events it
    /// contains. Returns an empty array when the chunk only completes part of
    /// a line.
    mutating func append(_ chunk: Data) -> [ServerSentEvent] {
        pending.append(chunk)
        return processPending()
    }

    /// Consumes a single byte and returns any complete events it completes.
    ///
    /// Streaming transports read byte-at-a-time from `URLSession.AsyncBytes`;
    /// feeding each byte here keeps the parser naturally aligned to arbitrary
    /// network fragmentation while emitting every completed event immediately.
    mutating func append(_ byte: UInt8) -> [ServerSentEvent] {
        pending.append(byte)
        return processPending()
    }

    private mutating func processPending() -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineEnd = pending.distance(from: pending.startIndex, to: newline)
            let lineData = pending.prefix(lineEnd)
            pending.removeSubrange(pending.startIndex...newline)
            process(line: decode(lineData), into: &events)
        }
        return events
    }

    /// Dispatches any event left without a trailing blank line at end of
    /// stream, then resets the parser to a fresh state.
    mutating func finish() -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        if !pending.isEmpty {
            process(line: decode(pending), into: &events)
            pending.removeAll()
        }
        if !dataLines.isEmpty {
            events.append(makeEvent())
            resetFields()
        }
        return events
    }

    // MARK: - Line processing

    private mutating func process(line: String, into events: inout [ServerSentEvent]) {
        if line.isEmpty {
            if !dataLines.isEmpty {
                events.append(makeEvent())
                resetFields()
            }
        } else if line.hasPrefix("data:") {
            let value = stripSingleLeadingSpace(line.dropFirst("data:".count))
            dataLines.append(value)
        } else if line.hasPrefix("event:") {
            eventType = stripSingleLeadingSpace(line.dropFirst("event:".count))
        }
        // Other fields (`id:`, `retry:`) and comment lines starting with `:`
        // are ignored; they carry no payload for the Chat Completions protocol.
    }

    private func makeEvent() -> ServerSentEvent {
        ServerSentEvent(eventType: eventType, data: dataLines.joined(separator: "\n"))
    }

    private mutating func resetFields() {
        eventType = ""
        dataLines.removeAll(keepingCapacity: true)
    }

    private func decode(_ data: Data) -> String {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        return line
    }

    /// Per the SSE spec, a field value keeps a single leading space only if it
    /// is present; further leading spaces are preserved.
    private func stripSingleLeadingSpace(_ value: Substring) -> String {
        if value.hasPrefix(" ") {
            return String(value.dropFirst())
        }
        return String(value)
    }
}
