import SwiftUI
import PhotosUI

struct ComposerView: View {
    @Binding var text: String
    @Binding var selectedPhotos: [PhotosPickerItem]
    let hasAttachments: Bool
    let isGenerating: Bool
    let send: () -> Void
    let stop: () -> Void
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
            }
            .accessibilityLabel("上传图片")
            .disabled(isGenerating)

            TextField("输入消息", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(sendMessageAndDismissKeyboard)
                .accessibilityIdentifier("composer-input")

            if isGenerating {
                Button(action: stop) {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .accessibilityLabel("停止生成")
            } else {
                Button(action: sendMessageAndDismissKeyboard) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasAttachments)
                .accessibilityLabel("发送")
            }
        }
        .padding()
        .background(.bar)
    }

    private func sendMessageAndDismissKeyboard() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments else { return }
        isInputFocused = false
        send()
    }
}
