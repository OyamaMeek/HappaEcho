import SwiftUI
import SwiftData
enum AppIdentity { static let name="HappaEcho" }
@main struct HappaEchoApp:App { private let uiTesting=CommandLine.arguments.contains("--ui-testing"); @State private var environment=AppEnvironment(); @Environment(\.scenePhase) private var phase; var body:some Scene { WindowGroup { ContentView().modelContainer(environment.container).environment(\.isUITesting,uiTesting).onChange(of:phase) { _,value in if value == .active { environment.resumePending() } } } } }
