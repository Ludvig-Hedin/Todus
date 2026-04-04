import SwiftUI

// MARK: - Folder Model

/// All email folders supported by the backend — matches server FOLDERS constant.
private enum EmailFolder: String, CaseIterable {
    case inbox    = "inbox"
    case drafts   = "draft"
    case sent     = "sent"
    case archive  = "archive"
    case snoozed  = "snoozed"
    case spam     = "spam"
    case bin      = "bin"

    var title: String {
        switch self {
        case .inbox:   "Inbox"
        case .drafts:  "Drafts"
        case .sent:    "Sent"
        case .archive: "Archive"
        case .snoozed: "Snoozed"
        case .spam:    "Spam"
        case .bin:     "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox:   "tray"
        case .drafts:  "doc"
        case .sent:    "paperplane"
        case .archive: "archivebox"
        case .snoozed: "clock"
        case .spam:    "exclamationmark.triangle"
        case .bin:     "trash"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .inbox: "No emails"
        case .drafts: "No drafts"
        case .sent: "Nothing sent yet"
        case .archive: "No archived emails"
        case .snoozed: "Nothing snoozed"
        case .spam: "No spam"
        case .bin: "Trash is empty"
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .inbox: "You're all caught up."
        case .drafts: "Drafts you save will show up here."
        case .sent: "Emails you send will show up here."
        case .archive: "Archived conversations will show up here."
        case .snoozed: "Snoozed emails appear here until their snooze expires."
        case .spam: "Spam flagged by your provider will show up here."
        case .bin: "Deleted emails will show up here until they're removed."
        }
    }

    /// Primary folders shown before the divider in the picker
    var isPrimary: Bool {
        switch self {
        case .inbox, .drafts, .sent: true
        default: false
        }
    }
}

// MARK: - Inbox View Mode

/// Toggle between viewing emails as individual threads or grouped by sender.
private enum InboxViewMode: String, CaseIterable {
    case threads = "Threads"
    case people  = "People"
}

/// Wrapper to disambiguate sender navigation from thread navigation (both are String).
private struct SenderDestination: Hashable {
    let email: String
}

/// A sender with their aggregated thread info, used by the People view mode.
private struct SenderGroup: Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let threads: [EmailThread]
    let unreadCount: Int
    let latestDate: Date
}

// MARK: - EmailInboxView

/// Email inbox — thread list with folder switching, search, pull-to-refresh, and swipe actions.
struct EmailInboxView: View {
    @Environment(AppServices.self) private var services

    @State private var searchText = ""
    @State private var selectedThreadId: String?
    @State private var filteredThreads: [EmailThread] = []
    /// Debounce task for server-side search — cancelled on each new keystroke.
    @State private var searchDebounceTask: Task<Void, Never>?
    /// Active folder — defaults to inbox, switchable via the folder menu in the header
    @State private var selectedFolder: EmailFolder = .inbox
    /// View mode — threads (default) or people (grouped by sender)
    @State private var viewMode: InboxViewMode = .threads
    /// Selected sender when in People view mode — uses SenderDestination to disambiguate from thread navigation
    @State private var selectedSender: SenderDestination?

    // Deterministic skeleton widths — computed once to avoid visual jitter from CGFloat.random in view body
    private static let skeletonNameWidths: [CGFloat]    = [120, 140, 130, 155, 125, 145]
    private static let skeletonSnippetWidths: [CGFloat] = [180, 200, 195, 215, 185, 205]

