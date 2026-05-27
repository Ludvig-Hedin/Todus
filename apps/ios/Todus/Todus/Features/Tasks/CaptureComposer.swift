import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Rich Input Types (shared by AI Chat, Email Compose, and CreateSheet)
// ─────────────────────────────────────────────────────────────────────────────

enum RichInputSurface {
    case emailCompose
    case aiChat
    case taskCapture
}

enum RichInputMentionKind: String, Codable, Hashable {
    case task
    case thread
    case event
    case person
}

struct RichInputMentionRef: Identifiable, Codable, Hashable {
    let id: String
    let kind: RichInputMentionKind
    let title: String
    let subtitle: String?
    let displayText: String
    let accessibilityLabel: String
}

enum RichInputCommandAction: Hashable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case checklist
    case divider
    case quote
    case insertMention(RichInputMentionKind)
    case signature
    case dueToday
    case dueTomorrow
    case dueNextWeek
    case inOneHour
}

struct RichInputCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: RichInputCommandAction
}

/// Returns the available slash/mention commands for a given input surface.
/// Internal visibility so CreateSheet can also use the .taskCapture commands.
func richInputCommands(for surface: RichInputSurface) -> [RichInputCommand] {
    switch surface {
    case .emailCompose:
        return [
            .init(id: "paragraph", title: "Paragraph", subtitle: "Continue with plain text", systemImage: "text.alignleft", action: .paragraph),
            .init(id: "heading1", title: "Heading 1", subtitle: "Insert a large heading", systemImage: "textformat.size.larger", action: .heading1),
            .init(id: "heading2", title: "Heading 2", subtitle: "Insert a medium heading", systemImage: "textformat.size", action: .heading2),
            .init(id: "heading3", title: "Heading 3", subtitle: "Insert a small heading", systemImage: "textformat.size.smaller", action: .heading3),
            .init(id: "bullet", title: "Bullet List", subtitle: "Insert a bulleted list", systemImage: "list.bullet", action: .bulletList),
            .init(id: "numbered", title: "Numbered List", subtitle: "Insert a numbered list", systemImage: "list.number", action: .numberedList),
            .init(id: "checklist", title: "Checklist", subtitle: "Insert a checklist", systemImage: "checklist", action: .checklist),
            .init(id: "divider", title: "Divider", subtitle: "Insert a divider", systemImage: "minus", action: .divider),
            .init(id: "quote", title: "Quote", subtitle: "Insert a quote block", systemImage: "quote.opening", action: .quote),
            .init(id: "task", title: "Task Mention", subtitle: "Search and insert a task", systemImage: "checklist", action: .insertMention(.task)),
            .init(id: "thread", title: "Email Thread", subtitle: "Search and insert an email thread", systemImage: "envelope", action: .insertMention(.thread)),
            .init(id: "event", title: "Event", subtitle: "Search and insert an event", systemImage: "calendar", action: .insertMention(.event)),
            .init(id: "person", title: "Person", subtitle: "Search and insert a person", systemImage: "person.2", action: .insertMention(.person)),
            .init(id: "signature", title: "Signature", subtitle: "Insert your active signature", systemImage: "signature", action: .signature),
        ]
    case .aiChat:
        return [
            .init(id: "task", title: "Task Mention", subtitle: "Search and insert a task", systemImage: "checklist", action: .insertMention(.task)),
            .init(id: "thread", title: "Email Thread", subtitle: "Search and insert an email thread", systemImage: "envelope", action: .insertMention(.thread)),
            .init(id: "event", title: "Event", subtitle: "Search and insert an event", systemImage: "calendar", action: .insertMention(.event)),
            .init(id: "person", title: "Person", subtitle: "Search and insert a person", systemImage: "person.2", action: .insertMention(.person)),
            .init(id: "paragraph", title: "Paragraph", subtitle: "Continue with plain text", systemImage: "text.alignleft", action: .paragraph),
            .init(id: "bullet", title: "Bullet List", subtitle: "Insert a bulleted list", systemImage: "list.bullet", action: .bulletList),
            .init(id: "numbered", title: "Numbered List", subtitle: "Insert a numbered list", systemImage: "list.number", action: .numberedList),
            .init(id: "checklist", title: "Checklist", subtitle: "Insert a checklist", systemImage: "checklist", action: .checklist),
            .init(id: "divider", title: "Divider", subtitle: "Insert a divider", systemImage: "minus", action: .divider),
            .init(id: "quote", title: "Quote", subtitle: "Insert a quote block", systemImage: "quote.opening", action: .quote),
        ]
    case .taskCapture:
        return [
            .init(id: "due-today", title: "Due Today", subtitle: "Set the due date to today", systemImage: "sun.max", action: .dueToday),
            .init(id: "due-tomorrow", title: "Due Tomorrow", subtitle: "Set the due date to tomorrow", systemImage: "sunrise", action: .dueTomorrow),
            .init(id: "due-next-week", title: "Due Next Week", subtitle: "Set the due date to next week", systemImage: "calendar.badge.plus", action: .dueNextWeek),
            .init(id: "in-one-hour", title: "In 1 Hour", subtitle: "Set the due date to one hour from now", systemImage: "clock", action: .inOneHour),
        ]
    }
}

