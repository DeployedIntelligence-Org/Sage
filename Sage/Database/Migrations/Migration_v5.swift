import Foundation
import SQLite3

/// Schema v5 — adds a `rating` column (1-5 stars) to `practice_sessions`.
///
/// Uses ALTER TABLE because SQLite doesn't support adding columns with constraints
/// after table creation. The column is nullable so existing rows are unaffected.
struct Migration_v5 {
    static let version = 5

    static func run(db: OpaquePointer) throws {
        let sql = """
        ALTER TABLE \(DatabaseSchema.PracticeSessions.tableName)
        ADD COLUMN \(DatabaseSchema.PracticeSessions.rating) INTEGER;
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.migrationFailed(version, msg)
        }
    }
}
