import Foundation

/// A single chat turn stored in the `messages` table.
struct Message: Identifiable, Equatable {
    var id: Int64?
    var conversationId: Int64
    /// Either `"user"` or `"assistant"`.
    var role: Role
    var content: String
    var createdAt: Date

    enum Role: String, CaseIterable {
        case user
        case assistant

        var isUser: Bool { self == .user }
    }

    init(
        id: Int64? = nil,
        conversationId: Int64,
        role: Role,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
