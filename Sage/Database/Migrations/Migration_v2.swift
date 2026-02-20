import Foundation
import SQLite3

/// Schema migration v2 — creates the `conversations` and `messages` tables.
struct Migration_v2 {

    static let version = 2

    static func apply(db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS \(DatabaseSchema.Conversations.tableName) (
            \(DatabaseSchema.Conversations.id)          INTEGER PRIMARY KEY AUTOINCREMENT,
            \(DatabaseSchema.Conversations.skillGoalId) INTEGER,
            \(DatabaseSchema.Conversations.title)       TEXT,
            \(DatabaseSchema.Conversations.createdAt)   DATETIME DEFAULT CURRENT_TIMESTAMP,
            \(DatabaseSchema.Conversations.updatedAt)   DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS \(DatabaseSchema.Messages.tableName) (
            \(DatabaseSchema.Messages.id)             INTEGER PRIMARY KEY AUTOINCREMENT,
            \(DatabaseSchema.Messages.conversationId) INTEGER NOT NULL,
            \(DatabaseSchema.Messages.role)           TEXT NOT NULL,
            \(DatabaseSchema.Messages.content)        TEXT NOT NULL,
            \(DatabaseSchema.Messages.createdAt)      DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw DatabaseError.migrationFailed(version, msg)
        }
    }
}
