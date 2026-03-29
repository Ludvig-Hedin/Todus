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

    @SceneStorage("selectedTab") private var selectedTab: AppTab = .home

    @State private var showCreateSheet = false
    @State private var showAIChat     = false
    @State private var createDefaultType: CreateItemType = .auto

    /// Wire to EventKit / CalendarService when ready.
    @State private var hasUpcomingCalendarEvent = false
    /// Confirmation dialog for session expired banner — prevents accidental sign-out on tap.
    @State private var showSessionExpiredConfirm = false

    /// Cached calendar authorization — updated on appear and whenever the app
    /// returns to the foreground (covers both in-app system dialog and Settings round-trips).
    @State private var calendarPermissionGranted = false

    /// Measured height of the AppTopHeader overlay on the calendar tab.
    /// Passed to CalendarContainerView as additionalSafeAreaInsets.top so CalendarKit's
    /// scroll content starts below our header instead of sliding under it.
    @State private var calendarHeaderHeight: CGFloat = 90

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // All tabs are rendered simultaneously and kept alive across tab switches.
            // Only the selected tab is visible and interactive — the others are hidden
            // with opacity(0) + allowsHitTesting(false). This prevents the 5+ second
            // hangs caused by destroying and recreating tab content (and re-firing all
            // .task / .onAppear / network fetches) on every tab change.
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .opacity(selectedTab == tab ? 1 : 0)
                    .allowsHitTesting(selectedTab == tab)
            }
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
        .animation(.easeInOut(duration: 0.3), value: services.networkMonitor.isConnected)
        .animation(.easeInOut(duration: 0.3), value: services.authService.isSessionExpired)
            // Prevent the keyboard from pushing the entire view (including tab bar) upward.
            // Individual tab views handle keyboard avoidance internally (e.g. ScrollView scrolling,
            // or the TasksTabView composer using KeyboardObserver to position above the keyboard).
            .ignoresSafeArea(.keyboard)
            // Custom tab bar sits in the safe-area inset slot — content is
            // automatically pushed up so nothing hides behind the bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    hasUpcomingCalendarEvent: hasUpcomingCalendarEvent,
                    onAI:     { showAIChat     = true },
                    onCreate: {
                        createDefaultType = defaultCreateType(for: selectedTab)
                        withAnimation(.snappy(duration: 0.2)) {
                            showCreateSheet = true
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)   // breathing room between scrollable content and the bar
                .padding(.bottom, 8) // space above the home indicator
            }
            .overlay {
                if showCreateSheet {
                    CreateSheet(
                        isPresented: $showCreateSheet,
                        defaultType: createDefaultType
                    )
                    .zIndex(20)
                }
            }
            .sheet(isPresented: $showAIChat) {
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
            // Listen for requestCreateSheet from child views (e.g. HomeView "+" buttons)
            .onChange(of: services.requestCreateSheet) { _, requested in
                guard let type = requested else { return }
                createDefaultType = type
                // Match the animation used by the tab bar's create button
                withAnimation(.snappy(duration: 0.2)) {
                    showCreateSheet = true
                }
                services.requestCreateSheet = nil
            }
            // Keep AppServices.currentTab in sync so AI suggestions are context-aware
            .onChange(of: selectedTab) { _, newTab in
                services.currentTab = newTab
            }
            // Re-check calendar permission whenever the app becomes active.
            // Covers both the in-app system dialog (app goes .inactive while it shows)
            // and returning from iOS Settings after granting access.
            .onAppear { calendarPermissionGranted = services.calendarService.canReadEvents() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    calendarPermissionGranted = services.calendarService.canReadEvents()
                }
            }
    }

    private func defaultCreateType(for tab: AppTab) -> CreateItemType {
        switch tab {
        case .calendar:
            return .event
        case .tasks:
            return .task
        case .home:
            return .auto
        case .email:
            return .email
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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tab Content
    // ─────────────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView() }
        case .tasks:
            NavigationStack { TasksTabView() }
        case .email:
            NavigationStack { EmailInboxView() }
        // CalendarContainerView has its own UINavigationController.
        // Wrapping in NavigationStack broke safe-area propagation (clips bottom 30%).
        // ignoresSafeArea(.container, edges: .bottom) lets CalendarKit's scroll view
        // extend under the tab bar, matching the iOS Calendar app behaviour.
        // If calendar permission denied/not-determined, show CalendarPermissionView instead.
        case .calendar:
            if calendarPermissionGranted {
                ZStack(alignment: .top) {
                    // CalendarKit UIKit view — topInset pushes its scroll content below our header
                    CalendarContainerView(topInset: calendarHeaderHeight)
                    // AppTopHeader overlay — sits above CalendarKit content.
                    // Background extends through the status-bar area so no CalendarKit
                    // content bleeds through. onGeometryChange measures the rendered height
                    // (including padding) and feeds it back to CalendarContainerView.
                    AppTopHeader(title: "Calendar")
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8) // Gap between title and calendar day row
                        .background(
                            // Match CalendarKit's white content background, not the gray app background
                            Color(UIColor.systemBackground)
                                .ignoresSafeArea(edges: .top)
                        )
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            calendarHeaderHeight = height
                        }
                }
                .ignoresSafeArea(.container, edges: .bottom)
            } else {
                NavigationStack {
                    CalendarPermissionView()
                        .background(AppTheme.backgroundTop)
                }
            }
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
                services.authService.signOut()
                services.authStore.signOutToGuest()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
