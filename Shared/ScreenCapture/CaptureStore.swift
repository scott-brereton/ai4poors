// CaptureStore.swift
// Ai4Poors - SQLite + FTS5 store for screen captures
//
// Raw SQLite3 C API for FTS5 full-text search support.
// WAL mode for concurrent reads/writes across extension and main app.
// Database lives in the shared App Group container.

import Foundation
import SQLite3

final class CaptureStore {

    static let shared = CaptureStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.ai4poors.capturestore", qos: .utility)

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard let containerURL = AppGroupConstants.sharedContainerURL else {
            debugLog("[CaptureStore] No shared container URL")
            return
        }

        let dbPath = containerURL.appendingPathComponent("screen_captures.sqlite").path

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(dbPath, &db, flags, nil)
        guard status == SQLITE_OK else {
            debugLog("[CaptureStore] Failed to open database: \(status)")
            return
        }

        // WAL mode for concurrent access (extension writes, main app reads)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)

        // 5 second busy timeout for cross-process contention
        sqlite3_busy_timeout(db, 5000)

        debugLog("[CaptureStore] Database opened at \(dbPath)")
    }

    private func createTables() {
        // Main captures table
        let capturesSQL = """
        CREATE TABLE IF NOT EXISTS captures (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            source_app TEXT,
            source_app_name TEXT,
            raw_ocr_text TEXT NOT NULL,
            summary TEXT,
            thumbnail_path TEXT,
            perceptual_hash INTEGER NOT NULL,
            created_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
        );
        """
        exec(capturesSQL)

        // FTS5 virtual table for full-text search (content-sync with captures)
        let ftsSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS captures_fts USING fts5(
            raw_ocr_text,
            summary,
            source_app_name,
            content='captures',
            content_rowid='rowid'
        );
        """
        exec(ftsSQL)

        // Triggers to keep FTS index in sync with captures table
        exec("""
        CREATE TRIGGER IF NOT EXISTS captures_ai AFTER INSERT ON captures BEGIN
            INSERT INTO captures_fts(rowid, raw_ocr_text, summary, source_app_name)
            VALUES (new.rowid, new.raw_ocr_text, new.summary, new.source_app_name);
        END;
        """)

        exec("""
        CREATE TRIGGER IF NOT EXISTS captures_ad AFTER DELETE ON captures BEGIN
            INSERT INTO captures_fts(captures_fts, rowid, raw_ocr_text, summary, source_app_name)
            VALUES ('delete', old.rowid, old.raw_ocr_text, old.summary, old.source_app_name);
        END;
        """)

        exec("""
        CREATE TRIGGER IF NOT EXISTS captures_au AFTER UPDATE ON captures BEGIN
            INSERT INTO captures_fts(captures_fts, rowid, raw_ocr_text, summary, source_app_name)
            VALUES ('delete', old.rowid, old.raw_ocr_text, old.summary, old.source_app_name);
            INSERT INTO captures_fts(rowid, raw_ocr_text, summary, source_app_name)
            VALUES (new.rowid, new.raw_ocr_text, new.summary, new.source_app_name);
        END;
        """)

        // Indexes
        exec("CREATE INDEX IF NOT EXISTS idx_captures_timestamp ON captures(timestamp DESC);")
        exec("CREATE INDEX IF NOT EXISTS idx_captures_source_app ON captures(source_app);")
    }

    // MARK: - Insert

    func insert(_ record: CaptureRecord) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO captures
                (id, timestamp, source_app, source_app_name, raw_ocr_text, summary, thumbnail_path, perceptual_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                debugLog("[CaptureStore] Insert prepare failed: \(errorMessage)")
                return
            }
            defer { sqlite3_finalize(stmt) }

            // Use SQLITE_TRANSIENT to ensure SQLite copies the string data.
            // Passing nil (SQLITE_STATIC) with temporary NSString bridges is
            // a use-after-free: ARC can release the temporary between bind and step.
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

            sqlite3_bind_text(stmt, 1, record.id, -1, transient)
            sqlite3_bind_double(stmt, 2, record.timestamp.timeIntervalSince1970)
            bindText(stmt, 3, record.sourceApp, transient)
            bindText(stmt, 4, record.sourceAppName, transient)
            sqlite3_bind_text(stmt, 5, record.rawOCRText, -1, transient)
            bindText(stmt, 6, record.summary, transient)
            bindText(stmt, 7, record.thumbnailPath, transient)
            sqlite3_bind_int64(stmt, 8, Int64(bitPattern: record.perceptualHash))

            if sqlite3_step(stmt) != SQLITE_DONE {
                debugLog("[CaptureStore] Insert failed: \(errorMessage)")
            }
        }
    }

    // MARK: - Full-Text Search

    func search(query: String, limit: Int = 50) -> [CaptureRecord] {
        queue.sync {
            // FTS5 query with snippet highlighting
            let sql = """
            SELECT c.id, c.timestamp, c.source_app, c.source_app_name,
                   c.raw_ocr_text, c.summary, c.thumbnail_path, c.perceptual_hash
            FROM captures c
            JOIN captures_fts f ON c.rowid = f.rowid
            WHERE captures_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                debugLog("[CaptureStore] Search prepare failed: \(errorMessage)")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            // FTS5 query: wrap in quotes for phrase search, or use as-is for term search
            let ftsQuery = sanitizeFTSQuery(query)
            sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            return readRecords(from: stmt)
        }
    }

    // MARK: - Recent Captures

    func recentCaptures(limit: Int = 50, app: String? = nil) -> [CaptureRecord] {
        queue.sync {
            let sql: String
            if app != nil {
                sql = """
                SELECT id, timestamp, source_app, source_app_name,
                       raw_ocr_text, summary, thumbnail_path, perceptual_hash
                FROM captures
                WHERE source_app = ?
                ORDER BY timestamp DESC
                LIMIT ?;
                """
            } else {
                sql = """
                SELECT id, timestamp, source_app, source_app_name,
                       raw_ocr_text, summary, thumbnail_path, perceptual_hash
                FROM captures
                ORDER BY timestamp DESC
                LIMIT ?;
                """
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                debugLog("[CaptureStore] Recent query failed: \(errorMessage)")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            if let app = app {
                sqlite3_bind_text(stmt, 1, (app as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }

            return readRecords(from: stmt)
        }
    }

    // MARK: - Last Stored Hash

    func lastStoredHash() -> UInt64? {
        queue.sync {
            let sql = "SELECT perceptual_hash FROM captures ORDER BY timestamp DESC LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return UInt64(bitPattern: sqlite3_column_int64(stmt, 0))
        }
    }

    // MARK: - Stats

    func captureCount() -> Int {
        queue.sync {
            let sql = "SELECT COUNT(*) FROM captures;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    func distinctApps() -> [(bundleID: String, name: String?, count: Int)] {
        queue.sync {
            let sql = """
            SELECT source_app, source_app_name, COUNT(*) as cnt
            FROM captures
            WHERE source_app IS NOT NULL
            GROUP BY source_app
            ORDER BY cnt DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var results: [(String, String?, Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let bundleID = String(cString: sqlite3_column_text(stmt, 0))
                let name: String? = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                    ? String(cString: sqlite3_column_text(stmt, 1)) : nil
                let count = Int(sqlite3_column_int(stmt, 2))
                results.append((bundleID, name, count))
            }
            return results
        }
    }

    // MARK: - Delete

    func delete(id: String) {
        queue.sync {
            let sql = "DELETE FROM captures WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, id, -1, transient)
            sqlite3_step(stmt)
        }
    }

    func deleteOlderThan(days: Int) -> Int {
        queue.sync {
            let cutoff = Date().timeIntervalSince1970 - Double(days * 86400)
            let sql = "DELETE FROM captures WHERE timestamp < ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, cutoff)
            sqlite3_step(stmt)
            return Int(sqlite3_changes(db))
        }
    }

    // MARK: - Update Summary

    func updateSummary(id: String, summary: String) {
        queue.sync {
            let sql = "UPDATE captures SET summary = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, summary, -1, transient)
            sqlite3_bind_text(stmt, 2, id, -1, transient)
            sqlite3_step(stmt)
        }
    }

    /// Lightweight query returning only IDs (for orphan cleanup without loading OCR text).
    func allCaptureIDs() -> Set<String> {
        queue.sync {
            let sql = "SELECT id FROM captures;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var ids = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.insert(String(cString: sqlite3_column_text(stmt, 0)))
            }
            return ids
        }
    }

    // MARK: - Records Without Summaries (for batch LLM processing)

    func recordsNeedingSummary(limit: Int = 10) -> [CaptureRecord] {
        queue.sync {
            let sql = """
            SELECT id, timestamp, source_app, source_app_name,
                   raw_ocr_text, summary, thumbnail_path, perceptual_hash
            FROM captures
            WHERE summary IS NULL
            ORDER BY timestamp DESC
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))
            return readRecords(from: stmt)
        }
    }

    // MARK: - Dedup: Find Similar Pairs

    /// Find captures from the same app within a time window that have similar text.
    func findDuplicateCandidates(windowMinutes: Int = 30) -> [(CaptureRecord, CaptureRecord)] {
        queue.sync {
            let sql = """
            SELECT a.id, a.timestamp, a.source_app, a.source_app_name,
                   a.raw_ocr_text, a.summary, a.thumbnail_path, a.perceptual_hash,
                   b.id, b.timestamp, b.source_app, b.source_app_name,
                   b.raw_ocr_text, b.summary, b.thumbnail_path, b.perceptual_hash
            FROM captures a
            JOIN captures b ON a.source_app = b.source_app
                AND a.id < b.id
                AND ABS(a.timestamp - b.timestamp) < ?
            ORDER BY a.timestamp DESC
            LIMIT 100;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, Double(windowMinutes * 60))

            var pairs: [(CaptureRecord, CaptureRecord)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let a = readRecord(from: stmt, offset: 0)
                let b = readRecord(from: stmt, offset: 8)
                pairs.append((a, b))
            }
            return pairs
        }
    }

    // MARK: - Helpers

    private func readRecords(from stmt: OpaquePointer?) -> [CaptureRecord] {
        var records: [CaptureRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            records.append(readRecord(from: stmt, offset: 0))
        }
        return records
    }

    private func readRecord(from stmt: OpaquePointer?, offset: Int32) -> CaptureRecord {
        let id = String(cString: sqlite3_column_text(stmt, offset + 0))
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, offset + 1))
        let sourceApp: String? = sqlite3_column_type(stmt, offset + 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, offset + 2)) : nil
        let sourceAppName: String? = sqlite3_column_type(stmt, offset + 3) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, offset + 3)) : nil
        let rawOCR = String(cString: sqlite3_column_text(stmt, offset + 4))
        let summary: String? = sqlite3_column_type(stmt, offset + 5) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, offset + 5)) : nil
        let thumbPath: String? = sqlite3_column_type(stmt, offset + 6) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, offset + 6)) : nil
        let hash = UInt64(bitPattern: sqlite3_column_int64(stmt, offset + 7))

        return CaptureRecord(
            id: id,
            timestamp: timestamp,
            sourceApp: sourceApp,
            sourceAppName: sourceAppName,
            rawOCRText: rawOCR,
            summary: summary,
            thumbnailPath: thumbPath,
            perceptualHash: hash
        )
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?, _ destructor: sqlite3_destructor_type?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value, -1, destructor)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func sanitizeFTSQuery(_ query: String) -> String {
        // Escape FTS5 special characters and handle multi-word queries
        let terms = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { term -> String in
                // Escape double quotes
                let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
        return terms.joined(separator: " ")
    }

    private func exec(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                debugLog("[CaptureStore] SQL error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    private var errorMessage: String {
        if let msg = sqlite3_errmsg(db) {
            return String(cString: msg)
        }
        return "unknown error"
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
