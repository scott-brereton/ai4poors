// ArticleReaderView.swift
// Ai4Poors - Distraction-free article reader powered by Crawl4AI
//
// Fetches and renders clean article text from any URL.
// Used from Safari extension results, History, clipboard detection, or direct URL input.

import SwiftUI

struct ArticleReaderView: View {
    let url: String
    /// If provided, skip the fetch and render this content directly (e.g. from history)
    var prefetchedMarkdown: String?
    var prefetchedTitle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var response: CrawlResponse?
    @State private var isLoading = false
    @State private var error: String?
    @State private var copied = false

    private var articleTitle: String {
        prefetchedTitle ?? response?.articleTitle ?? domainFromURL ?? "Article"
    }

    private var articleBody: String? {
        prefetchedMarkdown ?? response?.articleBody
    }

    private var domainFromURL: String? {
        URL(string: url)?.host
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error {
                    errorView(error)
                } else if let body = articleBody {
                    articleContent(body)
                } else {
                    loadingView
                }
            }
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = articleBody ?? ""
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(copied ? .green : .blue)
                        }
                        .disabled(articleBody == nil)

                        if let articleBody {
                            ShareLink(item: articleBody)
                        }
                    }
                }
            }
            .task {
                if prefetchedMarkdown == nil {
                    await fetchArticle()
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Extracting article...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let domain = domainFromURL {
                Text(domain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task { await fetchArticle() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                if let url = URL(string: url) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open in Safari", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Article Content

    private func articleContent(_ body: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(articleTitle)
                        .font(.title2.weight(.bold))

                    HStack(spacing: 8) {
                        if let author = response?.articleAuthor, !author.isEmpty {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let date = response?.articleDate, !date.isEmpty {
                            if response?.articleAuthor != nil {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let domain = domainFromURL {
                        Button {
                            if let url = URL(string: url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.caption2)
                                Text(domain)
                                    .font(.caption)
                            }
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Summary callout (if available from metadata)
                if let summary = response?.articleSummary, !summary.isEmpty {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 3)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.leading, 10)
                    }
                    .padding(.vertical, 4)
                }

                // Article body
                ArticleMarkdownText(content: body)
                    .textSelection(.enabled)

                // Bottom actions
                Divider()

                HStack(spacing: 12) {
                    Button {
                        if let url = URL(string: url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)

                    Spacer()
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
    }

    // MARK: - Fetch

    private func fetchArticle() async {
        isLoading = true
        error = nil

        do {
            let result = try await Crawl4AIClient.scrapeAndClean(url: url)
            response = result

            // Record domain as approved for clipboard detection
            Crawl4AIClient.recordApprovedDomain(from: url)

            // Save to history
            let title = result.articleTitle ?? domainFromURL ?? url
            HistoryService.save(
                channel: .reader,
                action: .read,
                inputPreview: title,
                result: result.articleBody ?? result.markdown ?? "",
                model: "crawl4ai",
                customInstruction: url
            )

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}
