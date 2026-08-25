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

    init(conversation: Conversation, environment: AppEnvironment, settings: AppSettings, context: ModelContext) {
        self.conversation = conversation
        self.environment = environment
        _session = State(initialValue: environment.makeChatSession(context: context, settings: settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(conversation.sortedMessages) { MessageRow(message: $0) }
                        generatingRow
                    }
                    .padding()
                }
                .onChange(of: conversation.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: session.state(for: conversation.id)) { _, _ in scrollToBottom(proxy) }
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
                Button { editingTitle = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("编辑标题")
            }
        }
        .alert("编辑标题", isPresented: $editingTitle) {
            TextField("标题", text: $conversation.title)
            Button("保存") { conversation.isTitleManuallyEdited = true; conversation.updatedAt = .now }
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
                        Label(attachment.originalFileName, systemImage: "photo")
                            .lineLimit(1)
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let id = conversation.sortedMessages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
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
