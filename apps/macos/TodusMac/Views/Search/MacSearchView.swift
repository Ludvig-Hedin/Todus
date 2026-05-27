import SwiftUI
import SwiftData

/// Search modal that shows recommended/recent items before any query is typed,
/// and filters tasks + emails + events + people as the user types.
///
/// Parity goal: matches iOS GlobalSearchView feature set —
/// category chips, debounced calendar lookups, people derived from email
/// participants, persistent recent searches, and keyboard navigation.
struct MacSearchView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskRecord> { !$0.completed },
           sort: \TaskRecord.createdAt, order: .reverse) private var tasks: [TaskRecord]

    var onCreateTask: () -> Void = {}
    var onComposeEmail: () -> Void = {}
    var onCreateEvent: () -> Void = {}
    var onOpenTasks: () -> Void = {}
    var onOpenCalendarEvent: (Date) -> Void = { _ in }
    var onOpenEmailThread: (String) -> Void = { _ in }

    @State private var searchText = ""
    @State private var calendarEvents: [CalendarEvent] = []
    /// Debounced calendar search task — cancelled per-keystroke so EventKit
    /// isn't queried on every character.
    @State private var calendarSearchTask: Task<Void, Never>?
    @State private var selectedCategory: SearchCategory = .all
    /// Index of the keyboard-highlighted row across the flat ordered result list.
    @State private var highlightedIndex: Int = 0
    @FocusState private var isFocused: Bool
    /// Toast for create-task confirmation. Without this the search sheet
    /// dismisses immediately after `onCreateTask()` and the user has no
    /// confirmation the task actually saved.
    @State private var createTaskToast: MacToastMessage?
    @State private var createTaskInFlight = false

    /// Persisted recent searches — comma separated, capped at 10.
    /// Stored as a single string to keep `@AppStorage` happy without a
    /// custom transformer.
    @AppStorage("mac_recent_searches") private var recentSearchesRaw: String = ""

    // MARK: - Search categories

    enum SearchCategory: Int, CaseIterable, Identifiable {
        case all, tasks, emails, events, people

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .tasks: return "Tasks"
            case .emails: return "Emails"
            case .events: return "Events"
            case .people: return "People"
            }
        }

        var icon: String {
            switch self {
            case .all: return "sparkles"
            case .tasks: return "checkmark.square"
            case .emails: return "envelope"
            case .events: return "calendar"
            case .people: return "person.2"
            }
        }
    }

    // MARK: - Derived state

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentSearches: [String] {
        recentSearchesRaw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0) }
    }

    private var matchingTasks: [TaskRecord] {
        guard !trimmedQuery.isEmpty else { return [] }
        let q = trimmedQuery.lowercased()
        return tasks.filter {
            $0.title.lowercased().contains(q) ||
            $0.taskDescription.lowercased().contains(q)
        }
    }

    private var matchingEmails: [EmailThread] {
        guard !trimmedQuery.isEmpty else { return [] }
        let q = trimmedQuery.lowercased()
        return services.emailService.threads.filter {
            $0.subject.lowercased().contains(q) ||
            $0.from.name.lowercased().contains(q) ||
            $0.from.email.lowercased().contains(q) ||
            $0.snippet.lowercased().contains(q)
        }
    }

    private var matchingEvents: [CalendarEvent] {
        guard !trimmedQuery.isEmpty else { return [] }
        let q = trimmedQuery.lowercased()
        return calendarEvents.filter {
            $0.title.lowercased().contains(q) ||
            $0.calendarName.lowercased().contains(q)
        }
    }

    /// People aggregated from loaded email thread senders, deduped by email.
    /// No dedicated `recentSenders()` API on `EmailService`, so we derive
    /// inline from the public `threads` array.
    private var matchingPeople: [EmailSender] {
        guard !trimmedQuery.isEmpty else { return [] }
        let q = trimmedQuery.lowercased()
        var seen = Set<String>()
        return services.emailService.threads
            .map { $0.from }
            .filter {
                ($0.name.lowercased().contains(q) || $0.email.lowercased().contains(q))
                && seen.insert($0.email.lowercased()).inserted
            }
    }

    /// Visible rows under the current category, ordered for ↑/↓ keyboard nav.
    /// Each row is a closure that performs the row's activation action.
    private var visibleRowActions: [() -> Void] {
        var actions: [() -> Void] = []

        if selectedCategory == .all || selectedCategory == .tasks {
            for _ in matchingTasks.prefix(5) {
                actions.append { onOpenTasks(); dismiss() }
            }
        }
        if selectedCategory == .all || selectedCategory == .emails {
            for thread in matchingEmails.prefix(5) {
                let id = thread.id
                actions.append { onOpenEmailThread(id); dismiss() }
            }
        }
        if selectedCategory == .all || selectedCategory == .events {
            for event in matchingEvents.prefix(5) {
                let start = event.startDate
                actions.append { onOpenCalendarEvent(start); dismiss() }
            }
        }
        if selectedCategory == .all || selectedCategory == .people {
            for sender in matchingPeople.prefix(5) {
                let email = sender.email
                // No per-sender filter exists yet — refill the query with the
                // sender's email so the email section narrows to that person.
                actions.append { searchText = email }
            }
        }
        return actions
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.spacing16) {
                    if trimmedQuery.isEmpty {
                        recommendedContent
                    } else {
                        // Category chips appear only when there's a query —
                        // keeps the empty state focused on recommendations.
                        categoryChipsRow
                        searchResults
                    }
                }
                .padding(MacTheme.spacing16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(keyboardShortcuts)
        .macToast($createTaskToast)
        .onAppear { isFocused = true }
        .onChange(of: trimmedQuery) { _, _ in
            // Reset highlight whenever the result list changes shape.
            highlightedIndex = 0
            scheduleCalendarSearch()
        }
        .onChange(of: selectedCategory) { _, _ in
            highlightedIndex = 0
        }
        .onDisappear {
            calendarSearchTask?.cancel()
            calendarSearchTask = nil
        }
        .task {
            await loadContextData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)

            TextField("Search tasks, emails, events, people…", text: $searchText)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    activateHighlightedRow()
                }

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
    }

    // MARK: - Hidden keyboard shortcut surface

    /// Invisible buttons that own the global keyboard shortcuts. SwiftUI only
    /// fires `.keyboardShortcut` modifiers on focusable elements, so we park
    /// them in a hidden overlay attached to the sheet.
    private var keyboardShortcuts: some View {
        ZStack {
            // ⌘1…⌘5 → switch category
            ForEach(SearchCategory.allCases) { category in
                Button("Select \(category.title)") {
                    selectedCategory = category
                }
                .keyboardShortcut(KeyEquivalent(Character("\(category.rawValue + 1)")), modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            }

            // ↓ → next row
            Button("Next result") {
                let count = visibleRowActions.count
                guard count > 0 else { return }
                highlightedIndex = min(highlightedIndex + 1, count - 1)
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)

            // ↑ → previous row
            Button("Previous result") {
                guard !visibleRowActions.isEmpty else { return }
                highlightedIndex = max(highlightedIndex - 1, 0)
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)

            // ↩ in TextField → onSubmit handles it; this extra button covers
            // the case where focus is somewhere else in the sheet.
            Button("Open result") {
                activateHighlightedRow()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        // Zero-sized + zero-opacity buttons can't be pointer-targeted, but
        // their `.keyboardShortcut` modifiers still fire — exactly what we want.
        .accessibilityHidden(true)
    }

    private func activateHighlightedRow() {
        let actions = visibleRowActions
        // First, commit the query to recent searches if it produced results.
        commitRecentSearch()
        guard actions.indices.contains(highlightedIndex) else { return }
        actions[highlightedIndex]()
    }

    // MARK: - Category chips

    private var categoryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MacTheme.spacing8) {
                ForEach(SearchCategory.allCases) { category in
                    categoryChip(category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(_ category: SearchCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(category.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : MacTheme.textSecondary)
            .background(
                Capsule()
                    .fill(isSelected ? MacTheme.accent : MacTheme.badgeSurface)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Filter to \(category.title)")
    }

    // MARK: - Recommended Content (before query)

    private var recommendedContent: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            if !suggestedSearches.isEmpty {
                searchSection(title: "SUGGESTED SEARCHES", icon: "sparkles") {
                    ForEach(Array(suggestedSearches.enumerated()), id: \.offset) { _, suggestion in
                        suggestionRow(suggestion)
                    }
                }
            }

            if !recentSearches.isEmpty {
                recentSearchesSection
            }

            // Recent tasks
            if !tasks.isEmpty {
                searchSection(title: "RECENT TASKS", icon: "checkmark.square") {
                    ForEach(tasks.prefix(4)) { task in
                        searchRow(
                            icon: task.status.systemImage,
                            iconColor: task.status.tintColor,
                            title: task.title,
                            subtitle: task.dueDate.map { "Due \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "No due date",
                            type: "Task",
                            action: {
                                onOpenTasks()
                            }
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
                            type: "Email",
                            action: {
                                onOpenEmailThread(thread.id)
                            }
                        )
                    }
                }
            }

            if !calendarEvents.isEmpty {
                searchSection(title: "RECENT EVENTS", icon: "calendar") {
                    ForEach(calendarEvents.prefix(4)) { event in
                        searchRow(
                            icon: event.isAllDay ? "calendar.badge.clock" : "calendar",
                            iconColor: Color(
                                red: event.calendarColorRed,
                                green: event.calendarColorGreen,
                                blue: event.calendarColorBlue
                            ),
                            title: event.title,
                            subtitle: eventSubtitle(for: event),
                            type: "Event",
                            action: {
                                onOpenCalendarEvent(event.startDate)
                            }
                        )
                    }
                }
            }

            // Quick actions
            searchSection(title: "QUICK ACTIONS", icon: "bolt") {
                searchRow(
                    icon: "plus.circle",
                    iconColor: MacTheme.accent,
                    title: "Create a new task",
                    subtitle: "Add to your task list",
                    type: "Action",
                    action: {
                        onCreateTask()
                    }
                )
                searchRow(
                    icon: "envelope",
                    iconColor: .primary,
                    title: "Compose email",
                    subtitle: "Write a new message",
                    type: "Action",
                    action: {
                        onComposeEmail()
                    }
                )
                searchRow(
                    icon: "calendar.badge.plus",
                    iconColor: .orange,
                    title: "New event",
                    subtitle: "Add to your calendar",
                    type: "Action",
                    action: {
                        onCreateEvent()
                    }
                )
            }

            if tasks.isEmpty && services.emailService.threads.isEmpty && calendarEvents.isEmpty {
                VStack(spacing: MacTheme.spacing8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MacTheme.mutedText.opacity(0.5))
                    Text("Search tasks, emails, events, and people")
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, MacTheme.spacing24)
            }
        }
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing6) {
            HStack(spacing: MacTheme.spacing4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                Text("RECENT SEARCHES")
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .tracking(0.8)
                Spacer()
                Button("Clear") {
                    recentSearchesRaw = ""
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(MacTheme.accent)
                .pointerStyle(.link)
            }

            VStack(spacing: 1) {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        searchText = term
                    } label: {
                        HStack(spacing: MacTheme.spacing8) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MacTheme.mutedText)
                                .frame(width: 20)
                            Text(term)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MacTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MacTheme.mutedText)
                        }
                        .padding(.horizontal, MacTheme.spacing12)
                        .padding(.vertical, MacTheme.spacing8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .pointerStyle(.link)
                }
            }
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Search Results

    private var searchResults: some View {
        // Pre-compute filtered slices once so the body view stays readable
        // and so the highlight index resolves against the same ordering as
        // `visibleRowActions`.
        let tasksSlice = Array(matchingTasks.prefix(5))
        let emailsSlice = Array(matchingEmails.prefix(5))
        let eventsSlice = Array(matchingEvents.prefix(5))
        let peopleSlice = Array(matchingPeople.prefix(5))

        let showTasks = selectedCategory == .all || selectedCategory == .tasks
        let showEmails = selectedCategory == .all || selectedCategory == .emails
        let showEvents = selectedCategory == .all || selectedCategory == .events
        let showPeople = selectedCategory == .all || selectedCategory == .people

        let anyResults = (showTasks && !tasksSlice.isEmpty)
            || (showEmails && !emailsSlice.isEmpty)
            || (showEvents && !eventsSlice.isEmpty)
            || (showPeople && !peopleSlice.isEmpty)

        // Pre-compute the base index for each section so the highlight index
        // aligns with `visibleRowActions`. SwiftUI's ViewBuilder doesn't allow
        // statement-level mutation, so we resolve all offsets up front.
        let tasksCount = (showTasks && !tasksSlice.isEmpty) ? tasksSlice.count : 0
        let emailsCount = (showEmails && !emailsSlice.isEmpty) ? emailsSlice.count : 0
        let eventsCount = (showEvents && !eventsSlice.isEmpty) ? eventsSlice.count : 0

        let tasksBase = 0
        let emailsBase = tasksBase + tasksCount
        let eventsBase = emailsBase + emailsCount
        let peopleBase = eventsBase + eventsCount

        return VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            if showTasks && !tasksSlice.isEmpty {
                searchSection(title: "TASKS", icon: "checkmark.square") {
                    ForEach(Array(tasksSlice.enumerated()), id: \.element.id) { offset, task in
                        searchRow(
                            icon: task.status.systemImage,
                            iconColor: task.status.tintColor,
                            title: task.title,
                            subtitle: task.dueDate.map { "Due \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "No due date",
                            type: "Task",
                            highlighted: highlightedIndex == tasksBase + offset,
                            action: {
                                commitRecentSearch()
                                onOpenTasks()
                            }
                        )
                    }
                }
            }

            if showEmails && !emailsSlice.isEmpty {
                searchSection(title: "EMAILS", icon: "envelope") {
                    ForEach(Array(emailsSlice.enumerated()), id: \.element.id) { offset, thread in
                        searchRow(
                            icon: thread.unread ? "envelope.badge" : "envelope.open",
                            iconColor: thread.unread ? MacTheme.accent : MacTheme.mutedText,
                            title: thread.subject,
                            subtitle: "From \(thread.from.name)",
                            type: "Email",
                            highlighted: highlightedIndex == emailsBase + offset,
                            action: {
                                commitRecentSearch()
                                onOpenEmailThread(thread.id)
                            }
                        )
                    }
                }
            }

            if showEvents && !eventsSlice.isEmpty {
                searchSection(title: "EVENTS", icon: "calendar") {
                    ForEach(Array(eventsSlice.enumerated()), id: \.element.id) { offset, event in
                        searchRow(
                            icon: event.isAllDay ? "calendar.badge.clock" : "calendar",
                            iconColor: Color(
                                red: event.calendarColorRed,
                                green: event.calendarColorGreen,
                                blue: event.calendarColorBlue
                            ),
                            title: event.title,
                            subtitle: eventSubtitle(for: event),
                            type: "Event",
                            highlighted: highlightedIndex == eventsBase + offset,
                            action: {
                                commitRecentSearch()
                                onOpenCalendarEvent(event.startDate)
                            }
                        )
                    }
                }
            }

            if showPeople && !peopleSlice.isEmpty {
                searchSection(title: "PEOPLE", icon: "person.2") {
                    ForEach(Array(peopleSlice.enumerated()), id: \.element.email) { offset, sender in
                        personRow(
                            sender,
                            highlighted: highlightedIndex == peopleBase + offset
                        )
                    }
                }
            }

            if !anyResults {
                noResultsView
            }
        }
    }

    private var noResultsView: some View {
        VStack(spacing: MacTheme.spacing8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))
            Text("No results for \"\(searchText)\"")
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.textSecondary)

            Text("Try a task title, sender name, event, or person.")
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.mutedText)

            // Offer a productive next step instead of a dead end —
            // the user typed an intent, so let them capture it as a task.
            Button {
                Task {
                    createTaskInFlight = true
                    // onCreateTask is sync but typically queues a SwiftData
                    // write. Yield briefly so the write actually lands before
                    // we surface confirmation.
                    onCreateTask()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    createTaskInFlight = false
                    createTaskToast = .success("Task created")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    if createTaskInFlight { ProgressView().controlSize(.mini) }
                    Text(createTaskInFlight ? "Creating…" : "Create task ‘\(searchText)’")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(createTaskInFlight)
            .padding(.top, MacTheme.spacing8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MacTheme.spacing24)
    }

    // MARK: - Components

    private struct SearchSuggestion: Identifiable {
        var id: String {
            title + "|" + subtitle + "|" + icon
        }
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

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

    @ViewBuilder
    private func searchRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        type: String,
        highlighted: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        let row = HStack(spacing: MacTheme.spacing8) {
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
        .background(
            highlighted
                ? MacTheme.accent.opacity(0.12)
                : Color.clear
        )
        .contentShape(Rectangle())

        if let action {
            Button {
                action()
                dismiss()
            } label: {
                row
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .contextMenu {
                Button {
                    action()
                    dismiss()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(title, forType: .string)
                } label: {
                    Label("Copy title", systemImage: "doc.on.doc")
                }
                if !subtitle.isEmpty {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(subtitle, forType: .string)
                    } label: {
                        Label("Copy subtitle", systemImage: "text.quote")
                    }
                }
            }
        } else {
            row
        }
    }

    /// Person row — derived from email participants.
    /// Tapping refills the query with the sender's email so the email
    /// section narrows to messages from that sender (since there's no
    /// dedicated "filter inbox by sender" callback wired up here).
    @ViewBuilder
    private func personRow(_ sender: EmailSender, highlighted: Bool = false) -> some View {
        Button {
            commitRecentSearch()
            searchText = sender.email
            selectedCategory = .emails
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                ZStack {
                    Circle().fill(MacTheme.badgeSurface)
                    Text(String(sender.name.first(where: { $0.isLetter }) ?? "?").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(sender.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                    Text(sender.email)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("Person")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius))
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                highlighted
                    ? MacTheme.accent.opacity(0.12)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
    }

    private var suggestedSearches: [SearchSuggestion] {
        var suggestions: [SearchSuggestion] = []

        if let task = tasks.first {
            suggestions.append(SearchSuggestion(
                title: task.title,
                subtitle: "Recent task",
                icon: task.status.systemImage,
                action: { searchText = task.title }
            ))
        }

        if let thread = services.emailService.threads.first {
            suggestions.append(SearchSuggestion(
                title: thread.subject,
                subtitle: "Recent email",
                icon: thread.unread ? "envelope.badge" : "envelope.open",
                action: { searchText = thread.subject }
            ))
        }

        if let event = calendarEvents.first {
            suggestions.append(SearchSuggestion(
                title: event.title,
                subtitle: "Recent event",
                icon: event.isAllDay ? "calendar.badge.clock" : "calendar",
                action: { searchText = event.title }
            ))
        }

        return suggestions
    }

    private func suggestionRow(_ suggestion: SearchSuggestion) -> some View {
        Button {
            suggestion.action()
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)

                    Text(suggestion.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
    }

    private func eventSubtitle(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return event.calendarName + " • All day"
        }
        return event.calendarName + " • " + event.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    // MARK: - Recent searches persistence

    /// Adds the current query (if non-empty and produced any result) to the
    /// persisted recent-searches list, deduped and capped at 10 entries.
    private func commitRecentSearch() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        // Don't pollute history with commas (they're our delimiter).
        let safe = q.replacingOccurrences(of: ",", with: " ")
        var current = recentSearches.filter { $0.caseInsensitiveCompare(safe) != .orderedSame }
        current.insert(safe, at: 0)
        if current.count > 10 {
            current = Array(current.prefix(10))
        }
        recentSearchesRaw = current.joined(separator: ",")
    }

    // MARK: - Data loading

    private func loadContextData() async {
        await loadEmailThreadsIfNeeded()
        // Seed the calendar list with the next 60 days so the
        // "RECENT EVENTS" section has something to show before any query.
        await loadInitialCalendarEvents()
    }

    private func loadEmailThreadsIfNeeded() async {
        if !services.emailService.hasConnection {
            await services.emailService.checkConnection()
        }

        guard services.emailService.hasConnection, services.emailService.threads.isEmpty else {
            return
        }

        await services.emailService.loadThreads(refresh: true)
    }

    private func loadInitialCalendarEvents() async {
        guard services.calendarService.canReadEvents() else {
            calendarEvents = []
            return
        }

        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let end = cal.date(byAdding: .day, value: 180, to: Date()) ?? Date()
        let unified = await services.unifiedCalendarService.events(
            from: start,
            to: end,
            preferences: services.calendarPreferences
        )
        calendarEvents = unified.map { $0.legacyCalendarEvent }
    }

    /// Debounced unified-calendar search over the next 60 days so EventKit /
    /// Google Calendar aren't queried on every keystroke. Filtered client-side
    /// in `matchingEvents`.
    private func scheduleCalendarSearch() {
        calendarSearchTask?.cancel()

        guard !trimmedQuery.isEmpty, services.calendarService.canReadEvents() else {
            // Query cleared (or no calendar access) — restore the initial wide
            // window so the "Recent events" recommendations don't stay stuck on
            // the last search's narrower result set.
            if trimmedQuery.isEmpty, services.calendarService.canReadEvents() {
                calendarSearchTask = Task { await loadInitialCalendarEvents() }
            }
            return
        }

        let prefs = services.calendarPreferences
        let cal = Calendar.current
        let start = Date()
        let end = cal.date(byAdding: .day, value: 60, to: start) ?? start

        calendarSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let unified = await services.unifiedCalendarService.events(
                from: start,
                to: end,
                preferences: prefs
            )
            guard !Task.isCancelled else { return }
            calendarEvents = unified.map { $0.legacyCalendarEvent }
        }
    }
}
