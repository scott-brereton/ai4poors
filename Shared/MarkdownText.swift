// MarkdownText.swift
// Ai4Poors - Renders markdown as native SwiftUI views
//
// Handles: bullets, numbered lists, bold, italic, code, headers,
// blockquotes, horizontal rules, and fenced code blocks.
// Uses AttributedString for inline formatting and VStack for block structure.

import SwiftUI

struct MarkdownText: View {
    let content: String
    let font: Font
    let paragraphSpacing: CGFloat

    init(_ content: String, font: Font = .body, paragraphSpacing: CGFloat = 4) {
        self.content = content
        self.font = font
        self.paragraphSpacing = paragraphSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: paragraphSpacing) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case paragraph(String)
        case bullet(String)
        case numbered(String, Int)
        case header(String, Int)
        case blockquote(String)
        case horizontalRule
        case codeBlock(String)
    }

    // MARK: - Parsing

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var currentParagraph = ""
        var numberCounter = 0
        var inCodeBlock = false
        var codeBlockLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    blocks.append(.codeBlock(codeBlockLines.joined(separator: "\n")))
                    codeBlockLines = []
                    inCodeBlock = false
                } else {
                    // Start code block
                    flushParagraph(&currentParagraph, into: &blocks)
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            // Horizontal rules
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph(&currentParagraph, into: &blocks)
                blocks.append(.horizontalRule)
                numberCounter = 0
                continue
            }

            // Headers
            if trimmed.hasPrefix("### ") {
                flushParagraph(&currentParagraph, into: &blocks)
                blocks.append(.header(String(trimmed.dropFirst(4)), 3))
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph(&currentParagraph, into: &blocks)
                blocks.append(.header(String(trimmed.dropFirst(3)), 2))
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph(&currentParagraph, into: &blocks)
                blocks.append(.header(String(trimmed.dropFirst(2)), 1))
                continue
            }

            // Blockquotes
            if trimmed.hasPrefix("> ") {
                flushParagraph(&currentParagraph, into: &blocks)
                let quoteText = String(trimmed.dropFirst(2))
                blocks.append(.blockquote(quoteText))
                numberCounter = 0
                continue
            }

            // Bullets
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushParagraph(&currentParagraph, into: &blocks)
                let text = String(trimmed.dropFirst(2))
                blocks.append(.bullet(text))
                numberCounter = 0
                continue
            }

            // Numbered lists
            if let match = trimmed.range(of: #"^\d+[\.\)] "#, options: .regularExpression) {
                flushParagraph(&currentParagraph, into: &blocks)
                numberCounter += 1
                let text = String(trimmed[match.upperBound...])
                blocks.append(.numbered(text, numberCounter))
                continue
            }

            // Empty line = paragraph break
            if trimmed.isEmpty {
                flushParagraph(&currentParagraph, into: &blocks)
                numberCounter = 0
                continue
            }

            // Regular text
            if currentParagraph.isEmpty {
                currentParagraph = trimmed
            } else {
                currentParagraph += " " + trimmed
            }
            numberCounter = 0
        }

        // Flush any remaining code block
        if inCodeBlock && !codeBlockLines.isEmpty {
            blocks.append(.codeBlock(codeBlockLines.joined(separator: "\n")))
        }

        flushParagraph(&currentParagraph, into: &blocks)
        return blocks
    }

    private func flushParagraph(_ text: inout String, into blocks: inout [Block]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(.paragraph(trimmed))
        }
        text = ""
    }

    // MARK: - Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inlineMarkdown(text)
                .font(font)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(font)
                    .foregroundStyle(.secondary)
                inlineMarkdown(text)
                    .font(font)
            }
            .padding(.leading, 4)

        case .numbered(let text, let num):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(num).")
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                inlineMarkdown(text)
                    .font(font)
            }
            .padding(.leading, 4)

        case .header(let text, let level):
            inlineMarkdown(text)
                .font(headerFont(level))
                .fontWeight(.semibold)
                .padding(.top, 4)

        case .blockquote(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3)
                inlineMarkdown(text)
                    .font(font)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
            .padding(.vertical, 2)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if canImport(UIKit)
                .background(Color(UIColor.systemGray6))
                #else
                .background(Color(nsColor: .controlBackgroundColor))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3
        case 2: return .headline
        default: return .subheadline
        }
    }

    // MARK: - Inline Markdown

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}

// MARK: - Article-Optimized Variant

/// A MarkdownText wrapper with article-friendly typography:
/// larger font, wider line spacing, and comfortable reading width.
struct ArticleMarkdownText: View {
    let content: String

    var body: some View {
        MarkdownText(content, font: .system(size: 17), paragraphSpacing: 8)
            .lineSpacing(4)
            .frame(maxWidth: 680, alignment: .leading)
    }
}
