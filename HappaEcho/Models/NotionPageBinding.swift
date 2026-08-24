import Foundation
import SwiftData

/// A page binding for one conversation. At most one binding may be `isCurrent`;
/// retired bindings remain as history for diagnostics when the database
/// changes.
@Model
final class NotionPageBinding {
    @Attribute(.unique) var id: UUID

    var databaseID: String
    var pageID: String
    var createdAt: Date
    var isCurrent: Bool

    var conversation: Conversation?

    init(
        id: UUID = UUID(),
        databaseID: String,
        pageID: String,
        createdAt: Date = .now,
        isCurrent: Bool = false
    ) {
        self.id = id
        self.databaseID = databaseID
        self.pageID = pageID
        self.createdAt = createdAt
        self.isCurrent = isCurrent
    }
}
