// TranscriptionStore.swift
// Ai4Poors - SQLite + FTS5 store for voice transcriptions
//
// Follows the same pattern as CaptureStore.swift: raw SQLite3 C API,
// WAL mode, FTS5 full-text search, App Group container.

import Foundation
import SQLite3

final class TranscriptionStore {

    static let shared = TranscriptionStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.ai4poors.transcriptionstore", qos: .utility)

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
            debugLog("[TranscriptionStore] No shared container URL")
            return
        }

        let dbPath = containerURL.appendingPathComponent("voice_transcriptions.sqlite").path

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(dbPath, &db, flags, nil)
        guard status == SQLITE_OK else {
            debugLog("[TranscriptionStore] Failed to open database: \(status)")
            return
        }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_busy_timeout(db, 5000)

        debugLog("[TranscriptionStore] Database opened at \(dbPath)")
    }

    private func createTables() {
        let transcriptionsSQL = """
        CREATE TABLE IF NOT EXISTS transcriptions (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            text TEXT NOT NULL,
            mode TEXT NOT NULL,
            cleaned_text TEXT,
            duration REAL NOT NULL,
            audio_file_path TEXT,
            foreground_app TEXT,
            language TEXT DEFAULT 'en',
            word_count INTEGER NOT NULL
        );
        """
        exec(transcriptionsSQL)

        let ftsSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS transcriptions_fts USING fts5(
            text,
            cleaned_text,
            content='transcriptions',
            content_rowid='rowid'
        );
        """
        exec(ftsSQL)

        exec("""
        CREATE TRIGGER IF NOT EXISTS transcriptions_ai AFTER INSERT ON transcriptions BEGIN
            INSERT INTO transcriptions_fts(rowid, text, cleaned_text)
            VALUES (new.rowid, new.text, new.cleaned_text);
        END;
        """)

        exec("""
        CREATE TRIGGER IF NOT EXISTS transcriptions_ad AFTER DELETE ON transcriptions BEGIN
            INSERT INTO transcriptions_fts(transcriptions_fts, rowid, text, cleaned_text)
            VALUES ('delete', old.rowid, old.text, old.cleaned_text);
        END;
        """)

        exec("""
        CREATE TRIGGER IF NOT EXISTS transcriptions_au AFTER UPDATE ON transcriptions BEGIN
            INSERT INTO transcriptions_fts(transcriptions_fts, rowid, text, cleaned_text)
            VALUES ('delete', old.rowid, old.text, old.cleaned_text);
            INSERT INTO transcriptions_fts(rowid, text, cleaned_text)
            VALUES (new.rowid, new.text, new.cleaned_text);
        END;
        """)

        exec("CREATE INDEX IF NOT EXISTS idx_transcriptions_timestamp ON transcriptions(timestamp DESC);")
        exec("CREATE INDEX IF NOT EXISTS idx_transcriptions_mode ON transcriptions(mode);")
    }

    // MARK: - Insert

    func insert(_ record: TranscriptionRecord) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO transcriptions
                (id, timestamp, text, mode, cleaned_text, duration, audio_file_path,
                 foreground_app, language, word_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                debugLog("[TranscriptionStore] Insert prepare failed: \(errorMessage)")
                return
            }
            defer { sqlite3_finalize(stmt) }

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

            sqlite3_bind_text(stmt, 1, record.id, -1, transient)
            sqlite3_bind_double(stmt, 2, record.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, record.text, -1, transient)
            sqlite3_bind_text(stmt, 4, record.mode.rawValue, -1, transient)
            bindText(stmt, 5, record.cleanedText, transient)
            sqlite3_bind_double(stmt, 6, record.duration)
            bindText(stmt, 7, record.audioFilePath, transient)
            bindText(stmt, 8, record.foregroundApp, transient)
            sqlite3_bind_text(stmt, 9, record.languageDetected, -1, transient)
            sqlite3_bind_int(stmt, 10, Int32(record.wordCount))

            if sqlite3_step(stmt) != SQLITE_DONE {
                debugLog("[TranscriptionStore] Insert failed: \(errorMessage)")
            }
        }
    }

    // MARK: - Full-Text Search

    func search(query: String, limit: Int = 50) -> [TranscriptionRecord] {
        queue.sync {
            let sql = """
            SELECT t.id, t.timestamp, t.text, t.mode, t.cleaned_text, t.duration,
                   t.audio_file_path, t.foreground_app, t.language, t.word_count
            FROM transcriptions t
            JOIN transcriptions_fts f ON t.rowid = f.rowid
            WHERE transcriptions_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                debugLog("[TranscriptionStore] Search prepare failed: \(errorMessage)")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            let ftsQuery = sanitizeFTSQuery(query)
            sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            return readRecords(from: stmt)
        }
    }

    // MARK: - Recent Transcriptions

    func recentTranscriptions(limit: Int = 50, mode: TranscriptionMode? = nil) -> [TranscriptionRecord] {
        queue.sync {
            let sql: String
            if mode != nil {
                sql = """
                SELECT id, timestamp, text, mode, cleaned_text, duration,
                       audio_file_path, foreground_app, language, word_count
                FROM transcriptions
                WHERE mode = ?
                ORDER BY timestamp DESC
                LIMIT ?;
                """
            } else {
                sql = """
                SELECT id, timestamp, text, mode, cleaned_text, duration,
                       audio_file_path, foreground_app, language, word_count
                FROM transcriptions
                ORDER BY timestamp DESC
                LIMIT ?;
                """
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                debugLog("[TranscriptionStore] Recent query failed: \(errorMessage)")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            if let mode = mode {
                sqlite3_bind_text(stmt, 1, (mode.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }

            return readRecords(from: stmt)
        }
    }

    // MARK: - Stats

    func transcriptionCount() -> Int {
        queue.sync {
            let sql = "SELECT COUNT(*) FROM transcriptions;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    func totalDuration() -> TimeInterval {
        queue.sync {
            let sql = "SELECT COALESCE(SUM(duration), 0) FROM transcriptions;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return sqlite3_column_double(stmt, 0)
        }
    }

    // MARK: - Delete

    func delete(id: String) {
        queue.sync {
            let sql = "DELETE FROM transcriptions WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, id, -1, transient)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Audio File Pruning

    func pruneAudioFiles(maxCount: Int = 500) {
        guard let containerURL = AppGroupConstants.sharedContainerURL else { return }
        let audioDir = containerURL.appendingPathComponent("VoiceTranscriptions/audio")

        guard let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: [.creationDateKey]) else { return }

        if files.count <= maxCount { return }

        let sorted = files.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return d1 < d2
        }

        let toDelete = sorted.prefix(files.count - maxCount)
        for file in toDelete {
            try? FileManager.default.removeItem(at: file)
        }

        debugLog("[TranscriptionStore] Pruned \(toDelete.count) audio files")
    }

    // MARK: - Helpers

    private func readRecords(from stmt: OpaquePointer?) -> [TranscriptionRecord] {
        var records: [TranscriptionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            records.append(readRecord(from: stmt))
        }
        return records
    }

    private func readRecord(from stmt: OpaquePointer?) -> TranscriptionRecord {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let text = String(cString: sqlite3_column_text(stmt, 2))
        let modeStr = String(cString: sqlite3_column_text(stmt, 3))
        let mode = TranscriptionMode(rawValue: modeStr) ?? .plain
        let cleanedText: String? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 4)) : nil
        let duration = sqlite3_column_double(stmt, 5)
        let audioFilePath: String? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 6)) : nil
        let foregroundApp: String? = sqlite3_column_type(stmt, 7) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 7)) : nil
        let language = String(cString: sqlite3_column_text(stmt, 8))
        let wordCount = Int(sqlite3_column_int(stmt, 9))

        return TranscriptionRecord(
            id: id,
            timestamp: timestamp,
            text: text,
            mode: mode,
            cleanedText: cleanedText,
            duration: duration,
            audioFilePath: audioFilePath,
            foregroundApp: foregroundApp,
            languageDetected: language,
            wordCount: wordCount
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
        let terms = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { term -> String in
                let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
        return terms.joined(separator: " ")
    }

    private func exec(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                debugLog("[TranscriptionStore] SQL error: \(String(cString: errMsg))")
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
