import Foundation
import SQLite3

/// Schema v3 — adds the `practice_sessions` table.
struct Migration_v3 {
    static let version = 3

    static func run(db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS \(DatabaseSchema.PracticeSessions.tableName) (
            \(DatabaseSchema.PracticeSessions.id)              INTEGER PRIMARY KEY AUTOINCREMENT,
            \(DatabaseSchema.PracticeSessions.skillGoalId)     INTEGER REFERENCES skill_goals(id) ON DELETE CASCADE,
            \(DatabaseSchema.PracticeSessions.durationMinutes) INTEGER NOT NULL DEFAULT 0,
            \(DatabaseSchema.PracticeSessions.notes)           TEXT,
            \(DatabaseSchema.PracticeSessions.metricEntries)   TEXT NOT NULL DEFAULT '[]',
            \(DatabaseSchema.PracticeSessions.createdAt)       TEXT NOT NULL
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.migrationFailed(3, msg)
        }
    }
}
