// CloudKitReceiver.swift
// Ai4Poors - Subscribe to and fetch CloudKit changes from Ai4PoorsMac
//
// Creates a CKDatabaseSubscription for the Ai4PoorsZone,
// fetches changes on silent push, and inserts into SwiftData.

import CloudKit
import Foundation
import SwiftData
import UserNotifications

@MainActor
final class CloudKitReceiver: ObservableObject {

    static let shared = CloudKitReceiver()

    private let container = CKContainer(identifier: "iCloud.com.example.ai4poors")
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitRecord.zoneName, ownerName: CKCurrentUserDefaultName)

    /// Tracks CloudKit record names we've already processed to prevent duplicates.
    private var processedRecordIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "cloudkit_processed_ids") ?? []) }
        set {
            // Keep bounded — only retain the most recent 500 IDs
            let bounded = Array(newValue.suffix(500))
            UserDefaults.standard.set(bounded, forKey: "cloudkit_processed_ids")
        }
    }

    private var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "cloudkit_change_token") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "cloudkit_change_token")
            } else {
                UserDefaults.standard.removeObject(forKey: "cloudkit_change_token")
            }
        }
    }

    private var subscriptionCreated: Bool {
        get { UserDefaults.standard.bool(forKey: "cloudkit_subscription_created") }
        set { UserDefaults.standard.set(newValue, forKey: "cloudkit_subscription_created") }
    }

    private init() {}

    // MARK: - Setup

    func setup() {
        Task {
            await createSubscriptionIfNeeded()
            await fetchChanges()
        }
    }

    // MARK: - Subscription

    private func createSubscriptionIfNeeded() async {
        guard !subscriptionCreated else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: "ai4poors-zone-changes")
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            try await container.privateCloudDatabase.save(subscription)
            subscriptionCreated = true
            print("[Ai4Poors] CloudKit subscription created")
        } catch {
            print("[Ai4Poors] Failed to create CloudKit subscription: \(error)")
        }
    }

    // MARK: - Fetch Changes

    func fetchChanges() async {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = serverChangeToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )

        var newRecords: [CKRecord] = []

        operation.recordWasChangedBlock = { _, result in
            switch result {
            case .success(let record):
                newRecords.append(record)
            case .failure(let error):
                print("[Ai4Poors] CloudKit record change error: \(error)")
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operation.recordZoneFetchResultBlock = { [weak self] _, result in
                switch result {
                case .success(let (token, _, _)):
                    Task { @MainActor in
                        self?.serverChangeToken = token
                    }
                case .failure(let error):
                    print("[Ai4Poors] CloudKit zone fetch error: \(error)")
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { _ in
                continuation.resume()
            }

            container.privateCloudDatabase.add(operation)
        }

        // Process fetched records, skipping any we've already seen
        guard !newRecords.isEmpty else { return }

        var known = processedRecordIDs
        var insertedCount = 0

        for record in newRecords {
            let recordName = record.recordID.recordName
            guard !known.contains(recordName) else { continue }
            guard let analysis = CloudKitRecord.fromCKRecord(record) else { continue }

            HistoryService.save(
                channel: .message,
                action: .custom,
                inputPreview: "[\(analysis.sender)] \(analysis.messagePreview)",
                result: analysis.result,
                model: analysis.model,
                customInstruction: "Message analysis from Mac",
                isViewed: false
            )

            await postLocalNotification(analysis: analysis)
            known.insert(recordName)
            insertedCount += 1
        }

        processedRecordIDs = known
        if insertedCount > 0 {
            print("[Ai4Poors] Processed \(insertedCount) new CloudKit records")
        }
    }

    // MARK: - Local Notification

    private func postLocalNotification(analysis: CloudKitRecord.MessageAnalysis) async {
        let content = UNMutableNotificationContent()
        content.title = "Message from \(analysis.sender)"
        content.body = analysis.result
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: analysis.id.uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
