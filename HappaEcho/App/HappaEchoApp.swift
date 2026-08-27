import SwiftUI
import SwiftData

enum AppIdentity { static let name = "HappaEcho" }

@main
struct HappaEchoApp: App {
    private let uiTesting = CommandLine.arguments.contains("--ui-testing")
    @State private var environment: AppEnvironment?
    @State private var launchError: String?
    @Environment(\.scenePhase) private var phase

    init() {
        do {
            _environment = State(initialValue: try AppEnvironment())
            _launchError = State(initialValue: nil)
        } catch {
            _environment = State(initialValue: nil)
            _launchError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                ContentView(environment: environment)
                    .modelContainer(environment.container)
                    .environment(\.isUITesting, uiTesting)
                    .onChange(of: phase) { _, value in
                        if value == .active {
                            environment.resumePending()
                        }
                    }
            } else {
                ContentUnavailableView(
                    "本地数据未能打开",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(launchError ?? "请重新启动应用。")
                )
                .padding()
            }
        }
    }
}
