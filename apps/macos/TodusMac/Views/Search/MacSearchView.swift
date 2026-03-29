import SwiftUI
import SwiftData

/// Search modal that shows recommended/recent items before any query is typed,
/// and filters tasks + emails as the user types.
struct MacSearchView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskRecord> { !$0.completed },
           sort: \TaskRecord.createdAt, order: .reverse) private var tasks: [TaskRecord]

    @State private var searchText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with search field
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)

                TextField("Search tasks, emails, events...", text: $searchText)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .focused($isFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }

                Button("Done") { dismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(MacTheme.spacing16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.spacing16) {
                    if searchText.isEmpty {
                        recommendedContent
                    } else {
                        searchResults
                    }
                }
                .padding(MacTheme.spacing16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { isFocused = true }
    }

    // MARK: - Recommended Content (before query)

    private var recommendedContent: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            // Recent tasks
            if !tasks.isEmpty {
                searchSection(title: "RECENT TASKS", icon: "checkmark.square") {
                    ForEach(tasks.prefix(4)) { task in
                        searchRow(
                            icon: task.status.systemImage,
                            iconColor: task.status.tintColor,
                            title: task.title,
                            subtitle: task.dueDate.map { "Due \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "No due date",
                            type: "Task"
                        )
                    }
                }
            }

            // Recent emails
            if !services.emailService.threads.isEmpty {
                searchSection(title: "RECENT EMAILS", icon: "envelope") {
                    ForEach(services.emailService.threads.prefix(3)) { thread in
                        searchRow(
                            icon: thread.unread ? "envelope.badge" : "envelope.open",
                            iconColor: thread.unread ? MacTheme.accent : MacTheme.mutedText,
                            title: thread.subject,
                            subtitle: "From \(thread.from.name)",
                            type: "Email"
                        )
                    }
                }
            }

            // Quick actions
            searchSection(title: "QUICK ACTIONS", icon: "bolt") {
                searchRow(icon: "plus.circle", iconColor: MacTheme.accent, title: "Create a new task", subtitle: "Add to your task list", type: "Action")
                searchRow(icon: "envelope", iconColor: .blue, title: "Compose email", subtitle: "Write a new message", type: "Action")
                searchRow(icon: "calendar.badge.plus", iconColor: .orange, title: "New event", subtitle: "Add to your calendar", type: "Action")
            }

            if tasks.isEmpty && services.emailService.threads.isEmpty {
                VStack(spacing: MacTheme.spacing8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MacTheme.mutedText.opacity(0.5))
                    Text("Start typing to search")
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, MacTheme.spacing24)
            }
        }
    }

    // MARK: - Search Results

    private var searchResults: some View {
        let query = searchText.lowercased()
        let matchingTasks = tasks.filter {
            $0.title.lowercased().contains(query) ||
            $0.taskDescription.lowercased().contains(query)
        }
        let matchingEmails = services.emailService.threads.filter {
            $0.subject.lowercased().contains(query) ||
            $0.from.name.lowercased().contains(query) ||
            $0.snippet.lowercased().contains(query)
        }

        return VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            if !matchingTasks.isEmpty {
                searchSection(title: "TASKS", icon: "checkmark.square") {
                    ForEach(matchingTasks.prefix(5)) { task in
                        searchRow(
                            icon: task.status.systemImage,
                            iconColor: task.status.tintColor,
                            title: task.title,
                            subtitle: task.dueDate.map { "Due \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "No due date",
                            type: "Task"
                        )
                    }
                }
            }

            if !matchingEmails.isEmpty {
                searchSection(title: "EMAILS", icon: "envelope") {
                    ForEach(matchingEmails.prefix(5)) { thread in
                        searchRow(
                            icon: thread.unread ? "envelope.badge" : "envelope.open",
                            iconColor: thread.unread ? MacTheme.accent : MacTheme.mutedText,
                            title: thread.subject,
                            subtitle: "From \(thread.from.name)",
                            type: "Email"
                        )
                    }
                }
            }

            if matchingTasks.isEmpty && matchingEmails.isEmpty {
                VStack(spacing: MacTheme.spacing8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MacTheme.mutedText.opacity(0.5))
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, MacTheme.spacing24)
            }
        }
    }

    // MARK: - Components

    private func searchSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing6) {
            HStack(spacing: MacTheme.spacing4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                Text(title)
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .tracking(0.8)
            }

            VStack(spacing: 1) {
                content()
            }
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func searchRow(icon: String, iconColor: Color, title: String, subtitle: String, type: String) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(type)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius))
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing8)
    }
}
