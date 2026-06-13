import AppKit
import SwiftUI

/// Handle that lets the compose toolbar insert markdown at the caret/selection
/// instead of blindly appending to the end of the body. Held by the SwiftUI
/// view and wired to the live `NSTextView` in `makeNSView`.
@MainActor
final class MacMarkdownEditorController {
    weak var textView: NSTextView?

    /// True once the underlying text view exists so callers can fall back to a
    /// plain append when the editor hasn't mounted yet.
    var isReady: Bool { textView != nil }

    /// Wraps the current selection (or inserts `placeholder` when there's no
    /// selection) with `opening`/`closing` markers, registering native undo and
    /// leaving the inner text selected so the user can keep typing.
    func wrapSelection(opening: String, closing: String, placeholder: String) {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let selectedText = sel.length > 0 ? ns.substring(with: sel) : ""
        let inner = selectedText.isEmpty ? placeholder : selectedText
        let replacement = "\(opening)\(inner)\(closing)"
        guard tv.shouldChangeText(in: sel, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: sel, with: replacement)
        tv.didChangeText()
        let innerLocation = sel.location + (opening as NSString).length
        tv.setSelectedRange(NSRange(location: innerLocation, length: (inner as NSString).length))
    }

    /// Inserts `prefix` at the start of the line containing the caret, keeping
    /// the caret in the same logical spot relative to the typed text.
    func insertLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let lineStart = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0)).location
        let insertRange = NSRange(location: lineStart, length: 0)
        guard tv.shouldChangeText(in: insertRange, replacementString: prefix) else { return }
        tv.textStorage?.replaceCharacters(in: insertRange, with: prefix)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: sel.location + (prefix as NSString).length, length: sel.length))
    }
}

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
    var controller: MacMarkdownEditorController? = nil

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

        // Placeholder — NSTextView has no built-in one. A non-interactive label
        // pinned at the text origin, toggled by emptiness, so an empty compose
        // body reads as "Write your message" instead of looking broken/blank.
        let placeholderLabel = NSTextField(labelWithString: placeholder)
        placeholderLabel.font = font
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.drawsBackground = false
        placeholderLabel.isBordered = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.sizeToFit()
        // x = inset + default line-fragment padding (5) to align with the caret.
        placeholderLabel.frame.origin = NSPoint(x: 16 + 5, y: 12)
        placeholderLabel.isHidden = !text.isEmpty
        textView.addSubview(placeholderLabel)
        context.coordinator.placeholderLabel = placeholderLabel

        scrollView.documentView = textView

        controller?.textView = textView
        context.coordinator.applyText(text, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only grab first responder on the rising edge of `isFocused` — doing it
        // every update pass would repeatedly yank focus away from other fields.
        if isFocused, !context.coordinator.lastIsFocused {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        context.coordinator.lastIsFocused = isFocused

        if text != context.coordinator.lastKnownText {
            context.coordinator.applyText(text, to: textView)
        }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, font: font, onFocusChange: onFocusChange)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let font: NSFont
        let onFocusChange: ((Bool) -> Void)?
        var lastKnownText: String = ""
        /// Tracks the previous external focus request so we only steal first
        /// responder on the rising edge, not on every `updateNSView` pass.
        var lastIsFocused: Bool = false
        /// Placeholder label shown while the body is empty (NSTextView has none).
        weak var placeholderLabel: NSTextField?

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
            placeholderLabel?.isHidden = !newText.isEmpty
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
            guard let storage = textView.textStorage else { return }
            // Restyle attributes in place — no string/selection replacement — so
            // native undo coalescing and the cursor stay intact and we avoid an
            // O(n) full-document rebuild + reselect on every keystroke.
            storage.beginEditing()
            applyStyling(to: storage)
            storage.endEditing()
        }

        private func buildAttributed(_ str: String) -> NSAttributedString {
            let attributed = NSMutableAttributedString(string: str)
            applyStyling(to: attributed)
            return attributed
        }

        /// Applies base + markdown attributes to `attributed` in place. The
        /// source text is read from `attributed.string`, so this works on a
        /// freshly built string and on a live `NSTextStorage` alike.
        private func applyStyling(to attributed: NSMutableAttributedString) {
            let str = attributed.string
            let len = attributed.length
            guard len > 0 else { return }
            let fullRange = NSRange(location: 0, length: len)

            // Base attributes — `setAttributes` clears stale styling from a prior
            // pass so re-applied markdown never leaves orphaned bold/italic runs.
            attributed.setAttributes([
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
        }
    }
}
