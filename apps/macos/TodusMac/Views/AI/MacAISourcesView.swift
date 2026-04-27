import SwiftUI

// MARK: - MacAISource

/// macOS mirror of iOS `AISource`. Represents one piece of context the AI
/// consumed for this turn — surfaced in the Sources affordance under the
/// assistant message. Mirrors the backend `AISource` interface in
/// `apps/server/src/lib/ai-sources.ts`.
struct MacAISource: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, Equatable, Hashable {
        case web, email, meeting
        case calendarEvent = "calendar_event"
        case document, note, thread, memory, task, company
    }

    enum Platform: String, Codable, Equatable, Hashable {
        case gmail
        case googleMeet = "google_meet"
        case googleCalendar = "google_calendar"
        case website, notion, document, notes, todus, memory, upsales, unknown
    }

    let id: String
    let kind: Kind
    let platform: Platform
    let title: String
    let subtitle: String?
    let timestamp: String?
    let url: String?
    let entityId: String?
    let snippet: String?
    let iconHint: String?

    var timestampDate: Date? {
        guard let timestamp else { return nil }
        return MacAISource.iso8601Fractional.date(from: timestamp)
            ?? MacAISource.iso8601Plain.date(from: timestamp)
    }

    private nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let iso8601Plain = ISO8601DateFormatter()
}

// MARK: - MacAISourcesButton

struct MacAISourcesButton: View {
    let sources: [MacAISource]
    var onSelect: (MacAISource) -> Void = { _ in }

    @State private var showingSheet = false

    private var stackedIcons: [MacAISource] {
        var seen = Set<MacAISource.Platform>()
        return sources.filter { seen.insert($0.platform).inserted }.prefix(3).map { $0 }
    }

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    let icons = stackedIcons
                    ForEach(Array(icons.enumerated()), id: \.element.id) { i, source in
                        MacSourcePlatformIcon(platform: source.platform, iconHint: source.iconHint, size: 18)
                            .background(
                                Circle().fill(Color(NSColor.windowBackgroundColor))
                                    .padding(-2)
                            )
                            .offset(x: CGFloat(i) * 12)
                    }
                }
                .frame(width: CGFloat(stackedIcons.count - 1) * 12 + 18, alignment: .leading)

                Text("Sources")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            MacAISourcesListSheet(sources: sources) { source in
                showingSheet = false
                onSelect(source)
            }
            .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 620)
        }
    }
}

// MARK: - MacAISourcesListSheet

struct MacAISourcesListSheet: View {
    let sources: [MacAISource]
    var onSelect: (MacAISource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detailSource: MacAISource?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sources) { source in
                        Button {
                            if source.kind == .web, let urlString = source.url, let openURL = URL(string: urlString) {
                                NSWorkspace.shared.open(openURL)
                                dismiss()
                            } else {
                                // Surface a detail sheet for non-web rows so a
                                // tap is never a silent no-op. The host caller
                                // can still react to `onSelect` if it wants
                                // app-level navigation behaviour.
                                onSelect(source)
                                detailSource = source
                            }
                        } label: {
                            MacAISourceRow(source: source)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .sheet(item: $detailSource) { source in
            MacAISourceDetailSheet(source: source)
                .frame(minWidth: 420, idealWidth: 480, minHeight: 360, idealHeight: 480)
        }
    }
}

// MARK: - MacAISourceDetailSheet

struct MacAISourceDetailSheet: View {
    let source: MacAISource

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MacSourcePlatformIcon(platform: source.platform, iconHint: source.iconHint, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(3)
                    if let subtitle = source.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            Divider()

            ScrollView {
                if let snippet = source.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No additional details available.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
        }
    }
}

// MARK: - MacAISourceRow

struct MacAISourceRow: View {
    let source: MacAISource

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(source.subtitle ?? defaultSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let stamp = source.timestampDate {
                        Text(formatted(stamp))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(source.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    MacSourcePlatformIcon(platform: source.platform, iconHint: source.iconHint, size: 16)
                    Text(platformName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
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
        }
    }

    private var platformName: String {
        switch source.platform {
        case .gmail: return "Gmail"
        case .googleMeet: return "Google Meet"
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

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM, yyyy HH:mm"
        return f.string(from: date)
    }
}

// MARK: - MacSourcePlatformIcon

/// Compact platform icon for the macOS Sources button + sheet rows.
/// Uses SF Symbols inside a rounded square container so the icons stay
/// consistent with `MacBrandIcons.swift` styling.
struct MacSourcePlatformIcon: View {
    let platform: MacAISource.Platform
    var iconHint: String?
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(background)
            content
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }

    private var background: Color {
        switch platform {
        case .document, .notion: return Color(red: 0.13, green: 0.46, blue: 0.95)
        default: return .white
        }
    }

    @ViewBuilder
    private var content: some View {
        switch platform {
        case .gmail:
            Image(systemName: "envelope.fill")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(red: 0.918, green: 0.263, blue: 0.208))
        case .googleCalendar:
            Image(systemName: "calendar")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(red: 1.0, green: 0.231, blue: 0.188))
        case .googleMeet:
            Image(systemName: "video.fill")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(red: 0.0, green: 0.55, blue: 0.27))
        case .notion, .document:
            Image(systemName: "doc.text.fill")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
        case .notes:
            Image(systemName: "note.text")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.20))
        case .todus:
            Image(systemName: "bubble.left.fill")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
        case .memory:
            Image(systemName: "brain.head.profile")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.purple)
        case .upsales:
            Image(systemName: "building.2.fill")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        case .website, .unknown:
            if let host = iconHint,
               let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://www.google.com/s2/favicons?domain=\(encodedHost)&sz=64") {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "globe")
                        .resizable().aspectRatio(contentMode: .fit)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "globe")
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
