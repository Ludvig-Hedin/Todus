import SwiftUI

/// Email inbox view — thread list with search, unread indicators, and navigation to thread detail.
/// Desktop layout: wider rows, hover states, time formatting adapted for desktop.
struct MacEmailInboxView: View {
    @Environment(MacAppServices.self) private var services
    @State private var searchText = ""
    @State private var selectedThread: IdentifiableString? = nil
    @State private var filteredThreads: [EmailThread] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var hoveredThreadId: String? = nil

    /// Which email folder to show (inbox, drafts, sent)
    var folder: String = "inbox"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
            searchBar
                .padding(.bottom, MacTheme.spacing12)

            // Thread list
            if !services.emailService.hasConnection {
                connectPrompt
            } else if services.emailService.isLoadingThreads && filteredThreads.isEmpty {
                loadingState
            } else if filteredThreads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .task {
            await services.emailService.checkConnection()
            if services.emailService.hasConnection {
                await services.emailService.loadThreads(folder: folder, refresh: true)
            }
        }
        .onChange(of: services.emailService.threads) { recomputeFiltered() }
        .onChange(of: searchText) {
            recomputeFiltered()
            debounceServerSearch()
        }
        .onAppear { recomputeFiltered() }
        .sheet(item: $selectedThread) { thread in
            MacEmailThreadView(threadId: thread.value)
                .frame(minWidth: 560, minHeight: 400)
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
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            if services.emailService.isLoadingThreads {
                ProgressView()
                    .controlSize(.small)
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

    // MARK: - Thread List

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredThreads) { thread in
                    threadRow(thread)
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
            selectedThread = IdentifiableString(value: thread.id)
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                // Unread indicator
                Circle()
                    .fill(thread.unread ? MacTheme.accent : Color.clear)
                    .frame(width: 6, height: 6)

                // Sender avatar circle
                senderInitial(thread.from)

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

                    Text(thread.subject)
                        .font(.system(size: 12, weight: thread.unread ? .medium : .regular))
                        .foregroundStyle(MacTheme.textPrimary.opacity(0.8))
                        .lineLimit(1)

                    Text(thread.snippet)
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(hoveredThreadId == thread.id ? MacTheme.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredThreadId = hovering ? thread.id : nil
        }
    }

    private func senderInitial(_ sender: EmailSender) -> some View {
        let initial = sender.name.first.map { String($0).uppercased() } ?? "?"
        let colorIndex = abs(sender.email.hashValue) % 8
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan]

        return ZStack {
            Circle()
                .fill(colors[colorIndex].opacity(0.15))
            Text(initial)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(colors[colorIndex])
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - States

    private var connectPrompt: some View {
        VStack(spacing: MacTheme.spacing12) {
            Spacer()
            Image(systemName: "envelope")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))
            Text("Connect Gmail to see your inbox")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
            Text("Sign in to your Google account to get started.")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText)
            connectGmailButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Button that initiates Gmail OAuth connection via the backend
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
            .padding(.horizontal, MacTheme.spacing16)
            .padding(.vertical, MacTheme.spacing8)
            .background(MacTheme.accent, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
        }
        .buttonStyle(.plain)
        .padding(.top, MacTheme.spacing4)
    }

    private var loadingState: some View {
        VStack(spacing: MacTheme.spacing8) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Loading emails...")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.textSecondary)
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
            Text(searchText.isEmpty ? "No emails" : "No matching emails")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)

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
}

/// Helper for sheet presentation with String IDs
struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}
