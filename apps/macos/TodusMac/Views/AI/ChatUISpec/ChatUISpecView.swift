import SwiftUI

/// Optional completion for async spec actions (draft save/send). Success + optional error message.
typealias MacChatUISpecActionCompletion = (Bool, String?) -> Void

/// Action name, string params map, and optional completion for operations that report back (e.g. drafts).
typealias MacChatUISpecOnAction = (String, [String: String], MacChatUISpecActionCompletion?) -> Void

// MARK: - Top-Level Renderer (macOS)

/// Mirror of the iOS ChatUISpecView, adapted to MacTheme tokens.
struct ChatUISpecView: View {
    let spec: ChatUISpec
    var onAction: MacChatUISpecOnAction? = nil

    var body: some View {
        renderElement(id: spec.root, depth: 0)
    }

    private func renderElement(id: String, depth: Int) -> AnyView {
        // Guard against a cyclic or pathologically deep spec — this is untrusted
        // model output, and unbounded recursion here stack-overflows the app.
        guard depth < 24 else { return AnyView(EmptyView()) }
        if let element = spec.elements[id] {
            return elementView(for: element, depth: depth)
        } else {
            return AnyView(EmptyView())
        }
    }

    private func elementView(for element: UIElement, depth: Int) -> AnyView {
        switch element.type {
        case "EmailCard":
            return AnyView(MacEmailCardView(props: element.props, onAction: onAction))
        case "TaskCard":
            return AnyView(MacTaskCardView(props: element.props, onAction: onAction))
        case "CalendarEventCard":
            return AnyView(MacCalendarEventCardView(props: element.props, onAction: onAction))
        case "NoteCard":
            return AnyView(MacNoteCardView(props: element.props))
        case "DraftCard":
            return AnyView(MacDraftCardView(props: element.props, onAction: onAction))
        case "LabelCard":
            return AnyView(MacLabelCardView(props: element.props))
        case "ContactCard":
            return AnyView(MacContactCardView(props: element.props))
        case "SearchResultCard":
            return AnyView(MacSearchResultCardView(props: element.props))

        case "TaskListCard":
            return AnyView(MacTaskListCardView(props: element.props, onAction: onAction))
        case "EmailListCard":
            return AnyView(MacEmailListCardView(props: element.props, onAction: onAction))
        case "CalendarEventListCard":
            return AnyView(MacCalendarEventListCardView(props: element.props, onAction: onAction))
        case "ContactListCard":
            return AnyView(MacContactListCardView(props: element.props))
        case "CopyableTextCard":
            return AnyView(MacCopyableTextCardView(props: element.props, onAction: onAction))
        case "InlineComposeCard":
            return AnyView(MacInlineComposeCardView(props: element.props, onAction: onAction))
        case "SuggestionsCard":
            return AnyView(MacSuggestionsCardView(props: element.props, onAction: onAction))
        case "ActionConfirmationCard":
            return AnyView(MacActionConfirmationCardView(props: element.props, onAction: onAction))
        case "QuoteCard":
            return AnyView(MacQuoteCardView(props: element.props, onAction: onAction))

        // Round 2 cards
        case "AttachmentCard":
            return AnyView(MacAttachmentCardView(props: element.props, onAction: onAction))
        case "CodeBlockCard":
            return AnyView(MacCodeBlockCardView(props: element.props, onAction: onAction))
        case "ChecklistCard":
            return AnyView(MacChecklistCardView(props: element.props, onAction: onAction))
        case "DocumentCard":
            return AnyView(MacDocumentCardView(props: element.props, onAction: onAction))
        case "WeeklyAgendaCard":
            return AnyView(MacWeeklyAgendaCardView(props: element.props, onAction: onAction))
        case "MetricCard":
            return AnyView(MacMetricCardView(props: element.props))

        case "Stack":
            return AnyView(MacStackView(props: element.props) {
                if let children = element.children {
                    ForEach(children, id: \.self) { childId in
                        renderElement(id: childId, depth: depth + 1)
                    }
                }
            })
        case "Card":
            return AnyView(MacCardContainerView(props: element.props) {
                if let children = element.children {
                    ForEach(children, id: \.self) { childId in
                        renderElement(id: childId, depth: depth + 1)
                    }
                }
            })
        case "Text":
            return AnyView(MacTextElementView(props: element.props))
        case "Button":
            return AnyView(MacButtonElementView(props: element.props, onAction: onAction))
        case "Badge":
            return AnyView(MacBadgeElementView(props: element.props))
        case "Divider":
            return AnyView(Divider().padding(.vertical, 2))

        default:
            #if DEBUG
            return AnyView(
                Text("Unknown: \(element.type)")
                    .font(.caption2)
                    .foregroundStyle(MacTheme.mutedText)
            )
            #else
            return AnyView(EmptyView())
            #endif
        }
    }
}

// MARK: - Layout Components

struct MacStackView<Content: View>: View {
    let props: [String: ChatJSONValue]
    @ViewBuilder var content: () -> Content

    private var isVertical: Bool { props["direction"]?.stringValue != "horizontal" }
    private var spacing: CGFloat {
        switch props["gap"]?.stringValue {
        case "none": return 0
        case "sm": return 4
        case "lg": return 16
        default: return 8
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

struct MacCardContainerView<Content: View>: View {
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
                Text(title).font(.subheadline).fontWeight(.medium)
            }
            if let description = props["description"]?.stringValue {
                Text(description).font(.caption).foregroundStyle(MacTheme.textSecondary)
            }
            content()
        }
        .padding(padding)
        .background(MacTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct MacTextElementView: View {
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
        case "caption": return AnyShapeStyle(MacTheme.textSecondary)
        default: return AnyShapeStyle(MacTheme.textPrimary)
        }
    }
}

struct MacButtonElementView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    var body: some View {
        Button(action: handleTap) {
            Text(props["label"]?.stringValue ?? "Button")
                .font(.caption)
                .fontWeight(.medium)
        }
        .buttonStyle(.bordered)
    }

    private func handleTap() {
        guard let action = props["action"]?.stringValue else { return }
        var params: [String: String] = [:]
        if let actionParams = props["actionParams"]?.objectValue {
            for (key, value) in actionParams {
                if let str = value.stringValue { params[key] = str }
            }
        }
        onAction?(action, params, nil)
    }
}

struct MacBadgeElementView: View {
    let props: [String: ChatJSONValue]

    private var color: Color {
        switch props["variant"]?.stringValue {
        case "success": return .green
        case "warning": return .orange
        case "destructive": return .red
        default: return MacTheme.textSecondary
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
