// CloudKitRecord.swift
// Ai4Poors - CloudKit record mapping shared by macOS (push) and iOS (pull)
//
// Record type: MessageAnalysis in custom zone Ai4PoorsZone
// Private database only — scoped to the user's iCloud account.

import CloudKit
import Foundation

enum CloudKitRecord {

    static let recordType = "MessageAnalysis"
    static let zoneName = "Ai4PoorsZone"

    enum Fields {
        static let id = "analysisID"
        static let timestamp = "timestamp"
        static let messageDate = "messageDate"
        static let sender = "sender"
        static let senderID = "senderID"
        static let messagePreview = "messagePreview"
        static let result = "result"
        static let model = "model"
    }

    // MARK: - Convert CKRecord → local data

    struct MessageAnalysis: Sendable {
        let id: UUID
        let timestamp: Date
        let messageDate: Date
        let sender: String
        let senderID: String
        let messagePreview: String
        let result: String
        let model: String
    }

    static func fromCKRecord(_ record: CKRecord) -> MessageAnalysis? {
        guard let idString = record[Fields.id] as? String,
              let id = UUID(uuidString: idString),
              let timestamp = record[Fields.timestamp] as? Date,
              let messageDate = record[Fields.messageDate] as? Date,
              let sender = record[Fields.sender] as? String,
              let senderID = record[Fields.senderID] as? String,
              let messagePreview = record[Fields.messagePreview] as? String,
              let result = record[Fields.result] as? String,
              let model = record[Fields.model] as? String
        else {
            return nil
        }

        return MessageAnalysis(
            id: id,
            timestamp: timestamp,
            messageDate: messageDate,
            sender: sender,
            senderID: senderID,
            messagePreview: messagePreview,
            result: result,
            model: model
        )
    }

    // MARK: - Create CKRecord from local data

    static func toCKRecord(
        _ analysis: MessageAnalysis,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: analysis.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        record[Fields.id] = analysis.id.uuidString
        record[Fields.timestamp] = analysis.timestamp as NSDate
        record[Fields.messageDate] = analysis.messageDate as NSDate
        record[Fields.sender] = analysis.sender
        record[Fields.senderID] = analysis.senderID
        record[Fields.messagePreview] = analysis.messagePreview
        record[Fields.result] = analysis.result
        record[Fields.model] = analysis.model

        return record
    }
}
