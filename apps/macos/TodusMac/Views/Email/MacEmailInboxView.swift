import Observation
import SwiftUI

/// Toggle between viewing emails as individual threads or grouped by sender.
private enum MacInboxViewMode: String, CaseIterable {
    case threads = "Threads"
    case people  = "People"
}

/// A sender with their aggregated thread info, used by the People view mode.
private struct MacSenderGroup: Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let threads: [EmailThread]
    let unreadCount: Int
    let latestDate: Date
}

/// Email inbox view — split layout: thread list on the left, thread detail on the right.
/// Clicking a thread shows it inline rather than in a modal sheet, matching the web app's side-panel pattern.
struct MacEmailInboxView: View {
    @Environment(MacAppServices.self) private var services
    @State private var searchText = ""
    @State private var selectedThreadId: String? = nil
    @State private var filteredThreads: [EmailThread] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var hoveredThreadId: String? = nil
    @State private var viewMode: MacInboxViewMode = .threads
    /// When in People mode, the currently selected sender email to show their threads
    @State private var selectedSenderEmail: String? = nil
    @FocusState private var isConnectGmailFocused: Bool

    /// Which email folder to show — matches backend FOLDERS constant.
    /// Values: "inbox", "draft", "sent", "archive", "snoozed", "spam", "bin"
    var folder: String = "inbox"

    private var isBackgroundRefreshing: Bool {
        services.emailService.isLoadingThreads && !services.emailService.threads.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: thread list panel (fixed width)
            leftPanel
                .frame(width: 300)
                .background(MacTheme.contentBackground)

            Divider()

            // RIGHT: thread detail, sender thread list, or placeholder
            if let threadId = selectedThreadId {
                MacEmailThreadView(threadId: threadId, onClose: {
                    withAnimation(.snappy(duration: 0.15)) {
                        selectedThreadId = nil
                    }
                })
                // Use id() so the view fully resets when switching threads
                .id(threadId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if viewMode == .people, let senderEmail = selectedSenderEmail,
                      let group = macSenderGroups.first(where: { $0.email == senderEmail }) {
                // Show threads from this sender in the detail panel
                macSenderDetailPanel(group)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                emptyDetailPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.15), value: selectedThreadId)
        .task(id: folder) {
            services.emailService.prepareFolder(folder)
            recomputeFiltered()
            await services.emailService.ensureMailboxReady(for: folder)
        }
        .onChange(of: services.emailService.threads) { recomputeFiltered() }
        .onChange(of: searchText) {
            recomputeFiltered()
            debounceServerSearch()
        }
        .onAppear { recomputeFiltered() }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            mailboxHeader
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.top, MacTheme.spacing12)
                .padding(.bottom, MacTheme.spacing8)

            // Search bar
            searchBar
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.bottom, MacTheme.spacing8)

            if !searchText.isEmpty {
                searchStatusRow
                    .padding(.horizontal, MacTheme.spacing12)
                    .padding(.bottom, MacTheme.spacing8)
            }

            if services.assistantAutomationPolicy.assistantThreadActionsVisible &&
                !services.emailService.assistantNudges.isEmpty &&
                searchText.isEmpty {
                assistantNudgesStrip
                    .padding(.horizontal, MacTheme.spacing12)
                    .padding(.bottom, MacTheme.spacing8)
            }

            Divider().opacity(0.3)

