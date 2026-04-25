import SwiftUI

/// Renders a markdown string with proper block-level visual structure.
/// Handles H1–H3 headings, paragraphs, unordered/ordered lists, code fences,
/// blockquotes, horizontal rules, and inline formatting (bold, italic, code, links).
/// Compatible with live streaming — content can be partial mid-response.
struct MarkdownView: View {
    let content: String
    var fontSize: CGFloat = 16

    // Cache the parsed block tree. Without this, SwiftUI re-runs `body` on any
    // upstream state change (chat scrolling, sibling typing, etc.) and the
    // computed property re-parses the entire markdown buffer for every visible
    // message — O(N²) on the main actor during streaming.
    @State private var blocks: [MarkdownBlock] = []
    @State private var parsedKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                MarkdownBlockView(block: block, fontSize: fontSize, isFirst: idx == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: content, initial: true) { _, new in
            guard parsedKey != new else { return }
            blocks = MarkdownParser.parse(new)
            parsedKey = new
        }
    }
}

// MARK: - Block model

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case codeBlock(language: String?, code: String)
    case blockQuote(text: String)
    case divider
}

// MARK: - Parser

enum MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Code fence
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") { blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4)))); i += 1; continue }
            if trimmed.hasPrefix("## ")  { blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3)))); i += 1; continue }
            if trimmed.hasPrefix("# ")   { blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2)))); i += 1; continue }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { blocks.append(.divider); i += 1; continue }

            // Block quote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = [stripQuoteMarker(trimmed)]
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") { quoteLines.append(stripQuoteMarker(t)); i += 1 }
                    else if t.isEmpty { break }
                    else { quoteLines.append(t); i += 1 }
                }
                blocks.append(.blockQuote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Unordered list
            if isULItem(trimmed) {
                var items: [String] = [ulText(trimmed)]
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if isULItem(t) { items.append(ulText(t)); i += 1 }
                    else if t.isEmpty {
                        if let j = nextNonEmpty(lines, from: i + 1), isULItem(lines[j].trimmingCharacters(in: .whitespaces)) { i = j }
                        else { break }
                    } else { break }
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if isOLItem(trimmed) {
                var items: [String] = [olText(trimmed)]
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if isOLItem(t) { items.append(olText(t)); i += 1 }
                    else if t.isEmpty {
                        if let j = nextNonEmpty(lines, from: i + 1), isOLItem(lines[j].trimmingCharacters(in: .whitespaces)) { i = j }
                        else { break }
                    } else { break }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // In a chat context each non-structural line is its own paragraph block so that
            // single newlines produce visible spacing (the AI doesn't always emit double newlines).
            if !trimmed.isEmpty {
                blocks.append(.paragraph(text: trimmed))
            }
            i += 1
        }

        return blocks
    }

    private static func stripQuoteMarker(_ s: String) -> String {
        var text = String(s.dropFirst())
        if text.hasPrefix(" ") { text = String(text.dropFirst()) }
        return text
    }
    private static func isULItem(_ s: String) -> Bool { s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") }
    private static func ulText(_ s: String) -> String { String(s.dropFirst(2)) }
    private static func isOLItem(_ s: String) -> Bool { s.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil }
    private static func olText(_ s: String) -> String {
        guard let r = s.range(of: #"^\d+\.\s"#, options: .regularExpression) else { return s }
        return String(s[r.upperBound...])
    }
    private static func nextNonEmpty(_ lines: [String], from start: Int) -> Int? {
        var j = start
        while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
        return j < lines.count ? j : nil
    }
}

// MARK: - Block view

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let fontSize: CGFloat
    let isFirst: Bool

    var body: some View {
        Group {
            switch block {
            case .heading(let level, let text):
                InlineMarkdownText(text, font: headingFont(level))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, isFirst ? 0 : headingTopPad(level))
                    .padding(.bottom, 4)

            case .paragraph(let text):
                InlineMarkdownText(text, font: .system(size: fontSize))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, isFirst ? 0 : 10)

            case .unorderedList(let items):
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: fontSize))
                                .frame(minWidth: 10)
                                .padding(.top, 1)
                            InlineMarkdownText(item, font: .system(size: fontSize))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, isFirst ? 0 : 10)

            case .orderedList(let items):
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1).")
                                .font(.system(size: fontSize))
                                .monospacedDigit()
                                .frame(minWidth: 20, alignment: .trailing)
                                .padding(.top, 1)
                            InlineMarkdownText(item, font: .system(size: fontSize))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, isFirst ? 0 : 10)

            case .codeBlock(let lang, let code):
                VStack(alignment: .leading, spacing: 0) {
                    if let lang, !lang.isEmpty {
                        Text(lang)
                            .font(.system(size: max(10, fontSize - 4), design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(size: max(12, fontSize - 2), design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, lang != nil && !lang!.isEmpty ? 4 : 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous))
                .padding(.top, isFirst ? 0 : 10)

            case .blockQuote(let text):
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3)
                    InlineMarkdownText(text, font: .system(size: fontSize))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                }
                .padding(.top, isFirst ? 0 : 10)

            case .divider:
                Divider().padding(.vertical, 6)
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: fontSize + 6, weight: .bold)
        case 2: return .system(size: fontSize + 3, weight: .semibold)
        default: return .system(size: fontSize + 1, weight: .semibold)
        }
    }

    private func headingTopPad(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 16
        case 2: return 12
        default: return 10
        }
    }
}

// MARK: - Inline markdown text

/// Renders a line/paragraph with inline markdown (bold, italic, code, links) via AttributedString.
struct InlineMarkdownText: View {
    let text: String
    let font: Font

    init(_ text: String, font: Font) {
        self.text = text
        self.font = font
    }

    var body: some View {
        // Prefer parsing inline markdown without relying on unavailable `.inlinesOnly`.
        // We build options explicitly and fall back gracefully if unavailable.
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed).font(font)
        } else if let attributed = try? AttributedString(markdown: text) {
            Text(attributed).font(font)
        } else {
            Text(text).font(font)
        }
    }
}