    private var emailService: EmailService { services.emailService }
    private var connectionsService: ConnectionsService { services.connectionsService }
    private var primaryFolders: [EmailFolder] { EmailFolder.allCases.filter(\.isPrimary) }
    private var secondaryFolders: [EmailFolder] { EmailFolder.allCases.filter { !$0.isPrimary } }
    private var isBackgroundRefreshing: Bool {
        emailService.isLoadingThreads && !emailService.threads.isEmpty
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            if emailService.isCheckingConnection && !emailService.hasResolvedConnection {
                loadingState
            } else if !emailService.hasConnection {
                EmailConnectView()
            } else if emailService.isLoadingThreads && emailService.threads.isEmpty {
                // First load — show skeleton rather than empty state to avoid flicker
                loadingState
            } else if emailService.errorMessage != nil && emailService.threads.isEmpty && !emailService.isLoadingThreads {
                // Load failed and no cached threads to show — surface the error
                errorState
            } else if emailService.threads.isEmpty && !emailService.isLoadingThreads {
                emptyState
            } else {
                threadList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Initial load — use ensureInitialInboxLoaded for inbox (avoids double-fetch
            // if threads are already cached), load fresh for other folders
            if selectedFolder == .inbox {
                await emailService.ensureInitialInboxLoaded()
            } else {
                await emailService.loadThreads(folder: selectedFolder.rawValue, refresh: true)
            }
        }
        .task {
            // Load connections for multi-account filter chips
            await connectionsService.loadConnections()
        }
        .onChange(of: selectedFolder) { _, newFolder in
            // Clear search and cancel any pending debounce task.
            // Setting searchText="" here would normally trigger onChange(of: searchText),
            // but the debounce task is cancelled first so no redundant load fires.
            searchDebounceTask?.cancel()
            searchText = ""
            Task { await emailService.loadThreads(folder: newFolder.rawValue, refresh: true) }
        }
        .navigationDestination(item: $selectedThreadId) { threadId in
            EmailThreadView(threadId: threadId)
        }
        .onAppear {
            recomputeFilteredThreads()
            consumePendingThreadNavigation()
        }
        .onChange(of: emailService.threads) { recomputeFilteredThreads() }
        // Deep navigation from AI chat cards — pick up pending thread ID set by AIChatView
        .onChange(of: services.pendingEmailThreadId) { _, _ in
            consumePendingThreadNavigation()
        }
        .onChange(of: searchText) {
            // Instant local filtering for immediate visual feedback
            recomputeFilteredThreads()
            // Debounced server search — waits 500ms after last keystroke so we don't
            // spam the API on every character, but still search automatically.
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await emailService.loadThreads(
                    folder: selectedFolder.rawValue,
                    query: searchText.isEmpty ? nil : searchText,
                    refresh: true
                )
            }
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        VStack(spacing: 0) {
            // Header — folder title + picker menu + optional loading spinner
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Mailbox")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .textCase(.uppercase)

                    Spacer()

                    if isBackgroundRefreshing {
                        InlineRefreshBadge()
                    }

                    // View mode toggle — threads vs people
                    viewModePicker
                }

                HStack(spacing: 8) {
                    Menu {
                        ForEach(primaryFolders, id: \.rawValue) { folder in
                            Button {
                                selectedFolder = folder
                            } label: {
                                Label(folder.title, systemImage: folder.systemImage)
                            }
                        }

                        Divider()

                        ForEach(secondaryFolders, id: \.rawValue) { folder in
                            Button {
                                selectedFolder = folder
                            } label: {
                                Label(folder.title, systemImage: folder.systemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            AppTopHeader(title: selectedFolder.title)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.mutedText)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                folderQuickSwitchRow

                // Multi-account filter chips — shown only when the user has 2+ connections.
                // Each chip toggles visibility for that account's emails.
                if connectionsService.hasMultipleConnections {
                    connectionFilterChips
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            // Search bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if !searchText.isEmpty {
                searchFeedbackRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            Divider().foregroundStyle(AppTheme.divider)

            if viewMode == .people {
                // People view — senders grouped, tap to see their threads
                peopleListView
            } else {
                // Thread list — assistant nudges live inside here so they scroll away
                threadListContent
            }
        }
    }

    // MARK: - Thread List Content (extracted from threadList)

    private var threadListContent: some View {
        List {
            // AI nudges section at the top
            if services.assistantAutomationPolicy.assistantThreadActionsVisible &&
               !emailService.assistantNudges.isEmpty && searchText.isEmpty {
                assistantNudgesInList
            }

            ForEach(filteredThreads) { thread in
                EmailRowView(thread: thread)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(AppTheme.divider)
                    .onTapGesture { selectedThreadId = thread.id }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await emailService.archiveThreads(ids: [thread.id]) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)

                        Button(role: .destructive) {
                            Task { await emailService.deleteThreads(ids: [thread.id]) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if thread.unread {
                            Button {
                                Task { await emailService.markAsRead(ids: [thread.id]) }
                            } label: {
                                Label("Read", systemImage: "envelope.open")
                            }
                            .tint(.blue)
                        } else {
                            Button {
                                Task { await emailService.markAsUnread(ids: [thread.id]) }
                            } label: {
                                Label("Unread", systemImage: "envelope.badge")
                            }
                            .tint(.blue)
                        }

                        Button {
                            Task { await emailService.toggleStar(ids: [thread.id]) }
                        } label: {
                            Label("Star", systemImage: "star")
                        }
                        .tint(.yellow)
                    }
            }

            if emailService.nextPageToken != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await emailService.loadThreads(folder: selectedFolder.rawValue) } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await emailService.loadThreads(
                folder: selectedFolder.rawValue,
                query: searchText.isEmpty ? nil : searchText,
                refresh: true
            )
        }
        .contentMargins(.bottom, 16, for: .scrollContent)
    }

    // MARK: - People View

    /// Groups threads by sender email for People view (most recent activity first).
    private var senderGroups: [SenderGroup] {
        Self.buildSenderGroups(from: filteredThreads)
    }

    /// Builds `SenderGroup` rows: one per sender, with unread counts and latest thread date.
    private static func buildSenderGroups(from threads: [EmailThread]) -> [SenderGroup] {
        var grouped: [String: (name: String, threads: [EmailThread])] = [:]
        for thread in threads {
            let key = thread.from.email.lowercased()
            if var existing = grouped[key] {
                existing.threads.append(thread)
                // Prefer the longer/more descriptive name (not just an email)
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
            return SenderGroup(
                email: email,
                name: info.name,
                threads: sorted,
                unreadCount: sorted.filter(\.unread).count,
                latestDate: sorted.first?.date ?? .distantPast
            )
        }
        .sorted { $0.latestDate > $1.latestDate }
    }

    private var peopleListView: some View {
        List {
            ForEach(senderGroups) { group in
                Button {
                    selectedSender = SenderDestination(email: group.email)
                } label: {
                    HStack(spacing: 10) {
                        SenderAvatarView(email: group.email, name: group.name)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.name)
                                    .font(.system(size: 15, weight: group.unreadCount > 0 ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text("\(group.threads.count)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText)
                            }

                            HStack(spacing: 6) {
                                Text(group.threads.first?.subject ?? "")
                                    .font(.system(size: 14, weight: group.unreadCount > 0 ? .semibold : .regular))
                                    .foregroundStyle(group.unreadCount > 0 ? .primary : AppTheme.subtleText)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if group.unreadCount > 0 {
                                    Text("\(group.unreadCount)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.accentBlue, in: Capsule())
                                }
                            }

                            Text(group.email)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.visible)
                .listRowSeparatorTint(AppTheme.divider)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await emailService.loadThreads(
                folder: selectedFolder.rawValue,
                query: searchText.isEmpty ? nil : searchText,
                refresh: true
            )
        }
        .contentMargins(.bottom, 16, for: .scrollContent)
        .navigationDestination(item: $selectedSender) { destination in
            SenderThreadsView(
                senderEmail: destination.email,
                senderName: senderGroups.first(where: { $0.email == destination.email })?.name ?? destination.email,
                searchQuery: searchText
            )
        }
    }

    // MARK: - View Mode Picker

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(InboxViewMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = mode
                    }
                } label: {
                    Image(systemName: mode == .threads ? "list.bullet" : "person.2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(viewMode == mode ? AppTheme.accent : AppTheme.mutedText)
                        .frame(width: 30, height: 26)
                        .background(
                            viewMode == mode ? AppTheme.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .threads ? "Thread list" : "People by sender")
                .accessibilityAddTraits(viewMode == mode ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
    }

    /// Assistant nudges rendered as List-compatible rows. Placed inside the scrollable List
    /// so they scroll away naturally — no longer a fixed header that crops the email list.
    @ViewBuilder
    private var assistantNudgesInList: some View {
        // Section label row
        Text("ASSISTANT")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(AppTheme.mutedText)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 2, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

        // Nudge card rows
        ForEach(emailService.assistantNudges.prefix(2)) { nudge in
            Button {
                if let firstThreadId = nudge.threadIds.first {
                    selectedThreadId = firstThreadId
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nudge.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(nudge.description)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Text("\(nudge.count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppTheme.subtleText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.surfaceSecondary.opacity(0.9), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.cardBorder.opacity(0.8), lineWidth: 0.8)
                        )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.rowStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(nudge.threadIds.isEmpty)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        // Spacer row between nudges and first email
        Color.clear
            .frame(height: 6)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: - Connection Filter Chips

    /// Horizontal row of filter chips for multi-account email filtering.
    /// Each chip shows a colored dot and truncated email; tapping toggles visibility.
    private var connectionFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" chip — selects/deselects all connections at once
                Button {
                    if connectionsService.isAllEnabled {
                        // If all are enabled, tapping "All" does nothing (can't disable all)
                    } else {
                        connectionsService.enableAll()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("All")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(connectionsService.isAllEnabled ? AppTheme.accent : AppTheme.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        connectionsService.isAllEnabled ? AppTheme.accent.opacity(0.12) : AppTheme.surfaceSecondary,
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                connectionsService.isAllEnabled ? AppTheme.accent.opacity(0.20) : AppTheme.cardBorder,
                                lineWidth: 0.8
                            )
                    )
                }
                .buttonStyle(.plain)

                // Per-connection chips
                ForEach(connectionsService.connections) { connection in
                    let isEnabled = connectionsService.enabledConnectionIds.contains(connection.id)
                    Button {
                        connectionsService.toggleConnection(connection.id)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: connection.displayColor))
                                .frame(width: 8, height: 8)
                            Text(truncatedEmail(connection.email))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isEnabled ? Color(hex: connection.displayColor) : AppTheme.mutedText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isEnabled ? Color(hex: connection.displayColor).opacity(0.12) : AppTheme.surfaceSecondary,
                            in: Capsule(style: .continuous)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    isEnabled ? Color(hex: connection.displayColor).opacity(0.20) : AppTheme.cardBorder,
                                    lineWidth: 0.8
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Truncates an email address for chip display — shows the part before @ plus a short domain hint.
    /// e.g. "john.doe@gmail.com" -> "john.doe@gm..."
    private func truncatedEmail(_ email: String) -> String {
        guard let atIndex = email.firstIndex(of: "@") else { return email }
        let local = email[email.startIndex..<atIndex]
        let domain = email[email.index(after: atIndex)...]
        let shortDomain = domain.prefix(4)
        if domain.count > 4 {
            return "\(local)@\(shortDomain)..."
        }
        return email
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)

            TextField("Search…", text: $searchText)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    Task {
                        await emailService.loadThreads(
                            folder: selectedFolder.rawValue,
                            query: searchText.isEmpty ? nil : searchText,
                            refresh: true
                        )
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await emailService.loadThreads(folder: selectedFolder.rawValue, refresh: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .minTouchTarget()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Glass effect on iOS 26; subtle surface card on older iOS
        .background {
            if #available(iOS 26.0, *) {
                // glassEffect is applied below via modifier
                Color.clear
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceSecondary.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                    )
            }
        }
        .modifier(SearchBarGlassModifier())
    }

    private var folderQuickSwitchRow: some View {
        HStack(spacing: 8) {
            ForEach(primaryFolders, id: \.rawValue) { folder in
                Button {
                    selectedFolder = folder
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: folder.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(folder.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(selectedFolder == folder ? AppTheme.accent : AppTheme.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        selectedFolder == folder ? AppTheme.accent.opacity(0.12) : AppTheme.surfaceSecondary,
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                selectedFolder == folder ? AppTheme.accent.opacity(0.20) : AppTheme.cardBorder,
                                lineWidth: 0.8
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(secondaryFolders, id: \.rawValue) { folder in
                    Button {
                        selectedFolder = folder
                    } label: {
                        Label(folder.title, systemImage: folder.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("More")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(secondaryFolders.contains(selectedFolder) ? AppTheme.accent : AppTheme.mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    secondaryFolders.contains(selectedFolder) ? AppTheme.accent.opacity(0.12) : AppTheme.surfaceSecondary,
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            secondaryFolders.contains(selectedFolder) ? AppTheme.accent.opacity(0.20) : AppTheme.cardBorder,
                            lineWidth: 0.8
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private var searchFeedbackRow: some View {
        HStack(spacing: 6) {
            if emailService.isLoadingThreads && filteredThreads.isEmpty {
                ProgressView()
                    .scaleEffect(0.6)
            }

            Text(
                emailService.isLoadingThreads
                    ? "Searching \(selectedFolder.title.lowercased())…"
                    : "Filtering loaded \(selectedFolder.title.lowercased()) threads"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading State

    /// Shown on first load when threads haven't arrived yet — skeleton prevents confusing empty flash.
    /// Uses `.frame(maxHeight: .infinity, alignment: .top)` so it fills the ZStack like threadList does
    /// (which gets full height naturally from the List inside it). Without this, the VStack centers.
    private var loadingState: some View {
        VStack(spacing: 0) {
            // Match the thread list header layout — shows current folder name
            HStack(spacing: 6) {
                AppTopHeader(title: selectedFolder.title)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            // Search bar placeholder
            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .disabled(true)

            Divider().foregroundStyle(AppTheme.divider)

            // Skeleton rows — visual hint that content is loading
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(AppTheme.surfaceSecondary)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.surfaceSecondary)
                                // Use static widths to prevent jitter from random values on re-render
                                .frame(width: EmailInboxView.skeletonNameWidths[index], height: 12)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.surfaceSecondary.opacity(0.6))
                                .frame(width: EmailInboxView.skeletonSnippetWidths[index], height: 10)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    Divider().foregroundStyle(AppTheme.divider)
                }
            }
            .redacted(reason: .placeholder)
        }
        // Fill the ZStack so the content pins to the top, matching threadList's full-height behaviour
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Empty State

    /// Shown after a successful load returns zero results — clearly "folder is empty", not "loading"
    private var emptyState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                AppTopHeader(title: selectedFolder.title)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider().foregroundStyle(AppTheme.divider)

            Spacer()
            if !searchText.isEmpty {
                // Search returned no results — offer clear action rather than Refresh
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Try a different search term.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.subtleText)
                    Button {
                        searchText = ""
                        Task { await emailService.loadThreads(folder: selectedFolder.rawValue, refresh: true) }
                    } label: {
                        Text("Clear Search")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            } else {
                // Folder is genuinely empty
                VStack(spacing: 12) {
                    Image(systemName: selectedFolder.systemImage)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(AppTheme.mutedText)
                    Text(selectedFolder.emptyStateTitle)
                        .font(.system(size: 17, weight: .semibold))
                    Text(selectedFolder.emptyStateDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.subtleText)
                    Button {
                        Task { await emailService.loadThreads(folder: selectedFolder.rawValue, refresh: true) }
                    } label: {
                        Text("Refresh")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
    }

    // MARK: - Error State

    /// Shown when a load fails and there are no cached threads — error is real, not just "empty"
    private var errorState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                AppTopHeader(title: selectedFolder.title)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider().foregroundStyle(AppTheme.divider)

            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppTheme.mutedText)
                Text("Couldn't load \(selectedFolder.title)")
                    .font(.system(size: 17, weight: .semibold))
                if let errorMessage = emailService.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.subtleText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Button {
                    Task { await emailService.loadThreads(folder: selectedFolder.rawValue, refresh: true) }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    // MARK: - Deep Navigation

    /// Picks up a pending thread ID set by AI chat card navigation and navigates to it.
    private func consumePendingThreadNavigation() {
        guard let threadId = services.pendingEmailThreadId else { return }
        services.pendingEmailThreadId = nil
        // Small delay to let the tab switch and view appear before pushing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            selectedThreadId = threadId
        }
    }

    // MARK: - Filtering

    private func recomputeFilteredThreads() {
        guard !searchText.isEmpty else {
            filteredThreads = emailService.threads
            return
        }
        let query = searchText.lowercased()
        filteredThreads = emailService.threads.filter {
            $0.subject.lowercased().contains(query)
            || $0.from.name.lowercased().contains(query)
            || $0.from.email.lowercased().contains(query)
            || $0.snippet.lowercased().contains(query)
        }
    }
}

// MARK: - Sender Threads View

/// Shows all email threads from a specific sender — navigated to from the People view mode.
/// Threads are read from `EmailService` (same pool as the inbox) so archive/read/star/delete update the list live.
struct SenderThreadsView: View {
    let senderEmail: String
    let senderName: String
    /// Same query as the parent inbox search bar — empty means “all threads in current folder load”.
    let searchQuery: String

    @Environment(AppServices.self) private var services
    @State private var selectedThreadId: String?

    private var emailService: EmailService { services.emailService }

    /// Matches `EmailInboxView.recomputeFilteredThreads` + sender filter so People drill-in stays consistent with search.
    private var threadsForSender: [EmailThread] {
        let key = senderEmail.lowercased()
        let pool: [EmailThread]
        if searchQuery.isEmpty {
            pool = emailService.threads
        } else {
            let q = searchQuery.lowercased()
            pool = emailService.threads.filter {
                $0.subject.lowercased().contains(q)
                    || $0.from.name.lowercased().contains(q)
                    || $0.from.email.lowercased().contains(q)
                    || $0.snippet.lowercased().contains(q)
            }
        }
        return pool
            .filter { $0.from.email.lowercased() == key }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            ForEach(threadsForSender) { thread in
                EmailRowView(thread: thread)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(AppTheme.divider)
                    .onTapGesture { selectedThreadId = thread.id }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await emailService.archiveThreads(ids: [thread.id]) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)

                        Button(role: .destructive) {
                            Task { await emailService.deleteThreads(ids: [thread.id]) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if thread.unread {
                            Button {
                                Task { await emailService.markAsRead(ids: [thread.id]) }
                            } label: {
                                Label("Read", systemImage: "envelope.open")
                            }
                            .tint(.blue)
                        } else {
                            Button {
                                Task { await emailService.markAsUnread(ids: [thread.id]) }
                            } label: {
                                Label("Unread", systemImage: "envelope.badge")
                            }
                            .tint(.blue)
                        }

                        Button {
                            Task { await emailService.toggleStar(ids: [thread.id]) }
                        } label: {
                            Label(
                                thread.isStarredInLabels ? "Unstar" : "Star",
                                systemImage: thread.isStarredInLabels ? "star.fill" : "star"
                            )
                        }
                        .tint(.yellow)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundTop)
        .navigationTitle(senderName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedThreadId) { threadId in
            EmailThreadView(threadId: threadId)
        }
    }
}

private extension EmailThread {
    /// Gmail label convention — same check as `EmailThreadView` star state.
    var isStarredInLabels: Bool {
        labels.contains { name in
            let n = name.uppercased()
            return n == "STARRED" || n == "\\STARRED"
        }
    }
}

// MARK: - Search Bar Glass Modifier

/// Applies `.glassEffect` on iOS 26, no-op on older iOS (background already applied inline).
private struct SearchBarGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
        }
    }
}
