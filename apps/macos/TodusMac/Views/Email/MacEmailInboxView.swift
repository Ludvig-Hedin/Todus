import AppKit
import CryptoKit
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
    @AppStorage("threadGroupingEnabled") private var threadGroupingEnabled = true
    @AppStorage("mac_show_unread_badge") private var showUnreadBadge = true
    @State private var searchText = ""
    @State private var selectedThreadId: String? = nil
    @State private var filteredThreads: [EmailThread] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var hoveredThreadId: String? = nil
    @State private var viewMode: MacInboxViewMode = .threads
    /// When in People mode, the currently selected sender email to show their threads
    @State private var selectedSenderEmail: String? = nil
    @State private var isConnectGmailLoading = false
    @State private var listPanelWidth: CGFloat = 300
    @State private var dragStartWidth: CGFloat = 300
    @State private var isListResizeDragging = false
    private let minPanelWidth: CGFloat = 200
    private let maxPanelWidth: CGFloat = 600

    /// Which email folder to show — matches backend FOLDERS constant.
    /// Values: "inbox", "draft", "sent", "archive", "snoozed", "spam", "bin"
    var folder: String = "inbox"
    /// Thread to open immediately on appear — used when navigating from Home.
    /// Consumed once; call `onInitialThreadConsumed` to clear the pending ID in the parent.
    var initialThreadId: String? = nil
    var onInitialThreadConsumed: (() -> Void)? = nil

    private var isBackgroundRefreshing: Bool {
        // Include reconciliation so the inline "Updating" badge stays visible while we wait
        // for the post-forceSync workflow to repopulate the backend DB — without this the
        // user sees the badge vanish but no fresh threads, looking like the refresh failed.
        (services.emailService.isLoadingThreads || services.emailService.isReconciling)
            && !services.emailService.threads.isEmpty
    }

    /// True when we have no threads to show but a sync is in flight — used to suppress the
    /// "No emails" empty-state placeholder while the backend re-sync workflow is running.
    /// Without this, a user with an empty backend DB sees "No emails" for ~30s after a
    /// trigger sync before fresh data lands, which reads as broken.
    private var isInitialSyncInFlight: Bool {
        (services.emailService.isLoadingThreads || services.emailService.isReconciling)
            && services.emailService.threads.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: thread list panel (resizable)
            leftPanel
                .frame(width: listPanelWidth)
                // Explicitly opt out of any inherited implicit animation on the
                // width — without this, the parent's `.animation(.snappy, value:
                // selectedThreadId)` modifier interpolates intermediate widths
                // and the drag visibly lags one frame behind the cursor.
                .animation(nil, value: listPanelWidth)
                .background(MacTheme.contentBackground)

            // Draggable divider
            Rectangle()
                .fill(Color.clear)
                .frame(width: 5)
                .overlay(Divider(), alignment: .center)
                .onHover { hovering in
                    guard !isListResizeDragging else { return }
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !isListResizeDragging {
                                isListResizeDragging = true
                                NSCursor.resizeLeftRight.set()
                            }
                            // translation is always relative to drag start, so adding to
                            // the captured pre-drag width gives the correct absolute value.
                            let newWidth = dragStartWidth + value.translation.width
                            let clamped = min(maxPanelWidth, max(minPanelWidth, newWidth))
                            // Force a non-animated transaction so each frame of
                            // the drag commits straight through. Without this,
                            // the implicit animations propagating from parent
                            // modifiers tween every width update for 100-200ms,
                            // which is what produced the "laggy" resize feel.
                            var txn = Transaction()
                            txn.disablesAnimations = true
                            withTransaction(txn) {
                                listPanelWidth = clamped
                            }
                        }
                        .onEnded { _ in
                            dragStartWidth = listPanelWidth
                            isListResizeDragging = false
                            NSCursor.arrow.set()
                        }
                )

            // RIGHT: thread detail, sender thread list, or placeholder
            if let threadId = selectedThreadId {
                MacEmailThreadView(threadId: threadId, onClose: {
                    withAnimation(MacTheme.Motion.fast) {
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
        .animation(MacTheme.Motion.fast, value: selectedThreadId)
        .task(id: folder) {
            services.emailService.prepareFolder(folder)
            recomputeFiltered()
            await services.emailService.ensureMailboxReady(for: folder)
        }
        .task(id: folder) {
            // Poll every 60s while this folder is visible — re-reads the backend DB so
            // newly synced threads appear without user intervention. Routine polls
            // intentionally do not call `mail.forceSync`: that mutation is destructive
            // (drops backend tables) and produced a multi-second empty-inbox window every
            // tick. The backend's continuous sync brings in new mail; pull-to-refresh and
            // the header refresh button remain the user-driven force-sync paths.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled,
                      services.emailService.hasConnection,
                      !services.emailService.isLoadingThreads,
                      !services.emailService.isReconciling
                else { continue }
                await services.emailService.loadThreads(folder: folder, refresh: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard services.emailService.hasConnection,
                  !services.emailService.isLoadingThreads,
                  !services.emailService.isReconciling
            else { return }
            // Foreground re-reads from DB only — same reasoning as the polling task.
            Task { await services.emailService.loadThreads(folder: folder, refresh: true) }
        }
        .onChange(of: services.emailService.threads) { recomputeFiltered() }
        .onChange(of: folder) {
            // The inbox view is reused across folder switches (no .id(folder)),
            // so clear the open-thread selection — otherwise the detail pane keeps
            // showing the previous folder's thread next to the new folder's list.
            selectedThreadId = nil
            selectedSenderEmail = nil
        }
        .onChange(of: searchText) {
            recomputeFiltered()
            debounceServerSearch()
        }
        .onAppear {
            syncViewModeFromPreference()
            recomputeFiltered()
            if let id = initialThreadId {
                selectedThreadId = id
                onInitialThreadConsumed?()
            }
        }
        // When the inbox is already mounted (user is on email) and a new thread
        // is requested (e.g. tapping a notification), `onAppear` won't re-fire —
        // react to the changed id directly so the thread still opens.
        .onChange(of: initialThreadId) { _, newValue in
            if let id = newValue {
                selectedThreadId = id
                onInitialThreadConsumed?()
            }
        }
        .onChange(of: viewMode) { _, newMode in
            let prefersThreads = newMode == .threads
            guard threadGroupingEnabled != prefersThreads else { return }
            threadGroupingEnabled = prefersThreads
        }
        .onChange(of: threadGroupingEnabled) { _, _ in
            syncViewModeFromPreference()
        }
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
            } else if !services.emailService.hasConnection && services.emailService.connectionCheckFailed {
                // Couldn't verify the connection (offline / timeout / server error).
                // Show a retry instead of wrongly prompting "Connect Gmail" — the user
                // may well be connected; we just couldn't confirm it.
                connectionCheckFailedState
            } else if !services.emailService.hasConnection {
                connectPrompt
            } else if isInitialSyncInFlight {
                // We have no threads yet but a sync is running — show the loading state
                // instead of "No emails" so the user knows fresh data is on its way.
                loadingState(message: "Loading \(folderTitle.lowercased())…")
            } else if services.emailService.errorMessage != nil && filteredThreads.isEmpty && !services.emailService.isLoadingThreads && !services.emailService.isReconciling {
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
                        withAnimation(MacTheme.Motion.fast) {
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
                .macClickablePointer()
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
                .macClickablePointer()
            }
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing6)
        .background(MacTheme.surfaceCard, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private var mailboxHeader: some View {
        HStack(spacing: MacTheme.spacing8) {
            Text(folderTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MacTheme.textPrimary)

            // Inline refresh indicator next to the title, not inside the search
            // bar — having it in the search bar inflated the search row's height
            // every time a sync started.
            if isBackgroundRefreshing {
                MacInlineRefreshBadge()
            }

            macViewModePicker

            Spacer()
        }
    }

    /// Threads vs People dropdown — shows the active mode label and expands into a menu
    /// for switching, matching the calendar tab pattern.
    private var macViewModePicker: some View {
        Menu {
            ForEach(MacInboxViewMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(MacTheme.Motion.fast) {
                        viewMode = mode
                        if mode == .threads { selectedSenderEmail = nil }
                    }
                } label: {
                    Label {
                        Text(mode.rawValue)
                    } icon: {
                        if mode == viewMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(viewMode.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
                if services.emailService.paginationFailed {
                    // A paginate call failed. Show an explicit retry instead of an
                    // auto-firing spinner — otherwise `.onAppear` re-fired against the
                    // same cursor on every LazyVStack rebuild, hammering the backend.
                    Button {
                        Task { await services.emailService.loadThreads(folder: folder) }
                    } label: {
                        Label("Couldn't load more — Retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(MacTheme.spacing12)
                } else if services.emailService.nextPageToken != nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(MacTheme.spacing12)
                        .onAppear {
                            // Guard against the spinner re-appearing while a paginate
                            // call is already in flight — `.onAppear` fires multiple
                            // times when LazyVStack rebuilds, which previously stacked
                            // duplicate `loadThreads` calls against the same cursor.
                            guard !services.emailService.isLoadingThreads,
                                  !services.emailService.paginationFailed else { return }
                            Task { await services.emailService.loadThreads(folder: folder) }
                        }
                }
            }
        }
    }

    private func threadRow(_ thread: EmailThread) -> some View {
        Button {
            withAnimation(MacTheme.Motion.fast) {
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

                        if showUnreadBadge && thread.unread {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 7, height: 7)
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
        .macClickablePointer()
        .onHover { hovering in
            hoveredThreadId = hovering ? thread.id : nil
        }
        .contextMenu {
            let senderDisplay = thread.from.name.isEmpty ? thread.from.email : thread.from.name
            Button {
                Self.copyToPasteboard(thread.subject)
            } label: {
                Label("Copy subject", systemImage: "text.quote")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button {
                Self.copyToPasteboard(senderDisplay)
            } label: {
                Label("Copy sender", systemImage: "person")
            }
            Button {
                Self.copyToPasteboard(thread.from.email)
            } label: {
                Label("Copy email address", systemImage: "envelope")
            }
            if !thread.snippet.isEmpty {
                Button {
                    Self.copyToPasteboard(thread.snippet)
                } label: {
                    Label("Copy preview", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button {
                withAnimation(MacTheme.Motion.fast) {
                    selectedThreadId = thread.id
                }
            } label: {
                Label("Open thread", systemImage: "tray.full")
            }
            .keyboardShortcut(.return, modifiers: [])

            let isStarred = thread.labels.contains("STARRED")
            Button {
                Task { await services.emailService.toggleStar(ids: [thread.id]) }
            } label: {
                Label(isStarred ? "Unstar" : "Star", systemImage: isStarred ? "star.slash" : "star")
            }
            .keyboardShortcut("s", modifiers: [])

            Button(thread.unread ? "Mark as read" : "Mark as unread") {
                Task {
                    if thread.unread {
                        await services.emailService.markAsRead(ids: [thread.id])
                    } else {
                        await services.emailService.markAsUnread(ids: [thread.id])
                    }
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button {
                // Close the detail pane if it's showing the thread we're archiving —
                // otherwise it keeps rendering a thread that's no longer in the list,
                // and reply/archive/delete from that stale pane act on a gone thread.
                if selectedThreadId == thread.id {
                    withAnimation(MacTheme.Motion.fast) { selectedThreadId = nil }
                }
                Task { await services.emailService.archiveThreads(ids: [thread.id]) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .keyboardShortcut("e", modifiers: .command)

            Button(role: .destructive) {
                if selectedThreadId == thread.id {
                    withAnimation(MacTheme.Motion.fast) { selectedThreadId = nil }
                }
                Task { await services.emailService.deleteThreads(ids: [thread.id]) }
            } label: {
                Label("Move to Bin", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    /// Writes a string to the system pasteboard. Centralised so every Copy
    /// menu item clears the pasteboard before writing — without the clear,
    /// older types (RTF, file URL) on the previous clipboard entry can
    /// shadow our new plain-text payload in apps that prefer richer types.
    private static func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
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
                        withAnimation(MacTheme.Motion.fast) {
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

                                    if showUnreadBadge && group.unreadCount > 0 {
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
                    .macClickablePointer()
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
                            withAnimation(MacTheme.Motion.fast) {
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

                                    if showUnreadBadge && thread.unread {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 7, height: 7)
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
                        .macClickablePointer()
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
                GmailIconView(size: 56)
                Text("Connect Gmail to see your inbox")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Sign in to your Google account to get started.")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .multilineTextAlignment(.center)
                if let err = services.emailService.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                }
                connectGmailButton
            }
            .padding(MacTheme.spacing24)
            .frame(maxWidth: 280)
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
            guard !isConnectGmailLoading else { return }
            Task { @MainActor in
                isConnectGmailLoading = true
                _ = await services.emailService.connectGmail(authService: services.authService)
                isConnectGmailLoading = false
            }
        } label: {
            HStack(spacing: 8) {
                GmailIconView(size: 20)
                if isConnectGmailLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                Text(isConnectGmailLoading ? "Connecting…" : "Connect Gmail")
            }
        }
        .buttonStyle(MacOnboardingPrimaryButtonStyle())
        .disabled(isConnectGmailLoading)
    }

    /// Shown when the connection check itself failed (network/timeout/5xx) — distinct
    /// from "no connection". Offers a retry rather than the Connect Gmail onboarding.
    private var connectionCheckFailedState: some View {
        VStack(spacing: MacTheme.spacing12) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))
            Text("Couldn't reach your mailbox")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
            Text("Check your connection and try again.")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task {
                    await services.emailService.checkConnection(force: true)
                    await services.emailService.ensureMailboxReady(for: folder)
                }
            }
            .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Task { await services.emailService.loadThreads(folder: folder, refresh: true, triggerSync: true, bypassSyncCooldown: true) }
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
                    Task { await services.emailService.loadThreads(folder: folder, refresh: true, triggerSync: true, bypassSyncCooldown: true) }
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

    private func syncViewModeFromPreference() {
        let preferredMode: MacInboxViewMode = threadGroupingEnabled ? .threads : .people
        guard viewMode != preferredMode else { return }
        viewMode = preferredMode
        if preferredMode == .threads {
            selectedSenderEmail = nil
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

// Domains of free personal email providers. Brand-favicon lookup is skipped for these —
// fetching their favicon would return the provider's own logo (Gmail's G, Outlook's O),
// not the individual sender's avatar. Gravatar handles personal addresses instead.
private let freeEmailProviderDomains: Set<String> = [
    "gmail.com", "googlemail.com",
    "outlook.com", "hotmail.com", "live.com", "msn.com",
    "yahoo.com", "yahoo.co.uk", "yahoo.fr", "yahoo.de", "yahoo.co.jp", "yahoo.com.br",
    "icloud.com", "me.com", "mac.com",
    "protonmail.com", "proton.me", "protonmail.ch",
    "zohomail.com", "zoho.com",
    "yandex.com", "yandex.ru",
    "mail.ru", "bk.ru", "inbox.ru", "list.ru",
    "gmx.com", "gmx.net", "gmx.de", "gmx.at",
    "aol.com", "aol.co.uk",
    "fastmail.com", "fastmail.fm",
    "hey.com",
    "tutanota.com", "tutamail.com",
]

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

/// Persistent avatar URL cache with TTL, last-successful memoization, and disk-backed storage.
///
/// Why persistent: avatar URL resolution is expensive (backend API + favicon HEAD requests).
/// Without persistence, every cold start re-resolves every sender. With it, we hit zero
/// network on cold start for senders we've seen before.
///
/// PERFORMANCE NOTE (mirrors iOS): Only `resolvedURLs` is observable. `lastSuccessful`,
/// `resolvedAt`, `inFlight`, and `saveTask` are `@ObservationIgnored` so the per-row
/// `recordSuccess(...)` write fired from `AsyncImage.onAppear` does NOT invalidate every
/// email row that previously read `candidates(for:)`. Before this change every scroll-
/// induced image success caused a full inbox re-render cascade — a measured main-thread
/// hang source on macOS. Disk I/O is dispatched to a background queue so JSON encode/
/// decode never blocks the UI.
@MainActor
@Observable
final class MacAvatarCache {
    static let shared = MacAvatarCache()

    /// email → ordered list of image URLs to try, best source first.
    /// The only property that SHOULD invalidate views — new sender resolved →
    /// row picks up URL.
    var resolvedURLs: [String: [URL]] = [:]

    /// email → URL that successfully rendered last time. Tried first on next render.
    @ObservationIgnored private var lastSuccessful: [String: URL] = [:]

    /// email → when this entry was resolved. Used to apply TTL.
    @ObservationIgnored private var resolvedAt: [String: Date] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []

    /// Successful resolutions stick around for 30 days.
    private static let successTTL: TimeInterval = 60 * 60 * 24 * 30

    /// Empty/failed resolutions are retried after 5 minutes — without this, a single
    /// transient backend failure would leave the avatar absent for the whole session.
    private static let emptyTTL: TimeInterval = 60 * 5

    private static let maxEntries = 5000

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var didBootstrap = false

    /// Serial background queue for all disk I/O. JSON encode/decode and atomic
    /// file writes run here, never on the main thread. Mirrors the iOS impl.
    nonisolated private static let diskQueue = DispatchQueue(
        label: "com.todus.macAvatarCache.disk",
        qos: .utility
    )

    nonisolated private static let cacheFileURL: URL? = {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("sender-avatar-cache.json")
    }()

    private init() {
        // Disk hydration is deferred to `bootstrap()` — calling `loadFromDisk`
        // here synchronously decodes up to 5000 JSON entries on first access of
        // `MacAvatarCache.shared` (which happens during the first inbox row body
        // evaluation). That's a visible hang. `bootstrap()` is called from
        // `MacAppServices.init` so hydration happens once, off-main.
    }

    // MARK: - Public API

    /// Returns candidate URLs for an email, ordered with last-known-good URL first.
    func candidates(for email: String) -> [URL]? {
        let key = normalizedEmail(email)
        guard let urls = resolvedURLs[key] else { return nil }
        if let preferred = lastSuccessful[key],
           let idx = urls.firstIndex(of: preferred), idx > 0 {
            var reordered = urls
            reordered.remove(at: idx)
            reordered.insert(preferred, at: 0)
            return reordered
        }
        return urls
    }

    func resolveIfNeeded(email: String, name: String, api: TodosAPIClient) async {
        let key = normalizedEmail(email)
        guard !key.isEmpty, !inFlight.contains(key) else { return }

        if let when = resolvedAt[key] {
            let urls = resolvedURLs[key] ?? []
            let ttl = urls.isEmpty ? Self.emptyTTL : Self.successTTL
            if Date().timeIntervalSince(when) < ttl {
                return
            }
        }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let urls = await fetchCandidateURLs(email: key, name: name, api: api)
        resolvedURLs[key] = urls
        resolvedAt[key] = Date()
        scheduleSave()
    }

    func recordSuccess(email: String, url: URL) {
        let key = normalizedEmail(email)
        guard lastSuccessful[key] != url else { return }
        lastSuccessful[key] = url
        scheduleSave()
    }

    // MARK: - Backend fetch

    private func fetchCandidateURLs(email: String, name: String, api: TodosAPIClient) async -> [URL] {
        // Same ordering as iOS: Google contact photo → Google s2 PNG / apple-touch-icon →
        // backend fallbacks → other primaries. This guarantees a reliable PNG hits first
        // for every real domain (matching Gmail's own behavior) and avoids relying on
        // AsyncImage's failure cascade through .ico links.
        var urls: [URL] = []
        var contactPhoto: URL? = nil
        var nonGooglePrimary: URL? = nil
        var backendFallbacks: [URL] = []

        do {
            let input = MacAvatarInput(email: email, name: name.isEmpty ? nil : name)
            let response: MacAvatarResponse = try await api.trpcQuery("avatar.getByEmail", input: input)

            if let primary = response.primary,
               primary.source != "bimi",
               let urlString = primary.url,
               let url = URL(string: urlString) {
                if primary.source == "google" {
                    contactPhoto = url
                } else {
                    nonGooglePrimary = url
                }
            }

            for fallback in response.fallbackUrls {
                if let url = URL(string: fallback) {
                    backendFallbacks.append(url)
                }
            }
        } catch {
            // Backend failure → fall through to local favicon guesses. Empty-TTL ensures
            // we'll retry the backend in 5 minutes rather than waiting for a relaunch.
        }

        if let cp = contactPhoto, !urls.contains(cp) { urls.append(cp) }
        for fallback in localFallbackURLs(for: email) where !urls.contains(fallback) {
            urls.append(fallback)
        }
        if let np = nonGooglePrimary, !urls.contains(np) { urls.append(np) }
        for fallback in backendFallbacks where !urls.contains(fallback) {
            urls.append(fallback)
        }

        // .ico URLs are intentionally kept — for transactional senders (resend, kivra,
        // etc.) that ship only `/favicon.ico`, those are often the only fallback that
        // actually serves an image. The MacSenderAvatarView failure cascade advances past
        // any URL that NSImage fails to decode, so leaving them in costs nothing while
        // preventing initials-only renders for this class of senders.
        return urls
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func localFallbackURLs(for email: String) -> [URL] {
        guard let domain = domainFromEmail(email), !domain.isEmpty else { return [] }

        // For personal email providers, skip brand-favicon lookup entirely.
        if freeEmailProviderDomains.contains(domain) {
            return gravatarURL(email: email).map { [$0] } ?? []
        }

        // Root domain first for best Clearbit hit rate; then subdomain; then www. variants.
        var rootHost: String? = rootDomain(from: domain)
        if rootHost == domain { rootHost = nil }

        var hosts: [String] = []
        if let root = rootHost { hosts.append(root) }
        hosts.append(domain)
        for host in Array(hosts) where !host.hasPrefix("www.") {
            hosts.append("www.\(host)")
        }
        var seen = Set<String>()
        hosts = hosts.filter { seen.insert($0).inserted }

        var candidates: [URL] = []

        // 1. Clearbit: high-quality brand logos, returns proper 404 (not a globe).
        for host in hosts where !host.hasPrefix("www.") {
            if let url = URL(string: "https://logo.clearbit.com/\(host)?size=256") {
                candidates.append(url)
            }
        }

        // 2. Gravatar
        if let grav = gravatarURL(email: email), !candidates.contains(grav) {
            candidates.append(grav)
        }

        // 3. icon.horse and DuckDuckGo: return 404 on failure
        for host in hosts where !host.hasPrefix("www.") {
            if let url = URL(string: "https://icon.horse/icon/\(host)"), !candidates.contains(url) {
                candidates.append(url)
            }
            if let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"), !candidates.contains(url) {
                candidates.append(url)
            }
        }

        // 4. Apple touch icons + favicon.ico — broad compatibility fallbacks.
        //    Google s2 is intentionally excluded: it returns a generic globe PNG (HTTP
        //    200) for unknown domains, which AsyncImage accepts as success and displays
        //    — hiding the sender's real initials behind a meaningless globe icon.
        for host in hosts {
            let rawURLs = [
                "https://\(host)/apple-touch-icon-precomposed.png",
                "https://\(host)/apple-touch-icon.png",
                "https://\(host)/favicon.ico",
            ]
            for raw in rawURLs {
                if let url = URL(string: raw), !candidates.contains(url) {
                    candidates.append(url)
                }
            }
        }

        return candidates
    }

    /// SHA-256 Gravatar URL for the given email (CryptoKit, macOS 10.15+).
    /// `d=404` makes Gravatar return HTTP 404 when no avatar exists so NSImage sees
    /// a failure and the waterfall advances rather than showing a default image.
    private func gravatarURL(email: String) -> URL? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let hash = SHA256.hash(data: Data(normalized.utf8))
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://www.gravatar.com/avatar/\(hashString)?s=256&d=404&r=g")
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

    // MARK: - Persistence

    /// `Sendable` so the snapshot can cross from the main actor to `diskQueue` without
    /// touching the live mutable dicts on the actor.
    fileprivate struct PersistedShape: Codable, Sendable {
        let resolvedURLs: [String: [URL]]
        let lastSuccessful: [String: URL]
        let resolvedAt: [String: Date]
    }

    /// Hydrate the in-memory cache from disk. Decodes the persisted blob off
    /// the main thread, then publishes a single mutation to `resolvedURLs` so
    /// SwiftUI sees one invalidation instead of N. Idempotent — second call is
    /// a no-op. Called from `MacAppServices.init`.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        let snapshot = await withCheckedContinuation { (cont: CheckedContinuation<PersistedShape?, Never>) in
            Self.diskQueue.async {
                cont.resume(returning: Self.readFromDisk())
            }
        }

        guard let snapshot else { return }

        let now = Date()
        var validURLs: [String: [URL]] = [:]
        var validAt: [String: Date] = [:]
        for (email, when) in snapshot.resolvedAt {
            let urls = snapshot.resolvedURLs[email] ?? []
            let ttl = urls.isEmpty ? Self.emptyTTL : Self.successTTL
            if now.timeIntervalSince(when) < ttl {
                validURLs[email] = urls
                validAt[email] = when
            }
        }

        // Single observable write so SwiftUI rerenders only once for the whole hydration.
        resolvedURLs = validURLs
        resolvedAt = validAt
        lastSuccessful = snapshot.lastSuccessful.filter { validURLs[$0.key] != nil }
    }

    private func scheduleSave() {
        dirty = true
        // Reuse the in-flight debounce window instead of cancelling +
        // reallocating — a busy inbox refresh fires `scheduleSave()` ~100 times
        // per second and the cancel-and-recreate pattern produced unbounded
        // Task churn on the main actor.
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            guard self.dirty else { return }
            self.dirty = false
            self.persistOffMain()
        }
    }

    /// Capture an in-memory snapshot on main, hand it off to `diskQueue` for
    /// the expensive JSON encode + atomic write. The trim step mutates the
    /// live dicts (so the cap is enforced) but only does cheap dictionary work
    /// on main.
    private func persistOffMain() {
        if resolvedURLs.count > Self.maxEntries {
            let sorted = resolvedAt.sorted { $0.value < $1.value }
            let toDrop = sorted.prefix(resolvedURLs.count - Self.maxEntries)
            for (key, _) in toDrop {
                resolvedURLs.removeValue(forKey: key)
                resolvedAt.removeValue(forKey: key)
                lastSuccessful.removeValue(forKey: key)
            }
        }

        let snapshot = PersistedShape(
            resolvedURLs: resolvedURLs,
            lastSuccessful: lastSuccessful,
            resolvedAt: resolvedAt
        )
        Self.diskQueue.async {
            Self.writeToDisk(snapshot)
        }
    }

    /// Background-queue helpers. Both run off the main thread.
    nonisolated private static func readFromDisk() -> PersistedShape? {
        guard let url = Self.cacheFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedShape.self, from: data)
    }

    nonisolated private static func writeToDisk(_ snapshot: PersistedShape) {
        guard let fileURL = Self.cacheFileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
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

        if let spec = MacSenderIconRegistry.icon(for: normalizedEmail) {
            // Bundled brand icon — instant, zero network, no flash, crisp at any scale.
            // SVG path → brand-color circle + tinted glyph.
            // No SVG (letter-only registry entry) → fall through to the neutral
            // initialsCircle below so the avatar reads as a generic initial rather
            // than a loud brand-colored letter.
            if let slug = spec.slug {
                ZStack {
                    Circle().fill(spec.background)
                    Image("sender-icon-\(slug)")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(spec.foreground)
                        .padding(size * 0.25)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialsCircle
            }
        } else {
            let candidates = MacAvatarCache.shared.candidates(for: normalizedEmail) ?? []
            Group {
                if urlIndex < candidates.count {
                    let currentURL = candidates[urlIndex]
                    AsyncImage(url: currentURL, transaction: Transaction(animation: nil)) { phase in
                        switch phase {
                        case .success(let image):
                            // Person photos (Google contacts, Gravatar) fill edge-to-edge.
                            // Brand logos (Clearbit, favicon) are fitted with padding on
                            // a neutral background so transparent-edge logos don't bleed
                            // a ring into the UI.
                            let isPhoto = Self.isPersonPhoto(currentURL)
                            ZStack {
                                Circle().fill(isPhoto ? .clear : Color(NSColor.windowBackgroundColor))
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: isPhoto ? .fill : .fit)
                                    .padding(isPhoto ? 0 : size * 0.10)
                            }
                            .onAppear {
                                MacAvatarCache.shared.recordSuccess(email: normalizedEmail, url: currentURL)
                            }
                        case .failure:
                            initialsCircle
                                .onAppear {
                                    if urlIndex < candidates.count {
                                        urlIndex += 1
                                    }
                                }
                        case .empty:
                            initialsCircle
                        @unknown default:
                            initialsCircle
                        }
                    }
                    .id(currentURL)
                } else {
                    initialsCircle
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
            .onChange(of: candidates.count) { _, newCount in
                if urlIndex >= newCount && newCount > 0 {
                    urlIndex = 0
                }
            }
        }
    }

    /// True for real person photos (Google profile photos, Gravatar).
    /// These render full-bleed. All other sources are fitted with padding to prevent
    /// transparent-edge artifacts.
    private static func isPersonPhoto(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.hasSuffix("googleusercontent.com") || host.hasSuffix("gravatar.com")
    }

    /// Neutral muted avatar — gray circle + white initials.
    /// Matches Notion Mail's restrained style: no rotating colors, no per-sender
    /// brand color noise. Saves visual saturation budget for real brand icons.
    private var initialsCircle: some View {
        Text(initials)
            .font(.system(size: max(size * 0.42, 10), weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(MacTheme.mutedAvatarFill, in: Circle())
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
}
