import Foundation

/// Central source of truth for table names, column names, and the current schema version.
enum DatabaseSchema {

    static let currentVersion = 2

    enum SkillGoals {
        static let tableName = "skill_goals"

        static let id               = "id"
        static let skillName        = "skill_name"
        static let skillDescription = "skill_description"
        static let skillCategory    = "skill_category"
        static let currentLevel     = "current_level"
        static let targetLevel      = "target_level"
        static let customMetrics    = "custom_metrics"
        static let createdAt        = "created_at"
        static let updatedAt        = "updated_at"
    }

    enum Conversations {
        static let tableName = "conversations"

        static let id          = "id"
        static let skillGoalId = "skill_goal_id"
        static let title       = "title"
        static let createdAt   = "created_at"
        static let updatedAt   = "updated_at"
    }

    enum Messages {
        static let tableName = "messages"

        static let id             = "id"
        static let conversationId = "conversation_id"
        static let role           = "role"
        static let content        = "content"
        static let createdAt      = "created_at"
    }
}
