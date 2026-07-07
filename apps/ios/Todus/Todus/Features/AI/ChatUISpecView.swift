import SwiftUI

/// Optional completion for async spec actions (draft save/send). Success + optional error message.
typealias ChatUISpecActionCompletion = (Bool, String?) -> Void

/// Action name, string params map, and optional completion for operations that report back (e.g. drafts).
typealias ChatUISpecOnAction = (String, [String: String], ChatUISpecActionCompletion?) -> Void

// MARK: - Top-Level Renderer

/// Renders a ChatUISpec by recursively resolving element IDs to SwiftUI views.
/// Unknown component types render as empty views with a debug warning.
struct ChatUISpecView: View {
    let spec: ChatUISpec
    /// Callback when user taps a card — passes the action name, parameters, and optional async completion.
    var onAction: ChatUISpecOnAction? = nil

    var body: some View {
        renderElement(id: spec.root)
    }

    /// Maximum nesting depth for an AI-produced spec. A malformed or adversarial spec could
    /// nest layout containers arbitrarily deep (or cycle via child IDs); bail past this to
    /// protect against unbounded recursion / stack overflow.
    private static let maxRenderDepth = 32

    private func renderElement(id: String, depth: Int = 0) -> AnyView {
        guard depth <= Self.maxRenderDepth else {
            #if DEBUG
            return AnyView(
                Text("Spec too deeply nested (truncated)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )
            #else
            return AnyView(EmptyView())
            #endif
        }
        if let element = spec.elements[id] {
            return elementView(for: element, depth: depth)
        } else {
            // Element ID not found in spec — render nothing
            return AnyView(EmptyView())
        }
    }

    private func elementView(for element: UIElement, depth: Int) -> AnyView {
        switch element.type {
        // Domain cards
        case "EmailCard":
            return AnyView(EmailCardView(props: element.props, onAction: onAction))
        case "TaskCard":
            return AnyView(TaskCardView(props: element.props, onAction: onAction))
        case "CalendarEventCard":
            return AnyView(CalendarEventCardView(props: element.props, onAction: onAction))
        case "NoteCard":
            return AnyView(NoteCardView(props: element.props))
        case "DraftCard":
            return AnyView(DraftCardView(props: element.props, onAction: onAction))
        case "LabelCard":
            return AnyView(LabelCardView(props: element.props))
        case "ContactCard":
            return AnyView(ContactCardView(props: element.props))
        case "SearchResultCard":
            return AnyView(SearchResultCardView(props: element.props))

        // List + utility cards
        case "TaskListCard":
            return AnyView(TaskListCardView(props: element.props, onAction: onAction))
        case "EmailListCard":
            return AnyView(EmailListCardView(props: element.props, onAction: onAction))
        case "CalendarEventListCard":
            return AnyView(CalendarEventListCardView(props: element.props, onAction: onAction))
        case "ContactListCard":
            return AnyView(ContactListCardView(props: element.props))
        case "CopyableTextCard":
            return AnyView(CopyableTextCardView(props: element.props, onAction: onAction))
        case "InlineComposeCard":
            return AnyView(InlineComposeCardView(props: element.props, onAction: onAction))
        case "SuggestionsCard":
            return AnyView(SuggestionsCardView(props: element.props, onAction: onAction))
        case "ActionConfirmationCard":
            return AnyView(ActionConfirmationCardView(props: element.props, onAction: onAction))
        case "QuoteCard":
            return AnyView(QuoteCardView(props: element.props, onAction: onAction))

        // Round 2 cards
        case "AttachmentCard":
            return AnyView(AttachmentCardView(props: element.props, onAction: onAction))
        case "CodeBlockCard":
            return AnyView(CodeBlockCardView(props: element.props, onAction: onAction))
        case "ChecklistCard":
            return AnyView(ChecklistCardView(props: element.props, onAction: onAction))
        case "DocumentCard":
            return AnyView(DocumentCardView(props: element.props, onAction: onAction))
        case "WeeklyAgendaCard":
            return AnyView(WeeklyAgendaCardView(props: element.props, onAction: onAction))
        case "MetricCard":
            return AnyView(MetricCardView(props: element.props))

        // Layout components
        case "Stack":
            return AnyView(StackView(props: element.props) {
                if let children = element.children {
                    ForEach(children, id: \.self) { childId in
                        renderElement(id: childId, depth: depth + 1)
                    }
                }
            })
        case "Card":
            return AnyView(CardContainerView(props: element.props) {
                if let children = element.children {
                    ForEach(children, id: \.self) { childId in
                        renderElement(id: childId, depth: depth + 1)
                    }
                }
            })
        case "Text":
            return AnyView(TextElementView(props: element.props))
        case "Button":
            return AnyView(ButtonElementView(props: element.props, onAction: onAction))
        case "Badge":
            return AnyView(BadgeElementView(props: element.props))
        case "Divider":
            return AnyView(
                Divider()
                    .padding(.vertical, 2)
            )

        default:
            // Unknown component type — fail gracefully
            #if DEBUG
            return AnyView(
                Text("Unknown: \(element.type)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )
            #else
            return AnyView(EmptyView())
            #endif
        }
    }
}

// MARK: - Layout Components

struct StackView<Content: View>: View {
    let props: [String: ChatJSONValue]
    @ViewBuilder var content: () -> Content

    private var isVertical: Bool {
        props["direction"]?.stringValue != "horizontal"
    }

    private var spacing: CGFloat {
        switch props["gap"]?.stringValue {
        case "none": return 0
        case "sm": return 4
        case "lg": return 16
        default: return 8 // "md"
        }
    }

    var body: some View {
        if isVertical {
            VStack(alignment: alignment, spacing: spacing) { content() }
        } else {
            HStack(alignment: vAlignment, spacing: spacing) { content() }
        }
    }

    private var alignment: HorizontalAlignment {
        switch props["align"]?.stringValue {
        case "center": return .center
        case "end": return .trailing
        default: return .leading
        }
    }

    private var vAlignment: VerticalAlignment {
        switch props["align"]?.stringValue {
        case "center": return .center
        case "end": return .bottom
        default: return .top
        }
    }
}

struct CardContainerView<Content: View>: View {
    let props: [String: ChatJSONValue]
    @ViewBuilder var content: () -> Content

    private var padding: CGFloat {
        switch props["padding"]?.stringValue {
        case "none": return 0
        case "sm": return 8
        case "lg": return 16
        default: return 12
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = props["title"]?.stringValue {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            if let description = props["description"]?.stringValue {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(padding)
        .background(AppTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

struct TextElementView: View {
    let props: [String: ChatJSONValue]

    var body: some View {
        Text(props["content"]?.stringValue ?? "")
            .font(font)
            .foregroundStyle(foregroundStyle)
    }

    private var font: Font {
        switch props["variant"]?.stringValue {
        case "heading": return .headline
        case "subheading": return .subheadline.weight(.medium)
        case "caption": return .caption
        case "code": return .system(.caption, design: .monospaced)
        default: return .subheadline
        }
    }

    private var foregroundStyle: some ShapeStyle {
        switch props["variant"]?.stringValue {
        case "caption": return AnyShapeStyle(.secondary)
        default: return AnyShapeStyle(.primary)
        }
    }
}

struct ButtonElementView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    var body: some View {
        Button(action: handleTap) {
            Text(props["label"]?.stringValue ?? "Button")
                .font(.caption)
                .fontWeight(.medium)
        }
        .buttonStyle(cardButtonStyle)
    }

    private var cardButtonStyle: some PrimitiveButtonStyle {
        .bordered
    }

    private func handleTap() {
        guard let action = props["action"]?.stringValue else { return }
        var params: [String: String] = [:]
        // Accept both "actionParams" and "params" — different card emitters use
        // different keys, and a button reading only one would silently no-op.
        if let actionParams = props["actionParams"]?.objectValue ?? props["params"]?.objectValue {
            for (key, value) in actionParams {
                if let str = value.stringValue {
                    params[key] = str
                }
            }
        }
        onAction?(action, params, nil)
    }
}

struct BadgeElementView: View {
    let props: [String: ChatJSONValue]

    private var color: Color {
        switch props["variant"]?.stringValue {
        case "success": return .green
        case "warning": return .orange
        case "destructive": return .red
        default: return .secondary
        }
    }

    var body: some View {
        Text(props["label"]?.stringValue ?? "")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
