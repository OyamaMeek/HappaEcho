import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct ChatView: View {
    @Bindable var conversation: Conversation
    private let environment: AppEnvironment
    @State private var session: ChatSessionController
    @State private var draft = ""
    @State private var draftAttachments: [MessageAttachment] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachmentError: String?
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var userIsAtBottom = true

    init(conversation: Conversation, environment: AppEnvironment, settings: AppSettings, context: ModelContext) {
        self.conversation = conversation
        self.environment = environment
        _session = State(initialValue: environment.makeChatSession(context: context, settings: settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                GeometryReader { viewport in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(conversation.sortedMessages) {
                                MessageRow(message: $0, attachmentStore: environment.attachmentStore)
                            }
                            generatingRow
                            Color.clear
                                .frame(height: 1)
                                .id(ChatScrollAnchor.bottom)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ChatScrollBottomOffsetKey.self,
                                            value: geometry.frame(in: .named("chat-scroll")).maxY
                                        )
                                    }
                                )
                        }
                        .padding()
                    }
                    .coordinateSpace(name: "chat-scroll")
                    .onPreferenceChange(ChatScrollBottomOffsetKey.self) { bottom in
                        userIsAtBottom = bottom <= viewport.size.height + 32
                    }
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToBottom(proxy, after: .newMessage)
                }
                .onChange(of: session.state(for: conversation.id)) { _, _ in
                    scrollToBottom(proxy, after: .streamingUpdate)
                }
            }
            Divider()
            draftAttachmentStrip
            ComposerView(
                text: $draft,
                selectedPhotos: $selectedPhotos,
                hasAttachments: !draftAttachments.isEmpty,
                isGenerating: conversation.isGenerating,
                send: send,
                stop: { session.stop(conversationID: conversation.id) }
            )
        }
        .navigationTitle(conversation.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    titleDraft = conversation.title
                    editingTitle = true
                } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("编辑标题")
            }
        }
        .alert("编辑标题", isPresented: $editingTitle) {
            TextField("标题", text: $titleDraft)
            Button("保存") {
                Task { await session.setManualTitle(titleDraft, in: conversation) }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("图片上传失败", isPresented: Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })) {
            Button("知道了", role: .cancel) { attachmentError = nil }
        } message: { Text(attachmentError ?? "") }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var draftAttachmentStrip: some View {
        if !draftAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draftAttachments) { attachment in
                        HStack(spacing: 6) {
                            AttachmentThumbnailView(attachment: attachment, attachmentStore: environment.attachmentStore)
                                .frame(width: 34, height: 34)
                            Text(attachment.originalFileName)
                                .lineLimit(1)
                        }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.happaSurface.opacity(0.75), in: Capsule())
                            .overlay(alignment: .topTrailing) {
                                Button { removeDraftAttachment(attachment) } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical)
                                }
                                .accessibilityLabel("移除图片 \(attachment.originalFileName)")
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var generatingRow: some View {
        if case let .generating(text) = session.state(for: conversation.id) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HappaEcho").font(.caption).foregroundStyle(.secondary)
                    if text.isEmpty { ProgressView().controlSize(.small) }
                    else { MessageContentView(content: text) }
                }
                .padding(12)
                .background(Color.happaSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
            }
        } else if case let .failed(message) = session.state(for: conversation.id) {
            ContentUnavailableView("回复失败", systemImage: "exclamationmark.triangle", description: Text(message))
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    Button("重试") { Task { await session.retryRestoredDraft(in: conversation) } }
                }
        } else if case .blocked(.unsupportedVision) = session.state(for: conversation.id) {
            Text("当前模型未启用图片输入，请在设置中开启后重试。")
                .font(.footnote).foregroundStyle(.orange).padding(.horizontal)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, after event: ChatScrollEvent) {
        guard ChatScrollPolicy.shouldScrollToBottom(after: event, userIsAtBottom: userIsAtBottom) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(ChatScrollAnchor.bottom, anchor: .bottom)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftAttachments.isEmpty else { return }
        let attachments = draftAttachments
        Task {
            if await session.send(text: text, attachments: attachments, conversation: conversation) {
                draft = ""
                draftAttachments = []
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        selectedPhotos = []
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .image
                let imported = try await environment.attachmentStore.importTransferredData(
                    data,
                    suggestedName: "photo-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")",
                    contentType: type,
                    conversationID: conversation.id
                )
                draftAttachments.append(imported.makeMessageAttachment(userOrder: draftAttachments.count))
            } catch {
                attachmentError = error.localizedDescription
            }
        }
    }

    private func removeDraftAttachment(_ attachment: MessageAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        for (index, item) in draftAttachments.enumerated() { item.userOrder = index }
        Task { try? await environment.attachmentStore.deleteDraft(attachment) }
    }
}

enum ChatScrollEvent {
    case newMessage
    case streamingUpdate
}

enum ChatScrollPolicy {
    static func shouldScrollToBottom(after event: ChatScrollEvent, userIsAtBottom: Bool) -> Bool {
        switch event {
        case .newMessage:
            true
        case .streamingUpdate:
            userIsAtBottom
        }
    }
}

private enum ChatScrollAnchor {
    static let bottom = "chat-scroll-bottom"
}

private struct ChatScrollBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