            if services.emailService.isCheckingConnection && !services.emailService.hasResolvedConnection {
                loadingState(message: "Checking Gmail connection…")
            } else if !services.emailService.hasConnection {
                connectPrompt
            } else if services.emailService.isLoadingThreads && filteredThreads.isEmpty {
                loadingState(message: "Loading \(folderTitle.lowercased())…")
            } else if services.emailService.errorMessage != nil && filteredThreads.isEmpty && !services.emailService.isLoadingThreads {
                // Load failed and no cached threads — show error with retry
                errorState
            } else if filteredThreads.isEmpty {
                emptyState
            } else if viewMode == .people {
                peopleList
            } else {
                threadList
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Empty Detail Placeholder

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: MacTheme.spacing8) {
            Image(systemName: "envelope.open")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(MacTheme.mutedText.opacity(0.3))
            Text("Select an email")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))
            Text("Choose a thread from \(folderTitle) to read and reply.")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Assistant Nudges Strip

    private var assistantNudgesStrip: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            Text("Assistant Picks")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(MacTheme.mutedText)
                .textCase(.uppercase)

            ForEach(services.emailService.assistantNudges.prefix(2)) { nudge in
                Button {
                    if let firstThreadId = nudge.threadIds.first {
                        withAnimation(.snappy(duration: 0.15)) {
                            selectedThreadId = firstThreadId
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: MacTheme.spacing8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(nudge.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(MacTheme.textPrimary)
                            Text(nudge.description)
                                .font(MacTheme.cardSubtitleFont())
                                .foregroundStyle(MacTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Text("\(nudge.count)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(MacTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                MacTheme.surfaceHover.opacity(0.9),
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(MacTheme.cardBorder.opacity(0.8), lineWidth: 0.6)
                            )
                    }
                    .padding(.horizontal, MacTheme.spacing12)
                    .padding(.vertical, MacTheme.spacing8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                            .stroke(MacTheme.cardBorder.opacity(0.65), lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(nudge.threadIds.isEmpty)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: MacTheme.spacing6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)

            TextField("Search emails...", text: $searchText)
                .font(.system(size: 12))
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await services.emailService.loadThreads(folder: folder, refresh: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            if isBackgroundRefreshing {
                MacInlineRefreshBadge()
            }
        }
        .padding(.horizontal, MacTheme.spacing8)
        .padding(.vertical, MacTheme.spacing6)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private var mailboxHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Mailbox")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(MacTheme.mutedText)
                    .textCase(.uppercase)

                Spacer()

                // View mode toggle — threads vs people
                macViewModePicker
            }

            Text(folderTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
        }
    }

    private var macViewModePicker: some View {
        HStack(spacing: 1) {
            ForEach(MacInboxViewMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewMode = mode
                        // Reset sender selection when switching modes
                        if mode == .threads { selectedSenderEmail = nil }
                    }
                } label: {
                    Image(systemName: mode == .threads ? "list.bullet" : "person.2")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(viewMode == mode ? MacTheme.accent : MacTheme.mutedText)
                        .frame(width: 24, height: 20)
                        .background(
                            viewMode == mode ? MacTheme.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(MacTheme.surfaceHover.opacity(0.5), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(MacTheme.cardBorder.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var searchStatusRow: some View {
        HStack(spacing: MacTheme.spacing6) {
            if services.emailService.isLoadingThreads && filteredThreads.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }

            Text(
                services.emailService.isLoadingThreads
                    ? "Searching \(folderTitle.lowercased())…"
                    : "Filtering loaded \(folderTitle.lowercased()) threads"
            )
            .font(MacTheme.cardSubtitleFont())
            .foregroundStyle(MacTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Thread List

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredThreads) { thread in
                    threadRow(thread)
                    Divider().opacity(0.25).padding(.leading, 52)
                }

                // Load more indicator
                if services.emailService.nextPageToken != nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(MacTheme.spacing12)
                        .onAppear {
                            Task { await services.emailService.loadThreads(folder: folder) }
                        }
                }
            }
        }
    }

    private func threadRow(_ thread: EmailThread) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) {
                selectedThreadId = thread.id
            }
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                // Sender avatar circle
                MacSenderAvatarView(email: thread.from.email, name: thread.from.name, size: 28)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(thread.from.name)
                            .font(.system(size: 13, weight: thread.unread ? .semibold : .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: MacTheme.spacing8)

                        Text(formatTime(thread.date))
                            .font(MacTheme.metaFont())
                            .foregroundStyle(MacTheme.mutedText)
                    }

                    // Subject + unread indicator on the right
                    HStack(spacing: 5) {
                        Text(thread.subject)
                            .font(.system(size: 12, weight: thread.unread ? .medium : .regular))
                            .foregroundStyle(MacTheme.textPrimary.opacity(0.8))
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if thread.unread {
                            Circle()
                                .fill(MacTheme.accent)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Text(thread.snippet)
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // Highlight selected thread with accent tint; otherwise subtle hover
                selectedThreadId == thread.id
                    ? MacTheme.accent.opacity(0.1)
                    : (hoveredThreadId == thread.id ? MacTheme.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredThreadId = hovering ? thread.id : nil
        }
    }

    // MARK: - People View

    /// Groups filtered threads by sender email, sorted by most recent message first.
    private var macSenderGroups: [MacSenderGroup] {
        var grouped: [String: (name: String, threads: [EmailThread])] = [:]
        for thread in filteredThreads {
            let key = thread.from.email.lowercased()
            if var existing = grouped[key] {
                existing.threads.append(thread)
                if thread.from.name.count > existing.name.count && thread.from.name != thread.from.email {
                    existing.name = thread.from.name
                }
                grouped[key] = existing
            } else {
                grouped[key] = (name: thread.from.name, threads: [thread])
            }
        }

        return grouped.map { email, info in
            let sorted = info.threads.sorted { $0.date > $1.date }
            return MacSenderGroup(
                email: email,
                name: info.name,
                threads: sorted,
                unreadCount: sorted.filter(\.unread).count,
                latestDate: sorted.first?.date ?? .distantPast
            )
        }
        .sorted { $0.latestDate > $1.latestDate }
    }

    private var peopleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(macSenderGroups) { group in
                    Button {
                        withAnimation(.snappy(duration: 0.15)) {
                            selectedSenderEmail = group.email
                            selectedThreadId = nil
                        }
                    } label: {
                        HStack(spacing: MacTheme.spacing8) {
                            MacSenderAvatarView(email: group.email, name: group.name, size: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(group.name)
                                        .font(.system(size: 13, weight: group.unreadCount > 0 ? .semibold : .medium))
                                        .foregroundStyle(MacTheme.textPrimary)
                                        .lineLimit(1)

                                    Spacer(minLength: MacTheme.spacing8)

                                    Text("\(group.threads.count)")
                                        .font(MacTheme.metaFont())
                                        .foregroundStyle(MacTheme.mutedText)
                                }

                                HStack(spacing: 5) {
                                    Text(group.threads.first?.subject ?? "")
                                        .font(.system(size: 12, weight: group.unreadCount > 0 ? .medium : .regular))
                                        .foregroundStyle(MacTheme.textPrimary.opacity(0.8))
                                        .lineLimit(1)

                                    Spacer(minLength: 0)

                                    if group.unreadCount > 0 {
                                        Text("\(group.unreadCount)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(MacTheme.accent, in: Capsule())
                                    }
                                }

                                Text(group.email)
                                    .font(MacTheme.cardSubtitleFont())
                                    .foregroundStyle(MacTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, MacTheme.spacing12)
                        .padding(.vertical, MacTheme.spacing8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedSenderEmail == group.email
                                ? MacTheme.accent.opacity(0.1)
                                : (hoveredThreadId == group.email ? MacTheme.surfaceHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredThreadId = hovering ? group.email : nil
                    }
                    Divider().opacity(0.25).padding(.leading, 48)
                }
            }
        }
    }

    /// Right panel detail view showing all threads from a specific sender.
    private func macSenderDetailPanel(_ group: MacSenderGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with sender info
            HStack(spacing: MacTheme.spacing12) {
                MacSenderAvatarView(email: group.email, name: group.name, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(group.email)
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textSecondary)
                }

                Spacer()

                Text("\(group.threads.count) emails")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .padding(MacTheme.spacing16)
            .background(MacTheme.contentBackground)

            Divider().opacity(0.3)

            // Threads from this sender
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(group.threads) { thread in
                        Button {
                            withAnimation(.snappy(duration: 0.15)) {
                                selectedThreadId = thread.id
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(thread.subject)
                                        .font(.system(size: 13, weight: thread.unread ? .semibold : .medium))
                                        .foregroundStyle(MacTheme.textPrimary)
                                        .lineLimit(1)

                                    Spacer(minLength: MacTheme.spacing8)

                                    if thread.unread {
                                        Circle()
                                            .fill(MacTheme.accent)
                                            .frame(width: 6, height: 6)
                                    }

                                    Text(formatTime(thread.date))
                                        .font(MacTheme.metaFont())
                                        .foregroundStyle(MacTheme.mutedText)
                                }

                                Text(thread.snippet)
                                    .font(MacTheme.cardSubtitleFont())
                                    .foregroundStyle(MacTheme.textSecondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, MacTheme.spacing16)
                            .padding(.vertical, MacTheme.spacing12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedThreadId == thread.id
                                    ? MacTheme.accent.opacity(0.08)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.2).padding(.leading, MacTheme.spacing16)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var connectPrompt: some View {
        VStack {
            Spacer()
            VStack(spacing: MacTheme.spacing12) {
                Image(systemName: "envelope")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(MacTheme.mutedText.opacity(0.5))
                Text("Connect Gmail to see your inbox")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Sign in to your Google account to get started.")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .multilineTextAlignment(.center)
                connectGmailButton
            }
            .padding(MacTheme.spacing24)
            .frame(maxWidth: 260)
            .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectGmailButton: some View {
        Button {
            Task { await services.emailService.connectGmail(authService: services.authService) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .medium))
                Text("Connect Gmail")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MacTheme.spacing20)
            .padding(.vertical, MacTheme.spacing8)
            .background(MacTheme.accent, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isConnectGmailFocused)
        .overlay(
            Capsule(style: .continuous)
                .stroke(isConnectGmailFocused ? MacTheme.accent.opacity(0.75) : Color.clear, lineWidth: 2)
        )
        .pointerStyle(.link)
        .padding(.top, MacTheme.spacing4)
    }

    private func loadingState(message: String) -> some View {
        VStack(spacing: MacTheme.spacing8) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown when a load fails and there are no cached threads to display
    private var errorState: some View {
        VStack(spacing: MacTheme.spacing12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))
            Text("Couldn't load \(folderTitle)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
            if let errorMessage = services.emailService.errorMessage {
                Text(errorMessage)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .multilineTextAlignment(.center)
            }
            Button("Try Again") {
                Task { await services.emailService.loadThreads(folder: folder, refresh: true) }
            }
            .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: MacTheme.spacing12) {
            Spacer()
            Image(systemName: "envelope.open")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))
            Text(searchText.isEmpty ? emptyStateTitle : "No matching emails")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)

            if searchText.isEmpty {
                Text(emptyStateDescription)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .multilineTextAlignment(.center)
            }

            if searchText.isEmpty {
                Button("Refresh") {
                    Task { await services.emailService.loadThreads(folder: folder, refresh: true) }
                }
                .font(.system(size: 12, weight: .medium))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func recomputeFiltered() {
        guard !searchText.isEmpty else {
            filteredThreads = services.emailService.threads
            return
        }
        let query = searchText.lowercased()
        filteredThreads = services.emailService.threads.filter {
            $0.subject.lowercased().contains(query) ||
            $0.from.name.lowercased().contains(query) ||
            $0.from.email.lowercased().contains(query) ||
            $0.snippet.lowercased().contains(query)
        }
    }

    private func debounceServerSearch() {
        searchDebounceTask?.cancel()
        guard !searchText.isEmpty else { return }
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await services.emailService.loadThreads(folder: folder, query: searchText, refresh: true)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), date > weekAgo {
            return date.formatted(.dateTime.weekday(.abbreviated))
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private var folderTitle: String {
        switch folder {
        case "draft": "Drafts"
        case "sent": "Sent"
        case "archive": "Archive"
        case "snoozed": "Snoozed"
        case "spam": "Spam"
        case "bin": "Trash"
        default: "Inbox"
        }
    }

    private var emptyStateTitle: String {
        switch folder {
        case "draft": "No drafts"
        case "sent": "Nothing sent yet"
        case "archive": "No archived emails"
        case "snoozed": "Nothing snoozed"
        case "spam": "No spam"
        case "bin": "Trash is empty"
        default: "No emails"
        }
    }

    private var emptyStateDescription: String {
        switch folder {
        case "draft": "Drafts you save will show up here."
        case "sent": "Emails you send will show up here."
        case "archive": "Archived conversations will show up here."
        case "snoozed": "Snoozed emails will show up here until they return."
        case "spam": "Spam filtered by your provider will show up here."
        case "bin": "Deleted emails will show up here until they're removed."
        default: "You're all caught up."
        }
    }
}

/// Helper for sheet presentation with String IDs (used by MacRootView for search-opened threads)
struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}

private struct MacAvatarInput: Encodable {
    let email: String
    let name: String?
}

private struct MacAvatarResponse: Decodable {
    let primary: Primary?
    let fallbackUrls: [String]

    struct Primary: Decodable {
        let source: String
        let url: String?
    }
}

@MainActor
@Observable
final class MacAvatarCache {
    static let shared = MacAvatarCache()

    var resolvedURLs: [String: [URL]] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    func resolveIfNeeded(email: String, name: String, api: TodosAPIClient) async {
        let normalized = normalizedEmail(email)
        guard resolvedURLs[normalized] == nil, !inFlight.contains(normalized) else { return }
        inFlight.insert(normalized)
        defer { inFlight.remove(normalized) }

        let urls = await fetchCandidateURLs(email: normalized, name: name, api: api)
        resolvedURLs[normalized] = urls
    }

    private func fetchCandidateURLs(email: String, name: String, api: TodosAPIClient) async -> [URL] {
        var urls: [URL] = []

        do {
            let input = MacAvatarInput(email: email, name: name.isEmpty ? nil : name)
            let response: MacAvatarResponse = try await api.trpcQuery("avatar.getByEmail", input: input)

            if let primary = response.primary,
               primary.source != "bimi",
               let urlString = primary.url,
               let url = URL(string: urlString),
               !urls.contains(url) {
                urls.append(url)
            }

            for fallback in response.fallbackUrls {
                if let url = URL(string: fallback), !urls.contains(url) {
                    urls.append(url)
                }
            }
        } catch {
            // Fall through to local favicon guesses.
        }

        for fallback in localFallbackURLs(for: email) where !urls.contains(fallback) {
            urls.append(fallback)
        }

        return urls
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func localFallbackURLs(for email: String) -> [URL] {
        guard let domain = domainFromEmail(email), !domain.isEmpty else { return [] }

        var hosts: [String] = [domain]
        if let root = rootDomain(from: domain), root != domain {
            hosts.append(root)
        }

        for host in Array(hosts) where !host.hasPrefix("www.") {
            hosts.append("www.\(host)")
        }

        var candidates: [URL] = []
        // Google's favicon service has the best coverage (same source Gmail uses),
        // so we prioritize it. Then apple-touch-icon (higher-res), then other fallbacks.
        for host in hosts {
            let rawURLs = [
                "https://www.google.com/s2/favicons?domain=\(host)&sz=128",
                "https://\(host)/apple-touch-icon.png",
                "https://\(host)/favicon.ico",
                "https://icons.duckduckgo.com/ip3/\(host).ico"
            ]

            for raw in rawURLs {
                if let url = URL(string: raw), !candidates.contains(url) {
                    candidates.append(url)
                }
            }
        }

        return candidates
    }

    private func domainFromEmail(_ email: String) -> String? {
        guard let atIndex = email.lastIndex(of: "@"), atIndex < email.index(before: email.endIndex) else {
            return nil
        }

        let domain = email[email.index(after: atIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        return domain.isEmpty ? nil : domain
    }

    private func rootDomain(from domain: String) -> String? {
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }

        if parts.count >= 3 {
            let tld = parts.suffix(2).joined(separator: ".")
            let commonSecondLevelTLDs: Set<String> = [
                "co.uk", "org.uk", "gov.uk", "ac.uk", "com.au", "co.jp", "com.br", "co.in"
            ]
            if commonSecondLevelTLDs.contains(tld) {
                return parts.suffix(3).joined(separator: ".")
            }
        }

        return parts.suffix(2).joined(separator: ".")
    }
}

private enum MacStableAvatarColorIndex {
    static func index(seed: String, paletteCount: Int) -> Int {
        precondition(paletteCount > 0, "paletteCount must be positive")
        var hash: Double = 0
        for unit in seed.utf16 {
            let code = Double(unit)
            let current = Int32(truncatingIfNeeded: Int64(hash))
            let shifted = current &<< 5
            let next = Double(shifted) - hash
            hash = code + next
        }
        return Int(abs(Int64(hash)) % Int64(paletteCount))
    }
}

struct MacSenderAvatarView: View {
    let email: String
    let name: String
    var size: CGFloat = 28

    @Environment(MacAppServices.self) private var services
    @State private var urlIndex = 0

    var body: some View {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = MacAvatarCache.shared.resolvedURLs[normalizedEmail] ?? []

        ZStack {
            initialsCircle

            if urlIndex < candidates.count {
                AsyncImage(url: candidates[urlIndex]) { phase in
                    switch phase {
                    case .success(let image):
                        // White background ensures transparent logos are visible
                        // and the colored initials circle doesn't bleed through.
                        Circle()
                            .fill(Color.white)
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        initialsCircle
                            .onAppear { urlIndex += 1 }
                    case .empty:
                        initialsCircle
                    @unknown default:
                        initialsCircle
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: normalizedEmail) {
            urlIndex = 0
            await MacAvatarCache.shared.resolveIfNeeded(
                email: normalizedEmail,
                name: name,
                api: services.apiClient
            )
        }
    }

    private var initialsCircle: some View {
        Text(initials)
            .font(.system(size: max(size * 0.38, 10), weight: .semibold, design: .rounded))
            .foregroundStyle(avatarForegroundColor)
            .frame(width: size, height: size)
            .background(avatarBackgroundColor, in: Circle())
    }

    private var initials: String {
        let parts = name
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first }

        if !parts.isEmpty {
            return String(parts).uppercased()
        }

        return String(email.first.map { Character(String($0).uppercased()) } ?? "?")
    }

    private var avatarPaletteIndex: Int {
        MacStableAvatarColorIndex.index(seed: email.lowercased(), paletteCount: 8)
    }

    private var avatarBackgroundColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan]
        return colors[avatarPaletteIndex].opacity(0.16)
    }

    private var avatarForegroundColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan]
        return colors[avatarPaletteIndex]
    }
}
