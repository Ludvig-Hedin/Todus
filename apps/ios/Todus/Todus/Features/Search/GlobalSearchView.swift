import SwiftUI
import SwiftData
import EventKit

/// Full-screen global search sheet — searches tasks, emails, calendar events, and people
/// from a single text field. Accessible via the magnifying glass in AppTopHeader.
struct GlobalSearchView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    // All tasks from SwiftData — filtered locally below
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var query = ""
    @State private var calendarResults: [CalendarEvent] = []
    @FocusState private var isSearchFocused: Bool
    /// Debounce handle for calendar lookups — cancelled on each keystroke so we
    /// only fetch events after the user has paused typing for ~250 ms.
    @State private var calendarSearchTask: Task<Void, Never>?

    // MARK: - Derived results (all local — no extra network calls)

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var taskResults: [TaskRecord] {
        guard !trimmedQuery.isEmpty else { return [] }
        let q = trimmedQuery.lowercased()
        return allTasks.filter {
            $0.title.lowercased().contains(q) ||
            (!$0.taskDescription.isEmpty && $0.taskDescription.lowercased().contains(q))
        }
    }

    private var emailResults: [EmailThread] {
        guard !trimmedQuery.isEmpty else { return [] }
        let q = trimmedQuery.lowercased()
        return services.emailService.threads.filter {
            $0.subject.lowercased().contains(q) ||
            $0.from.name.lowercased().contains(q) ||
            $0.from.email.lowercased().contains(q) ||
            $0.snippet.lowercased().contains(q)
        }
    }

    /// Unique people from loaded email threads matching the query
    private var peopleResults: [EmailSender] {
        guard !trimmedQuery.isEmpty else { return [] }
        let q = trimmedQuery.lowercased()
        var seen = Set<String>()
        return services.emailService.threads
            .map { $0.from }
            .filter {
                ($0.name.lowercased().contains(q) || $0.email.lowercased().contains(q))
                && seen.insert($0.email).inserted
            }
    }

    private var hasResults: Bool {
        !taskResults.isEmpty || !emailResults.isEmpty || !calendarResults.isEmpty || !peopleResults.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                Divider().foregroundStyle(AppTheme.divider)

                if trimmedQuery.isEmpty {
                    emptyPrompt
                } else if !hasResults {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .background(AppTheme.sheetBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Search")
                        .font(.system(size: 16, weight: .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
        .onAppear {
            // Auto-focus the search field when the sheet opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFocused = true
            }
        }
        .onChange(of: trimmedQuery) { scheduleCalendarSearch() }
        .onDisappear {
            calendarSearchTask?.cancel()
            calendarSearchTask = nil
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)

            TextField("Tasks, emails, events, people…", text: $query)
                .font(.system(size: 16, weight: .medium))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isSearchFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .minTouchTarget()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.strongBorder, lineWidth: 1)
        )
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !taskResults.isEmpty {
                    resultSection(title: "Tasks", icon: "checklist") {
                        ForEach(taskResults.prefix(5)) { task in
                            taskRow(task)
                        }
                    }
                }

                if !emailResults.isEmpty {
                    resultSection(title: "Emails", icon: "envelope.fill") {
                        ForEach(emailResults.prefix(5)) { thread in
                            emailRow(thread)
                        }
                    }
                }

                if !calendarResults.isEmpty {
                    resultSection(title: "Events", icon: "calendar") {
                        ForEach(calendarResults.prefix(5)) { event in
                            eventRow(event)
                        }
                    }
                }

                if !peopleResults.isEmpty {
                    resultSection(title: "People", icon: "person.2.fill") {
                        ForEach(peopleResults.prefix(5), id: \.email) { sender in
                            personRow(sender)
                        }
                    }
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func resultSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    // MARK: - Row Views

    private func taskRow(_ task: TaskRecord) -> some View {
        Button {
            dismiss()
            // Navigate to tasks tab and open the task detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.navigateTo = .tasks
                services.pendingTaskId = task.id
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(task.completed ? Color.primary : AppTheme.subtleText)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(task.completed ? .secondary : .primary)
                        .lineLimit(1)

                    if let due = task.dueDate {
                        Text(due, format: .dateTime.month(.abbreviated).day().year())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emailRow(_ thread: EmailThread) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.navigateTo = .email
                services.pendingEmailThreadId = thread.id
            }
        } label: {
            HStack(spacing: 12) {
                // Unread dot
                Circle()
                    .fill(thread.unread ? Color.primary : Color.clear)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(thread.from.name)
                            .font(.system(size: 14, weight: thread.unread ? .semibold : .medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(thread.date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(thread.subject)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.8))
                    Text(thread.snippet)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.navigateTo = .calendar
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hue: Double(event.calendarColor % 360) / 360.0, saturation: 0.6, brightness: 0.8))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if event.isAllDay {
                        Text(event.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(event.startDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func personRow(_ sender: EmailSender) -> some View {
        HStack(spacing: 12) {
            // Initials avatar
            ZStack {
                Circle().fill(AppTheme.surfaceSecondary)
                Text(String(sender.name.first(where: { $0.isLetter }) ?? "?").uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(sender.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(sender.email)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
    }

    // MARK: - Empty States

    private var emptyPrompt: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppTheme.mutedText)

                Text("Search everything")
                    .font(.system(size: 17, weight: .semibold))

                // Category chips hint
                HStack(spacing: 10) {
                    categoryChip(icon: "checklist", label: "Tasks")
                    categoryChip(icon: "envelope", label: "Emails")
                    categoryChip(icon: "calendar", label: "Events")
                    categoryChip(icon: "person", label: "People")
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func categoryChip(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 64, height: 56)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.mutedText)
            Text("No results for \"\(trimmedQuery)\"")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: - Calendar Fetch

    /// Debounces calendar searches so that EventKit isn't queried on every keystroke.
    /// Cancels any in-flight task; if the query is empty, clears immediately.
    private func scheduleCalendarSearch() {
        calendarSearchTask?.cancel()

        guard !trimmedQuery.isEmpty, services.calendarService.canReadEvents() else {
            calendarResults = []
            return
        }

        let q = trimmedQuery.lowercased()
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let oneYearAhead = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

        calendarSearchTask = Task { @MainActor in
            // ~250 ms debounce — feels responsive without thrashing EventKit.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let events = await services.calendarService.events(from: sixMonthsAgo, to: oneYearAhead)
            guard !Task.isCancelled else { return }
            calendarResults = events.filter { $0.title.lowercased().contains(q) }
        }
    }
}
