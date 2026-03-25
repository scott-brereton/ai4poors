// CloudKitSyncService.swift
// Ai4PoorsMac - Push message analyses to CloudKit private database
//
// Syncs analysis results to iCloud so the iOS Ai4Poors app can receive them.
// Uses CKModifyRecordsOperation for reliable delivery.

import CloudKit
import Foundation

actor CloudKitSyncService {

    static let shared = CloudKitSyncService()

    private let container = CKContainer(identifier: "iCloud.com.example.ai4poors")
    private let zoneID = CKRecordZone.ID(zoneName: "Ai4PoorsZone", ownerName: CKCurrentUserDefaultName)
    private var zoneCreated = false

    private init() {}

    // MARK: - Zone Setup

    private func ensureZoneExists() async throws {
        guard !zoneCreated else { return }

        let zone = CKRecordZone(zoneID: zoneID)
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    // Zone already exists → partialFailure wrapping per-zone errors.
                    // Any CKError here is non-fatal for zone creation; treat as success.
                    if error is CKError {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            container.privateCloudDatabase.add(operation)
        }

        zoneCreated = true
        print("[Ai4PoorsMac] CloudKit zone ready")
    }

    // MARK: - Push Analysis

    func pushAnalysis(
        id: UUID,
        messageDate: Date,
        sender: String,
        senderID: String,
        messagePreview: String,
        result: String,
        model: String
    ) async {
        do {
            try await ensureZoneExists()

            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: CloudKitRecord.recordType, recordID: recordID)

            record[CloudKitRecord.Fields.id] = id.uuidString
            record[CloudKitRecord.Fields.timestamp] = Date() as NSDate
            record[CloudKitRecord.Fields.messageDate] = messageDate as NSDate
            record[CloudKitRecord.Fields.sender] = sender
            record[CloudKitRecord.Fields.senderID] = senderID
            record[CloudKitRecord.Fields.messagePreview] = messagePreview
            record[CloudKitRecord.Fields.result] = result
            record[CloudKitRecord.Fields.model] = model

            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                self.container.privateCloudDatabase.add(operation)
            }

            print("[Ai4PoorsMac] Pushed analysis to CloudKit: \(sender)")
        } catch {
            print("[Ai4PoorsMac] CloudKit push failed: \(error)")
        }
    }
}
