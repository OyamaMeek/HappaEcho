import SwiftUI
import SwiftData

private struct UITestingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues { var isUITesting: Bool { get { self[UITestingKey.self] } set { self[UITestingKey.self] = newValue } } }

@MainActor
struct ContentView: View {
    let environment: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query private var storedSettings: [AppSettings]
    @State private var selection: Conversation?
    @State private var search = ""
    @State private var showSettings = false
    @State private var settingsViewModel = SettingsViewModel()
    @State private var conversationPendingDeletion: Conversation?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                search: $search,
                create: createConversation,
                requestDeletion: { conversationPendingDeletion = $0 }
            )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gear") }.accessibilityLabel("设置")
                    }
                }
        } detail: {
            if let selection, let settings = storedSettings.first {
                ChatView(conversation: selection, environment: environment, settings: settings, context: context)
                    .id(sessionConfigurationKey(for: settings))
            } else {
                ContentUnavailableView("选择或新建对话", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .sheet(isPresented: $showSettings) { if let settings = storedSettings.first { SettingsView(viewModel: settingsViewModel, settings: settings) } }
        .alert("删除对话？", isPresented: deletionConfirmationPresented, presenting: conversationPendingDeletion) { conversation in
            Button("删除", role: .destructive) {
                deleteConversation(conversation)
            }
            Button("取消", role: .cancel) {}
        } message: { conversation in
            Text("“\(conversation.title)”及其消息和图片将被永久删除。")
        }
        .task { ensureSettings(); if selection == nil { selection = conversations.first } }
    }

    private func sessionConfigurationKey(for settings: AppSettings) -> String {
        "\(settings.endpoint)|\(settings.modelID)|\(settings.supportsVision)|\(settings.systemPrompt ?? "")"
    }

    private func ensureSettings() { guard storedSettings.isEmpty else { return }; context.insert(AppSettings()); try? context.save() }
    private func createConversation() { let conversation = Conversation(); context.insert(conversation); try? context.save(); selection = conversation }

    private var deletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { conversationPendingDeletion != nil },
            set: { if !$0 { conversationPendingDeletion = nil } }
        )
    }

    private func deleteConversation(_ conversation: Conversation) {
        if selection?.id == conversation.id {
            selection = nil
        }
        conversationPendingDeletion = nil
        Task {
            let coordinator = ConversationDeletionCoordinator(
                context: context,
                scheduler: environment.syncScheduler,
                attachmentStore: environment.attachmentStore
            )
            await coordinator.delete(conversation: conversation)
            if selection == nil {
                selection = conversations.first(where: { $0.id != conversation.id })
            }
        }
    }
}
