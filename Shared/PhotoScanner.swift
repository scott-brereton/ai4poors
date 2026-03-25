// PhotoScanner.swift
// Ai4Poors - Scans photo library and indexes photos using AI vision analysis

#if canImport(UIKit)
import Photos
import UIKit

@MainActor
final class PhotoScanner: ObservableObject {
    static let shared = PhotoScanner()

    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var totalToScan = 0
    @Published var currentError: String?

    var maxPhotos = 200
    private var scanTask: Task<Void, Never>?

    private init() {}

    var indexedCount: Int { PhotoIndex.shared.count }

    func requestPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    func startScan() {
        guard !isScanning else { return }
        guard AppGroupConstants.isAPIKeyConfigured else {
            currentError = "No API key configured"
            return
        }

        scanTask = Task {
            await performScan()
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func performScan() async {
        isScanning = true
        scannedCount = 0
        currentError = nil

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = maxPhotos

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var unindexedAssets: [PHAsset] = []

        assets.enumerateObjects { asset, _, _ in
            if !PhotoIndex.shared.isIndexed(asset.localIdentifier) {
                unindexedAssets.append(asset)
            }
        }

        totalToScan = unindexedAssets.count

        if unindexedAssets.isEmpty {
            isScanning = false
            return
        }

        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .exact
        requestOptions.isNetworkAccessAllowed = true

        for asset in unindexedAssets {
            guard !Task.isCancelled else { break }

            do {
                let image = try await requestImage(
                    manager: imageManager,
                    asset: asset,
                    targetSize: CGSize(width: 1280, height: 1280),
                    options: requestOptions
                )

                let instruction = "Describe this photo: what's in it, any visible text, people/places/objects, and context. Be specific. 2-3 sentences max."

                let analysis = try await OpenRouterService.shared.analyzeImage(
                    image: image,
                    instruction: instruction
                )

                let entry = PhotoIndexEntry(
                    id: asset.localIdentifier,
                    analysisText: analysis,
                    creationDate: asset.creationDate,
                    indexedAt: Date()
                )
                PhotoIndex.shared.add(entry)
                scannedCount += 1

                // Persist every 10 photos to avoid excessive I/O
                if scannedCount.isMultiple(of: 10) {
                    PhotoIndex.shared.persist()
                }

                // Rate limit: 2 seconds between requests
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                print("[Ai4Poors] Failed to scan photo \(asset.localIdentifier): \(error)")
                // Continue to next photo on failure
            }
        }

        PhotoIndex.shared.persist()
        isScanning = false
    }

    private func requestImage(
        manager: PHImageManager,
        asset: PHAsset,
        targetSize: CGSize,
        options: PHImageRequestOptions
    ) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                guard !isDegraded, !hasResumed else { return }
                hasResumed = true

                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: Ai4PoorsError.imageEncodingFailed)
                }
            }
        }
    }
}
#endif
