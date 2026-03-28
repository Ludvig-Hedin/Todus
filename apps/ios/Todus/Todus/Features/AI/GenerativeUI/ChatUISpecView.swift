import SwiftUI

// MARK: - Top-Level Renderer

/// Renders a ChatUISpec by recursively resolving element IDs to SwiftUI views.
/// Unknown component types render as empty views with a debug warning.
struct ChatUISpecView: View {
    let spec: ChatUISpec
    /// Callback when user taps a card — passes the action name and parameters.
    var onAction: ((String, [String: String]) -> Void)? = nil

    var body: some View {
        renderElement(id: spec.root)
    }

    @ViewBuilder
    private func renderElement(id: String) -> some View {
        if let element = spec.elements[id] {
            elementView(for: element)
        } else {
            // Element ID not found in spec — render nothing
            EmptyView()
        }
    }

    @ViewBuilder
    private func elementView(for element: UIElement) -> some View {
        switch element.type {
        // Domain cards
        case "EmailCard":
            EmailCardView(props: element.props, onAction: onAction)
        case "TaskCard":
            TaskCardView(props: element.props, onAction: onAction)
        case "CalendarEventCard":
            CalendarEventCardView(props: element.props, onAction: onAction)
        case "NoteCard":
            NoteCardView(props: element.props)
        case "DraftCard":
            DraftCardView(props: element.props, onAction: onAction)
        case "LabelCard":
            LabelCardView(props: element.props)
        case "ContactCard":
            ContactCardView(props: element.props)
        case "SearchResultCard":
            SearchResultCardView(props: element.props)

        // Layout components
        case "Stack":
            StackView(props: element.props) {
                if let children = element.children {
                    ForEach(children, id: \.self) { childId in
                        renderElement(id: childId)
                    }
                }
            }
        case "Card":
            CardContainerView(props: element.props) {
                if let children = element.children {
                    ForEach(children, id: \.self) { childId in
                        renderElement(id: childId)
                    }
                }
            }
        case "Text":
            TextElementView(props: element.props)
        case "Button":
            ButtonElementView(props: element.props, onAction: onAction)
        case "Badge":
            BadgeElementView(props: element.props)
        case "Divider":
            Divider()
                .padding(.vertical, 2)

        default:
            // Unknown component type — fail gracefully
            #if DEBUG
            Text("Unknown: \(element.type)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #else
            EmptyView()
            #endif
        }
    }
}

// MARK: - Layout Components

struct StackView<Content: View>: View {
    let props: [String: JSONValue]
    @ViewBuilder let content: Content

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
            VStack(alignment: alignment, spacing: spacing) { content }
        } else {
            HStack(alignment: vAlignment, spacing: spacing) { content }
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
    let props: [String: JSONValue]
    @ViewBuilder let content: Content

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
            content
        }
        .padding(padding)
        .background(Color(.systemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

struct TextElementView: View {
    let props: [String: JSONValue]

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
    let props: [String: JSONValue]
    var onAction: ((String, [String: String]) -> Void)?

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
        if let actionParams = props["actionParams"]?.objectValue {
            for (key, value) in actionParams {
                if let str = value.stringValue {
                    params[key] = str
                }
            }
        }
        onAction?(action, params)
    }
}

struct BadgeElementView: View {
    let props: [String: JSONValue]

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
