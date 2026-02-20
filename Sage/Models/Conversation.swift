import Foundation

/// A chat session between the user and the AI coach, stored in the `conversations` table.
struct Conversation: Identifiable, Equatable {
    var id: Int64?
    var skillGoalId: Int64?
    var title: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        skillGoalId: Int64? = nil,
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.skillGoalId = skillGoalId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Display-friendly title — falls back to a formatted creation date.
    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
