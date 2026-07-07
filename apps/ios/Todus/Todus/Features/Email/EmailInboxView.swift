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
    @Environment(\.scenePhase) private var scenePhase

    @State private var searchText = ""
    @State private var selectedThreadId: String?
    @State private var filteredThreads: [EmailThread] = []
    /// The query for which `emailService.threads` currently holds *server* search
    /// results. Set once a debounced server search resolves for the active
    /// `searchText`, cleared on every keystroke. While set and equal to the query,
    /// `recomputeFilteredThreads` trusts the server's matches as-is instead of
    /// re-filtering locally against the subject/from/snippet blob — which would
    /// drop body-only matches the server found (the "0 results despite hits" bug).
    @State private var serverSearchQuery: String?
    /// Cached sender grouping for the People view. Recomputed only when `filteredThreads`
    /// changes — previously the computed property rebuilt the entire group-by + sort on
    /// every body evaluation, including when the user was in Threads mode.
    @State private var cachedSenderGroups: [SenderGroup] = []
    /// Precomputed lowercased search blob per thread (`subject + name + email + snippet`),
    /// rebuilt once whenever `emailService.threads` changes. `recomputeFilteredThreads`
    /// then matches against this instead of lowercasing four fields × every thread on
    /// every keystroke — search was previously O(threads × 4 lowercasings) per character.
    @State private var searchBlobs: [String: String] = [:]
    /// Debounce task for server-side search — cancelled on each new keystroke.
    @State private var searchDebounceTask: Task<Void, Never>?
    /// Active in-flight search Task. Held separately so a stale request can be cancelled
    /// before its results are applied, even if the debounce wrapper has already fired.
    @State private var searchTask: Task<Void, Never>?
    /// Active folder — defaults to inbox, switchable via the folder menu in the header
    @State private var selectedFolder: EmailFolder = .inbox
    /// View mode — threads (default) or people (grouped by sender)
    @State private var viewMode: InboxViewMode = .threads
    /// Selected sender when in People view mode — uses SenderDestination to disambiguate from thread navigation
    @State private var selectedSender: SenderDestination?
    /// Thread queued for delete confirmation. Setting this presents the confirmation dialog.
    @State private var pendingDeleteThread: EmailThread?
    /// True after a pagination request fails so we can show a tap-to-retry CTA instead of an
    /// indefinite spinner. Reset whenever a new pagination attempt starts.
    @State private var paginationFailed = false
    /// Guards the pagination retry button + onAppear trigger so rapid taps or
    /// re-renders don't fire concurrent `loadNextPage()` calls that re-fetch
    /// the same cursor.
    @State private var isLoadingNextPage = false
    /// True after the connection check has been spinning for too long with no resolution —
    /// switches the loading state to a softer "Still checking…" message and offers recovery.
    @State private var connectionCheckTimedOut = false
    /// Last visible thread ID, captured so we can restore scroll position after switching
    /// between People view and Threads view (or returning from a thread detail).
    @State private var lastVisibleId: String?
    @Environment(\.modelContext) private var modelContext
    @State private var threadAwaitingFolderPick: EmailThread?
    /// Tracks the search field focus so we can show a blur button when active.
    @FocusState private var searchFieldFocused: Bool

    @State private var emailHeaderHeight: CGFloat = 120
    private let emailScrimTail: CGFloat = 32
    /// Holds the delayed push triggered by `consumePendingThreadNavigation` so a
    /// new invocation or `.onDisappear` can cancel it. Without this, a
    /// `DispatchQueue.main.asyncAfter` could fire after the inbox has already
    /// disappeared and re-push a thread that the user navigated away from.
    @State private var pendingThreadNavTask: Task<Void, Never>?

    /// UI-level wallclock cap on the inline "Updating" badge. The service already bounds
    /// its loading/reconciling state via timeouts and a watchdog, but a defensive cap here
    /// guarantees the badge can never linger past this ceiling even if a future regression
    /// re-introduces a stuck-state path. Tripped by the watchdog task below.
    @State private var badgeForciblyHidden = false
    private static let badgeMaxVisibleSeconds: Double = 90

    // Deterministic skeleton widths — computed once to avoid visual jitter from CGFloat.random in view body
    private static let skeletonNameWidths: [CGFloat]    = [120, 140, 130, 155, 125, 145]
    private static let skeletonSnippetWidths: [CGFloat] = [180, 200, 195, 215, 185, 205]

    private var emailService: EmailService { services.emailService }
    private var connectionsService: ConnectionsService { services.connectionsService }
    private var primaryFolders: [EmailFolder] { EmailFolder.allCases.filter(\.isPrimary) }
    private var secondaryFolders: [EmailFolder] { EmailFolder.allCases.filter { !$0.isPrimary } }
    /// True while a refresh is happening on top of an already-populated inbox — drives the
    /// inline "Updating" badge in the header. Includes the background reconciliation task
    /// (the post-forceSync poll) so the user sees a live indicator while we're still waiting
    /// for the server to surface fresh threads, instead of an empty stretch followed by a
    /// surprise update.
    private var isBackgroundRefreshing: Bool {
        (emailService.isLoadingThreads || emailService.isReconciling)
            && !emailService.threads.isEmpty
            && !badgeForciblyHidden
    }

    /// Raw signal from the service — used by the badge watchdog so it can detect the
    /// "service still claims it's loading" condition independently of the UI cap above.
    private var serviceIsRefreshing: Bool {
        (emailService.isLoadingThreads || emailService.isReconciling)
            && !emailService.threads.isEmpty
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            // Until the connection check resolves, never show the Connect Gmail screen — even
            // a single frame of "Connect Gmail" while we're actually connected is jarring.
            // We also keep the loading state if we already have cached threads so the inbox
            // doesn't visually empty out while a background re-check runs.
            if !emailService.hasResolvedConnection && !connectionCheckTimedOut {
                if !emailService.threads.isEmpty {
                    threadList
                } else {
                    loadingState
                        .task {
                            // If the connection check hangs for more than 10s, flip into a recoverable
                            // state so the user isn't stuck staring at a skeleton forever.
                            try? await Task.sleep(for: .seconds(10))
                            if !emailService.hasResolvedConnection {
                                connectionCheckTimedOut = true
                            }
                        }
                }
            } else if connectionCheckTimedOut && !emailService.hasResolvedConnection {
                connectionTimeoutState
            } else if !emailService.hasConnection {
                VStack(spacing: 0) {
                    AppTopHeader(title: "Mail")
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    EmailConnectView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
            } else if (emailService.isLoadingThreads || emailService.isReconciling) && emailService.threads.isEmpty {
                // First load OR post-forceSync reconciliation — show skeleton rather than
                // the empty state. Without including isReconciling, a fresh-DB user briefly
                // sees the empty placeholder before the workflow repopulates threads.
                loadingState
            } else if emailService.errorMessage != nil && emailService.threads.isEmpty && !emailService.isLoadingThreads && !emailService.isReconciling {
                // Load failed and no cached threads to show — surface the error
                errorState
            } else if emailService.threads.isEmpty && !emailService.isLoadingThreads && !emailService.isReconciling {
                emptyState
            } else {
                threadList
            }
        }
        .animation(.easeInOut(duration: 0.18), value: emailService.hasResolvedConnection)
        .animation(.easeInOut(duration: 0.18), value: emailService.hasConnection)
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
        .task {
            // Poll every 60s while the inbox is visible — re-reads the backend DB so freshly
            // synced threads appear without user intervention. Routine polls intentionally
            // do **not** call `mail.forceSync`: that mutation drops the backend tables and
            // kicks an async workflow, producing a multi-second empty-inbox window every
            // tick. The backend's continuous sync brings in new mail; pull-to-refresh and
            // the header refresh button remain the user-driven force-sync paths.
            // Skip a tick if a refresh or reconciliation is already running so we don't pile
            // up concurrent loads.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled,
                      emailService.hasConnection,
                      !emailService.isLoadingThreads,
                      !emailService.isReconciling
                else { continue }
                // Routine polling tick — pass `triggerSync: true` so the backend's
                // soft-sync path (non-destructive: upserts newest 20 thread IDs from
                // Gmail) runs. Without this, users whose continuous sync has stalled
                // see month-old mail with no recovery short of an explicit
                // pull-to-refresh. The 2-minute cooldown still coalesces calls so
                // this tick can't flood the backend.
                await emailService.loadThreads(
                    folder: selectedFolder.rawValue,
                    refresh: true,
                    triggerSync: true
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active,
                  emailService.hasConnection,
                  !emailService.isLoadingThreads,
                  !emailService.isReconciling
            else { return }
            // Re-foreground triggers a soft sync — user expects to see new mail on
            // open, not a stale snapshot from last launch. Cooldown still applies so
            // back-to-back open/close doesn't flood the backend.
            Task {
                await emailService.loadThreads(
                    folder: selectedFolder.rawValue,
                    refresh: true,
                    triggerSync: true
                )
            }
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
        .sheet(item: $threadAwaitingFolderPick) { thread in
            FolderPickerSheet(title: "Add Email") { folder in
                services.captureService.addItemToFolder(
                    kind: .email,
                    itemId: thread.id,
                    title: thread.subject,
                    subtitle: thread.from.name.isEmpty ? thread.from.email : thread.from.name,
                    folder: folder,
                    in: modelContext
                )
            }
            .appSheetBackground()
        }
        .onAppear {
            syncViewModeFromPreference()
            rebuildSearchBlobs()
            recomputeFilteredThreads()
            consumePendingThreadNavigation()
            consumePendingSearchSeed()
        }
        .onChange(of: services.pendingEmailSearchQuery) { _, _ in
            consumePendingSearchSeed()
        }
        .onDisappear {
            // Cancel any pending deep-navigation push so it can't fire after the
            // inbox is offscreen and re-push a thread we've already navigated away from.
            pendingThreadNavTask?.cancel()
            pendingThreadNavTask = nil
        }
        .onChange(of: viewMode) { _, newMode in
            let shouldGroupByThread = newMode == .threads
            if services.threadGroupingEnabled != shouldGroupByThread {
                services.threadGroupingEnabled = shouldGroupByThread
            }
            // Rebuild the People grouping the first time the user enters People mode
            // (the cache is otherwise only refilled by `recomputeFilteredThreads`).
            recomputeSenderGroupsIfPeopleMode()
        }
        .onChange(of: services.threadGroupingEnabled) { _, _ in
            syncViewModeFromPreference()
        }
        .onChange(of: emailService.threads) {
            rebuildSearchBlobs()
            recomputeFilteredThreads()
        }
        .onChange(of: emailService.hasResolvedConnection) { _, resolved in
            // Once the connection check returns, drop the timeout flag so subsequent
            // re-checks don't keep showing the timeout copy.
            if resolved { connectionCheckTimedOut = false }
        }
        // Defensive UI cap on the "Updating" badge. The service already bounds loading +
        // reconciliation state, but if any future regression leaves a stuck flag this
        // ensures the user never sees a multi-minute spinner. Reset whenever the service
        // legitimately finishes so the next refresh starts fresh.
        .onChange(of: serviceIsRefreshing) { _, refreshing in
            if !refreshing { badgeForciblyHidden = false }
        }
        .task(id: serviceIsRefreshing) {
            guard serviceIsRefreshing else { return }
            try? await Task.sleep(for: .seconds(Self.badgeMaxVisibleSeconds))
            // If the service is still claiming a refresh is in flight after the
            // wallclock budget, hide the badge — better to look idle than to look broken.
            if serviceIsRefreshing {
                badgeForciblyHidden = true
                AppLogger.shared.log(
                    "[EmailInboxView] badge wallclock cap tripped after \(Self.badgeMaxVisibleSeconds)s"
                )
            }
        }
        // Deep navigation from AI chat cards — pick up pending thread ID set by AIChatView
        .onChange(of: services.pendingEmailThreadId) { _, _ in
            consumePendingThreadNavigation()
        }
        // Header ellipsis menu actions
        .onChange(of: services.emailRefreshTick) { _, _ in
            // Header ellipsis "Refresh" — also user-explicit, bypass cooldown.
            Task {
                await emailService.loadThreads(
                    folder: selectedFolder.rawValue,
                    query: searchText.isEmpty ? nil : searchText,
                    refresh: true,
                    triggerSync: searchText.isEmpty,
                    bypassSyncCooldown: true
                )
            }
        }
        .onChange(of: services.emailMarkAllReadTick) { _, _ in
            let unreadIds = filteredThreads.filter(\.unread).map(\.id)
            guard !unreadIds.isEmpty else { return }
            Task { await emailService.markAsRead(ids: unreadIds) }
        }
        .onChange(of: searchText) { oldValue, newValue in
            // A keystroke invalidates any prior server-result set — fall back to the
            // instant local filter until the new debounced server search resolves.
            serverSearchQuery = nil
            // Instant local filtering for immediate visual feedback
            recomputeFilteredThreads()
            // Debounced server search — waits 500ms after last keystroke so we don't
            // spam the API on every character, but still search automatically. Cancel
            // both the debounce task AND the in-flight network task on each keystroke
            // so a stale slow response can't overwrite a newer fast one.
            searchDebounceTask?.cancel()
            searchTask?.cancel()
            // When the user clears the search field, `emailService.threads` is still
            // populated with the *search* result set (the previous server search call
            // overwrote it). Re-running the local filter would just leave those few
            // results visible. Re-fetch the unfiltered inbox so the user sees their
            // full inbox again instead of being stuck in search-results state.
            if newValue.isEmpty {
                if !oldValue.isEmpty {
                    Task {
                        await emailService.loadThreads(
                            folder: selectedFolder.rawValue,
                            refresh: true
                        )
                    }
                }
                return
            }
            // Skip server search if we only changed case/whitespace — the local
            // filter already covered that.
            let normalizedNew = newValue.trimmingCharacters(in: .whitespaces).lowercased()
            let normalizedOld = oldValue.trimmingCharacters(in: .whitespaces).lowercased()
            guard normalizedNew != normalizedOld else { return }
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                let task = Task {
                    guard !Task.isCancelled else { return }
                    await emailService.loadThreads(
                        folder: selectedFolder.rawValue,
                        query: searchText.isEmpty ? nil : searchText,
                        refresh: true
                    )
                }
                searchTask = task
                await task.value
            }
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        ZStack(alignment: .top) {
            // Scrollable content fills full screen; inset below the pinned header overlay.
            Group {
                if viewMode == .people {
                    peopleListView
                } else {
                    threadListContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: emailHeaderHeight + emailScrimTail)
            }

            // Pinned header overlay with transparent scrim — content scrolls under it.
            VStack(spacing: 0) {
                inboxHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                folderAndSearchRow
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                if connectionsService.hasMultipleConnections {
                    connectionFilterChips
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                if !searchText.isEmpty {
                    searchFeedbackRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                emailHeaderHeight = height
            }
            .pageHeaderScrim(scrimHeight: emailHeaderHeight + emailScrimTail)
        }
    }

    /// Top header — page name "Mail" with the threads/people view-mode dropdown
    /// to its right, mirroring the calendar tab pattern.
    private var inboxHeader: some View {
        AppTopHeader(title: "Mail") {
            HStack(spacing: 8) {
                Text("Mail")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(.primary)

                viewModeDropdown

                if isBackgroundRefreshing {
                    InlineRefreshBadge()
                }
            }
        }
    }

    /// Folder picker dropdown + search bar on the same row.
    private var folderAndSearchRow: some View {
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
                    Text(selectedFolder.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    if #available(iOS 26.0, *) {
                        // Pure `.glassEffect` alone reads as non-interactive chrome
                        // (no visible fill/border) — unlike the search bar next to it,
                        // this is a Menu, so it needs to look tappable. Add a faint
                        // capsule tint underneath the glass so it reads as a control.
                        Capsule(style: .continuous)
                            .fill(AppTheme.surfaceSecondary.opacity(0.35))
                    } else {
                        Capsule(style: .continuous)
                            .fill(AppTheme.surfaceSecondary.opacity(0.6))
                            .overlay(Capsule(style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 0.5))
                    }
                }
                .modifier(SearchBarGlassModifier())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)

            searchBar
        }
    }

    // MARK: - Thread List Content (extracted from threadList)

    private var threadListContent: some View {
        ScrollViewReader { proxy in
            List {
                // AI nudges section at the top
                if services.assistantAutomationPolicy.assistantThreadActionsVisible &&
                   !emailService.assistantNudges.isEmpty && searchText.isEmpty {
                    assistantNudgesInList
                }

                ForEach(filteredThreads) { thread in
                    inboxThreadRow(thread)
                }

                if emailService.nextPageToken != nil {
                    paginationFooter
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                let delta = new - old
                if delta > 8 && new > 40 {
                    withAnimation(.easeOut(duration: 0.2)) { services.hideTabBar = true }
                } else if delta < -8 {
                    withAnimation(.easeOut(duration: 0.2)) { services.hideTabBar = false }
                }
            }
            // Prefetch next page when 80% scrolled — loads ahead of the visible footer
            // so there's no spinner stall when the user reaches the bottom.
            .onScrollGeometryChange(for: Bool.self) { geo in
                let visibleBottom = geo.contentOffset.y + geo.containerSize.height
                let contentHeight = geo.contentSize.height
                return contentHeight > 200 && visibleBottom >= contentHeight * 0.80
            } action: { _, nearBottom in
                if nearBottom, emailService.nextPageToken != nil, !isLoadingNextPage, !paginationFailed {
                    Task { await loadNextPage() }
                }
            }
            .refreshable {
                // Clear any latched badge cap from a previous refresh — without
                // this the inline "Updating" badge can stay hidden across the
                // next refresh and the user gets no progress signal.
                badgeForciblyHidden = false
                // Pull-to-refresh is an explicit user request — bypass the forceSync
                // cooldown so we always pull fresh data from Gmail, regardless of how
                // recently the 60s polling tick fired.
                await emailService.loadThreads(
                    folder: selectedFolder.rawValue,
                    query: searchText.isEmpty ? nil : searchText,
                    refresh: true,
                    triggerSync: searchText.isEmpty,
                    bypassSyncCooldown: true
                )
                // Tactile confirmation that the refresh completed — closes the
                // feedback loop on the pull gesture, which otherwise just snaps
                // back silently. Done here (after the await) so the haptic only
                // fires once the network call resolved.
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .contentMargins(.bottom, 130, for: .scrollContent)
            // Confirm before destructive delete — archive remains unconfirmed (it's reversible).
            .confirmationDialog(
                "Delete this conversation?",
                isPresented: Binding(
                    get: { pendingDeleteThread != nil },
                    set: { if !$0 { pendingDeleteThread = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteThread
            ) { thread in
                Button("Delete", role: .destructive) {
                    let id = thread.id
                    pendingDeleteThread = nil
                    Task { await emailService.deleteThreads(ids: [id]) }
                }
                Button("Cancel", role: .cancel) { pendingDeleteThread = nil }
            } message: { thread in
                Text("\"\(thread.subject)\" will be moved to Trash.")
            }
            .onAppear {
                // Restore scroll anchor when returning from a thread or switching view modes
                if let id = lastVisibleId, filteredThreads.contains(where: { $0.id == id }) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    /// Pagination footer — shows a spinner while loading the next page, or a tap-to-retry CTA
    /// if the previous attempt errored. Triggers the next-page fetch on appear.
    @ViewBuilder
    private var paginationFooter: some View {
        Group {
            if paginationFailed {
                Button {
                    // Re-check in-flight state at tap time, not just via `.disabled` —
                    // SwiftUI's re-render that flips the disabled state lags a frame
                    // behind a rapid double-tap, so guard here too. `loadNextPage()`
                    // itself also re-checks, but bailing before flipping
                    // `paginationFailed` avoids a visible flicker back to the spinner
                    // state on the redundant tap.
                    guard !isLoadingNextPage else { return }
                    paginationFailed = false
                    Task { await loadNextPage() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isLoadingNextPage ? "Retrying…" : "Tap to retry")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingNextPage)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .onAppear { Task { await loadNextPage() } }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Fetch the next page of threads. Detects failure by observing whether the
    /// service produced an error message during the call so we can flip into the
    /// retry footer state.
    private func loadNextPage() async {
        // Re-entry guard — multiple onAppear/retry-tap firings could otherwise
        // spawn concurrent loadThreads calls that race on the cursor.
        guard !isLoadingNextPage else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        let priorError = emailService.errorMessage
        let cursorBeforeCall = emailService.nextPageToken
        await emailService.loadThreads(
            folder: selectedFolder.rawValue,
            query: searchText.isEmpty ? nil : searchText
        )
        // Treat pagination as failed when an error surfaced during this call OR
        // when the cursor is unchanged AND no new threads landed — a stale cursor
        // would otherwise re-fetch the same page indefinitely on retry. Reset
        // the cursor on failure so the next retry starts a fresh paginated walk
        // instead of looping over the broken position.
        let didError = (emailService.errorMessage != nil)
            && (emailService.errorMessage != priorError)
        if didError {
            paginationFailed = true
            emailService.nextPageToken = nil
        } else if emailService.nextPageToken == cursorBeforeCall && cursorBeforeCall != nil {
            // No advance — backend likely returned an empty page with the same
            // cursor. Clear so the user can retry from page 1.
            paginationFailed = true
            emailService.nextPageToken = nil
        } else {
            paginationFailed = false
        }
    }

    @ViewBuilder
    private func inboxThreadRow(_ thread: EmailThread) -> some View {
        let baseRow = EmailRowView(thread: thread)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.visible)
            .listRowSeparatorTint(AppTheme.divider)
            .onTapGesture {
                lastVisibleId = thread.id
                selectedThreadId = thread.id
            }
            .contextMenu {
                Button {
                    threadAwaitingFolderPick = thread
                } label: {
                    Label("Add to folder…", systemImage: "folder.badge.plus")
                }
            }

        if services.swipeGesturesEnabled {
            baseRow
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Archive is reversible — don't paint it red with `.destructive`.
                    // Reserve the destructive role (and the system's red colour) for
                    // Delete, which is what users actually need to think twice about.
                    Button {
                        Task { await emailService.archiveThreads(ids: [thread.id]) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.orange)

                    Button(role: .destructive) {
                        pendingDeleteThread = thread
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
                        .tint(Color(UIColor.systemGray3))
                    } else {
                        Button {
                            Task { await emailService.markAsUnread(ids: [thread.id]) }
                        } label: {
                            Label("Unread", systemImage: "envelope.badge")
                        }
                        .tint(Color(UIColor.systemGray3))
                    }

                    Button {
                        Task { await emailService.toggleStar(ids: [thread.id]) }
                    } label: {
                        // Reflect current state like SenderThreadsView's row —
                        // a starred thread previously still read "Star" with a
                        // hollow icon while the action actually un-starred it.
                        Label(
                            thread.isStarredInLabels ? "Unstar" : "Star",
                            systemImage: thread.isStarredInLabels ? "star.fill" : "star"
                        )
                    }
                    .tint(.yellow)
                }
        } else {
            baseRow
        }
    }

    private func syncViewModeFromPreference() {
        let preferredMode: InboxViewMode = services.threadGroupingEnabled ? .threads : .people
        guard viewMode != preferredMode else { return }
        viewMode = preferredMode
        if preferredMode == .threads {
            selectedSender = nil
        }
    }

    // MARK: - People View

    /// Groups threads by sender email for People view (most recent activity first).
    /// Returns the @State cache; refilled by `recomputeSenderGroupsIfPeopleMode`
    /// when threads change. Avoids rebuilding the full group-by + sort tree on
    /// every body evaluation, which previously hit on every scroll-driven re-render.
    private var senderGroups: [SenderGroup] { cachedSenderGroups }

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
                                        .background(Color(UIColor.systemBlue), in: Capsule())
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
            // Mirror the threads-mode refresh: clear the latched badge cap and
            // emit a success haptic when the request resolves.
            badgeForciblyHidden = false
            await emailService.loadThreads(
                folder: selectedFolder.rawValue,
                query: searchText.isEmpty ? nil : searchText,
                refresh: true,
                triggerSync: searchText.isEmpty,
                bypassSyncCooldown: true
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .contentMargins(.bottom, 130, for: .scrollContent)
        .navigationDestination(item: $selectedSender) { destination in
            SenderThreadsView(
                senderEmail: destination.email,
                senderName: senderGroups.first(where: { $0.email == destination.email })?.name ?? destination.email,
                searchQuery: searchText
            )
        }
    }

    // MARK: - View Mode Dropdown

    /// Threads vs People dropdown — shows the active mode label, expands into a menu
    /// matching the calendar view-mode picker pattern.
    private var viewModeDropdown: some View {
        Menu {
            ForEach(InboxViewMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { viewMode = mode }
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
            HStack(spacing: 4) {
                Text(viewMode.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .tint(.primary)
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
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
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
                // "All" chip — re-enables every connection. Disabled when already
                // selected so the user doesn't get press feedback on a no-op tap;
                // toggling individual chips off is the way to narrow the filter.
                Button {
                    connectionsService.enableAll()
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
                .disabled(connectionsService.isAllEnabled)

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

    /// Truncates the search query shown in the "No results for ..." empty state so a
    /// long pasted/typed query doesn't blow out the message layout or wrap awkwardly.
    private var truncatedSearchQuery: String {
        let trimmed = searchText
        if trimmed.count > 20 {
            return "\(trimmed.prefix(20))…"
        }
        return trimmed
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
                .focused($searchFieldFocused)
                .onSubmit {
                    Task {
                        await emailService.loadThreads(
                            folder: selectedFolder.rawValue,
                            query: searchText.isEmpty ? nil : searchText,
                            refresh: true
                        )
                    }
                }

            // Show clear/blur button while focused so the user can dismiss the keyboard
            // without first emptying the field. Tapping clears any text and ends focus.
            if searchFieldFocused || !searchText.isEmpty {
                Button {
                    if !searchText.isEmpty {
                        searchText = ""
                    }
                    searchFieldFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .minTouchTarget()
                .transition(.opacity)
                .accessibilityLabel(searchText.isEmpty ? "Dismiss search" : "Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            if #available(iOS 26.0, *) {
                // glassEffect is applied via .modifier below
                Color.clear
            } else {
                Capsule(style: .continuous)
                    .fill(AppTheme.surfaceSecondary.opacity(0.6))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                    )
            }
        }
        .modifier(SearchBarGlassModifier())
        .animation(.easeInOut(duration: 0.15), value: searchFieldFocused)
    }

    private var searchFeedbackRow: some View {
        HStack(spacing: 6) {
            if emailService.isLoadingThreads {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Searching \(selectedFolder.title.lowercased())…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                // Search finished — surface the result count so the user knows
                // the in-flight indicator has resolved. Previously this row
                // always read "Searching…", which made it ambiguous whether the
                // request was still running or had simply returned a few matches.
                let count = filteredThreads.count
                Text(count == 1 ? "1 result" : "\(count) results")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading State

    /// Shown on first load when threads haven't arrived yet — skeleton prevents confusing empty flash.
    /// Uses `.frame(maxHeight: .infinity, alignment: .top)` so it fills the ZStack like threadList does
    /// (which gets full height naturally from the List inside it). Without this, the VStack centers.
    private var loadingState: some View {
        VStack(spacing: 0) {
            inboxHeader
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 4)

            folderAndSearchRow
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .disabled(true)

            Divider().foregroundStyle(AppTheme.divider)

            // Skeleton rows — visual hint that content is loading
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    // Geometry must match EmailRowView (spacing 10, 40pt avatar, vpad 11)
                    // so rows don't shift/jump when the skeleton swaps to real content.
                    HStack(spacing: 10) {
                        Circle()
                            .fill(AppTheme.surfaceSecondary)
                            .frame(width: 40, height: 40)
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
                    .padding(.vertical, 11)
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
            inboxHeader
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 4)

            folderAndSearchRow
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            Divider().foregroundStyle(AppTheme.divider)

            Spacer()
            if !searchText.isEmpty {
                // Search returned no results — offer clear action rather than Refresh
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("No results for \"\(truncatedSearchQuery)\"")
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
                            .foregroundStyle(.primary)
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
                    // Refresh CTA is only useful for folders that receive a server
                    // sync (inbox/drafts/sent/archive). Snoozed/Spam/Trash are
                    // either local-only state (Snoozed) or curated by the provider
                    // (Spam/Trash) — tapping Refresh there does nothing visible to
                    // the user and reads as a broken button.
                    if folderSupportsManualRefresh(selectedFolder) {
                        Button {
                            Task { await emailService.loadThreads(folder: selectedFolder.rawValue, refresh: true, triggerSync: true) }
                        } label: {
                            Text("Refresh")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Error State

    /// Shown when a load fails and there are no cached threads — error is real, not just "empty"
    private var errorState: some View {
        VStack(spacing: 0) {
            inboxHeader
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 4)

            folderAndSearchRow
                .padding(.horizontal, 16)
                .padding(.top, 8)
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
                    Task { await emailService.loadThreads(folder: selectedFolder.rawValue, refresh: true, triggerSync: true) }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    // MARK: - Connection Timeout State

    /// Shown when the connection check has been pending for too long. Lets the user retry
    /// or fall back to an empty/connect state instead of staring at a perpetual skeleton.
    private var connectionTimeoutState: some View {
        VStack(spacing: 0) {
            inboxHeader
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)

            Divider().foregroundStyle(AppTheme.divider)

            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppTheme.mutedText)
                Text("Still checking…")
                    .font(.system(size: 17, weight: .semibold))
                Text("This is taking longer than usual. Check your connection and try again.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.subtleText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    connectionCheckTimedOut = false
                    Task { await emailService.checkConnection(force: true) }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    // MARK: - Deep Navigation

    /// Picks up a pending thread ID set by AI chat card navigation and navigates to it.
    /// Uses a tracked Task so a rapid second invocation cancels the previous one,
    /// and so the push is dropped entirely when the inbox disappears before the
    /// delay elapses (the prior `DispatchQueue.main.asyncAfter` had no such hook
    /// and could fire after the view was gone).
    private func consumePendingThreadNavigation() {
        guard let threadId = services.pendingEmailThreadId else { return }
        services.pendingEmailThreadId = nil
        pendingThreadNavTask?.cancel()
        pendingThreadNavTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            selectedThreadId = threadId
        }
    }

    /// Picks up a search query seeded by GlobalSearchView's "See all N in Mail" row
    /// and applies it to the inbox's own search field. Setting `searchText` here
    /// flows through the existing `.onChange(of: searchText)` debounce/server-search
    /// pipeline exactly as if the user had typed it.
    private func consumePendingSearchSeed() {
        guard let seed = services.pendingEmailSearchQuery else { return }
        services.pendingEmailSearchQuery = nil
        searchText = seed
    }

    /// Whether the given folder's empty-state should expose a manual Refresh
    /// button. Snoozed/Spam/Trash never benefit from a Gmail re-sync — their
    /// contents are either local-only (Snoozed) or fully managed server-side
    /// (Spam/Trash) — so we suppress the no-op CTA there.
    private func folderSupportsManualRefresh(_ folder: EmailFolder) -> Bool {
        switch folder {
        case .snoozed, .spam, .bin: false
        default: true
        }
    }

    // MARK: - Filtering

    /// Rebuilds the per-thread lowercased search blob cache. Called once when
    /// `emailService.threads` changes (and on first appear) so per-keystroke
    /// filtering only does cheap `contains` checks against precomputed strings.
    private func rebuildSearchBlobs() {
        var blobs: [String: String] = [:]
        blobs.reserveCapacity(emailService.threads.count)
        for thread in emailService.threads {
            blobs[thread.id] = Self.searchBlob(for: thread)
        }
        searchBlobs = blobs
    }

    /// Joins the searchable fields into a single lowercased blob. A space
    /// separator prevents adjacent fields from forming spurious cross-field
    /// matches (e.g. subject ending "ab" + name starting "cd" matching "abcd").
    private static func searchBlob(for thread: EmailThread) -> String {
        [thread.subject, thread.from.name, thread.from.email, thread.snippet]
            .joined(separator: " ")
            .lowercased()
    }

    /// Looks up a thread's cached blob, falling back to computing it on the fly
    /// if the cache hasn't been populated for this id yet (defensive — keeps
    /// search correct even on the first keystroke after a thread set swap).
    private func blob(for thread: EmailThread) -> String {
        searchBlobs[thread.id] ?? Self.searchBlob(for: thread)
    }

    private func recomputeFilteredThreads() {
        guard !searchText.isEmpty else {
            filteredThreads = emailService.threads
            recomputeSenderGroupsIfPeopleMode()
            return
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            filteredThreads = emailService.threads
            recomputeSenderGroupsIfPeopleMode()
            return
        }

        // If `emailService.threads` currently holds server search results for exactly
        // this query, trust them as-is. The server matches on message bodies too, which
        // the local blob (subject/from/snippet only) doesn't have — re-filtering here
        // would drop body-only hits and show "0 results" despite real matches.
        if let sq = serverSearchQuery,
           sq.trimmingCharacters(in: .whitespaces).lowercased() == query {
            filteredThreads = emailService.threads
            recomputeSenderGroupsIfPeopleMode()
            return
        }

        // Exact contains — fast path, highest precision. Matches the precomputed
        // lowercased blob instead of re-lowercasing four fields per thread per keystroke.
        let exactMatches = emailService.threads.filter { blob(for: $0).contains(query) }
        if !exactMatches.isEmpty {
            filteredThreads = exactMatches
            recomputeSenderGroupsIfPeopleMode()
            return
        }

        // Fuzzy fallback — handles 1-char typos (e.g. "hoogle" → "google")
        // Only runs when exact search finds nothing, so no perf cost on normal queries.
        guard query.count >= 3 else {
            filteredThreads = exactMatches
            recomputeSenderGroupsIfPeopleMode()
            return
        }
        filteredThreads = emailService.threads.filter { thread in
            fuzzyContains(blob(for: thread), query: query)
        }
        recomputeSenderGroupsIfPeopleMode()
    }

    /// Rebuild the cached People grouping only when the user is actually viewing
    /// People mode. Skipping the work in Threads mode keeps inbox refreshes cheap.
    private func recomputeSenderGroupsIfPeopleMode() {
        guard viewMode == .people else {
            // Drop stale cache so the next switch into People rebuilds from current data.
            if !cachedSenderGroups.isEmpty { cachedSenderGroups = [] }
            return
        }
        cachedSenderGroups = Self.buildSenderGroups(from: filteredThreads)
    }

    /// Returns true if `text` contains `query` with at most 1 character removed.
    /// Covers the most common typos: extra char, wrong char, transposed pair.
    private func fuzzyContains(_ text: String, query: String) -> Bool {
        for i in query.indices {
            var variant = query
            variant.remove(at: i)
            if text.contains(variant) { return true }
        }
        return false
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
    @State private var pendingDeleteThread: EmailThread?
    /// Cached filtered+sorted thread list for this sender. Recomputed only when the
    /// underlying thread pool or the search query changes — previously this was a
    /// computed property that re-filtered + re-sorted the entire inbox on every
    /// body evaluation (e.g. every swipe-action render, every state change).
    @State private var cachedThreads: [EmailThread] = []

    private var emailService: EmailService { services.emailService }

    /// Matches `EmailInboxView.recomputeFilteredThreads` + sender filter so People drill-in stays consistent with search.
    private static func computeThreads(
        from threads: [EmailThread],
        senderEmail: String,
        searchQuery: String
    ) -> [EmailThread] {
        let key = senderEmail.lowercased()
        let pool: [EmailThread]
        if searchQuery.isEmpty {
            pool = threads
        } else {
            let q = searchQuery.lowercased()
            pool = threads.filter {
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

    /// Refreshes the cached list from the current service threads + query.
    private func recomputeThreads() {
        cachedThreads = Self.computeThreads(
            from: emailService.threads,
            senderEmail: senderEmail,
            searchQuery: searchQuery
        )
    }

    var body: some View {
        List {
            ForEach(cachedThreads) { thread in
                senderThreadRow(thread)
            }
        }
        .onAppear { recomputeThreads() }
        .onChange(of: emailService.threads) { recomputeThreads() }
        .onChange(of: searchQuery) { recomputeThreads() }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundTop)
        .navigationTitle(senderName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: Binding(
                get: { pendingDeleteThread != nil },
                set: { if !$0 { pendingDeleteThread = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteThread
        ) { thread in
            Button("Delete", role: .destructive) {
                let id = thread.id
                pendingDeleteThread = nil
                Task { await emailService.deleteThreads(ids: [id]) }
            }
            Button("Cancel", role: .cancel) { pendingDeleteThread = nil }
        } message: { thread in
            Text("\"\(thread.subject)\" will be moved to Trash.")
        }
        .navigationDestination(item: $selectedThreadId) { threadId in
            EmailThreadView(threadId: threadId)
        }
    }

    @ViewBuilder
    private func senderThreadRow(_ thread: EmailThread) -> some View {
        let baseRow = EmailRowView(thread: thread)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.visible)
            .listRowSeparatorTint(AppTheme.divider)
            .onTapGesture { selectedThreadId = thread.id }

        if services.swipeGesturesEnabled {
            baseRow
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Archive is reversible — keep it orange but drop the destructive
                    // role so the system doesn't tint it red on full swipe.
                    Button {
                        Task { await emailService.archiveThreads(ids: [thread.id]) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.orange)

                    Button(role: .destructive) {
                        pendingDeleteThread = thread
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
                        .tint(Color(UIColor.systemGray3))
                    } else {
                        Button {
                            Task { await emailService.markAsUnread(ids: [thread.id]) }
                        } label: {
                            Label("Unread", systemImage: "envelope.badge")
                        }
                        .tint(Color(UIColor.systemGray3))
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
        } else {
            baseRow
        }
    }
}

// MARK: - Search Bar Glass Modifier

/// Applies `.glassEffect` on iOS 26, no-op on older iOS (background already applied inline).
private struct SearchBarGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: Capsule(style: .continuous))
        } else {
            content
        }
    }
}
