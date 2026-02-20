import Foundation
import SQLite3

/// Thread-safe SQLite wrapper providing CRUD operations for Sage's local database.
///
/// The database file lives in the app's Documents directory so it persists across
/// launches and is excluded from iCloud backup by default.
///
/// Pass a custom `url` to the initializer to use a non-default path (e.g. in tests).
final class DatabaseService {

    // MARK: - Singleton

    static let shared = DatabaseService()

    // MARK: - Private state

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.sage.database", qos: .utility)
    private let customURL: URL?

    // MARK: - Init

    /// - Parameter url: Override the database file location. Defaults to `Documents/sage.db`.
    init(url: URL? = nil) {
        self.customURL = url
    }

    // MARK: - Lifecycle

    /// Opens (or creates) the SQLite database and runs any pending migrations.
    func open() throws {
        let url: URL
        if let custom = customURL {
            url = custom
        } else {
            url = try databaseURL()
        }
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw DatabaseError.connectionFailed("Could not open database at \(url.path)")
        }

        // Enable WAL mode for better concurrent read performance.
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)

        try runMigrations()
    }

    /// Closes the database connection. Call from app teardown if needed.
    func close() {
        queue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    // MARK: - SkillGoal CRUD

    /// Inserts a new SkillGoal and returns the saved copy with its generated `id`.
    @discardableResult
    func insert(_ goal: SkillGoal) throws -> SkillGoal {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let metricsJSON = try goal.customMetricsJSON()
            let sql = """
            INSERT INTO \(DatabaseSchema.SkillGoals.tableName)
                (\(DatabaseSchema.SkillGoals.skillName),
                 \(DatabaseSchema.SkillGoals.skillDescription),
                 \(DatabaseSchema.SkillGoals.skillCategory),
                 \(DatabaseSchema.SkillGoals.currentLevel),
                 \(DatabaseSchema.SkillGoals.targetLevel),
                 \(DatabaseSchema.SkillGoals.customMetrics),
                 \(DatabaseSchema.SkillGoals.createdAt),
                 \(DatabaseSchema.SkillGoals.updatedAt))
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            bind(stmt, 1, goal.skillName)
            bind(stmt, 2, goal.skillDescription)
            bind(stmt, 3, goal.skillCategory)
            bind(stmt, 4, goal.currentLevel)
            bind(stmt, 5, goal.targetLevel)
            bind(stmt, 6, metricsJSON)
            bind(stmt, 7, iso8601(goal.createdAt))
            bind(stmt, 8, iso8601(goal.updatedAt))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            let rowID = sqlite3_last_insert_rowid(db)
            var saved = goal
            saved.id = rowID
            return saved
        }
    }

    /// Returns all SkillGoals ordered by most recently created.
    func fetchAll() throws -> [SkillGoal] {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            SELECT \(DatabaseSchema.SkillGoals.id),
                   \(DatabaseSchema.SkillGoals.skillName),
                   \(DatabaseSchema.SkillGoals.skillDescription),
                   \(DatabaseSchema.SkillGoals.skillCategory),
                   \(DatabaseSchema.SkillGoals.currentLevel),
                   \(DatabaseSchema.SkillGoals.targetLevel),
                   \(DatabaseSchema.SkillGoals.customMetrics),
                   \(DatabaseSchema.SkillGoals.createdAt),
                   \(DatabaseSchema.SkillGoals.updatedAt)
            FROM \(DatabaseSchema.SkillGoals.tableName)
            ORDER BY \(DatabaseSchema.SkillGoals.createdAt) DESC, \(DatabaseSchema.SkillGoals.id) DESC;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(errmsg(db))
            }

            var results: [SkillGoal] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(try rowToSkillGoal(stmt))
            }
            return results
        }
    }

    /// Returns the SkillGoal with the given `id`, or throws `DatabaseError.notFound`.
    func fetch(id: Int64) throws -> SkillGoal {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            SELECT \(DatabaseSchema.SkillGoals.id),
                   \(DatabaseSchema.SkillGoals.skillName),
                   \(DatabaseSchema.SkillGoals.skillDescription),
                   \(DatabaseSchema.SkillGoals.skillCategory),
                   \(DatabaseSchema.SkillGoals.currentLevel),
                   \(DatabaseSchema.SkillGoals.targetLevel),
                   \(DatabaseSchema.SkillGoals.customMetrics),
                   \(DatabaseSchema.SkillGoals.createdAt),
                   \(DatabaseSchema.SkillGoals.updatedAt)
            FROM \(DatabaseSchema.SkillGoals.tableName)
            WHERE \(DatabaseSchema.SkillGoals.id) = ?;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, id)

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw DatabaseError.notFound
            }

            return try rowToSkillGoal(stmt)
        }
    }

    /// Updates an existing SkillGoal. The goal must have a non-nil `id`.
    func update(_ goal: SkillGoal) throws {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }
            guard let goalID = goal.id else {
                throw DatabaseError.updateFailed("SkillGoal has no id")
            }

            let metricsJSON = try goal.customMetricsJSON()
            let now = Date()
            let sql = """
            UPDATE \(DatabaseSchema.SkillGoals.tableName)
            SET \(DatabaseSchema.SkillGoals.skillName)        = ?,
                \(DatabaseSchema.SkillGoals.skillDescription) = ?,
                \(DatabaseSchema.SkillGoals.skillCategory)    = ?,
                \(DatabaseSchema.SkillGoals.currentLevel)     = ?,
                \(DatabaseSchema.SkillGoals.targetLevel)      = ?,
                \(DatabaseSchema.SkillGoals.customMetrics)    = ?,
                \(DatabaseSchema.SkillGoals.updatedAt)        = ?
            WHERE \(DatabaseSchema.SkillGoals.id) = ?;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.updateFailed(errmsg(db))
            }

            bind(stmt, 1, goal.skillName)
            bind(stmt, 2, goal.skillDescription)
            bind(stmt, 3, goal.skillCategory)
            bind(stmt, 4, goal.currentLevel)
            bind(stmt, 5, goal.targetLevel)
            bind(stmt, 6, metricsJSON)
            bind(stmt, 7, iso8601(now))
            sqlite3_bind_int64(stmt, 8, goalID)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.updateFailed(errmsg(db))
            }
        }
    }

    /// Deletes the SkillGoal with the given `id`.
    func delete(id: Int64) throws {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            DELETE FROM \(DatabaseSchema.SkillGoals.tableName)
            WHERE \(DatabaseSchema.SkillGoals.id) = ?;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.deleteFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.deleteFailed(errmsg(db))
            }
        }
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        guard let db else { return }

        // Use SQLite's built-in user_version pragma to track schema version.
        let currentVersion = userVersion()

        if currentVersion < 1 {
            try Migration_v1.apply(db: db)
            setUserVersion(1)
        }
        if currentVersion < 2 {
            try Migration_v2.apply(db: db)
            setUserVersion(2)
        }
        if currentVersion < 3 {
            try Migration_v3.run(db: db)
            setUserVersion(3)
        }
    }

    private func userVersion() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func setUserVersion(_ version: Int) {
        guard let db else { return }
        sqlite3_exec(db, "PRAGMA user_version = \(version);", nil, nil, nil)
    }

    // MARK: - Helpers

    private func databaseURL() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DatabaseError.connectionFailed("Documents directory unavailable")
        }
        return docs.appendingPathComponent("sage.db")
    }

    /// Reads a row from a prepared statement into a SkillGoal.
    private func rowToSkillGoal(_ stmt: OpaquePointer?) throws -> SkillGoal {
        let id          = sqlite3_column_int64(stmt, 0)
        let skillName   = string(stmt, 1) ?? ""
        let description = string(stmt, 2)
        let category    = string(stmt, 3)
        let currentLvl  = string(stmt, 4)
        let targetLvl   = string(stmt, 5)
        let metricsJSON = string(stmt, 6) ?? "[]"
        let createdStr  = string(stmt, 7) ?? ""
        let updatedStr  = string(stmt, 8) ?? ""

        let metrics = try SkillGoal.decodeMetrics(from: metricsJSON)
        let createdAt = parseISO8601(createdStr) ?? Date()
        let updatedAt = parseISO8601(updatedStr) ?? Date()

        return SkillGoal(
            id: id,
            skillName: skillName,
            skillDescription: description,
            skillCategory: category,
            currentLevel: currentLvl,
            targetLevel: targetLvl,
            customMetrics: metrics,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - SQLite binding helpers

    private func bind(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func string(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: cStr)
    }

    private func errmsg(_ db: OpaquePointer?) -> String {
        guard let db else { return "unknown error" }
        return String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Date helpers

    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func iso8601(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func parseISO8601(_ string: String) -> Date? {
        // Try with fractional seconds first, fall back to plain ISO 8601.
        if let d = dateFormatter.date(from: string) { return d }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: string)
    }

    // MARK: - Conversation CRUD

    /// Inserts a new Conversation and returns the saved copy with its generated `id`.
    @discardableResult
    func insert(_ conversation: Conversation) throws -> Conversation {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            INSERT INTO \(DatabaseSchema.Conversations.tableName)
                (\(DatabaseSchema.Conversations.skillGoalId),
                 \(DatabaseSchema.Conversations.title),
                 \(DatabaseSchema.Conversations.createdAt),
                 \(DatabaseSchema.Conversations.updatedAt))
            VALUES (?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            if let goalId = conversation.skillGoalId {
                sqlite3_bind_int64(stmt, 1, goalId)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            bind(stmt, 2, conversation.title)
            bind(stmt, 3, iso8601(conversation.createdAt))
            bind(stmt, 4, iso8601(conversation.updatedAt))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            var saved = conversation
            saved.id = sqlite3_last_insert_rowid(db)
            return saved
        }
    }

    /// Returns all Conversations for the given skill goal, ordered newest first.
    func fetchConversations(skillGoalId: Int64) throws -> [Conversation] {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            SELECT \(DatabaseSchema.Conversations.id),
                   \(DatabaseSchema.Conversations.skillGoalId),
                   \(DatabaseSchema.Conversations.title),
                   \(DatabaseSchema.Conversations.createdAt),
                   \(DatabaseSchema.Conversations.updatedAt)
            FROM \(DatabaseSchema.Conversations.tableName)
            WHERE \(DatabaseSchema.Conversations.skillGoalId) = ?
            ORDER BY \(DatabaseSchema.Conversations.updatedAt) DESC;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, skillGoalId)

            var results: [Conversation] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(rowToConversation(stmt))
            }
            return results
        }
    }

    /// Updates the `title` and `updated_at` of an existing Conversation.
    func updateConversationTitle(_ conversation: Conversation) throws {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }
            guard let convId = conversation.id else {
                throw DatabaseError.updateFailed("Conversation has no id")
            }

            let sql = """
            UPDATE \(DatabaseSchema.Conversations.tableName)
            SET \(DatabaseSchema.Conversations.title)     = ?,
                \(DatabaseSchema.Conversations.updatedAt) = ?
            WHERE \(DatabaseSchema.Conversations.id) = ?;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.updateFailed(errmsg(db))
            }

            bind(stmt, 1, conversation.title)
            bind(stmt, 2, iso8601(Date()))
            sqlite3_bind_int64(stmt, 3, convId)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.updateFailed(errmsg(db))
            }
        }
    }

    /// Deletes a Conversation and all its child Messages (cascade via FK).
    func deleteConversation(id: Int64) throws {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            DELETE FROM \(DatabaseSchema.Conversations.tableName)
            WHERE \(DatabaseSchema.Conversations.id) = ?;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.deleteFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.deleteFailed(errmsg(db))
            }
        }
    }

    // MARK: - Message CRUD

    /// Inserts a new Message and returns the saved copy with its generated `id`.
    @discardableResult
    func insert(_ message: Message) throws -> Message {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            INSERT INTO \(DatabaseSchema.Messages.tableName)
                (\(DatabaseSchema.Messages.conversationId),
                 \(DatabaseSchema.Messages.role),
                 \(DatabaseSchema.Messages.content),
                 \(DatabaseSchema.Messages.createdAt))
            VALUES (?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, message.conversationId)
            bind(stmt, 2, message.role.rawValue)
            bind(stmt, 3, message.content)
            bind(stmt, 4, iso8601(message.createdAt))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            // Touch parent conversation's updated_at so the list re-sorts correctly.
            sqlite3_exec(db, """
            UPDATE \(DatabaseSchema.Conversations.tableName)
            SET \(DatabaseSchema.Conversations.updatedAt) = '\(iso8601(Date()))'
            WHERE \(DatabaseSchema.Conversations.id) = \(message.conversationId);
            """, nil, nil, nil)

            var saved = message
            saved.id = sqlite3_last_insert_rowid(db)
            return saved
        }
    }

    /// Returns all Messages for a conversation ordered by creation time (oldest first).
    func fetchMessages(conversationId: Int64) throws -> [Message] {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            SELECT \(DatabaseSchema.Messages.id),
                   \(DatabaseSchema.Messages.conversationId),
                   \(DatabaseSchema.Messages.role),
                   \(DatabaseSchema.Messages.content),
                   \(DatabaseSchema.Messages.createdAt)
            FROM \(DatabaseSchema.Messages.tableName)
            WHERE \(DatabaseSchema.Messages.conversationId) = ?
            ORDER BY \(DatabaseSchema.Messages.createdAt) ASC, \(DatabaseSchema.Messages.id) ASC;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, conversationId)

            var results: [Message] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let msg = rowToMessage(stmt) { results.append(msg) }
            }
            return results
        }
    }

    /// Updates the `content` column of an existing message row.
    ///
    /// Called after SSE streaming completes to persist the fully-assembled assistant reply.
    func updateMessageContent(_ message: Message) throws {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }
            guard let id = message.id else { throw DatabaseError.queryFailed("Message has no id") }

            let sql = """
            UPDATE \(DatabaseSchema.Messages.tableName)
            SET \(DatabaseSchema.Messages.content) = ?
            WHERE \(DatabaseSchema.Messages.id) = ?;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(errmsg(db))
            }

            sqlite3_bind_text(stmt, 1, (message.content as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 2, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.queryFailed(errmsg(db))
            }
        }
    }

    /// Deletes a single message row by its primary key.
    ///
    /// Used to remove an empty/partial assistant placeholder when streaming fails.
    func deleteMessage(id: Int64) throws {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = "DELETE FROM \(DatabaseSchema.Messages.tableName) WHERE \(DatabaseSchema.Messages.id) = ?;"

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.queryFailed(errmsg(db))
            }
        }
    }

    // MARK: - PracticeSession CRUD

    /// Inserts a new PracticeSession and returns the saved copy with its generated `id`.
    @discardableResult
    func insert(_ session: PracticeSession) throws -> PracticeSession {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let entriesJSON = try session.metricEntriesJSON()
            let sql = """
            INSERT INTO \(DatabaseSchema.PracticeSessions.tableName)
                (\(DatabaseSchema.PracticeSessions.skillGoalId),
                 \(DatabaseSchema.PracticeSessions.durationMinutes),
                 \(DatabaseSchema.PracticeSessions.notes),
                 \(DatabaseSchema.PracticeSessions.metricEntries),
                 \(DatabaseSchema.PracticeSessions.createdAt))
            VALUES (?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            if let goalId = session.skillGoalId {
                sqlite3_bind_int64(stmt, 1, goalId)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_int64(stmt, 2, Int64(session.durationMinutes))
            bind(stmt, 3, session.notes)
            bind(stmt, 4, entriesJSON)
            bind(stmt, 5, iso8601(session.createdAt))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.insertFailed(errmsg(db))
            }

            var saved = session
            saved.id = sqlite3_last_insert_rowid(db)
            return saved
        }
    }

    /// Returns all PracticeSessions for the given skill goal, ordered newest first.
    func fetchPracticeSessions(skillGoalId: Int64) throws -> [PracticeSession] {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            SELECT \(DatabaseSchema.PracticeSessions.id),
                   \(DatabaseSchema.PracticeSessions.skillGoalId),
                   \(DatabaseSchema.PracticeSessions.durationMinutes),
                   \(DatabaseSchema.PracticeSessions.notes),
                   \(DatabaseSchema.PracticeSessions.metricEntries),
                   \(DatabaseSchema.PracticeSessions.createdAt)
            FROM \(DatabaseSchema.PracticeSessions.tableName)
            WHERE \(DatabaseSchema.PracticeSessions.skillGoalId) = ?
            ORDER BY \(DatabaseSchema.PracticeSessions.createdAt) DESC;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, skillGoalId)

            var results: [PracticeSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(try rowToPracticeSession(stmt))
            }
            return results
        }
    }

    /// Deletes a PracticeSession by its primary key.
    func deletePracticeSession(id: Int64) throws {
        try queue.sync {
            guard let db else { throw DatabaseError.connectionFailed("Database not open") }

            let sql = """
            DELETE FROM \(DatabaseSchema.PracticeSessions.tableName)
            WHERE \(DatabaseSchema.PracticeSessions.id) = ?;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.deleteFailed(errmsg(db))
            }

            sqlite3_bind_int64(stmt, 1, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.deleteFailed(errmsg(db))
            }
        }
    }

    // MARK: - Row mappers (Conversation / Message)

    private func rowToConversation(_ stmt: OpaquePointer?) -> Conversation {
        let id          = sqlite3_column_int64(stmt, 0)
        let goalId      = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                            ? sqlite3_column_int64(stmt, 1) as Int64?
                            : nil
        let title       = string(stmt, 2)
        let createdStr  = string(stmt, 3) ?? ""
        let updatedStr  = string(stmt, 4) ?? ""

        return Conversation(
            id: id,
            skillGoalId: goalId,
            title: title,
            createdAt: parseISO8601(createdStr) ?? Date(),
            updatedAt: parseISO8601(updatedStr) ?? Date()
        )
    }

    private func rowToMessage(_ stmt: OpaquePointer?) -> Message? {
        let id           = sqlite3_column_int64(stmt, 0)
        let convId       = sqlite3_column_int64(stmt, 1)
        let roleStr      = string(stmt, 2) ?? "user"
        let content      = string(stmt, 3) ?? ""
        let createdStr   = string(stmt, 4) ?? ""

        guard let role = Message.Role(rawValue: roleStr) else { return nil }

        return Message(
            id: id,
            conversationId: convId,
            role: role,
            content: content,
            createdAt: parseISO8601(createdStr) ?? Date()
        )
    }

    private func rowToPracticeSession(_ stmt: OpaquePointer?) throws -> PracticeSession {
        let id             = sqlite3_column_int64(stmt, 0)
        let goalId: Int64? = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                                ? sqlite3_column_int64(stmt, 1)
                                : nil
        let duration       = Int(sqlite3_column_int64(stmt, 2))
        let notes          = string(stmt, 3)
        let entriesJSON    = string(stmt, 4) ?? "[]"
        let createdStr     = string(stmt, 5) ?? ""

        let entries = try PracticeSession.decodeMetricEntries(from: entriesJSON)
        let createdAt = parseISO8601(createdStr) ?? Date()

        return PracticeSession(
            id: id,
            skillGoalId: goalId,
            durationMinutes: duration,
            notes: notes,
            metricEntries: entries,
            createdAt: createdAt
        )
    }
}