private func applyRichInputFormatting(_ action: RichInputCommandAction) -> String {
    switch action {
    case .paragraph:
        return ""
    case .heading1:
        return "# "
    case .heading2:
        return "## "
    case .heading3:
        return "### "
    case .bulletList:
        return "• "
    case .numberedList:
        return "1. "
    case .checklist:
        return "☐ "
    case .divider:
        return "\n---\n"
    case .quote:
        return "> "
    case .insertMention:
        return "@"
    case .signature, .dueToday, .dueTomorrow, .dueNextWeek, .inOneHour:
        return ""
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RichComposerInput (used by AI Chat and Email Compose)
// ─────────────────────────────────────────────────────────────────────────────

struct RichComposerInput: View {
    @Binding var text: String
    @Binding var mentions: [RichInputMentionRef]

    let placeholder: String
    let surface: RichInputSurface
    let mentionOptions: [RichInputMentionRef]
    var isFocused: Bool? = nil
    /// Max content height before scrolling kicks in (0 = unlimited)
    var maxHeight: CGFloat = 0
    var onPasteImage: ((UIImage) -> Void)? = nil
    /// Pasted file data (e.g. from clipboard) — extension is a best-effort filename suffix (e.g. `pdf`, `png`).
    var onPasteFileData: ((Data, String) -> Void)? = nil
    var onCommand: ((RichInputCommandAction) -> Void)? = nil
    /// Called when the text input gains or loses focus
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var activeMentionQuery = ""
    @State private var activeSlashQuery = ""
    @State private var showsMentionMenu = false
    @State private var showsSlashMenu = false
    @State private var preferredMentionKind: RichInputMentionKind? = nil
    @State private var suppressSuggestionReopen = false

    private var filteredMentions: [RichInputMentionRef] {
        let normalized = activeMentionQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return mentionOptions.filter { mention in
            if let preferredMentionKind, mention.kind != preferredMentionKind {
                return false
            }

            if normalized.isEmpty {
                return true
            }

            return mention.title.lowercased().contains(normalized)
                || mention.displayText.lowercased().contains(normalized)
                || (mention.subtitle?.lowercased().contains(normalized) ?? false)
        }
    }

    private var filteredSlashCommands: [RichInputCommand] {
        let normalized = activeSlashQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let commands = richInputCommands(for: surface)

        guard !normalized.isEmpty else { return commands }

        return commands.filter {
            $0.title.lowercased().contains(normalized) || $0.subtitle.lowercased().contains(normalized)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsMentionMenu {
                suggestionPanel {
                    ForEach(filteredMentions) { mention in
                        suggestionRow(
                            title: mention.title,
                            subtitle: mention.subtitle ?? mention.accessibilityLabel,
                            systemImage: suggestionIcon(for: mention.kind)
                        ) {
                            insertMention(mention)
                        }
                    }
                }
            }

            if showsSlashMenu {
                suggestionPanel {
                    ForEach(filteredSlashCommands) { command in
                        suggestionRow(
                            title: command.title,
                            subtitle: command.subtitle,
                            systemImage: command.systemImage
                        ) {
                            applyCommand(command.action)
                        }
                    }
                }
            }

            PasteHandlingTextInput(
                text: $text,
                placeholder: placeholder,
                highlightTerms: mentions.map { "@\($0.displayText)" },
                isFocused: isFocused,
                maxHeight: maxHeight,
                onPasteImage: { image in
                    onPasteImage?(image)
                },
                onPasteFileData: { data, ext in
                    onPasteFileData?(data, ext)
                },
                onFocusChange: onFocusChange
            )
            .onChange(of: text) { _, newValue in
                updateSuggestions(for: newValue)
                pruneMissingMentions(from: newValue)
            }
        }
    }

    @ViewBuilder
    private func suggestionPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .padding(8)
        .background(
            AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.strongBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadowColor, radius: 12, x: 0, y: -4)
    }

    private func suggestionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accentBlue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func updateSuggestions(for value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(whereSeparator: \.isWhitespace)

        if suppressSuggestionReopen {
            let lastToken = components.last ?? ""
            if lastToken.hasPrefix("@") || lastToken.hasPrefix("/") {
                showsMentionMenu = false
                showsSlashMenu = false
                return
            }

            suppressSuggestionReopen = false
        }

        guard let last = components.last else {
            showsMentionMenu = false
            showsSlashMenu = false
            preferredMentionKind = nil
            return
        }

        if last.hasPrefix("@") {
            activeMentionQuery = String(last.dropFirst())
            showsMentionMenu = true
            showsSlashMenu = false
            return
        }

        if last.hasPrefix("/") {
            activeSlashQuery = String(last.dropFirst())
            showsSlashMenu = true
            showsMentionMenu = false
            preferredMentionKind = nil
            return
        }

        showsMentionMenu = false
        showsSlashMenu = false
        preferredMentionKind = nil
    }

    private func insertMention(_ mention: RichInputMentionRef) {
        replaceActiveToken(with: "@\(mention.displayText) ")
        if !mentions.contains(mention) {
            mentions.append(mention)
        }
        showsMentionMenu = false
        preferredMentionKind = nil
        suppressSuggestionReopen = true
    }

    private func applyCommand(_ action: RichInputCommandAction) {
        onCommand?(action)

        switch action {
        case .signature:
            showsSlashMenu = false
            preferredMentionKind = nil
        case .insertMention(let kind):
            preferredMentionKind = kind
            replaceActiveToken(with: "@")
            showsSlashMenu = false
            showsMentionMenu = true
        default:
            replaceActiveToken(with: applyRichInputFormatting(action))
            showsSlashMenu = false
            preferredMentionKind = nil
        }
    }

    private func replaceActiveToken(with replacement: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(whereSeparator: \.isWhitespace)
        guard let last = components.last, last.hasPrefix("@") || last.hasPrefix("/") else {
            text += replacement
            return
        }

        if let range = text.range(of: String(last), options: .backwards) {
            text.replaceSubrange(range, with: replacement)
        } else {
            text += replacement
        }
    }

    private func pruneMissingMentions(from value: String) {
        mentions.removeAll { mention in
            !value.contains("@\(mention.displayText)")
        }
    }

    private func suggestionIcon(for kind: RichInputMentionKind) -> String {
        switch kind {
        case .task:
            return "checklist"
        case .thread:
            return "envelope"
        case .event:
            return "calendar"
        case .person:
            return "person.2"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PasteHandlingTextInput
// ─────────────────────────────────────────────────────────────────────────────

/// UITextView wrapper that intercepts paste to detect images from the clipboard
/// and provides auto-formatting for markdown bullet lists.
struct PasteHandlingTextInput: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var highlightTerms: [String] = []
    var isFocused: Bool? = nil
    /// Max content height before scrolling kicks in (0 = unlimited)
    var maxHeight: CGFloat = 0
    let onPasteImage: (UIImage) -> Void
    var onPasteFileData: ((Data, String) -> Void)?
    /// Called when the UITextView gains or loses focus — drives isInputExpanded in AIChatView
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            placeholder: placeholder,
            highlightTerms: highlightTerms,
            onPasteImage: onPasteImage,
            onPasteFileData: onPasteFileData,
            onFocusChange: onFocusChange,
            maxHeight: maxHeight
        )
    }

    func makeUIView(context: Context) -> PasteInterceptingTextView {
        let view = PasteInterceptingTextView()
        view.delegate = context.coordinator
        view.onPasteImage = onPasteImage
        view.onPasteFileData = onPasteFileData
        view.backgroundColor = .clear
        view.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        // Disabled so SwiftUI's layout drives the height based on content
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Hug content vertically so the view shrinks to one line when empty
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.highlightTerms = highlightTerms
        view.maxContentHeight = maxHeight

        // Show placeholder initially
        if text.isEmpty {
            view.text = placeholder
            view.textColor = UIColor.placeholderText
        } else {
            view.text = text
            view.textColor = UIColor.label
            context.coordinator.applyHighlights(to: view)
        }

        // Preserve the existing auto-focus behavior unless the parent explicitly controls focus.
        if isFocused ?? true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                view.becomeFirstResponder()
            }
        }
        return view
    }

    func updateUIView(_ uiView: PasteInterceptingTextView, context: Context) {
        context.coordinator.highlightTerms = highlightTerms
        context.coordinator.onPasteFileData = onPasteFileData
        uiView.highlightTerms = highlightTerms
        uiView.onPasteFileData = onPasteFileData

        if let isFocused {
            if isFocused, !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            } else if !isFocused, uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.resignFirstResponder()
                }
            }
        }

        // Only sync when text is changed externally (e.g. after submit clears it).
        // CRITICAL: do NOT call applyHighlights on every render — it writes a fresh
        // NSAttributedString to `attributedText`, which interrupts the active input
        // session on iOS 17+. Symptom: keyboard dismisses on every keystroke because
        // the textView briefly resigns first responder during the attributed write.
        // Highlights are already re-applied from textViewDidChange (internal edits)
        // and from the non-guard branch below (external text changes), so the guard
        // branch can be a pure no-op.
        guard text != context.coordinator.lastKnownText else { return }
        context.coordinator.lastKnownText = text

        if text.isEmpty {
            if uiView.isFirstResponder {
                // Clear content but keep keyboard open
                uiView.text = ""
                uiView.textColor = UIColor.label
            } else {
                uiView.text = placeholder
                uiView.textColor = UIColor.placeholderText
            }
        } else {
            uiView.text = text
            uiView.textColor = UIColor.label
            context.coordinator.applyHighlights(to: uiView)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        let placeholder: String
        var highlightTerms: [String]
        let onPasteImage: (UIImage) -> Void
        var onPasteFileData: ((Data, String) -> Void)?
        let onFocusChange: ((Bool) -> Void)?
        let maxHeight: CGFloat
        /// Tracks the last text value the coordinator wrote to the binding,
        /// used to distinguish external (submit) clears from internal edits.
        var lastKnownText: String = ""

        init(
            text: Binding<String>,
            placeholder: String,
            highlightTerms: [String],
            onPasteImage: @escaping (UIImage) -> Void,
            onPasteFileData: ((Data, String) -> Void)? = nil,
            onFocusChange: ((Bool) -> Void)? = nil,
            maxHeight: CGFloat = 0
        ) {
            _text = text
            self.placeholder = placeholder
            self.highlightTerms = highlightTerms
            self.onPasteImage = onPasteImage
            self.onPasteFileData = onPasteFileData
            self.onFocusChange = onFocusChange
            self.maxHeight = maxHeight
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Replace placeholder with empty field on focus
            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
                // Reset intrinsic size and scroll offset so the cursor starts at
                // the top-left (0,0), matching where the placeholder text was rendered.
                textView.invalidateIntrinsicContentSize()
                textView.setContentOffset(.zero, animated: false)
            }
            onFocusChange?(true)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
            guard textView.textColor != UIColor.placeholderText else { return true }

            let nsText = (textView.text ?? "") as NSString
            guard let mentionRange = mentionRangeIntersecting(range, in: nsText) else {
                return true
            }

            let updated = nsText.replacingCharacters(in: mentionRange, with: replacementText)
            textView.text = updated
            text = updated
            lastKnownText = updated
            applyHighlights(to: textView)
            textView.selectedRange = NSRange(location: mentionRange.location + (replacementText as NSString).length, length: 0)
            textView.invalidateIntrinsicContentSize()
            return false
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textView.text = placeholder
                textView.textColor = UIColor.placeholderText
                text = ""
                lastKnownText = ""
            }
            onFocusChange?(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.textColor != UIColor.placeholderText else { return }
            var updatedText = textView.text ?? ""

            // Auto-format: replace "- " at start of a line with "• " (markdown bullets)
            let lines = updatedText.components(separatedBy: "\n")
            var modified = false
            let newLines = lines.map { line -> String in
                if line.hasPrefix("- ") {
                    modified = true
                    return "• " + line.dropFirst(2)
                }
                return line
            }
            if modified {
                updatedText = newLines.joined(separator: "\n")
                textView.text = updatedText
            }

            lastKnownText = updatedText
            text = updatedText
            // Only re-style when something stylable is in the buffer. Skipping the
            // attributed-text rewrite on plain typing keeps the iOS 17+ input session
            // intact (writing attributedText mid-edit causes the keyboard to dismiss).
            if needsHighlights(text: updatedText) {
                applyHighlights(to: textView)
            }

            // Toggle scrolling based on whether content exceeds max height threshold
            if maxHeight > 0 {
                let fitsContent = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height <= maxHeight
                textView.isScrollEnabled = !fitsContent
            }

            // Notify SwiftUI layout to re-measure height from intrinsicContentSize
            textView.invalidateIntrinsicContentSize()
        }

        // MARK: - Markdown regex (compiled once; NSRegularExpression is thread-safe)
        private static let mdBoldRegex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
        private static let mdItalicRegex = try? NSRegularExpression(pattern: #"(?<![_*])_([^_\n]+)_(?![_*])"#)
        private static let mdHeadingRegex = try? NSRegularExpression(pattern: #"^(#{1,3}) (.+)$"#, options: .anchorsMatchLines)
        private static let mdQuoteRegex = try? NSRegularExpression(pattern: #"^> (.+)$"#, options: .anchorsMatchLines)

        /// Applies live markdown rendering to `attributed` in-place.
        /// Delimiters (**  _ # >) are dimmed; the enclosed text gets the
        /// matching font/color so users see formatted output while retaining
        /// the raw markdown that feeds the send pipeline.
        private func applyMarkdownStyling(to attributed: NSMutableAttributedString) {
            let str = attributed.string
            let len = attributed.length
            guard len > 0 else { return }
            let fullRange = NSRange(location: 0, length: len)
            let dimColor = UIColor.tertiaryLabel

            // Bold: **text**
            Coordinator.mdBoldRegex?.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges == 2 else { return }
                let content = match.range(at: 1)
                let full = match.range(at: 0)
                guard full.length >= 4 else { return }
                attributed.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: content)
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location, length: 2))
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location + full.length - 2, length: 2))
            }

            // Italic: _text_
            Coordinator.mdItalicRegex?.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges == 2 else { return }
                let content = match.range(at: 1)
                let full = match.range(at: 0)
                guard full.length >= 3 else { return }
                attributed.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 16), range: content)
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
                attributed.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: size), range: contentRange)
                let prefixLen = min(level + 1, match.range(at: 0).length)
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: match.range(at: 0).location, length: prefixLen))
            }

            // Blockquote: > text
            Coordinator.mdQuoteRegex?.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges == 2 else { return }
                let full = match.range(at: 0)
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: full.location, length: min(2, full.length)))
                attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: match.range(at: 1))
            }
        }

        /// True iff `text` contains anything that `applyHighlights` would actually style.
        /// Used to skip the attributed-text rewrite during plain typing (no @mentions,
        /// no markdown). The rewrite resets the UITextView's input session on iOS 17+,
        /// which manifests as the keyboard dismissing on every keystroke.
        func needsHighlights(text: String) -> Bool {
            if !highlightTerms.isEmpty {
                for term in highlightTerms where !term.isEmpty {
                    if text.contains(term) { return true }
                }
            }
            // Cheap markdown sniff — same patterns applyMarkdownStyling renders.
            return text.contains("**")
                || text.contains("_")
                || text.contains("# ")
                || text.contains("\n> ")
                || text.hasPrefix("> ")
        }

        func applyHighlights(to textView: UITextView) {
            guard textView.textColor != UIColor.placeholderText else { return }

            let currentText = textView.text ?? ""
            let selectedRange = textView.selectedRange
            let attributed = NSMutableAttributedString(string: currentText)
            attributed.addAttributes([
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.label,
            ], range: NSRange(location: 0, length: attributed.length))

            // Render markdown syntax as live formatting (bold, italic, headings, quotes)
            applyMarkdownStyling(to: attributed)

            for term in highlightTerms where !term.isEmpty {
                let nsText = currentText as NSString
                var searchRange = NSRange(location: 0, length: nsText.length)

                while searchRange.location < nsText.length {
                    let found = nsText.range(of: term, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }

                    attributed.addAttributes([
                        .foregroundColor: UIColor.systemBlue,
                    ], range: found)

                    let nextLocation = found.location + found.length
                    searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
                }
            }

            textView.attributedText = attributed
            textView.selectedRange = selectedRange
            textView.setNeedsDisplay()
        }

        private func mentionRangeIntersecting(_ range: NSRange, in text: NSString) -> NSRange? {
            for term in highlightTerms where !term.isEmpty {
                var searchRange = NSRange(location: 0, length: text.length)

                while searchRange.location < text.length {
                    let found = text.range(of: term, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }

                    if NSIntersectionRange(found, range).length > 0
                        || (range.length == 0 && range.location > found.location && range.location <= found.location + found.length) {
                        return found
                    }

                    let nextLocation = found.location + found.length
                    searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
                }
            }

            return nil
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PasteInterceptingTextView
// ─────────────────────────────────────────────────────────────────────────────

/// UITextView subclass that intercepts paste to detect images from the clipboard.
/// Overrides intrinsicContentSize so SwiftUI's layout system drives height from content,
/// not from available space — keeping the composer at single-line until the user types.
final class PasteInterceptingTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteFileData: ((Data, String) -> Void)?
    var highlightTerms: [String] = []
    var mentionHighlightColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.14)
    /// When > 0, caps intrinsic height and enables scrolling beyond this threshold
    var maxContentHeight: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        // Keep the empty composer compact; the placeholder should behave like a
        // single-line input instead of inheriting a tall measured height.
        // Use a strict isEmpty check (not trimmed) so pressing Return on an
        // otherwise-empty field — text becomes "\n" — still grows the view.
        if textColor == UIColor.placeholderText || (text?.isEmpty ?? true) {
            let lineHeight = font?.lineHeight ?? 20
            let verticalInsets = textContainerInset.top + textContainerInset.bottom
            let height = ceil(lineHeight + verticalInsets)
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        }

        // Measure the height required for the current content.
        let measured = sizeThatFits(
            CGSize(width: frame.width > 0 ? frame.width : UIScreen.main.bounds.width,
                   height: .greatestFiniteMagnitude)
        )
        let height = max(measured.height, 20)
        // Cap at maxContentHeight if set — enables scrolling beyond this point
        if maxContentHeight > 0 && height > maxContentHeight {
            return CGSize(width: UIView.noIntrinsicMetric, height: maxContentHeight)
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func draw(_ rect: CGRect) {
        drawMentionHighlights()
        super.draw(rect)
    }

    private func drawMentionHighlights() {
        guard textColor != UIColor.placeholderText, !highlightTerms.isEmpty else { return }

        let nsText = (text ?? "") as NSString
        let inset = textContainerInset

        mentionHighlightColor.setFill()

        for term in highlightTerms where !term.isEmpty {
            var searchRange = NSRange(location: 0, length: nsText.length)

            while searchRange.location < nsText.length {
                let found = nsText.range(of: term, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: found, actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphRange,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: textContainer
                ) { rect, _ in
                    let pillRect = rect
                        .offsetBy(dx: inset.left, dy: inset.top)
                        .insetBy(dx: -5, dy: -2)
                    UIBezierPath(
                        roundedRect: pillRect,
                        cornerRadius: pillRect.height / 2
                    ).fill()
                }

                let nextLocation = found.location + found.length
                searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
            }
        }
    }

    override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image {
            onPasteImage?(image)
            return
        }
        if ClipboardPasteFileLoader.pasteboardIsPlainTextOnly {
            super.paste(sender)
            return
        }
        Task { @MainActor in
            let parts = await ClipboardPasteFileLoader.loadFileParts(
                from: UIPasteboard.general.itemProviders
            )
            if !parts.isEmpty {
                for (data, ext) in parts {
                    onPasteFileData?(data, ext)
                }
            } else {
                super.paste(sender)
            }
        }
    }
}

