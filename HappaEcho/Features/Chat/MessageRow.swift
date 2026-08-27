import SwiftUI
import UIKit

struct MessageRow: View {
    let message: Message
    let attachmentStore: AttachmentStore

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.role == .user ? "你" : "HappaEcho")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !message.attachments.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(message.attachments.sorted(by: { $0.userOrder < $1.userOrder })) {
                            AttachmentThumbnailView(attachment: $0, attachmentStore: attachmentStore)
                                .frame(width: 112, height: 112)
                        }
                    }
                }
                if !message.content.isEmpty {
                    MessageContentView(content: message.content)
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.happaIndigo.opacity(0.55) : Color.happaSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            if message.role != .user { Spacer() }
        }
        .id(message.id)
        .accessibilityElement(children: .contain)
    }
}

@MainActor
final class AttachmentThumbnailLoader {
    private let store: AttachmentStore

    init(store: AttachmentStore) {
        self.store = store
    }

    func image(for attachment: MessageAttachment) async -> UIImage? {
        guard let data = try? await store.data(for: attachment) else { return nil }
        return UIImage(data: data)
    }
}

struct AttachmentThumbnailView: View {
    let attachment: MessageAttachment
    let attachmentStore: AttachmentStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.happaSurface.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: attachment.id) {
            image = await AttachmentThumbnailLoader(store: attachmentStore).image(for: attachment)
        }
        .accessibilityLabel("图片 \(attachment.originalFileName)")
    }
}
