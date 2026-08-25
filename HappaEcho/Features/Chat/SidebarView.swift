import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Binding var selection: Conversation?
    @Binding var search: String
    let create: () -> Void
    let requestDeletion: (Conversation) -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                Button(action: create) { Label("新建对话", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("new-conversation-button")
            }
            ForEach(filtered) { conversation in
                NavigationLink(value: conversation) {
                    VStack(alignment: .leading) {
                        Text(conversation.title).lineLimit(1)
                        if conversation.isGenerating { Label("正在生成", systemImage: "ellipsis").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        requestDeletion(conversation)
                    } label: {
                        Label("删除对话", systemImage: "trash")
                    }
                }
                .accessibilityHint("长按可删除此对话")
            }
        }.searchable(text: $search, prompt: "搜索对话").navigationTitle("HappaEcho")
    }
    private var filtered: [Conversation] { search.isEmpty ? conversations : conversations.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains { $0.content.localizedCaseInsensitiveContains(search) } } }
}
