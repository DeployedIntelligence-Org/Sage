import Foundation
import SQLite3

/// Schema v4 — adds the `scheduled_sessions` table.
struct Migration_v4 {
    static let version = 4

    static func run(db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS \(DatabaseSchema.ScheduledSessions.tableName) (
            \(DatabaseSchema.ScheduledSessions.id)              INTEGER PRIMARY KEY AUTOINCREMENT,
            \(DatabaseSchema.ScheduledSessions.skillGoalId)     INTEGER REFERENCES skill_goals(id) ON DELETE CASCADE,
            \(DatabaseSchema.ScheduledSessions.scheduledStart)  TEXT NOT NULL,
            \(DatabaseSchema.ScheduledSessions.scheduledEnd)    TEXT NOT NULL,
            \(DatabaseSchema.ScheduledSessions.calendarEventId) TEXT,
            \(DatabaseSchema.ScheduledSessions.completed)       INTEGER NOT NULL DEFAULT 0,
            \(DatabaseSchema.ScheduledSessions.completedAt)     TEXT,
            \(DatabaseSchema.ScheduledSessions.createdAt)       TEXT NOT NULL
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.migrationFailed(4, msg)
        }
    }
}
