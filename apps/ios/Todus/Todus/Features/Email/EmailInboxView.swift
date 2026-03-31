import SwiftUI

/// Email inbox — thread list with search, pull-to-refresh, and swipe actions.
struct EmailInboxView: View {
    @Environment(AppServices.self) private var services

    @State private var searchText = ""
    @State private var selectedThreadId: String?
    @State private var filteredThreads: [EmailThread] = []
    /// Debounce task for server-side search — cancelled on each new keystroke.
    @State private var searchDebounceTask: Task<Void, Never>?

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
            } else if emailService.threads.isEmpty && !emailService.isLoadingThreads {
                emptyState
            } else {
                threadList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await emailService.ensureInitialInboxLoaded()
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
                    query: searchText.isEmpty ? nil : searchText,
                    refresh: true
                )
            }
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        VStack(spacing: 0) {
            // Header — consistent 4pt top across all tabs
            HStack(spacing: 6) {
                AppTopHeader(title: "Inbox")
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
                        .onAppear { Task { await emailService.loadThreads() } }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await emailService.loadThreads(
                    query: searchText.isEmpty ? nil : searchText,
                    refresh: true
                )
            }
            .contentMargins(.bottom, 16, for: .scrollContent)
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
                            query: searchText.isEmpty ? nil : searchText,
                            refresh: true
                        )
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await emailService.loadThreads(refresh: true) }
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
            // Match the thread list header layout
            HStack(spacing: 6) {
                AppTopHeader(title: "Inbox")
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

    /// Shown after a successful load returns zero results — clearly "inbox is empty", not "loading"
    private var emptyState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                AppTopHeader(title: "Inbox")
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
                Image(systemName: "tray")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppTheme.mutedText)
                Text("Inbox is empty")
                    .font(.system(size: 17, weight: .semibold))
                Text("You're all caught up.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.subtleText)
                Button {
                    // Pass active search query so Refresh respects the current filter,
                    // matching the pull-to-refresh behavior in threadList
                    Task { await emailService.loadThreads(refresh: true, query: searchText.isEmpty ? nil : searchText) }
                } label: {
                    Text("Refresh")
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
