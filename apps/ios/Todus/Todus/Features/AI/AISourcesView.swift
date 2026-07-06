import SwiftUI

// MARK: - SourcePlatformIcon

/// Small platform-aware icon (Gmail / Google Meet / Calendar / Notes / Document / Todus chat / website / etc.).
/// Used both as the stacked indicator on the Sources button and as the row trailing glyph in the list sheet.
struct SourcePlatformIcon: View {
    let platform: AISource.Platform
    /// Optional domain for favicon-backed platforms (used when `platform == .website`).
    var iconHint: String?
    var size: CGFloat = 22

    var body: some View {
        switch platform {
        case .gmail:
            GmailIconView(size: size)
        case .appleCalendar, .googleCalendar:
            AppleCalendarIconView(size: size)
        case .googleMeet:
            GoogleMeetIconView(size: size)
        case .notion, .document:
            DocumentIconView(size: size)
        case .notes:
            NotesIconView(size: size)
        case .todus:
            TodusChatIconView(size: size)
        case .memory:
            MemoryIconView(size: size)
        case .upsales:
            CompanyIconView(size: size)
        case .website, .unknown:
            WebsiteIconView(size: size, host: iconHint)
        }
    }
}

// MARK: - AISourcesButton

/// Sources affordance rendered inline with the action row beneath an assistant message.
/// Shows up to three stacked platform icons + the word "Sources". Tapping opens the list sheet.
struct AISourcesButton: View {
    let sources: [AISource]
    var onSelect: (AISource) -> Void = { _ in }

    @State private var showingSheet = false

    private var stackedIcons: [AISource] {
        // Take the first occurrence of each distinct platform so the icon stack feels diverse.
        var seen = Set<AISource.Platform>()
        return sources.filter { seen.insert($0.platform).inserted }.prefix(3).map { $0 }
    }

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 8) {
                stackedIconsView
                Text("Sources")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            AISourcesListSheet(sources: sources, onSelect: { source in
                showingSheet = false
                onSelect(source)
            })
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var stackedIconsView: some View {
        let icons = stackedIcons
        // Stack icons with overlap. Each icon sits on a slightly larger
        // surface-coloured rounded square (via `.background` + negative
        // padding) so adjacent icons get a visible 2pt ring without
        // distorting the brand artwork inside.
        return HStack(spacing: -6) {
            ForEach(Array(icons.enumerated()), id: \.element.id) { _, source in
                SourcePlatformIcon(platform: source.platform, iconHint: source.iconHint, size: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 22 * 0.225 + 1.5, style: .continuous)
                            .fill(AppTheme.surfacePrimary)
                            .padding(-1.5)
                    )
            }
        }
    }
}

// MARK: - AISourcesListSheet

struct AISourcesListSheet: View {
    let sources: [AISource]
    var onSelect: (AISource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detailSource: AISource?

    /// True when the source has a clear in-app navigation target — the parent
    /// chat view can navigate to a thread / event / email / task. Other kinds
    /// fall back to an inline detail sheet showing the snippet.
    private func canNavigate(_ source: AISource) -> Bool {
        guard source.entityId != nil else { return false }
        switch source.kind {
        case .thread, .calendarEvent, .meeting, .email, .task: return true
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sources) { source in
                        Button {
                            if canNavigate(source) {
                                onSelect(source)
                            } else {
                                // Web rows + memory / document / note / company —
                                // surface in a follow-up sheet so taps never silently no-op.
                                detailSource = source
                            }
                        } label: {
                            AISourceRow(source: source)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.visible)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                } header: {
                    Text("Sources (\(sources.count))")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accentColor, AppTheme.surfaceSecondary)
                    }
                    .accessibilityLabel("Close sources")
                }
            }
            .sheet(item: $detailSource) { source in
                AISourceDetailSheet(source: source)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - AISourceRow

struct AISourceRow: View {
    let source: AISource

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(source.subtitle ?? defaultSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if let stamp = source.timestampDate {
                        Text(formatted(stamp))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.mutedText)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(source.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    SourcePlatformIcon(platform: source.platform, iconHint: source.iconHint, size: 18)
                    Text(platformName)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(platformName)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
    }

    private var defaultSubtitle: String {
        switch source.kind {
        case .email: return "Email"
        case .meeting: return "Meeting"
        case .calendarEvent: return "Upcoming Event"
        case .document: return "Document"
        case .note: return "Note"
        case .thread: return "Todus chat thread"
        case .memory: return "Memory"
        case .task: return "Task"
        case .company: return "Company"
        case .web: return source.iconHint ?? "Website"
        case .unknown:
            return source.iconHint ?? "Source"
        }
    }

    private var platformName: String {
        switch source.platform {
        case .gmail: return "Gmail"
        case .googleMeet: return "Google Meet"
        case .appleCalendar: return "Apple Calendar"
        case .googleCalendar: return "Google Calendar"
        case .website: return source.iconHint ?? "Website"
        case .notion: return "Notion"
        case .document: return "Document"
        case .notes: return "Note"
        case .todus: return "Todus"
        case .memory: return "Memory"
        case .upsales: return "Upsales"
        case .unknown: return source.iconHint ?? ""
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, yyyy HH:mm"
        return f
    }()

    private func formatted(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }
}

// MARK: - AISourceDetailSheet

/// Inline detail for any source kind. Web rows get an "Open in Safari"
/// button; everything else just surfaces the snippet so taps never feel
/// dead-end. In-app navigation targets (thread / event / email / task)
/// bypass this sheet and use the parent chat view's navigation handler
/// instead — see `canNavigate(_:)` in `AISourcesListSheet`.
struct AISourceDetailSheet: View {
    let source: AISource

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    SourcePlatformIcon(platform: source.platform, iconHint: source.iconHint, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(3)
                        if let subtitle = source.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(2)
                        }
                    }
                }

                if let snippet = source.snippet, !snippet.isEmpty {
                    ScrollView {
                        Text(snippet)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }

                if source.kind == .web, let urlString = source.url, let openURL = URL(string: urlString) {
                    Link(destination: openURL) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Open in Safari")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                    }
                }

                if source.snippet?.isEmpty != false && source.kind != .web {
                    Spacer()
                }
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .accessibilityLabel("Close source detail")
                }
            }
        }
    }
}
