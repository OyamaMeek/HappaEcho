import SwiftUI

/// Environment key that surfaces the `--ui-testing` launch flag.
private struct UITestingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isUITesting: Bool {
        get { self[UITestingKey.self] }
        set { self[UITestingKey.self] = newValue }
    }
}

/// Root view of the HappaEcho shell.
///
/// Task 1 establishes the primary "新建对话" (new conversation) action that the
/// UI smoke test looks for. Later tasks wire real conversation behavior.
struct ContentView: View {
    @Environment(\.isUITesting) private var isUITesting

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Button {
                    // New conversation action — wired in a later task.
                } label: {
                    Label("新建对话", systemImage: "square.and.pencil")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("新建对话")
                .accessibilityIdentifier("new-conversation-button")
                .padding()
                Spacer()
                if isUITesting {
                    Text("UI 测试模式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("HappaEcho")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
