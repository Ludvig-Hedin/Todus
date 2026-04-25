import SwiftUI
import SwiftData

// MARK: - Navigation Model

enum EmailSection: String, CaseIterable, Hashable {
    // Primary folders — shown at the top of the expanded email group
    case inbox, drafts, sent
    // Secondary folders — archive, snoozed, spam, bin (matches backend FOLDERS constant)
    case archive, snoozed, spam, bin

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

    /// SF Symbol for each folder — used in the sidebar child rows
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

    /// Primary folders shown before the divider; secondary shown after
    var isPrimary: Bool {
        switch self {
        case .inbox, .drafts, .sent: true
        default: false
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
    case home, tasks, email(EmailSection), calendar(CalendarSection), meetings, docs

    var title: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .email(let section): section.title
        case .calendar(let section): section.title
        case .meetings: "Meetings"
        case .docs: "Docs"
        }
    }

    /// Top-level category for grouping
    var category: String {
        switch self {
        case .home: "home"
        case .tasks: "tasks"
        case .email: "email"
        case .calendar: "calendar"
        case .meetings: "meetings"
        case .docs: "docs"
        }
    }

    /// Serialized form used to persist selection across launches via @AppStorage.
    /// Stored as a single string ("home", "email:inbox", "calendar:work", etc.) so it
    /// round-trips cleanly through UserDefaults.
    var storageKey: String {
        switch self {
        case .home: return "home"
        case .tasks: return "tasks"
        case .email(let section): return "email:\(section.rawValue)"
        case .calendar(let section): return "calendar:\(section.rawValue)"
        case .meetings: return "meetings"
        case .docs: return "docs"
        }
    }

    /// Restore from `storageKey`. Returns nil if the encoded value is unknown so the
    /// caller can fall back to a sensible default (e.g. `.home`).
    static func fromStorageKey(_ raw: String) -> MacPrimarySelection? {
        switch raw {
        case "home": return .home
        case "tasks": return .tasks
        case "meetings": return .meetings
        case "docs": return .docs
        default:
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            switch parts[0] {
            case "email":
                if let section = EmailSection(rawValue: parts[1]) { return .email(section) }
            case "calendar":
                if let section = CalendarSection(rawValue: parts[1]) { return .calendar(section) }
            default:
                return nil
            }
            return nil
        }
    }
}

// MARK: - Root View

