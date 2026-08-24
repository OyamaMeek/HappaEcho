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
        [.init(kind: .paragraph, richText: [.init(content: marker(for: message.id, index: batchIndex))], markerMessageID: message.id)] + contentBlocks(message.content)
    }

    func batches(for message: Message) -> [NotionBlockBatch] {
        let content = contentBlocks(message.content)
        let capacity = max(1, maxBlocksPerBatch - 1)
        let groups = stride(from: 0, to: content.count, by: capacity).map { Array(content[$0..<min($0 + capacity, content.count)]) }
        let nonempty = groups.isEmpty ? [[]] : groups
        return nonempty.enumerated().map { index, group in
            NotionBlockBatch(index: index, marker: marker(for: message.id, index: index), blocks: [.init(kind: .paragraph, richText: [.init(content: marker(for: message.id, index: index))], markerMessageID: message.id)] + group)
        }
    }

    private func marker(for id: UUID, index: Int) -> String { "happaecho-message:\(id.uuidString.lowercased()):batch:\(index)" }

    private func contentBlocks(_ content: String) -> [NotionBlock] {
        let lines = content.components(separatedBy: "\n")
        var result: [NotionBlock] = []; var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)); var code: [String] = []; i += 1
                while i < lines.count, !lines[i].hasPrefix("```") { code.append(lines[i]); i += 1 }
                if i < lines.count { result.append(block(.code(language: language), text: code.joined(separator: "\n"))); i += 1; continue }
                result.append(contentsOf: splitParagraph([line] + code)); continue
            }
            if line.hasPrefix("# ") { result.append(block(.heading(level: 1), text: String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") { result.append(block(.bulletedListItem, text: String(line.dropFirst(2)))) }
            else if line.hasPrefix("> ") { result.append(block(.quote, text: String(line.dropFirst(2)))) }
            else if !line.isEmpty { result.append(contentsOf: splitParagraph([line])) }
            i += 1
        }
        return result
    }

    private func splitParagraph(_ lines: [String]) -> [NotionBlock] { [block(.paragraph, text: lines.joined(separator: "\n"))] }
    private func block(_ kind: NotionBlockKind, text: String) -> NotionBlock { .init(kind: kind, richText: stride(from: 0, to: text.count, by: maxRichTextCharacters).map { start in let a = text.index(text.startIndex, offsetBy: start); let b = text.index(a, offsetBy: min(maxRichTextCharacters, text.distance(from: a, to: text.endIndex))); return .init(content: String(text[a..<b])) }, markerMessageID: nil) }
}
