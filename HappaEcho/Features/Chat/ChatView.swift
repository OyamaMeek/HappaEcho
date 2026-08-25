import SwiftUI
import SwiftData

struct ChatView: View {
    @Bindable var conversation: Conversation
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var editingTitle = false
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView { LazyVStack(alignment: .leading, spacing: 14) { ForEach(conversation.sortedMessages) { MessageRow(message: $0) } }.padding() }
                    .onChange(of: conversation.messages.count) { _, _ in if let id = conversation.sortedMessages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            Divider()
            ComposerView(text: $draft) { send() }
        }.navigationTitle(conversation.title).toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { editingTitle = true } label: { Image(systemName: "pencil") }.accessibilityLabel("编辑标题") }
        }.alert("编辑标题", isPresented: $editingTitle) {
            TextField("标题", text: $conversation.title)
            Button("保存") { conversation.isTitleManuallyEdited = true; conversation.updatedAt = .now; try? context.save() }
            Button("取消", role: .cancel) {}
        }.navigationBarTitleDisplayMode(.inline)
    }
    private func send() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let message = Message(role: .user, content: value, sequence: (conversation.messages.map(\.sequence).max() ?? -1) + 1)
        message.conversation = conversation; conversation.messages.append(message); conversation.updatedAt = .now; context.insert(message); try? context.save(); draft = ""
    }
}
