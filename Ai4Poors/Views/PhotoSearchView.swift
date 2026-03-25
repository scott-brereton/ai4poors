// PhotoSearchView.swift
// Ai4Poors - Natural language photo search powered by AI-indexed descriptions

import SwiftUI
import Photos

struct PhotoSearchView: View {
    @State private var searchQuery = ""
    @State private var results: [PhotoIndexEntry] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @StateObject private var photoScanner = PhotoScanner.shared

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding()

            // Inline scan progress
            if photoScanner.isScanning {
                HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Indexing \(photoScanner.scannedCount)/\(photoScanner.totalToScan)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { photoScanner.stopScan() }
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, Ai4PoorsDesign.Spacing.sm)
            }

            if isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if results.isEmpty && hasSearched {
                Spacer()
                ContentUnavailableView.search(text: searchQuery)
                Spacer()
            } else if results.isEmpty && !hasSearched {
                if PhotoIndex.shared.count == 0 {
                    Spacer()
                    emptyIndexState
                    Spacer()
                } else {
                    // Show recently indexed photos
                    recentPhotosGrid
                }
            } else {
                photoGrid
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search your photos...", text: $searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit { performSearch() }
                .onChange(of: searchQuery) { _, newValue in
                    // Debounced local search as you type
                    searchDebounceTask?.cancel()
                    if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                        hasSearched = false
                        results = []
                        return
                    }
                    searchDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        performLocalSearch()
                    }
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - States

    private var emptyIndexState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Photos Indexed")
                .font(.headline)
            Text("Scan your photo library to enable AI-powered search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task {
                    let granted = await photoScanner.requestPermission()
                    if granted { photoScanner.startScan() }
                }
            } label: {
                Label("Scan Photos", systemImage: "photo.badge.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Recent Photos Grid

    private var recentPhotosGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.sm) {
                HStack {
                    Text("Recently Indexed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(PhotoIndex.shared.count) photos")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Ai4PoorsDesign.Spacing.sm)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2)
                ], spacing: 2) {
                    ForEach(Array(PhotoIndex.shared.allEntries.prefix(30))) { entry in
                        PhotoThumbnail(assetIdentifier: entry.assetLocalIdentifier, analysisText: entry.analysisText, showCaption: true)
                    }
                }
                .padding(2)
            }
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ], spacing: 2) {
                ForEach(results) { entry in
                    PhotoThumbnail(assetIdentifier: entry.assetLocalIdentifier, analysisText: entry.analysisText, showCaption: true)
                }
            }
            .padding(2)
        }
    }

    // MARK: - Search Logic

    private func performLocalSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        hasSearched = true
        let localResults = PhotoIndex.shared.search(query: query)
        results = Array(localResults.prefix(50))
    }

    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        hasSearched = true

        // Local string matching first
        let localResults = PhotoIndex.shared.search(query: searchQuery)

        if !localResults.isEmpty {
            results = Array(localResults.prefix(50))
            return
        }

        // Fall back to AI search for complex queries
        let allEntries = PhotoIndex.shared.allEntries
        guard allEntries.count > 0, allEntries.count <= 2000 else {
            results = []
            return
        }

        isSearching = true
        Task {
            defer { isSearching = false }

            let descriptions = allEntries.enumerated().map { idx, entry in
                "[\(entry.id)] \(entry.analysisText)"
            }.joined(separator: "\n")

            let instruction = """
            Here are descriptions of the user's photos (each prefixed with [assetID]):
            \(descriptions)

            The user is searching for: \(searchQuery)

            Return ONLY a JSON array of matching assetIDs (strings). Return at most 30. Example: ["id1","id2"]
            If no photos match, return: []
            """

            do {
                let response = try await OpenRouterService.shared.analyzeText(
                    text: "",
                    instruction: instruction,
                    model: "google/gemini-3-flash-preview"
                )

                // Parse JSON array from response
                if let data = response.data(using: .utf8),
                   let ids = try? JSONDecoder().decode([String].self, from: data) {
                    results = ids.compactMap { id in
                        allEntries.first { $0.id == id }
                    }
                } else {
                    // Try to extract JSON array from text response
                    let cleaned = response
                        .replacingOccurrences(of: "```json", with: "")
                        .replacingOccurrences(of: "```", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = cleaned.data(using: .utf8),
                       let ids = try? JSONDecoder().decode([String].self, from: data) {
                        results = ids.compactMap { id in
                            allEntries.first { $0.id == id }
                        }
                    } else {
                        results = []
                    }
                }
            } catch {
                print("[Ai4Poors] AI photo search failed: \(error)")
                results = []
            }
        }
    }
}

// MARK: - Photo Thumbnail

struct PhotoThumbnail: View {
    let assetIdentifier: String
    let analysisText: String
    var showCaption: Bool = false

    @State private var image: UIImage?
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            ZStack(alignment: .bottom) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Color(UIColor.tertiarySystemGroupedBackground)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            ProgressView()
                        }
                }

                if showCaption {
                    Text(String(analysisText.prefix(40)))
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.55))
                }
            }
        }
        .buttonStyle(.plain)
        .task { await loadImage() }
        .sheet(isPresented: $showDetail) {
            photoDetail
        }
    }

    private var photoDetail: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Description")
                            .font(.headline)
                        Text(analysisText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Photo Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDetail = false }
                }
            }
        }
    }

    private func loadImage() async {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        let size = CGSize(width: 300, height: 300)

        let loadedImage: UIImage? = await withCheckedContinuation { continuation in
            var hasResumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { img, info in
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                guard !isDegraded, !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: img)
            }
        }

        await MainActor.run {
            self.image = loadedImage
        }
    }
}
