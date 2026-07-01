import Foundation
import SQLite3

enum SQLiteError: Error { case open(String) }

/// Minimal read-only SQLite reader, for providers whose sessions live in a
/// database rather than JSONL files (opencode). Every value comes back as a
/// `String` — enough for our needs, where columns are JSON blobs or
/// epoch-millisecond integers. Read-only open still sees WAL-resident rows.
struct SQLiteDatabase {
    private let handle: OpaquePointer

    /// Open `path` read-only. Throws if the file is missing or unreadable.
    init(path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let db { sqlite3_close(db) }
            throw SQLiteError.open(message)
        }
        handle = db
    }

    func close() { sqlite3_close(handle) }

    /// Run `sql` with positional `?` text bindings; return rows keyed by column
    /// name (NULL columns are omitted).
    func rows(_ sql: String, _ bindings: [String] = []) -> [[String: String]] {
        // SQLITE_TRANSIENT: tell SQLite to copy the bound bytes.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement
        else { return [] }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        let columns = (0..<sqlite3_column_count(statement))
            .map { String(cString: sqlite3_column_name(statement, $0)) }

        var out: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<columns.count {
                if let text = sqlite3_column_text(statement, Int32(index)) {
                    row[columns[index]] = String(cString: text)
                }
            }
            out.append(row)
        }
        return out
    }
}
