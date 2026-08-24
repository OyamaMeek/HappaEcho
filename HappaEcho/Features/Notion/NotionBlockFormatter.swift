import Foundation

struct NotionBlockFormatter: Sendable {
    let maxRichTextCharacters: Int
    let maxBlocksPerBatch: Int

    init(maxRichTextCharacters: Int = 2_000, maxBlocksPerBatch: Int = 100) { self.maxRichTextCharacters = maxRichTextCharacters; self.maxBlocksPerBatch = maxBlocksPerBatch }

    func pageProperties(for conversation: Conversation) -> [String: NotionProperty] {
        let status: String
        if conversation.messages.isEmpty { status = "none" }
        else if conversation.messages.contains(where: { $0.syncState == .failed }) { status = "failed" }
        else if conversation.messages.contains(where: { $0.syncState == .syncing || $0.syncState == .pending }) { status = "syncing" }
        else { status = "success" }
        return ["Title": .title(conversation.title), "Created": .date(conversation.createdAt), "Updated": .date(conversation.updatedAt), "Model": .richText(conversation.modelID ?? ""), "MessageCount": .number(conversation.messages.count), "Status": .select(status)]
    }

    func blocks(for message: Message, batchIndex: Int) -> [NotionBlock] {
        [.init(kind: .paragraph, richText: [.init(content: marker(for: message.id, index: batchIndex))], markerMessageID: message.id), .paragraph(message.role == .assistant ? "Assistant" : "User"), .paragraph(ISO8601DateFormatter().string(from: message.createdAt))] + contentBlocks(message.content)
    }

    func batches(for message: Message) -> [NotionBlockBatch] {
        let content = contentBlocks(message.content)
        var batches: [NotionBlockBatch] = []
        var offset = 0
        var index = 0
        while offset < content.count || batches.isEmpty {
            let metadata: [NotionBlock] = index == 0 ? [.paragraph("\(message.role == .assistant ? "Assistant" : "User") · \(ISO8601DateFormatter().string(from: message.createdAt))")] : []
            let capacity = max(0, maxBlocksPerBatch - 1 - metadata.count)
            let group = capacity > 0 ? Array(content[offset..<min(offset + capacity, content.count)]) : []
            let marker = marker(for: message.id, index: index)
            batches.append(NotionBlockBatch(index: index, marker: marker, blocks: [.init(kind: .paragraph, richText: [.init(content: marker)], markerMessageID: message.id)] + metadata + group))
            if capacity == 0 { index += 1; continue }
            offset += group.count; index += 1
        }
        return batches
    }

    private func marker(for id: UUID, index: Int) -> String { "happaecho-message:\(id.uuidString.lowercased()):batch:\(index)" }

    private func contentBlocks(_ content: String) -> [NotionBlock] {
        let lines = content.components(separatedBy: "\n")
        var result: [NotionBlock] = []; var paragraph: [String] = []; var i = 0
        func flushParagraph() { if !paragraph.isEmpty { result.append(contentsOf: splitParagraph(paragraph)); paragraph.removeAll() } }
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                flushParagraph(); let language = String(line.dropFirst(3)); var code: [String] = []; i += 1
                while i < lines.count, !lines[i].hasPrefix("```") { code.append(lines[i]); i += 1 }
                if i < lines.count { result.append(block(.code(language: language), text: code.joined(separator: "\n"))); i += 1; continue }
                result.append(contentsOf: splitParagraph([line] + code)); continue
            }
            if line.hasPrefix("# ") { flushParagraph(); result.append(block(.heading(level: 1), text: String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") { flushParagraph(); result.append(block(.bulletedListItem, text: String(line.dropFirst(2)))) }
            else if line.hasPrefix("> ") { flushParagraph(); result.append(block(.quote, text: String(line.dropFirst(2)))) }
            else if line.isEmpty { flushParagraph() }
            else { paragraph.append(line) }
            i += 1
        }
        flushParagraph()
        return result
    }

    private func splitParagraph(_ lines: [String]) -> [NotionBlock] { [block(.paragraph, text: lines.joined(separator: "\n"))] }
    private func block(_ kind: NotionBlockKind, text: String) -> NotionBlock { .init(kind: kind, richText: stride(from: 0, to: text.count, by: maxRichTextCharacters).map { start in let a = text.index(text.startIndex, offsetBy: start); let b = text.index(a, offsetBy: min(maxRichTextCharacters, text.distance(from: a, to: text.endIndex))); return .init(content: String(text[a..<b])) }, markerMessageID: nil) }
}
