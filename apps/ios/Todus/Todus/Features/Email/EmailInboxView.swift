import SwiftUI

/// Email inbox — thread list with search, pull-to-refresh, and swipe actions.
struct EmailInboxView: View {
    @Environment(AppServices.self) private var services

    @State private var searchText = ""
    @State private var selectedThreadId: String?

    private var emailService: EmailService { services.emailService }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            if !emailService.hasConnection {
                EmailConnectView()
            } else if emailService.threads.isEmpty && !emailService.isLoadingThreads {
                emptyState
            } else {
                threadList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await emailService.checkConnection()
            if emailService.hasConnection {
                await emailService.loadThreads(refresh: true)
            }
        }
        .navigationDestination(item: $selectedThreadId) { threadId in
            EmailThreadView(threadId: threadId)
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inbox")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Search bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Thread list
            List {
                ForEach(filteredThreads) { thread in
                    EmailRowView(thread: thread)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .onTapGesture {
                            selectedThreadId = thread.id
                        }
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

                // Load more trigger
                if emailService.nextPageToken != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .onAppear {
                            Task { await emailService.loadThreads() }
                        }
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
            // Extra bottom padding so content isn't hidden behind custom tab bar
            .contentMargins(.bottom, 90, for: .scrollContent)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)

            TextField("Search emails\u{2026}", text: $searchText)
                .font(.system(size: 14, weight: .medium))
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
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            AppTheme.surfaceSecondary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.mutedText)

            Text("No emails yet")
                .font(.system(size: 18, weight: .semibold))

            Text("Pull down to refresh")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.subtleText)
        }
    }

    // MARK: - Filtering

    /// Client-side filter while user is typing (before submit triggers server search)
    private var filteredThreads: [EmailThread] {
        if searchText.isEmpty {
            return emailService.threads
        }
        let query = searchText.lowercased()
        return emailService.threads.filter {
            $0.subject.lowercased().contains(query)
            || $0.from.name.lowercased().contains(query)
            || $0.from.email.lowercased().contains(query)
            || $0.snippet.lowercased().contains(query)
        }
    }
}
