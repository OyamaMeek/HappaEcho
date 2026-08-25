import SwiftUI
import SwiftData

private struct UITestingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isUITesting: Bool { get { self[UITestingKey.self] } set { self[UITestingKey.self] = newValue } }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query private var storedSettings: [AppSettings]
    @State private var selection: Conversation?
    @State private var search = ""
    @State private var showSettings = false
    @State private var settingsViewModel = SettingsViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, search: $search, create: createConversation)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gear") }
                            .accessibilityLabel("设置")
                    }
                }
        } detail: {
            if let selection { ChatView(conversation: selection) }
            else { ContentUnavailableView("选择或新建对话", systemImage: "bubble.left.and.bubble.right") }
        }
        .sheet(isPresented: $showSettings) {
            if let settings = storedSettings.first { SettingsView(viewModel: settingsViewModel, settings: settings) }
        }
        .task {
            ensureSettings()
            if selection == nil { selection = conversations.first }
        }
    }

    private func ensureSettings() {
        guard storedSettings.isEmpty else { return }
        context.insert(AppSettings())
        try? context.save()
    }
    private func createConversation() {
        let conversation = Conversation()
        context.insert(conversation)
        try? context.save()
        selection = conversation
    }
}
