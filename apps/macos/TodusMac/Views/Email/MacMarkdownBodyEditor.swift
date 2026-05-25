import AppKit
import SwiftUI

/// NSTextView wrapper for the email compose body. Applies live markdown-aware
/// NSAttributedString styling (bold, italic, headings, blockquote) so the user
/// sees formatted output while the underlying `text` binding still stores raw
/// markdown for the send pipeline.
struct MacMarkdownBodyEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Write your message"
    var isFocused: Bool = false
    var font: NSFont = .systemFont(ofSize: 13)
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = context.coordinator.textView
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        // isRichText = true so textStorage accepts and preserves NSAttributedString styling.
        // We control all attributes programmatically; the system Format menu is not needed
        // here but doesn't break anything.
        textView.isRichText = true
        textView.font = font
        textView.textColor = .labelColor
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 16, height: 12)

        scrollView.documentView = textView

        context.coordinator.applyText(text, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if isFocused {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        guard text != context.coordinator.lastKnownText else { return }
        context.coordinator.applyText(text, to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, font: font, onFocusChange: onFocusChange)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let font: NSFont
        let onFocusChange: ((Bool) -> Void)?
        var lastKnownText: String = ""

        lazy var textView = NSTextView()

        // Compiled once — NSRegularExpression is thread-safe
        private static let mdBoldRegex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
        private static let mdItalicRegex = try? NSRegularExpression(pattern: #"(?<![_*])_([^_\n]+)_(?![_*])"#)
        private static let mdHeadingRegex = try? NSRegularExpression(pattern: #"^(#{1,3}) (.+)$"#, options: .anchorsMatchLines)
        private static let mdQuoteRegex = try? NSRegularExpression(pattern: #"^> (.+)$"#, options: .anchorsMatchLines)

        init(text: Binding<String>, font: NSFont, onFocusChange: ((Bool) -> Void)?) {
            _text = text
            self.font = font
            self.onFocusChange = onFocusChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newText = tv.string
            lastKnownText = newText
            text = newText
            reapplyMarkdown(to: tv)
        }

        func textDidBeginEditing(_ notification: Notification) {
            onFocusChange?(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            onFocusChange?(false)
        }

        /// Sets text and applies markdown styling, preserving the cursor position.
        func applyText(_ newText: String, to textView: NSTextView) {
            lastKnownText = newText
            let selectedRange = textView.selectedRange()
            let attributed = buildAttributed(newText)
            textView.textStorage?.setAttributedString(attributed)
            // Clamp selection to valid range after external text replacement
            let clamped = NSRange(
                location: min(selectedRange.location, attributed.length),
                length: min(selectedRange.length, max(0, attributed.length - selectedRange.location))
            )
            textView.setSelectedRange(clamped)
        }

        private func reapplyMarkdown(to textView: NSTextView) {
            let currentText = textView.string
            let selectedRange = textView.selectedRange()
            let attributed = buildAttributed(currentText)
            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(selectedRange)
        }

        private func buildAttributed(_ str: String) -> NSAttributedString {
            let attributed = NSMutableAttributedString(string: str)
            let len = attributed.length
            guard len > 0 else { return attributed }
            let fullRange = NSRange(location: 0, length: len)

            // Base attributes
            attributed.addAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ], range: fullRange)

            let dimColor = NSColor.tertiaryLabelColor

            // Bold: **text**
            Coordinator.mdBoldRegex?.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges == 2 else { return }
                let content = match.range(at: 1)
                let full = match.range(at: 0)
                guard full.length >= 4 else { return }
                let boldFont = NSFont.boldSystemFont(ofSize: font.pointSize)
                attributed.addAttribute(.font, value: boldFont, range: content)
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location, length: 2))
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location + full.length - 2, length: 2))
            }

            // Italic: _text_
            Coordinator.mdItalicRegex?.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges == 2 else { return }
                let content = match.range(at: 1)
                let full = match.range(at: 0)
                guard full.length >= 3 else { return }
                let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                attributed.addAttribute(.font, value: italicFont, range: content)
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location, length: 1))
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location + full.length - 1, length: 1))
            }

            // Headings: # H1 / ## H2 / ### H3
            Coordinator.mdHeadingRegex?.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges == 3 else { return }
                let levelRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let level = min(levelRange.length, 3)
                let size: CGFloat = level == 1 ? 22 : level == 2 ? 18 : 15
                attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: contentRange)
                let prefixLen = min(level + 1, match.range(at: 0).length)
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: match.range(at: 0).location, length: prefixLen))
            }

            // Blockquote: > text
            Coordinator.mdQuoteRegex?.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges == 2 else { return }
                let full = match.range(at: 0)
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location, length: min(2, full.length)))
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 1))
            }

            return attributed
        }
    }
}
