import SwiftUI

/// Root navigation shell.
///
/// Layout:
///   Native bottom tab bar: Home | Tasks | [+] | Email | Calendar
///   AI floating button: sparkles gradient FAB above the right side of the tab bar.
///
/// • The [+] tab is intercepted — tapping it shows the create sheet and the
///   selected tab is immediately reverted to the prior one.
/// • `services.hideTabBar` hides both the native tab bar and the AI FAB
///   (used by EmailThreadView for its own bottom bar).
struct MainTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @SceneStorage("selectedTab") private var selectedTab: AppTab = .home
    /// Last real (non-create) tab — used as context hint for AI chat.
    @State private var previousNavigationTab: AppTab = .home

    @State private var showCreateSheet = false
    @State private var createSheetInitialType: CreateItemType = .auto
    @State private var showSessionExpiredConfirm = false
    @State private var calendarPermissionGranted = false

    @State private var homeTabId = UUID()
    @State private var tasksTabId = UUID()
    @State private var emailTabId = UUID()
    @State private var calendarTabId = UUID()

    @State private var sheetTab: AppTab? = nil

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            tabView

            if !services.networkMonitor.isConnected {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if services.authService.isSessionExpired {
                sessionExpiredBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: services.networkMonitor.isConnected)
        .animation(.easeInOut(duration: 0.3), value: services.authService.isSessionExpired)
        .ignoresSafeArea(.keyboard)
        // FAB is in the outer overlay so its reference point is the ZStack's safe-area-
        // inset bottom edge (= above the home indicator). Tab bar adds another 49pt on
        // top of that, so padding(.bottom, 49 + 12) clears the tab bar with 12pt of air.
        .overlay(alignment: .bottomTrailing) {
            if !services.hideTabBar {
                aiFAB
                    .padding(.trailing, 20)
                    .padding(.bottom, 49 + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: services.hideTabBar)
    }

    // MARK: - Tab View

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .id(homeTabId)
                .tabItem { Label("Home", systemImage: selectedTab == .home ? "house.fill" : "house") }
                .tag(AppTab.home)

            NavigationStack { TasksTabView() }
                .id(tasksTabId)
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(AppTab.tasks)

            // Action tab — intercepted immediately; content is never shown.
            Color.clear.ignoresSafeArea()
                .tabItem { Label("New", systemImage: "plus.circle.fill") }
                .tag(AppTab.create)

            NavigationStack { EmailInboxView() }
                .id(emailTabId)
                .tabItem { Label("Email", systemImage: selectedTab == .email ? "envelope.fill" : "envelope") }
                .tag(AppTab.email)

            Group {
                if calendarPermissionGranted {
                    CalendarTabView()
                } else {
                    NavigationStack {
                        CalendarPermissionView()
                            .background(AppTheme.backgroundTop)
                    }
                }
            }
            .id(calendarTabId)
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(AppTab.calendar)
        }
        .tint(AppTheme.accentBlue)
        .toolbar(services.hideTabBar ? .hidden : .visible, for: .tabBar)
        .onChange(of: selectedTab) { old, new in
            switch new {
            case .create:
                let revertTo: AppTab = (old == .create) ? .home : old
                selectedTab = revertTo
                createSheetInitialType = createType(for: revertTo)
                withAnimation(.snappy(duration: 0.2)) { showCreateSheet = true }
            default:
                previousNavigationTab = new
                services.currentTab = new
            }
        }
        .overlay {
            if showCreateSheet {
                CreateSheet(initialType: createSheetInitialType, isPresented: $showCreateSheet)
                    .zIndex(20)
            }
        }
        .sheet(isPresented: settingsBinding) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: aiChatBinding, onDismiss: {
            services.showsAIChat = false
        }) {
            AIChatView(currentTab: previousNavigationTab)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: composeEmailBinding, onDismiss: {
            services.composeEmailSeedBody = nil
            services.composeEmailSeedTo = nil
            services.composeEmailSeedSubject = nil
        }) {
            EmailComposeView(
                to: services.composeEmailSeedTo,
                subject: services.composeEmailSeedSubject,
                body: services.composeEmailSeedBody
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(item: $sheetTab) { tab in
            NavigationStack { sheetContent(for: tab) }
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .onChange(of: services.navigateTo) { _, newTab in
            guard let tab = newTab else { return }
            selectedTab = tab
            services.navigateTo = nil
        }
        .onChange(of: services.showsComposeEmail) { _, isPresented in
            if !isPresented { services.composeEmailSeedBody = nil }
        }
        .onChange(of: services.requestCreateSheet) { _, requested in
            guard let requested else { return }
            createSheetInitialType = requested
            withAnimation(.snappy(duration: 0.2)) { showCreateSheet = true }
            services.requestCreateSheet = nil
        }
        .onChange(of: services.navigateToSheet) { _, tab in
            guard let tab else { return }
            if tab == .meetings {
                sheetTab = tab
            } else {
                selectedTab = tab
                sheetTab = nil
            }
            services.navigateToSheet = nil
        }
        .onAppear {
            if selectedTab == .create { selectedTab = .home }
            calendarPermissionGranted = services.calendarService.canReadEvents()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                calendarPermissionGranted = services.calendarService.canReadEvents()
            }
        }
    }

    // MARK: - AI Floating Action Button

    private var aiFAB: some View {
        Button {
            services.showsAIChat = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(aiGradient)
                .frame(width: 56, height: 56)
                .fabGlass()
        }
        .buttonStyle(FABButtonStyle())
    }

    /// Figma: linear-gradient(151deg, #00AAF5 8.66%, #EF00C2 26.94%, #FF0038 57.95%, #F99F00 91.34%)
    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0,          green: 0xAA/255.0, blue: 0xF5/255.0), location: 0.087),
                .init(color: Color(red: 0xEF/255.0, green: 0,          blue: 0xC2/255.0), location: 0.269),
                .init(color: Color(red: 1,          green: 0,          blue: 0x38/255.0), location: 0.580),
                .init(color: Color(red: 0xF9/255.0, green: 0x9F/255.0, blue: 0),         location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }

    // MARK: - Helpers

    private func createType(for tab: AppTab) -> CreateItemType {
        switch tab {
        case .tasks:    return .task
        case .calendar: return .event
        case .email:    return .email
        default:        return .auto
        }
    }

    // MARK: - Bindings

    private var settingsBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsSettings
    }

    private var aiChatBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsAIChat
    }

    private var composeEmailBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsComposeEmail
    }

    // MARK: - Sheet content (non-tab pages)

    @ViewBuilder
    private func sheetContent(for tab: AppTab) -> some View {
        switch tab {
        case .meetings:
            MeetingsListView()
        case .home, .tasks, .email, .calendar, .create:
            EmptyView()
        case .ai:
            AIChatView(currentTab: previousNavigationTab)
        }
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text("No internet connection")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.red.opacity(0.85), in: Capsule())
        .padding(.top, 4)
    }

    // MARK: - Session Expired Banner

    private var sessionExpiredBanner: some View {
        Button {
            showSessionExpiredConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Session expired")
                    .font(.system(size: 13, weight: .medium))
                Text("Sign in again")
                    .font(.system(size: 13, weight: .semibold))
                    .underline()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .confirmationDialog("Your session has expired", isPresented: $showSessionExpiredConfirm, titleVisibility: .visible) {
            Button("Sign In Again", role: .destructive) {
                services.authService.isSessionExpired = false
                services.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - FAB helpers

private extension View {
    /// Liquid Glass on iOS 26; ultraThinMaterial circle with shadow on earlier OS.
    @ViewBuilder
    func fabGlass() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