struct MacRootView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    // Live task count for sidebar badge
    @Query(filter: #Predicate<TaskRecord> { !$0.completed }) private var incompleteTasks: [TaskRecord]

    // Persisted UI state — survives app relaunches via UserDefaults.
    // selection: encoded via MacPrimarySelection.storageKey ("home", "email:inbox", etc.)
    // The selection itself is mirrored into local @State so the view tree can bind
    // a SwiftUI Binding<MacPrimarySelection> (the enum has associated values, so it
    // can't live directly in @AppStorage which only handles raw types).
    @AppStorage("mac_sidebar_selection") private var selectionStorageKey: String = "home"
    @AppStorage("mac_email_expanded") private var isEmailExpanded = true
    @AppStorage("mac_calendar_expanded") private var isCalendarExpanded = true
    @AppStorage("mac_assistant_presented") private var isAssistantPresented = false
    @AppStorage("mac_assistant_display_mode") private var assistantDisplayModeRaw: String = AssistantDisplayMode.floating.rawValue
    @AppStorage("mac_compact_sidebar") private var compactSidebar = false
    // Side pane resize — user can drag the divider to adjust width
    @AppStorage("mac_side_pane_width") private var sidePaneWidth: Double = 380
    /// Live floating geometry — **not** @AppStorage; binding updates every frame during drag/resize. Disk sync on gesture end to avoid jank.
    @State private var assistantFloatSize: CGSize = CGSize(width: 400, height: 560)
    @State private var assistantFloatOffset: CGSize = .zero
    @State private var didLoadAssistantFloatLayout = false
    @State private var selection: MacPrimarySelection = .home
    @State private var sidePaneDragStartWidth: CGFloat?

    private var assistantDisplayMode: AssistantDisplayMode {
        AssistantDisplayMode(rawValue: assistantDisplayModeRaw) ?? .floating
    }

    /// Two-way binding for `assistantDisplayMode` backed by `assistantDisplayModeRaw`.
    private var assistantDisplayModeBinding: Binding<AssistantDisplayMode> {
        Binding(
            get: { AssistantDisplayMode(rawValue: assistantDisplayModeRaw) ?? .floating },
            set: { assistantDisplayModeRaw = $0.rawValue }
        )
    }

    private var assistantFloatingSizeBinding: Binding<CGSize> {
        Binding(
            get: { assistantFloatSize },
            set: { assistantFloatSize = $0 }
        )
    }

    private var assistantFloatingOffsetBinding: Binding<CGSize> {
        Binding(
            get: { assistantFloatOffset },
            set: { assistantFloatOffset = $0 }
        )
    }

    private func loadAssistantFloatLayoutIfNeeded() {
        guard !didLoadAssistantFloatLayout else { return }
        didLoadAssistantFloatLayout = true
        let d = UserDefaults.standard
        let w = d.double(forKey: "mac_assistant_floating_width")
        let h = d.double(forKey: "mac_assistant_floating_height")
        let ox = d.double(forKey: "mac_assistant_floating_offset_x")
        let oy = d.double(forKey: "mac_assistant_floating_offset_y")
        assistantFloatSize = CGSize(
            width: w > 0 ? w : 400,
            height: h > 0 ? h : 560
        )
        assistantFloatOffset = CGSize(width: ox, height: oy)
    }

    private func syncAssistantFloatLayoutToDisk() {
        let d = UserDefaults.standard
        d.set(assistantFloatSize.width, forKey: "mac_assistant_floating_width")
        d.set(assistantFloatSize.height, forKey: "mac_assistant_floating_height")
        d.set(assistantFloatOffset.width, forKey: "mac_assistant_floating_offset_x")
        d.set(assistantFloatOffset.height, forKey: "mac_assistant_floating_offset_y")
    }

    @State private var isComposePresented = false
    @State private var isCreatePresented = false
    @State private var isSearchPresented = false
    @State private var isNotificationsPresented = false
    @State private var selectedEmailThread: IdentifiableString? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var calendarViewMode: String = "Week"
    @State private var calendarSelectedDate: Date = Date()
    @State private var composeEmailSeedBody: String = ""
    @State private var composeEmailSeedTo: String = ""
    @State private var composeEmailSeedSubject: String = ""
    @State private var hasBootstrappedAuthState = false
    @State private var hasAppliedStartupSelection = false

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
            } else if !services.hasConfiguredGmailPrompt {
                MacGmailOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredCalendarPrompt {
                MacCalendarOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredRemindersPrompt {
                MacRemindersOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredStartupViewPrompt {
                MacStartupOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredNotificationsPrompt {
                MacNotificationsOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredDefaultMailPrompt {
                MacDefaultMailOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                // Authenticated or guest → show main app shell
                mainAppView
                    .transition(.opacity)
            }
        }
        // Disable system focus rings on buttons/cards — keeps keyboard focus without blue chrome.
        .focusEffectDisabled()
        // Primary text tint so symbols and controls are not system / accent blue.
        .tint(Color.primary)
        .animation(.snappy(duration: 0.3), value: services.authService.showsOnboarding)
        .animation(.snappy(duration: 0.3), value: services.authService.isAuthenticated)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredGmailPrompt)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredCalendarPrompt)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredRemindersPrompt)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredStartupViewPrompt)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredNotificationsPrompt)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredDefaultMailPrompt)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let onboardingStep = onboardingStep {
                HStack {
                    Spacer()
                    Text("\(onboardingStep) of 6")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(MacTheme.cardBorder.opacity(0.8), lineWidth: 1)
                        )
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: services.showsAssistantPanel) { _, isPresented in
            isAssistantPresented = isPresented
        }
        .onChange(of: isAssistantPresented) { _, isPresented in
            services.showsAssistantPanel = isPresented
        }
        // mailto: deep link — open compose with pre-filled fields when set by TodusMacApp
        .onChange(of: services.pendingMailto) { _, pending in
            guard let p = pending else { return }
            let hasField = p.to != nil || p.subject != nil || p.body != nil
            guard hasField else { return }
            composeEmailSeedTo = p.to ?? ""
            composeEmailSeedSubject = p.subject ?? ""
            composeEmailSeedBody = p.body ?? ""
            withAnimation(.snappy(duration: 0.18)) { isComposePresented = true }
            services.pendingMailto = nil
        }
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
            await services.loadSharedAIProfile()
        }
        .onChange(of: services.authService.showsOnboarding) { _, showsLogin in
            guard showsLogin else { return }
            services.closeSettingsWindowIfPresent()
        }
        .onAppear {
            if services.authService.showsOnboarding {
                services.closeSettingsWindowIfPresent()
            }
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

                Text("Checking your session…")
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

            // Inline create / compose side panels — replace the previous .sheet modal
            // presentations so users can keep using the rest of the app while a draft
            // or quick-add form is open.
            if isCreatePresented {
                Divider()
                MacCreateSheet(
                    defaultType: defaultCreateType,
                    onComposeEmail: { body in
                        composeEmailSeedTo = ""
                        composeEmailSeedSubject = ""
                        composeEmailSeedBody = body
                        isComposePresented = true
                    },
                    onClose: {
                        withAnimation(.snappy(duration: 0.18)) { isCreatePresented = false }
                    }
                )
                .frame(width: 440)
                .frame(maxHeight: .infinity)
                .background(MacTheme.contentBackground)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if isComposePresented {
                Divider()
                MacEmailComposeView(
                    to: composeEmailSeedTo,
                    subject: composeEmailSeedSubject,
                    body: composeEmailSeedBody,
                    onClose: {
                        withAnimation(.snappy(duration: 0.18)) { isComposePresented = false }
                        composeEmailSeedTo = ""
                        composeEmailSeedSubject = ""
                        composeEmailSeedBody = ""
                    }
                )
                .frame(width: 560)
                .frame(maxHeight: .infinity)
                .background(MacTheme.contentBackground)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

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
                                if sidePaneDragStartWidth == nil { sidePaneDragStartWidth = CGFloat(sidePaneWidth) }
                                let start = sidePaneDragStartWidth ?? CGFloat(sidePaneWidth)
                                // Negative translation = dragging left = wider panel.
                                // Clamp to keep the panel usable: never narrower than 280pt
                                // (assistant chat is unreadable below this) or wider than 600pt
                                // (would crowd the main content area on smaller windows).
                                let proposed = start - value.translation.width
                                sidePaneWidth = Double(max(280, min(600, proposed)))
                            }
                            .onEnded { _ in sidePaneDragStartWidth = nil }
                    )

                MacAssistantPanel(
                    isPresented: $isAssistantPresented,
                    displayMode: assistantDisplayModeBinding,
                    floatingSize: assistantFloatingSizeBinding,
                    floatingOffset: assistantFloatingOffsetBinding,
                    onFloatingLayoutCommit: syncAssistantFloatLayoutToDisk,
                    currentSelection: selection
                )
                .frame(width: CGFloat(sidePaneWidth))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isAssistantPresented && assistantDisplayMode == .sidepane)
        .animation(.snappy(duration: 0.18), value: isCreatePresented)
        .animation(.snappy(duration: 0.18), value: isComposePresented)
        // Floating mode — overlay panel positioned bottom-right
        .overlay(alignment: .bottomTrailing) {
            if isAssistantPresented && assistantDisplayMode == .floating {
                MacAssistantPanel(
                    isPresented: $isAssistantPresented,
                    displayMode: assistantDisplayModeBinding,
                    floatingSize: assistantFloatingSizeBinding,
                    floatingOffset: assistantFloatingOffsetBinding,
                    onFloatingLayoutCommit: syncAssistantFloatLayoutToDisk,
                    currentSelection: selection
                )
                .animation(nil, value: assistantFloatSize)
                .animation(nil, value: assistantFloatOffset)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isAssistantPresented && assistantDisplayMode == .floating)
        // Offline banner — shown when the device has no network connectivity
        .overlay(alignment: .top) {
            if !services.networkMonitor.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11, weight: .semibold))
                    Text("No internet connection")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.red.gradient, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: services.networkMonitor.isConnected)
        .onChange(of: selection) { _, newValue in
            // Persist sidebar selection so the next launch restores the same view.
            selectionStorageKey = newValue.storageKey
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { syncAssistantFloatLayoutToDisk() }
        }
        .onChange(of: assistantDisplayModeRaw) { _, _ in
            if isAssistantPresented { syncAssistantFloatLayoutToDisk() }
        }
        .onAppear {
            loadAssistantFloatLayoutIfNeeded()
            applyStartupSelectionIfNeeded()
        }
    }

    /// The NavigationSplitView with detail content, toolbar, and sheets.
    /// Extracted so the assistant panel HStack can wrap it cleanly.
    private var mainNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebarView(
                selection: $selection,
                isEmailExpanded: $isEmailExpanded,
                isCalendarExpanded: $isCalendarExpanded,
                onOpenSettings: { openWindow(id: "settings") },
                onCompose: { isComposePresented = true },
                taskCount: incompleteTasks.count,
                onCreateItem: { isCreatePresented = true },
                onCalendarDayTap: { date in
                    calendarSelectedDate = date
                    selection = .calendar(.all)
                }
            )
            .navigationSplitViewColumnWidth(
                min: compactSidebar ? 176 : 200,
                ideal: compactSidebar ? 196 : 220,
                max: compactSidebar ? 220 : 260
            )
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                // Content-area base background — slightly tinted to match iOS app tone
                MacTheme.contentBackground
                    .ignoresSafeArea()

                // Calendar manages its own scroll and needs edge-to-edge layout;
                // other views use a standard padded ScrollView wrapper.
                if selection.category == "calendar" || selection.category == "docs" || selection.category == "email" {
                    // These views manage their own layout/scroll and need edge-to-edge frames.
                    // WKWebView (docs) must not be wrapped in a ScrollView — it has no intrinsic height
                    // and would render as 0-height (black) inside one.
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
            .toolbar {
                // Context-specific toolbar items based on active view
                ToolbarItemGroup(placement: .secondaryAction) {
                    contextToolbarItems
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    // Notifications — AI-powered digest of tasks due, events, and important emails
                    Button {
                        isNotificationsPresented = true
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.9))
                    }
                    .help("Daily Brief")
                    .accessibilityLabel("Notifications")
                    .accessibilityHint("Opens your daily brief with tasks, events, and emails")
                    .macClickablePointer()
                    .popover(isPresented: $isNotificationsPresented, arrowEdge: .bottom) {
                        MacNotificationCenterView()
                    }

                    Menu {
                        Button("Preferences…  ⌘,") { openWindow(id: "settings") }
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.9))
                    }
                    .tint(Color.primary.opacity(0.55))
                    .help("More Options")
                    .accessibilityLabel("More options menu")
                    .macClickablePointer()

                    // Create / compose
                    Button {
                        isCreatePresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                            .background(
                                MacTheme.surfaceCard.opacity(0.95),
                                in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                                    .stroke(MacTheme.cardBorder.opacity(0.9), lineWidth: 0.6)
                            )
                    }
                    .help("New Item (⌘N)")
                    .accessibilityLabel("Create new item")
                    .macClickablePointer()
                    .keyboardShortcut("n", modifiers: .command)

                    // Search — ⌘K (command palette convention)
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                            .background(
                                MacTheme.surfaceCard.opacity(0.95),
                                in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                                    .stroke(MacTheme.cardBorder.opacity(0.9), lineWidth: 0.6)
                            )
                    }
                    .macClickablePointer()
                    .keyboardShortcut("k", modifiers: .command)
                    .help("Search (⌘K)")
                    .accessibilityLabel("Search")
                }
            }
        }
        .animation(.none, value: selection)
        // Global keyboard shortcuts registered via hidden background buttons.
        // These cover actions not already bound to visible toolbar buttons.
        .background {
            Group {
                // ⌘,  — Settings (standard macOS convention)
                Button("") { openWindow(id: "settings") }
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

                Button("") { selection = .meetings }
                    .keyboardShortcut("5", modifiers: .command)

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
        // Compose & create are now inline trailing panels in `mainAppView`,
        // not modal sheets. Search remains a modal sheet (small, transient).
        .sheet(isPresented: $isSearchPresented) {
            searchSheet
                .frame(minWidth: 480, minHeight: 360)
        }
        .sheet(item: $selectedEmailThread) { thread in
            MacEmailThreadView(threadId: thread.value)
                .frame(minWidth: 560, minHeight: 400)
        }
        .onAppear {
            applyStartupSelectionIfNeeded()
        }
    }

    private var onboardingStep: Int? {
        guard !services.authService.showsOnboarding else { return nil }
        if !services.hasConfiguredGmailPrompt { return 1 }
        if !services.hasConfiguredCalendarPrompt { return 2 }
        if !services.hasConfiguredRemindersPrompt { return 3 }
        if !services.hasConfiguredStartupViewPrompt { return 4 }
        if !services.hasConfiguredNotificationsPrompt { return 5 }
        if !services.hasConfiguredDefaultMailPrompt { return 6 }
        return nil
    }

    private var startupSelection: MacPrimarySelection {
        switch services.startupView {
        case "inbox":
            return .email(.inbox)
        case "tasks":
            return .tasks
        case "meetings":
            return .meetings
        default:
            return .home
        }
    }

    private func applyStartupSelectionIfNeeded() {
        guard !hasAppliedStartupSelection else { return }
        if services.restoreLastViewedPage,
           let restored = MacPrimarySelection.fromStorageKey(selectionStorageKey) {
            selection = restored
        } else {
            selection = startupSelection
        }
        hasAppliedStartupSelection = true
    }

    // MARK: - Context Toolbar

    /// Toolbar items that change based on the active view.
    /// Only functional actions are shown — filter menus removed until backend filtering is wired up.
    @ViewBuilder
    private var contextToolbarItems: some View {
        switch selection.category {
        case "email":
            // Mark all read — functional, wired to EmailService
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

        default:
            // No context toolbar items for calendar, tasks, home
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
            MacTasksView(onCreateItem: { isCreatePresented = true })
        case .email(let section):
            MacEmailInboxView(folder: section.rawValue)
        case .calendar:
            MacCalendarView(viewMode: $calendarViewMode, selectedDate: $calendarSelectedDate)
        case .meetings:
            MacMeetingsView()
        case .docs:
            MacDocsView()
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
