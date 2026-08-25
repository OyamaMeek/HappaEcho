import Foundation
import SwiftData
@MainActor final class AppEnvironment { let container:ModelContainer; let settingsRepository:SettingsRepository; let syncScheduler:NotionSyncScheduling
 init(container:ModelContainer = try! HappaEchoSchema.makeContainer(inMemory:false), settingsRepository:SettingsRepository = .init(), syncScheduler:NotionSyncScheduling = NoopNotionScheduler()) { self.container=container; self.settingsRepository=settingsRepository; self.syncScheduler=syncScheduler }
 func settings(context:ModelContext)->AppSettings { let descriptor=FetchDescriptor<AppSettings>(); if let settings=try? context.fetch(descriptor).first { return settings }; let settings=AppSettings(); context.insert(settings); try? context.save(); return settings }
 func resumePending(){ syncScheduler.resumePending() }
}
final class NoopNotionScheduler:NotionSyncScheduling,@unchecked Sendable { func enqueue(messageID:UUID){} }
