import SwiftUI

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

    @State private var selection: MacPrimarySelection = .home
    @State private var isEmailExpanded = true
    @State private var isCalendarExpanded = true
    @State private var isAssistantPresented = false
    @State private var isSettingsPresented = false
    @State private var isComposePresented = false
    @State private var isSearchPresented = false
    @State private var showNotifications = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var calendarViewMode: String = "Week"

    var body: some View {
        Group {
            if services.authService.showsOnboarding {
                // Not authenticated → show sign-in screen
                MacAuthView()
                    .transition(.opacity)
            } else {
                // Authenticated or guest → show main app shell
                mainAppView
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: services.authService.showsOnboarding)
        .animation(.snappy(duration: 0.3), value: services.authService.isAuthenticated)
        .task {
            // Validate session on launch — but DON'T sign out on failure.
            // attemptSilentRefresh() returns false for both expired tokens AND
            // network errors (offline, DNS hiccup). Signing out here would
            // destroy a valid Keychain-stored session during a transient outage.
            // Instead, just refresh isSessionExpired so the UI can show a banner.
            // Actual sign-out on 401 is handled reactively by the API client.
            if services.authService.isAuthenticated {
                await services.authService.attemptSilentRefresh()
            }
        }
    }

    // MARK: - Main App Shell

    private var mainAppView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebarView(
                selection: $selection,
                isEmailExpanded: $isEmailExpanded,
                isCalendarExpanded: $isCalendarExpanded,
                onOpenSettings: { isSettingsPresented = true },
                onCompose: { isComposePresented = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
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

                AssistantButton { isAssistantPresented = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
            }
            .navigationTitle(selection.title)
            .toolbar {
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
                        Button("Preferences...") { isSettingsPresented = true }
                        Divider()
                        Button("Share...") {}
                        Button("Export...") {}
                    } label: {
                        Image(systemName: "ellipsis")
                    }

                    Button {
                        isComposePresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("Compose (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Search (⌘F)")
                }
            }
        }
        .animation(.none, value: selection)
        // Hidden button to register ⌘B for sidebar toggle
        .background {
            Button("") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    columnVisibility = columnVisibility == .detailOnly
                        ? .automatic : .detailOnly
                }
            }
            .keyboardShortcut("b", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $isAssistantPresented) {
            sheetView(title: "AI Assistant", description: "Assistant interface will appear here.")
                .frame(minWidth: 400, minHeight: 260)
        }
        .sheet(isPresented: $isSettingsPresented) {
            MacSettingsView()
                .frame(minWidth: 460, minHeight: 360)
        }
        .sheet(isPresented: $isComposePresented) {
            MacEmailComposeView()
                .frame(minWidth: 520, minHeight: 380)
        }
        .sheet(isPresented: $isSearchPresented) {
            searchSheet
                .frame(minWidth: 480, minHeight: 200)
        }
    }

    // MARK: - Context Toolbar

    /// Toolbar items that change based on the active view
    @ViewBuilder
    private var contextToolbarItems: some View {
        switch selection.category {
        case "email":
            Button {
                // Mark all read action
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
            }
            .help("Filter")

        case "calendar":
            Button {
                // Go to today
                selection = .calendar(.all)
            } label: {
                Image(systemName: "calendar.circle")
            }
            .help("Today")

            Picker("View", selection: $calendarViewMode) {
                Text("Day").tag("Day")
                Text("Week").tag("Week")
                Text("Month").tag("Month")
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

        case "tasks":
            Button {} label: {
                Image(systemName: "plus")
            }
            .help("New Task (⌘T)")
            .keyboardShortcut("t", modifiers: .command)

            Menu {
                Button("All") {}
                Button("Today") {}
                Button("Upcoming") {}
                Divider()
                Button("Completed") {}
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .help("Filter Tasks")

        default:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(for selection: MacPrimarySelection) -> some View {
        switch selection {
        case .home:
            MacHomeView()
        case .tasks:
            MacTasksView()
        case .email(let section):
            MacEmailInboxView(folder: section.rawValue)
        case .calendar:
            MacCalendarView()
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

    private var searchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))

            TextField("Search emails, tasks, events...", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            Text("Start typing to search across all items.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
