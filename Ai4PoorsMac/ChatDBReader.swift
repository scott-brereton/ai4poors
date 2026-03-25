// ChatDBReader.swift
// Ai4PoorsMac - Read-only access to ~/Library/Messages/chat.db
//
// Uses the SQLite C API directly (no external dependencies).
// Requires Full Disk Access (TCC) to read the Messages database.

import Foundation
import SQLite3
import Contacts
import os.log

private let log = Logger(subsystem: "com.example.ai4poors.mac", category: "ChatDB")

struct MessageAttachment: Sendable {
    let mimeType: String  // e.g. "image/jpeg", "video/mp4", "application/pdf"
    let filename: String  // e.g. "IMG_1234.jpg"
}

struct ChatContext: Sendable {
    let chatID: Int64          // chat.ROWID
    let isGroup: Bool          // chat.style == 43
    let groupName: String?     // chat.display_name (user-set group name, may be nil)
}

struct ChatMessage: Identifiable, Sendable {
    let id: Int64          // ROWID from message table
    let text: String
    let date: Date
    let isFromMe: Bool
    let senderID: String   // handle.id (phone number or email)
    let attachments: [MessageAttachment]
    let chat: ChatContext? // nil if chat lookup fails
}

enum ChatDBReader {

    private static let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/Library/Messages/chat.db"
    }()

    // MARK: - Permission Check

    static var canAccessDatabase: Bool {
        FileManager.default.isReadableFile(atPath: dbPath)
    }

    // MARK: - Fetch New Messages

    /// Fetches messages with ROWID > afterRowID that are NOT from the user.
    /// Returns messages ordered by ROWID ascending.
    static func fetchNewMessages(after afterRowID: Int64) -> [ChatMessage] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("[Ai4PoorsMac] Cannot open chat.db: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        // Join through chat_message_join → chat for group context
        let query = """
            SELECT m.ROWID, m.text, m.date, m.is_from_me, m.attributedBody, h.id,
                   c.ROWID, c.style, c.display_name
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN chat c ON c.ROWID = cmj.chat_id
            WHERE m.ROWID > ?
              AND m.is_from_me = 0
              AND IFNULL(m.associated_message_type, 0) = 0
              AND IFNULL(m.associated_message_guid, '') = ''
            ORDER BY m.ROWID ASC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            print("[Ai4PoorsMac] SQL prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, afterRowID)

        var messages: [ChatMessage] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(stmt, 0)

            // Try text column first, fall back to attributedBody
            var messageText: String?
            if let cText = sqlite3_column_text(stmt, 1) {
                messageText = String(cString: cText)
            } else if let blobPointer = sqlite3_column_blob(stmt, 4) {
                let blobLength = Int(sqlite3_column_bytes(stmt, 4))
                let data = Data(bytes: blobPointer, count: blobLength)
                messageText = extractTextFromAttributedBody(data)
            }

            let text = messageText ?? ""

            let rawDate = sqlite3_column_int64(stmt, 2)
            let date = Date(timeIntervalSinceReferenceDate: Double(rawDate) / 1_000_000_000)

            let isFromMe = sqlite3_column_int(stmt, 3) != 0

            let senderID: String
            if let cSender = sqlite3_column_text(stmt, 5) {
                senderID = String(cString: cSender)
            } else {
                senderID = "Unknown"
            }

            // Chat context (group name, style)
            let chatContext: ChatContext?
            if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
                let chatID = sqlite3_column_int64(stmt, 6)
                let style = sqlite3_column_int(stmt, 7)  // 43 = group, 45 = 1-on-1
                let groupName: String?
                if let cName = sqlite3_column_text(stmt, 8) {
                    let name = String(cString: cName)
                    groupName = name.isEmpty ? nil : name
                } else {
                    groupName = nil
                }
                // style 43 = iMessage group, 42 = SMS group
                chatContext = ChatContext(chatID: chatID, isGroup: style == 43 || style == 42, groupName: groupName)
            } else {
                chatContext = nil
            }

            // Query attachments for this message
            let attachments = fetchAttachments(for: rowID, db: db)

            // Skip messages with no text AND no attachments
            guard !text.isEmpty || !attachments.isEmpty else { continue }

            messages.append(ChatMessage(
                id: rowID,
                text: text,
                date: date,
                isFromMe: isFromMe,
                senderID: senderID,
                attachments: attachments,
                chat: chatContext
            ))
        }

        return messages
    }

    // MARK: - Attachment Query

    /// Fetches attachments associated with a given message ROWID.
    private static func fetchAttachments(for messageID: Int64, db: OpaquePointer?) -> [MessageAttachment] {
        let query = """
            SELECT a.mime_type, a.transfer_name FROM attachment a
            JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
            WHERE maj.message_id = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, messageID)

        var attachments: [MessageAttachment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let mimeType: String
            if let cMime = sqlite3_column_text(stmt, 0) {
                mimeType = String(cString: cMime)
            } else {
                mimeType = "application/octet-stream"
            }

            let filename: String
            if let cName = sqlite3_column_text(stmt, 1) {
                filename = String(cString: cName)
            } else {
                filename = "unknown"
            }

            attachments.append(MessageAttachment(mimeType: mimeType, filename: filename))
        }

        return attachments
    }

    /// Get the current maximum ROWID in the messages table.
    static func currentMaxRowID() -> Int64 {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return 0
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT MAX(ROWID) FROM message"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return 0
    }

    // MARK: - Contact Resolution

    private static var contactCache: [String: String] = [:]
    private static var contactsAuthorized = false

    /// Request Contacts access. Call once at startup.
    static func requestContactsAccess() {
        CNContactStore().requestAccess(for: .contacts) { granted, error in
            contactsAuthorized = granted
            log.warning("Contacts access: \(granted ? "granted" : "denied", privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
        }
    }

    /// Resolves a phone number or email to a contact name. Caches results.
    static func contactName(for identifier: String) -> String? {
        if let cached = contactCache[identifier] { return cached.isEmpty ? nil : cached }

        let store = CNContactStore()

        let status = CNContactStore.authorizationStatus(for: .contacts)
        log.warning("Contact lookup for '\(identifier, privacy: .public)', auth status: \(status.rawValue)")
        // .authorized = 3 on macOS 15+, .limited = 2 — accept both
        guard status.rawValue >= 2 else {
            log.warning("Contacts not authorized")
            return nil
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        // Try direct phone number predicate
        let isPhone = identifier.contains("+") || identifier.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" || $0 == " " || $0 == "(" || $0 == ")" })
        if isPhone {
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: identifier))
            if let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
               let contact = contacts.first {
                let name = extractName(from: contact)
                if let name {
                    log.warning("Resolved '\(identifier, privacy: .public)' → '\(name, privacy: .public)' (direct match)")
                    contactCache[identifier] = name
                    return name
                }
            }

            // Fallback: strip to last 10 digits and scan all contacts
            let digits = String(identifier.filter { $0.isNumber }.suffix(10))
            if digits.count >= 7 {
                let request = CNContactFetchRequest(keysToFetch: keys)
                var match: CNContact?
                try? store.enumerateContacts(with: request) { contact, stop in
                    for phone in contact.phoneNumbers {
                        let phoneDigits = String(phone.value.stringValue.filter { $0.isNumber }.suffix(10))
                        if phoneDigits == digits {
                            match = contact
                            stop.pointee = true
                            return
                        }
                    }
                }
                if let contact = match, let name = extractName(from: contact) {
                    log.warning("Resolved '\(identifier, privacy: .public)' → '\(name, privacy: .public)' (digit match)")
                    contactCache[identifier] = name
                    return name
                }
            }

            log.warning("No contact match for phone: \(identifier, privacy: .public)")
        }

        // Try email lookup
        if identifier.contains("@") {
            let predicate = CNContact.predicateForContacts(matchingEmailAddress: identifier)
            if let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
               let contact = contacts.first, let name = extractName(from: contact) {
                log.warning("Resolved '\(identifier, privacy: .public)' → '\(name, privacy: .public)' (email)")
                contactCache[identifier] = name
                return name
            }
            log.warning("No contact match for email: \(identifier, privacy: .public)")
        }

        contactCache[identifier] = ""
        return nil
    }

    private static func extractName(from contact: CNContact) -> String? {
        let name = contact.nickname.isEmpty
            ? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            : contact.nickname
        return name.isEmpty ? nil : name
    }

    // MARK: - attributedBody Extraction

    /// Extracts plain text from the attributedBody blob.
    /// iMessage stores this as an NSKeyedArchiver archive. The text content
    /// sits after a specific byte marker in the binary plist.
    private static func extractTextFromAttributedBody(_ data: Data) -> String? {
        // Modern approach: use permissive unarchiving (allows all classes)
        if let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
            unarchiver.requiresSecureCoding = false
            if let attrString = unarchiver.decodeObject(forKey: "NSString") as? String {
                unarchiver.finishDecoding()
                return attrString.isEmpty ? nil : attrString
            }
            // Try root object
            if let attrString = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString {
                unarchiver.finishDecoding()
                let text = attrString.string
                return text.isEmpty ? nil : text
            }
            unarchiver.finishDecoding()
        }

        // Fallback: scan binary data for the text payload.
        // In iMessage's attributedBody, the plain text is stored after a
        // streamtyped marker. The pattern is: 0x01 followed by '+' (0x2B),
        // then a length byte, then the UTF-8 text.
        return extractTextByScanning(data)
    }

    /// Byte-level scan for text in the attributedBody binary blob.
    private static func extractTextByScanning(_ data: Data) -> String? {
        let bytes = Array(data)
        // Look for the pattern: 0x01, 0x2B ('+'), then text length, then text
        for i in 0..<(bytes.count - 3) {
            if bytes[i] == 0x01 && bytes[i + 1] == 0x2B {
                // Next byte(s) encode the length
                let lengthStart = i + 2
                guard lengthStart < bytes.count else { continue }

                let length = Int(bytes[lengthStart])
                let textStart = lengthStart + 1
                let textEnd = min(textStart + length, bytes.count)

                guard textStart < textEnd else { continue }

                let textData = Data(bytes[textStart..<textEnd])
                if let text = String(data: textData, encoding: .utf8), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }
}
