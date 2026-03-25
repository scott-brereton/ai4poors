// Crawl4AIClient.swift
// Ai4Poors - Web scraping and article extraction via Crawl4AI Cloud API
//
// Extracts clean markdown content from any URL. Used by Reader mode
// in Safari extension and in-app article reading.

import Foundation
import os.log

private let log = Logger(subsystem: "com.example.ai4poors", category: "Crawl4AI")

/// Writes to both os_log and a file in the App Group container for easy retrieval.
private func crawlLog(_ message: String) {
    log.info("\(message)")
    guard let url = AppGroupConstants.sharedContainerURL?.appendingPathComponent("crawl4ai_debug.log") else { return }
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(timestamp)] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(entry.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        try? entry.data(using: .utf8)?.write(to: url)
    }
}

enum Crawl4AIClient {
    static let endpoint = URL(string: "https://api.crawl4ai.com/v1/crawl")!

    // MARK: - Basic Scrape

    /// Scrapes a URL and returns raw markdown content.
    /// Uses magic mode for anti-bot bypass and cache_mode bypass for fresh content.
    static func scrape(url: String) async throws -> CrawlResponse {
        let apiKey = AppGroupConstants.crawl4aiAPIKey
        guard !apiKey.isEmpty else { throw CrawlError.noAPIKey }

        crawlLog("scrape() called for: \(url)")
        let body: [String: Any] = [
            "url": url,
            "crawler_config": [
                "type": "CrawlerRunConfig",
                "params": [
                    "cache_mode": "bypass",
                    "magic": true,
                    "remove_overlay_elements": true,
                    "word_count_threshold": 10
                ]
            ]
        ]
        return try await post(body: body, apiKey: apiKey)
    }

    // MARK: - Scrape + Clean (1 Crawl4AI credit + Gemini Flash pass)

    /// Scrapes a URL via Crawl4AI, then cleans the raw markdown through
    /// Gemini Flash to strip navigation, ads, and web artifacts.
    /// If content is too short (paywall), tries the Wayback Machine as fallback.
    /// Returns the CrawlResponse with `markdown` replaced by cleaned text.
    static func scrapeAndClean(url: String, skipWayback: Bool = false) async throws -> CrawlResponse {
        let raw = try await scrape(url: url)

        guard let rawBody = raw.articleBody else {
            crawlLog("scrapeAndClean: no raw body to clean")
            return raw
        }

        // Skip cleaning for short content — already clean enough
        guard rawBody.count > 2000 else {
            crawlLog("scrapeAndClean: content short (\(rawBody.count) chars), skipping clean")
            return raw
        }

        crawlLog("scrapeAndClean: cleaning \(rawBody.count) chars via Gemini Flash")

        let systemPrompt = """
            You are an article cleaner. The user will give you raw markdown scraped from a web page. \
            Your job is to return ONLY the article content as clean markdown. \
            You MUST reproduce the COMPLETE article text — every single paragraph, quote, and detail. \
            Do NOT summarize. Do NOT shorten. Do NOT skip paragraphs. \
            The output should be roughly the same length as the article portion of the input.
            """

        let userPrompt = """
            Clean the following raw web page markdown. \
            KEEP: headline (# heading), author, date, all body paragraphs, blockquotes, subheadings, lists. \
            REMOVE: navigation links, menus, "Skip to content", accessibility links, \
            ads, Outbrain/Taboola widgets, "Related stories", "Recommended" sections, \
            footer, copyright, newsletter signups, social sharing, comments, \
            image markdown (![...](...)).

            RAW MARKDOWN:
            \(rawBody)
            """

        do {
            // Raw article ~28K chars ≈ 7K tokens; request enough headroom for full output
            let outputTokens = max(rawBody.count / 3, 8192)
            let cleaned = try await OpenRouterService.shared.transformText(
                text: userPrompt,
                systemPrompt: systemPrompt,
                model: "google/gemini-3-flash-preview",
                maxTokens: outputTokens
            )
            crawlLog("scrapeAndClean: cleaned to \(cleaned.count) chars (from \(rawBody.count))")
            let result = CrawlResponse(
                markdown: cleaned,
                metadata: raw.metadata,
                extractedContent: raw.extractedContent
            )
            // Try Wayback fallback if content is suspiciously short (paywall)
            if !skipWayback && !url.contains("web.archive.org") {
                return await tryWaybackFallback(url: url, directResult: result)
            }
            return result
        } catch {
            // If cleaning fails, return the raw content rather than failing entirely
            crawlLog("scrapeAndClean: Gemini cleanup failed (\(error.localizedDescription)), returning raw")
            if !skipWayback && !url.contains("web.archive.org") {
                return await tryWaybackFallback(url: url, directResult: raw)
            }
            return raw
        }
    }

    // MARK: - Wayback Machine Fallback