// MARK: - Clipboard file paste (iOS)

private enum ClipboardPasteFileLoader {
    static var pasteboardIsPlainTextOnly: Bool {
        let providers = UIPasteboard.general.itemProviders
        guard !providers.isEmpty, providers.count == 1, let p = providers.first else { return false }
        let types = p.registeredTypeIdentifiers
        return types.count == 1 && types[0] == UTType.utf8PlainText.identifier
    }

    static func loadFileParts(from providers: [NSItemProvider]) async -> [(Data, String)] {
        var out: [(Data, String)] = []
        for p in providers {
            if p.registeredTypeIdentifiers == [UTType.utf8PlainText.identifier] { continue }
            if let one = await loadOneFile(from: p) {
                out.append(one)
            }
        }
        return out
    }

    private static func loadOneFile(from provider: NSItemProvider) async -> (Data, String)? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadFileURL(from: provider) {
                if url.isFileURL {
                    let did = url.startAccessingSecurityScopedResource()
                    defer { if did { url.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: url) {
                        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
                        return (d, ext)
                    }
                }
            }
        }

        for typeId in typePriority where provider.hasItemConformingToTypeIdentifier(typeId) {
            if typeId == UTType.fileURL.identifier { continue }
            if let d = await loadDataRepresentation(from: provider, typeId: typeId), !d.isEmpty {
                let ext = fileExtensionForTypeId(typeId, data: d)
                return (d, ext)
            }
        }
        for typeId in provider.registeredTypeIdentifiers {
            if typeId == UTType.utf8PlainText.identifier { continue }
            if typeId == UTType.plainText.identifier { continue }
            if let d = await loadDataRepresentation(from: provider, typeId: typeId), !d.isEmpty {
                let ext = fileExtensionForTypeId(typeId, data: d)
                return (d, ext)
            }
        }
        return nil
    }

    private static var typePriority: [String] {
        [
            UTType.image.identifier,
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.tiff.identifier,
            UTType.gif.identifier,
            UTType.pdf.identifier,
            "public.heic",
            "public.data",
        ]
    }

    private static func fileExtensionForTypeId(_ typeId: String, data: Data) -> String {
        if let u = UTType(typeId) {
            if u.conforms(to: .image) {
                if u == .png || u.conforms(to: .png) { return "png" }
                if u == .jpeg || u.conforms(to: .jpeg) { return "jpg" }
                if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
                if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
            }
            if u.conforms(to: .pdf) { return "pdf" }
            if let s = u.preferredFilenameExtension { return s }
        }
        return "dat"
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { c in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let u = item as? URL { c.resume(returning: u) }
                else if let n = item as? NSURL { c.resume(returning: n as URL) }
                else { c.resume(returning: nil) }
            }
        }
    }

    private static func loadDataRepresentation(from provider: NSItemProvider, typeId: String) async -> Data? {
        await withCheckedContinuation { c in
            provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, _ in
                c.resume(returning: data)
            }
        }
    }
}

private extension Data {
    func starts(with bytes: [UInt8]) -> Bool {
        guard count >= bytes.count else { return false }
        return bytes.enumerated().allSatisfy { self[$0.offset] == $0.element }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CameraPicker
// ─────────────────────────────────────────────────────────────────────────────

/// Camera picker that returns the actual captured UIImage.
/// Internal so it can also be used by CreateSheet and AIChatView.
struct CameraPicker: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            let image = info[.originalImage] as? UIImage
            onComplete(image)
        }
    }
}
