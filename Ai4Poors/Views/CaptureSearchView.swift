// CaptureSearchView.swift
// Ai4Poors - Unified search: screen captures + photo search
//
// Segmented picker at top lets users switch between screen
// capture OCR search and AI-indexed photo search.

import SwiftUI
import ReplayKit

// MARK: - Unified Search View (Tab wrapper)

struct CaptureSearchView: View {
    @State private var searchMode: SearchMode = .captures

    enum SearchMode: String, CaseIterable {
        case captures = "Captures"
        case photos = "Photos"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Search Mode", selection: $searchMode) {
                    ForEach(SearchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, Ai4PoorsDesign.Spacing.sm)

                switch searchMode {
                case .captures:
                    CaptureListView()
                case .photos:
                    PhotoSearchView()
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Capture List View (extracted from old CaptureSearchView)

struct CaptureListView: View {
    @State private var searchText = ""
    @State private var results: [CaptureRecord] = []
    @State private var selectedRecord: CaptureRecord?
    @State private var isSearching = false
    @State private var filterApp: String?
    @State private var apps: [(bundleID: String, name: String?, count: Int)] = []
    @State private var totalCount = 0
    @State private var searchDebounceTask: Task<Void, Never>?

    private let store = CaptureStore.shared

    var body: some View {
        List {
            // Header pinned at top — always visible
            Section {
                captureSearchBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                broadcastHeader
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                if !apps.isEmpty {
                    appFilterBar
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            }

            // Content
            if isSearching && results.isEmpty {
                Section {
                    ForEach(0..<4, id: \.self) { index in
                        HStack(spacing: Ai4PoorsDesign.Spacing.md) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 50, height: 90)
                            VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.xs) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(height: 12)
                                    .frame(maxWidth: 120)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.10))
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.10))
                                    .frame(height: 10)
                                    .frame(maxWidth: 180)
                            }
                        }
                        .padding(.vertical, Ai4PoorsDesign.Spacing.xs)
                        .opacity(0.6 + Double(4 - index) * 0.1)
                    }
                    .listRowSeparator(.hidden)
                    .transition(.opacity)
                }
            } else if results.isEmpty && !searchText.isEmpty && !isSearching {
                Section {
                    ContentUnavailableView.search(text: searchText)
                        .listRowSeparator(.hidden)
                }
            } else if results.isEmpty && searchText.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Captures Yet", systemImage: "record.circle")
                    } description: {
                        Text("Capture and OCR everything on your screen for instant full-text search.")
                    } actions: {
                        BroadcastButton()
                    }
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(results) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            CaptureRowView(record: record)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(id: record.id)
                                if let path = record.thumbnailPath {
                                    try? FileManager.default.removeItem(atPath: path)
                                }
                                performSearch(query: searchText)
                                loadStats()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                UIPasteboard.general.string = record.summary ?? record.rawOCRText
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                performSearch(query: newValue)
            }
        }
        .onChange(of: filterApp) { _, _ in
            performSearch(query: searchText)
        }
        .onAppear {
            loadStats()
            loadRecent()
        }
        .sheet(item: $selectedRecord) { record in
            CaptureDetailView(record: record)
        }
    }

    // MARK: - Search Bar

    private var captureSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search everything you've seen", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
        .padding(.horizontal)
        .padding(.top, Ai4PoorsDesign.Spacing.sm)
    }

    // MARK: - Broadcast Control Header

    private var broadcastHeader: some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.xs) {
                    Text("\(totalCount) captures")
                        .font(.headline)
                        .contentTransition(.numericText())
                    if !apps.isEmpty {
                        Text("from \(apps.count) apps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                BroadcastButton()
            }
            .padding(.horizontal)
            .padding(.top, Ai4PoorsDesign.Spacing.sm)
        }
    }

    // MARK: - App Filter

    private var appFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    isSelected: filterApp == nil,
                    action: { filterApp = nil }
                )

                ForEach(apps.prefix(10), id: \.bundleID) { app in
                    FilterChip(
                        title: app.name ?? app.bundleID.components(separatedBy: ".").last ?? app.bundleID,
                        count: app.count,
                        isSelected: filterApp == app.bundleID,
                        action: { filterApp = app.bundleID }
                    )
                }

                if apps.count > 10 {
                    FilterChip(
                        title: "+\(apps.count - 10) more",
                        isSelected: false,
                        action: {}
                    )
                    .opacity(0.6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func performSearch(query: String) {
        if query.isEmpty {
            loadRecent()
            return
        }

        isSearching = true
        let currentFilter = filterApp
        DispatchQueue.global(qos: .userInitiated).async {
            var found = store.search(query: query, limit: 100)
            if let appFilter = currentFilter {
                found = found.filter { $0.sourceApp == appFilter }
            }
            DispatchQueue.main.async {
                results = found
                isSearching = false
            }
        }
    }

    private func loadRecent() {
        DispatchQueue.global(qos: .userInitiated).async {
            let recent = store.recentCaptures(limit: 50, app: filterApp)
            DispatchQueue.main.async {
                results = recent
            }
        }
    }

    private func loadStats() {
        DispatchQueue.global(qos: .userInitiated).async {
            let count = store.captureCount()
            let appList = store.distinctApps()
            DispatchQueue.main.async {
                totalCount = count
                apps = appList
            }
        }
    }
}

// MARK: - Capture Row

struct CaptureRowView: View {
    let record: CaptureRecord

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
                .frame(width: 50, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                // App name + timestamp
                HStack {
                    if let appName = record.sourceAppName {
                        Text(appName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Text(record.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Text preview
                Text(record.summary ?? record.textPreview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let path = record.thumbnailPath,
           let image = loadThumbnail(path: path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func loadThumbnail(path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }
}

// MARK: - Capture Detail View

struct CaptureDetailView: View {
    let record: CaptureRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Thumbnail
                    if let path = record.thumbnailPath,
                       let image = UIImage(contentsOfFile: path) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        if let appName = record.sourceAppName ?? record.sourceApp {
                            Label(appName, systemImage: "app.fill")
                                .font(.subheadline)
                        }

                        Label(record.timestamp.formatted(.dateTime.month().day().hour().minute()),
                              systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Summary
                    if let summary = record.summary {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text(summary)
                                .font(.body)
                        }

                        Divider()
                    }

                    // Raw OCR text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extracted Text")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(record.rawOCRText)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: record.rawOCRText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count = count {
                    Text("\(count)")
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
            .padding(.horizontal, Ai4PoorsDesign.Spacing.md)
            .padding(.vertical, Ai4PoorsDesign.Spacing.xs)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityValue(count.map { "\($0) captures" } ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Broadcast Button

struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let wrapper = BroadcastButtonWrapper()
        return wrapper
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private class BroadcastButtonWrapper: UIView {
    private let picker = RPSystemBroadcastPickerView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        picker.preferredExtension = "com.example.ai4poors.broadcast"
        picker.showsMicrophoneButton = false
        picker.isHidden = true
        addSubview(picker)

        let button = UIButton(type: .system)
        button.setTitle(" Record", for: .normal)
        button.setImage(UIImage(systemName: "record.circle"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = .systemRed
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @objc private func tapped() {
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                return
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 120, height: 36)
    }
}