    /// Checks the Wayback Machine for an archived snapshot and scrapes it if the
    /// direct result was too short (likely paywalled).
    private static func tryWaybackFallback(url: String, directResult: CrawlResponse) async -> CrawlResponse {
        let directLen = directResult.articleBody?.count ?? 0

        // Only try fallback if content is suspiciously short
        guard directLen < 1500 else { return directResult }

        crawlLog("Wayback fallback: direct content only \(directLen) chars, checking archive...")

        // Check Wayback availability API (free, no credits)
        guard let checkURL = URL(string: "https://archive.org/wayback/available?url=\(url)") else {
            return directResult
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: checkURL)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshots = json["archived_snapshots"] as? [String: Any],
                  let closest = snapshots["closest"] as? [String: Any],
                  let available = closest["available"] as? Bool, available,
                  let archiveURL = closest["url"] as? String else {
                crawlLog("Wayback fallback: no snapshot available")
                return directResult
            }

            crawlLog("Wayback fallback: snapshot found, scraping \(archiveURL)")
            let waybackResult = try await scrapeAndClean(url: archiveURL, skipWayback: true)
            let waybackLen = waybackResult.articleBody?.count ?? 0

            if waybackLen > directLen {
                crawlLog("Wayback fallback: got \(waybackLen) chars (vs \(directLen) direct) — using archive")
                return CrawlResponse(
                    markdown: waybackResult.markdown,
                    metadata: directResult.metadata ?? waybackResult.metadata,
                    extractedContent: waybackResult.extractedContent
                )
            } else {
                crawlLog("Wayback fallback: archive not better (\(waybackLen) chars) — keeping direct")
                return directResult
            }
        } catch {
            crawlLog("Wayback fallback: failed — \(error.localizedDescription)")
            return directResult
        }
    }

    // MARK: - Private

    private static func post(body: [String: Any], apiKey: String) async throws -> CrawlResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            crawlLog("ERROR: Invalid response (not HTTPURLResponse)")
            throw CrawlError.requestFailed(statusCode: 0, message: "Invalid response")
        }

        crawlLog("HTTP \(http.statusCode) — \(data.count) bytes")

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            crawlLog("ERROR: HTTP \(http.statusCode) — \(message)")
            throw CrawlError.requestFailed(statusCode: http.statusCode, message: message)
        }

        do {
            let result = try JSONDecoder().decode(CrawlResponse.self, from: data)
            crawlLog("OK — markdown: \(result.markdown?.count ?? 0) chars, title: \(result.articleTitle ?? "(none)")")
            return result
        } catch {
            crawlLog("DECODE ERROR: \(error)")
            throw error
        }
    }
}

// MARK: - Response Models

struct CrawlResponse: Decodable {
    let markdown: String?
    let metadata: CrawlMetadata?
    let extractedContent: String?
    let screenshot: String?

    enum CodingKeys: String, CodingKey {
        case markdown, metadata, screenshot
        case extractedContent = "extracted_content"
    }

    init(markdown: String?, metadata: CrawlMetadata?, extractedContent: String? = nil, screenshot: String? = nil) {
        self.markdown = markdown
        self.metadata = metadata
        self.extractedContent = extractedContent
        self.screenshot = screenshot
    }

    /// Convenience: best available article body (markdown content).
    var articleBody: String? {
        if let md = markdown, !md.isEmpty { return md }
        return nil
    }

    /// Convenience: best available article title.
    /// Tries metadata first, then extracts from the first # heading in markdown.
    var articleTitle: String? {
        if let t = metadata?.ogTitle ?? metadata?.title { return t }
        // Extract from first markdown heading
        guard let md = markdown else { return nil }
        for line in md.split(separator: "\n", maxSplits: 10) where line.hasPrefix("# ") {
            let title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
    }

    /// Convenience: returns author if available in metadata.
    var articleAuthor: String? {
        metadata?.author
    }

    /// Convenience: returns publication date if available in metadata.
    var articleDate: String? {
        nil // Not available from the current API; kept for caller compatibility
    }

    /// Convenience: returns summary/description if available.
    var articleSummary: String? {
        metadata?.ogDescription ?? metadata?.description
    }

    // Backward compat — callers that referenced .content
    var content: String? { markdown }
}

struct CrawlMetadata: Decodable {
    let title: String?
    let description: String?
    let author: String?
    let keywords: String?
    let ogTitle: String?
    let ogDescription: String?
    let ogImage: String?
    let ogUrl: String?

    enum CodingKeys: String, CodingKey {
        case title, description, author, keywords
        case ogTitle = "og:title"
        case ogDescription = "og:description"
        case ogImage = "og:image"
        case ogUrl = "og:url"
    }
}

// MARK: - Errors

enum CrawlError: Error, LocalizedError {
    case noAPIKey
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Crawl4AI API key configured. Add one in Ai4Poors Settings."
        case .requestFailed(let code, let message):
            if code == 0 { return "Crawl4AI request failed: \(message)" }
            return "Crawl4AI error (\(code)): \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noAPIKey:
            return "Open the Ai4Poors app and enter your Crawl4AI API key in Settings."
        case .requestFailed(let code, _):
            if code == 401 { return "Your Crawl4AI API key may be invalid." }
            if code == 429 { return "Rate limited. Wait a moment and try again." }
            return "Check your internet connection and try again."
        }
    }
}

// MARK: - Debug Log Access

extension Crawl4AIClient {
    /// Read the debug log file contents (most recent entries last).
    static func readDebugLog() -> String {
        guard let url = AppGroupConstants.sharedContainerURL?.appendingPathComponent("crawl4ai_debug.log"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return "(no log file yet)"
        }
        // Return last 8KB to keep it manageable
        if text.count > 8000 {
            return "...(truncated)\n" + String(text.suffix(8000))
        }
        return text
    }

    /// Clear the debug log.
    static func clearDebugLog() {
        guard let url = AppGroupConstants.sharedContainerURL?.appendingPathComponent("crawl4ai_debug.log") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Domain Tracking

extension Crawl4AIClient {
    /// Extracts domain from a URL string and records it as an approved reader domain.
    static func recordApprovedDomain(from urlString: String) {
        guard let url = URL(string: urlString), let host = url.host else { return }
        // Strip www. prefix for cleaner matching
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        AppGroupConstants.addApprovedReaderDomain(domain)
    }
}
