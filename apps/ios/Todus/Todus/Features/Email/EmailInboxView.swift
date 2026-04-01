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

    /// Primary folders shown before the divider in the picker
    var isPrimary: Bool {
        switch self {
        case .inbox, .drafts, .sent: true
        default: false
        }
    }
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

    // Deterministic skeleton widths — computed once to avoid visual jitter from CGFloat.random in view body
    private static let skeletonNameWidths: [CGFloat]    = [120, 140, 130, 155, 125, 145]
    private static let skeletonSnippetWidths: [CGFloat] = [180, 200, 195, 215, 185, 205]

    private var emailService: EmailService { services.emailService }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            if !emailService.hasConnection {
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
            HStack(spacing: 6) {
                // Folder picker — tapping the title opens a menu to switch folders
                Menu {
                    // Primary folders
                    ForEach(EmailFolder.allCases.filter(\.isPrimary), id: \.rawValue) { folder in
                        Button {
                            selectedFolder = folder
                        } label: {
                            Label(folder.title, systemImage: folder.systemImage)
                        }
                    }
                    Divider()
                    // Secondary folders
                    ForEach(EmailFolder.allCases.filter { !$0.isPrimary }, id: \.rawValue) { folder in
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

                if emailService.isLoadingThreads {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            // Search bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // Inline searching indicator — shown when a search query is active and results are loading
            if !searchText.isEmpty && emailService.isLoadingThreads {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Searching\u{2026}")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            if services.assistantAutomationPolicy.assistantThreadActionsVisible &&
                !emailService.assistantNudges.isEmpty &&
                searchText.isEmpty {
                assistantNudgesStrip
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Divider().foregroundStyle(AppTheme.divider)

            // Thread list
            List {
                ForEach(filteredThreads) { thread in
                    EmailRowView(thread: thread)
                        .listRowInsets(EdgeInsets())
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
                        // Load next page — pass current folder so pagination stays in the right mailbox
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
    }

    private var assistantNudgesStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mail Assistant")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.purple)
                .textCase(.uppercase)

            ForEach(emailService.assistantNudges.prefix(3)) { nudge in
                Button {
                    if let firstThreadId = nudge.threadIds.first {
                        selectedThreadId = firstThreadId
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nudge.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(nudge.description)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.mutedText)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Text("\(nudge.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.65), in: Capsule(style: .continuous))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
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

    // MARK: - Loading State

    /// Shown on first load when threads haven't arrived yet — skeleton prevents confusing empty flash
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
                    Text("\(selectedFolder.title) is empty")
                        .font(.system(size: 17, weight: .semibold))
                    if selectedFolder == .inbox {
                        Text("You're all caught up.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.subtleText)
                    }
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
