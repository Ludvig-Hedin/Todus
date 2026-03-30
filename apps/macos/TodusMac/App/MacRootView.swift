import SwiftUI
import SwiftData

// MARK: - Navigation Model

enum EmailSection: String, CaseIterable, Hashable {
    case inbox, drafts, sent

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .drafts: "Drafts"
        case .sent: "Sent"
        }
    }
}

enum CalendarSection: String, CaseIterable, Hashable {
    case all, personal, work

    var title: String {
        switch self {
        case .all: "All Events"
        case .personal: "Personal"
        case .work: "Work"
        }
    }
}

enum MacPrimarySelection: Hashable {
    case home, tasks, email(EmailSection), calendar(CalendarSection)

    var title: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .email(let section): section.title
        case .calendar(let section): section.title
        }
    }

    /// Top-level category for grouping
    var category: String {
        switch self {
        case .home: "home"
        case .tasks: "tasks"
        case .email: "email"
        case .calendar: "calendar"
        }
    }
}

// MARK: - Root View

struct MacRootView: View {
    @Environment(MacAppServices.self) private var services

    // Live task count for sidebar badge
    @Query(filter: #Predicate<TaskRecord> { !$0.completed }) private var incompleteTasks: [TaskRecord]

    @State private var selection: MacPrimarySelection = .home
    @State private var isEmailExpanded = true
    @State private var isCalendarExpanded = true
    @State private var isAssistantPresented = false
    @State private var assistantDisplayMode: AssistantDisplayMode = .floating
    // Side pane resize — user can drag the divider to adjust width
    @State private var sidePaneWidth: CGFloat = 380
    @State private var sidePaneDragStartWidth: CGFloat?
    @State private var isSettingsPresented = false
    @State private var isComposePresented = false
    @State private var isCreatePresented = false
    @State private var isSearchPresented = false
    @State private var selectedEmailThread: IdentifiableString? = nil
    @State private var showNotifications = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var calendarViewMode: String = "Week"
    @State private var calendarSelectedDate: Date = Date()
    @State private var composeEmailSeedBody: String = ""
    @State private var hasBootstrappedAuthState = false

    // Accent color — drives .tint() on root so SwiftUI controls update immediately
    @AppStorage("mac_accent_color") private var accentColorKey = "blue"

    var body: some View {
        Group {
            if !hasBootstrappedAuthState && services.authService.hasPersistedBearerToken {
                restoringSessionView
                    .transition(.opacity)
            } else if services.authService.showsOnboarding {
                // Not authenticated → show sign-in screen
                MacAuthView()
                    .transition(.opacity)
            } else {
                // Authenticated or guest → show main app shell
                mainAppView
                    .transition(.opacity)
            }
        }
        .tint(MacTheme.accentColor(for: accentColorKey))
        .animation(.snappy(duration: 0.3), value: services.authService.showsOnboarding)
        .animation(.snappy(duration: 0.3), value: services.authService.isAuthenticated)
        .task {
            guard !hasBootstrappedAuthState else { return }
            defer { hasBootstrappedAuthState = true }

            if services.authService.hasPersistedBearerToken {
                _ = await services.authService.restorePersistedSession()
            }
        }
        .task {
            // Validate session on launch — but DON'T sign out on failure.
            // attemptSilentRefresh() returns false for both expired tokens AND
            // network errors (offline, DNS hiccup). Signing out here would
            // destroy a valid Keychain-stored session during a transient outage.
            // Instead, just refresh isSessionExpired so the UI can show a banner.
            // Actual sign-out on 401 is handled reactively by the API client.
            if services.authService.isAuthenticated && hasBootstrappedAuthState {
                _ = await services.authService.attemptSilentRefresh()
            }
        }
        .task(id: services.authService.isAuthenticated) {
            // Fetch user profile (name, avatar, email) whenever auth state changes
            // to authenticated. Uses task(id:) so it re-runs after login — a plain
            // .task{} only fires on initial appear (before login), when bearerToken
            // is still nil. Matches iOS RootView behavior.
            guard services.authService.isAuthenticated else { return }
            await services.authService.fetchUserProfile()
        }
    }

    private var restoringSessionView: some View {
        ZStack {
            MacTheme.contentBackground
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image("BrandLogo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 44, height: 44)

                ProgressView()
                    .controlSize(.small)

                Text("Verifying session…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Main App Shell

    private var mainAppView: some View {
        HStack(spacing: 0) {
            // Main content area (NavigationSplitView)
            mainNavigationView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Side pane mode — docked assistant panel on the right
            if isAssistantPresented && assistantDisplayMode == .sidepane {
                // Draggable resize divider — replaces plain Divider() so user can adjust side pane width
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if sidePaneDragStartWidth == nil { sidePaneDragStartWidth = sidePaneWidth }
                                let start = sidePaneDragStartWidth ?? sidePaneWidth
                                // Negative translation = dragging left = wider panel
                                sidePaneWidth = max(280, min(600, start - value.translation.width))
                            }
                            .onEnded { _ in sidePaneDragStartWidth = nil }
                    )

                MacAssistantPanel(
                    isPresented: $isAssistantPresented,
                    displayMode: $assistantDisplayMode,
                    currentSelection: selection
                )
                .frame(width: sidePaneWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isAssistantPresented && assistantDisplayMode == .sidepane)
        // Floating mode — overlay panel positioned bottom-right
        .overlay(alignment: .bottomTrailing) {
            if isAssistantPresented && assistantDisplayMode == .floating {
                MacAssistantPanel(
                    isPresented: $isAssistantPresented,
                    displayMode: $assistantDisplayMode,
                    currentSelection: selection
                )
                // Panel self-manages its size via floatingSize state — no fixed frame here
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isAssistantPresented && assistantDisplayMode == .floating)
        // Settings overlay — full-screen dimmed backdrop; tap outside to dismiss
        .overlay {
            if isSettingsPresented {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) {
                                isSettingsPresented = false
                            }
                        }

                    MacSettingsView(isPresented: $isSettingsPresented)
                        .frame(width: 560)
                        .frame(maxHeight: 680)
                        .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.28), radius: 32, y: 12)
                        // Prevent taps on the panel itself from propagating to the backdrop
                        .onTapGesture {}
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: isSettingsPresented)
    }

    /// The NavigationSplitView with detail content, toolbar, and sheets.
    /// Extracted so the assistant panel HStack can wrap it cleanly.
    private var mainNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebarView(
                selection: $selection,
                isEmailExpanded: $isEmailExpanded,
                isCalendarExpanded: $isCalendarExpanded,
                onOpenSettings: { isSettingsPresented = true },
                onCompose: { isComposePresented = true },
                taskCount: incompleteTasks.count,
                onCreateItem: { isCreatePresented = true },
                onCalendarDayTap: { date in
                    calendarSelectedDate = date
                    selection = .calendar(.all)
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                // Content-area base background — slightly tinted to match iOS app tone
                MacTheme.contentBackground
                    .ignoresSafeArea()

                // Calendar manages its own scroll and needs edge-to-edge layout;
                // other views use a standard padded ScrollView wrapper.
                if selection.category == "calendar" {
                    contentView(for: selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(selection)
                } else {
                    ScrollView {
                        contentView(for: selection)
                            .padding(.horizontal, 28)
                            .padding(.top, 20)
                            .padding(.bottom, 80)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(selection)
                }

                // Hide the FAB when the assistant panel is already open
                if !isAssistantPresented {
                    AssistantButton {
                        withAnimation(.snappy(duration: 0.25)) {
                            isAssistantPresented = true
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: isAssistantPresented)
            .navigationTitle(selection.title)
            // Hide the toolbar's own background so the content-area
            // MacTheme.contentBackground bleeds through seamlessly.
            // (.hidden doesn't paint anything, so no sidebar clipping issue —
            // that only happened with .visible which drew an opaque bar.)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            columnVisibility = columnVisibility == .detailOnly
                                ? .automatic : .detailOnly
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Toggle Sidebar")
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }

                // Context-specific toolbar items based on active view
                ToolbarItemGroup(placement: .secondaryAction) {
                    contextToolbarItems
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showNotifications.toggle()
                    } label: {
                        Image(systemName: "bell")
                    }
                    .help("Notifications")
                    .popover(isPresented: $showNotifications, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notifications")
                                .font(.system(size: 13, weight: .semibold))
                            Text("No new notifications.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(width: 220)
                    }

                    Menu {
                        Button("Preferences…  ⌘,") { isSettingsPresented = true }
                        Divider()
                        Button("New Email  ⌘⇧E") { isComposePresented = true }
                        Button("Refresh  ⌘R") {
                            Task { await services.emailService.loadThreads(refresh: true) }
                        }
                        Divider()
                        Button("Toggle Sidebar  ⌘B") {
                            columnVisibility = columnVisibility == .detailOnly
                                ? .automatic : .detailOnly
                        }
                        // Toggle assistant — shows checkmark when open
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                isAssistantPresented.toggle()
                            }
                        } label: {
                            if isAssistantPresented {
                                Text("Hide AI Assistant  ⌘L")
                            } else {
                                Text("AI Assistant  ⌘L")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(Color.primary.opacity(0.7))
                    .help("More Options")

                    // Create / compose
                    Button {
                        isCreatePresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New Item (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)

                    // Search — ⌘K (command palette convention)
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    .help("Search (⌘K)")
                }
            }
        }
        .animation(.none, value: selection)
        // Global keyboard shortcuts registered via hidden background buttons.
        // These cover actions not already bound to visible toolbar buttons.
        .background {
            Group {
                // ⌘,  — Settings (standard macOS convention)
                Button("") { isSettingsPresented = true }
                    .keyboardShortcut(",", modifiers: .command)

                // ⌘B — Toggle sidebar
                Button("") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility = columnVisibility == .detailOnly
                            ? .automatic : .detailOnly
                    }
                }
                .keyboardShortcut("b", modifiers: .command)

                // ⌘L — Toggle AI Assistant (not just open — toggle so it can be closed too)
                Button("") {
                    withAnimation(.snappy(duration: 0.25)) {
                        isAssistantPresented.toggle()
                    }
                }
                .keyboardShortcut("l", modifiers: .command)

                // ⌘⇧N — New Task specifically
                Button("") {
                    defaultCreateType == .task
                        ? (isCreatePresented = true)
                        : (selection = .tasks)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                // ⌘R — Refresh (email threads when in email view)
                Button("") {
                    if selection.category == "email" {
                        Task { await services.emailService.loadThreads(refresh: true) }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                // ⌘1-4 — Navigate to sections
                Button("") { selection = .home }
                    .keyboardShortcut("1", modifiers: .command)

                Button("") { selection = .tasks }
                    .keyboardShortcut("2", modifiers: .command)

                Button("") { selection = .email(.inbox) }
                    .keyboardShortcut("3", modifiers: .command)

                Button("") { selection = .calendar(.all) }
                    .keyboardShortcut("4", modifiers: .command)

                // ⌘⇧M — Mark all read (email)
                Button("") {
                    if selection.category == "email" {
                        Task {
                            let ids = services.emailService.threads.filter(\.unread).map(\.id)
                            if !ids.isEmpty { await services.emailService.markAsRead(ids: ids) }
                        }
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                // ⌘⇧E — Compose email
                Button("") { isComposePresented = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $isComposePresented) {
            MacEmailComposeView(seedBody: composeEmailSeedBody)
                .frame(minWidth: 520, minHeight: 380)
                .onDisappear { composeEmailSeedBody = "" }
        }
        .sheet(isPresented: $isCreatePresented) {
            MacCreateSheet(
                defaultType: defaultCreateType,
                onComposeEmail: { body in
                    composeEmailSeedBody = body
                    isComposePresented = true
                }
            )
            .frame(minWidth: 440, minHeight: 300)
        }
        .sheet(isPresented: $isSearchPresented) {
            searchSheet
                .frame(minWidth: 480, minHeight: 360)
        }
        .sheet(item: $selectedEmailThread) { thread in
            MacEmailThreadView(threadId: thread.value)
                .frame(minWidth: 560, minHeight: 400)
        }
    }

    // MARK: - Context Toolbar

    /// Toolbar items that change based on the active view
    @ViewBuilder
    private var contextToolbarItems: some View {
        switch selection.category {
        case "email":
            Button {
                Task {
                    let ids = services.emailService.threads.filter(\.unread).map(\.id)
                    if !ids.isEmpty {
                        await services.emailService.markAsRead(ids: ids)
                    }
                }
            } label: {
                Image(systemName: "envelope.open")
            }
            .help("Mark All Read")

            Menu {
                Button("All Mail") {}
                Button("Unread") {}
                Button("Flagged") {}
                Button("With Attachments") {}
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            .tint(Color.primary.opacity(0.7))
            .help("Filter")

        case "calendar":
            // No extra toolbar items — view picker and Today button live inside
            // the calendar header. The global compose button (⌘N) handles new events.
            EmptyView()

        case "tasks":
            Menu {
                Button("All") {}
                Button("Today") {}
                Button("Upcoming") {}
                Divider()
                Button("Completed") {}
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            .tint(Color.primary.opacity(0.7))
            .help("Filter Tasks")

        default:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(for currentSelection: MacPrimarySelection) -> some View {
        switch currentSelection {
        case .home:
            MacHomeView(onNavigate: { selection = $0 })
        case .tasks:
            MacTasksView()
        case .email(let section):
            MacEmailInboxView(folder: section.rawValue)
        case .calendar:
            MacCalendarView(viewMode: $calendarViewMode, selectedDate: $calendarSelectedDate)
        }
    }

    private func placeholderContent(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Content will appear here once connected to the backend.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func sheetView(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Determines default create type based on active sidebar selection
    private var defaultCreateType: CreateItemType {
        switch selection.category {
        case "tasks": return .task
        case "email": return .email
        case "calendar": return .event
        default: return .auto
        }
    }

    private var searchSheet: some View {
        MacSearchView(
            onCreateTask: {
                selection = .tasks
                isCreatePresented = true
            },
            onComposeEmail: {
                isComposePresented = true
            },
            onCreateEvent: {
                selection = .calendar(.all)
                isCreatePresented = true
            },
            onOpenTasks: {
                selection = .tasks
            },
            onOpenCalendarEvent: { date in
                calendarSelectedDate = date
                selection = .calendar(.all)
            },
            onOpenEmailThread: { threadId in
                selectedEmailThread = IdentifiableString(value: threadId)
            }
        )
    }
}
