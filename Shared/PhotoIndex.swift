// PhotoIndex.swift
// Ai4Poors - Photo library AI index using JSON storage in App Group container

import Foundation

// MARK: - Photo Index Entry

struct PhotoIndexEntry: Codable, Identifiable {
    let id: String // PHAsset localIdentifier
    let analysisText: String
    let creationDate: Date?
    let indexedAt: Date

    var assetLocalIdentifier: String { id }
}

// MARK: - Photo Index Store

final class PhotoIndex {
    static let shared = PhotoIndex()

    private let fileURL: URL?
    private var entries: [String: PhotoIndexEntry] = [:] // keyed by assetLocalIdentifier

    private init() {
        fileURL = AppGroupConstants.sharedContainerURL?.appendingPathComponent("photo_index.json")
        load()
    }

    var count: Int { entries.count }

    var allEntries: [PhotoIndexEntry] {
        Array(entries.values).sorted { ($0.indexedAt) > ($1.indexedAt) }
    }

    func isIndexed(_ assetLocalIdentifier: String) -> Bool {
        entries[assetLocalIdentifier] != nil
    }

    func add(_ entry: PhotoIndexEntry) {
        entries[entry.id] = entry
    }

    func persist() {
        save()
    }

    func search(query: String) -> [PhotoIndexEntry] {
        let lowered = query.lowercased()
        let terms = lowered.split(separator: " ").map(String.init)
        return allEntries.filter { entry in
            let text = entry.analysisText.lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    func clear() {
        entries = [:]
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PhotoIndexEntry].self, from: data) else {
            return
        }
        entries = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func save() {
        guard let url = fileURL else { return }
        let array = Array(entries.values)
        guard let data = try? JSONEncoder().encode(array) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
