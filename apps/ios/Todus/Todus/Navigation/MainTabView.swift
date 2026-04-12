import SwiftUI

/// Root navigation shell.
///
/// Layout:
///   • Full-screen tab content (NavigationStack per tab).
///   • Custom floating tab bar injected via `safeAreaInset(edge: .bottom)` so
///     the system automatically pushes scroll content up to avoid overlap —
///     identical behaviour to the system tab bar.
///   • Bar: two glass pills — nav tabs (fill width) + action buttons (fixed).
struct MainTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @AppStorage("TaskApp.hasSeenTabBarCoachmarks") private var hasSeenTabBarCoachmarks = false
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .home

    @State private var showCreateSheet = false
    @State private var showAIChat     = false
    /// Controls the More overflow sheet (Docs, future items)
    @State private var showMoreSheet  = false
    /// Presents a non-tab-bar page (e.g. Meetings) as a full-screen sheet from Home
    @State private var sheetTab: AppTab? = nil

    /// Wire to EventKit / CalendarService when ready.
    @State private var hasUpcomingCalendarEvent = false
    /// Confirmation dialog for session expired banner — prevents accidental sign-out on tap.
    @State private var showSessionExpiredConfirm = false
    @State private var activeTabTrace: PerformanceTrace.IntervalState?

    /// Cached calendar authorization — updated on appear and whenever the app
    /// returns to the foreground (covers both in-app system dialog and Settings round-trips).
    @State private var calendarPermissionGranted = false

    /// Measured height of the AppTopHeader overlay on the calendar tab.
    /// Passed to CalendarContainerView as additionalSafeAreaInsets.top so CalendarKit's
    /// scroll content starts below our header instead of sliding under it.

    @State private var showTabBarCoachmarks = false

    @State private var homeTabId = UUID()
    @State private var tasksTabId = UUID()
    @State private var emailTabId = UUID()
    @State private var meetingsTabId = UUID()
    @State private var calendarTabId = UUID()

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Render only the active tab. Keeping every tab tree alive caused broad
            // invalidation and hidden work whenever shared observable state changed.
            tabContent(for: selectedTab)
            // Dismiss keyboard when tapping anywhere outside a text field.
            // simultaneousGesture ensures buttons/links still receive taps.
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            )

            // Offline banner — shown when network is unavailable
            if !services.networkMonitor.isConnected {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Session expired banner — shown when a 401 is received and refresh fails
            if services.authService.isSessionExpired {
                sessionExpiredBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showTabBarCoachmarks {
                tabBarCoachmarks
                    .padding(.horizontal, 24)
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: services.networkMonitor.isConnected)
        .animation(.easeInOut(duration: 0.3), value: services.authService.isSessionExpired)
        .animation(.snappy(duration: 0.25), value: showTabBarCoachmarks)
            // Prevent the keyboard from pushing the entire view (including tab bar) upward.
            // Individual tab views handle keyboard avoidance internally (e.g. ScrollView scrolling,
            // or the TasksTabView composer using KeyboardObserver to position above the keyboard).
            .ignoresSafeArea(.keyboard)
            // Custom tab bar sits in the safe-area inset slot — content is
            // automatically pushed up so nothing hides behind the bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Hide the custom floating tab bar when a detail view requests it
                // (e.g. EmailThreadView) so its own bottom bar is visible.
                if !services.hideTabBar {
                    ZStack(alignment: .bottom) {
                        // Full-bleed gradient scrim — must be declared first (behind the pills).
                        // ignoresSafeArea(edges: .bottom) extends it past the home indicator to the
                        // physical screen bottom. No horizontal padding so it spans wall-to-wall.
                        LinearGradient(
                            stops: [
                                .init(color: AppTheme.backgroundTop.opacity(0.5), location: 0),
                                .init(color: AppTheme.backgroundTop.opacity(0),   location: 1),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)

                        // Floating tab bar pills — sit on top of the gradient
                        CustomTabBar(
                            selectedTab: $selectedTab,
                            tabs: services.tabBarTabs,
                            hasUpcomingCalendarEvent: hasUpcomingCalendarEvent,
                            onAI:     {
                                dismissTabBarCoachmarks()
                                services.showsAIChat = true
                            },
                            onCreate: {
                                dismissTabBarCoachmarks()
                                withAnimation(.snappy(duration: 0.2)) {
                                    showCreateSheet = true
                                }
                            },
                            onMore: {
                                dismissTabBarCoachmarks()
                                showMoreSheet = true
                            },
                            onReselect: { tab in
                                switch tab {
                                case .home: homeTabId = UUID()
                                case .tasks: tasksTabId = UUID()
                                case .email: emailTabId = UUID()
                                case .meetings: meetingsTabId = UUID()
                                case .calendar: calendarTabId = UUID()
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: services.hideTabBar)
            .overlay {
                if showCreateSheet {
                    CreateSheet(isPresented: $showCreateSheet)
                        .zIndex(20)
                }
            }
            .sheet(isPresented: $showAIChat, onDismiss: {
                services.showsAIChat = false
            }) {
                AIChatView(currentTab: selectedTab)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(services.appearancePreference.colorScheme)
            }
            .sheet(isPresented: settingsBinding) {
                SettingsView()
                    .presentationDetents([.medium, .large])
                    .preferredColorScheme(services.appearancePreference.colorScheme)
            }
            // Global compose sheet — triggered by HomeView email "+" button
            .sheet(isPresented: composeEmailBinding, onDismiss: {
                services.composeEmailSeedBody = nil
            }) {
                if let seedBody = services.composeEmailSeedBody,
                   !seedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmailComposeView(body: seedBody)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .preferredColorScheme(services.appearancePreference.colorScheme)
                } else {
                    EmailComposeView()
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .preferredColorScheme(services.appearancePreference.colorScheme)
                }
            }
            // More sheet — overflow navigation (Docs, future items)
            .sheet(isPresented: $showMoreSheet) {
                MoreSheetView { destination in
                    services.navigateTo = destination
                }
                    .preferredColorScheme(services.appearancePreference.colorScheme)
            }
            // React to tab navigation requests from child views (e.g. HomeView).
            .onChange(of: services.navigateTo) { _, newTab in
                guard let tab = newTab else { return }
                selectedTab = tab
                services.navigateTo = nil
            }
            .onChange(of: services.showsComposeEmail) { _, isPresented in
                if !isPresented {
                    services.composeEmailSeedBody = nil
                }
            }
            .onChange(of: services.showsAIChat) { _, isPresented in
                showAIChat = isPresented
            }
            // Listen for requestCreateSheet from child views (e.g. HomeView "+" buttons)
            .onChange(of: services.requestCreateSheet) { _, requested in
                guard requested != nil else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    showCreateSheet = true
                }
                services.requestCreateSheet = nil
            }
            // Present non-tab pages (e.g. Meetings) as a sheet when requested from child views
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
            .sheet(item: $sheetTab) { tab in
                // Wrap in NavigationStack so the view gets proper navigation context.
                // sheetContent avoids re-wrapping views that already embed their own NavigationStack.
                NavigationStack { sheetContent(for: tab) }
                    .preferredColorScheme(services.appearancePreference.colorScheme)
            }
            // Keep AppServices.currentTab in sync so AI suggestions are context-aware
            .onChange(of: selectedTab) { _, newTab in
                dismissTabBarCoachmarks()
                services.currentTab = newTab
                activeTabTrace = PerformanceTrace.beginInterval(
                    PerformanceTrace.tabSwitch,
                    message: "Tab switch begin: \(newTab.rawValue)"
                )
            }
            // Re-check calendar permission whenever the app becomes active.
            // Covers both the in-app system dialog (app goes .inactive while it shows)
            // and returning from iOS Settings after granting access.
            .onAppear {
                calendarPermissionGranted = services.calendarService.canReadEvents()
                maybeShowTabBarCoachmarks()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    calendarPermissionGranted = services.calendarService.canReadEvents()
                    maybeShowTabBarCoachmarks()
                }
            }
            .task(id: selectedTab) {
                await Task.yield()
                if let activeTabTrace {
                    PerformanceTrace.endInterval(
                        PerformanceTrace.tabSwitch,
                        activeTabTrace,
                        message: "Tab switch end: \(selectedTab.rawValue)"
                    )
                    self.activeTabTrace = nil
                } else {
                    PerformanceTrace.event(
                        PerformanceTrace.tabSwitch,
                        message: "Initial tab rendered: \(selectedTab.rawValue)"
                    )
                }
            }
    }

    // MARK: - Bindings

    private var settingsBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsSettings
    }

    private var composeEmailBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsComposeEmail
    }

    private var tabBarCoachmarks: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack {
                coachmarkBubble("More pages")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                coachmarkBubble("Ask AI")
                coachmarkBubble("Create")
            }
        }
    }

    private func coachmarkBubble(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.cardBorder.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private func maybeShowTabBarCoachmarks() {
        guard services.hasConfiguredTabBarPrompt else { return }
        guard !hasSeenTabBarCoachmarks else { return }
        guard !showTabBarCoachmarks else { return }

        showTabBarCoachmarks = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            dismissTabBarCoachmarks()
        }
    }

    private func dismissTabBarCoachmarks() {
        guard showTabBarCoachmarks || !hasSeenTabBarCoachmarks else { return }
        hasSeenTabBarCoachmarks = true
        withAnimation(.snappy(duration: 0.2)) {
            showTabBarCoachmarks = false
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tab Content
    // ─────────────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView() }
                .id(homeTabId)
        case .tasks:
            NavigationStack { TasksTabView() }
                .id(tasksTabId)
        case .email:
            NavigationStack { EmailInboxView() }
                .id(emailTabId)
        // CalendarContainerView has its own UINavigationController.
        // Wrapping in NavigationStack broke safe-area propagation (clips bottom 30%).
        // ignoresSafeArea(.container, edges: .bottom) lets CalendarKit's scroll view
        // extend under the tab bar, matching the iOS Calendar app behaviour.
        // If calendar permission denied/not-determined, show CalendarPermissionView instead.
        case .meetings:
            NavigationStack { MeetingsListView() }
                .id(meetingsTabId)
        case .calendar:
            if calendarPermissionGranted {
                CalendarTabView()
                    .id(calendarTabId)
            } else {
                NavigationStack {
                    CalendarPermissionView()
                        .background(AppTheme.backgroundTop)
                }
                .id(calendarTabId)
            }
        }
    }

    /// Bare content views for non-tab-bar pages presented as sheets from Home.
    /// These intentionally exclude the outer NavigationStack (added by the sheet caller).
    @ViewBuilder
    private func sheetContent(for tab: AppTab) -> some View {
        switch tab {
        case .meetings:
            MeetingsListView()
        case .home, .tasks, .email, .calendar:
            EmptyView()
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
            // Show confirmation before signing out to prevent accidental taps
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
