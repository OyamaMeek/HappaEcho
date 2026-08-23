import SwiftUI

/// App-level identity shared by the application shell and smoke tests.
enum AppIdentity {
    /// Stable product name used by unit tests and Notion metadata.
    static let name = "HappaEcho"
}

@main
struct HappaEchoApp: App {
    /// True when the UI test runner launches the app with `--ui-testing`.
    /// Later tasks use this flag to inject deterministic fakes.
    private let isUITesting = CommandLine.arguments.contains("--ui-testing")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.isUITesting, isUITesting)
        }
    }
}
