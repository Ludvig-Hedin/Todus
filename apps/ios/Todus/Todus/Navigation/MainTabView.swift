import EventKit
import SwiftUI
import UIKit

/// Root navigation shell backed by the native iOS `TabView`.
///
/// The legacy floating `CustomTabBar` implementation remains in the codebase,
/// but it is no longer presented in the live shell.
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
    @State private var createTabId = UUID()
    @State private var emailTabId = UUID()
    @State private var calendarTabId = UUID()

    @State private var sheetTab: AppTab? = nil

    /// FAB edge length scales with the user's Dynamic Type setting so the AI button
    /// stays tappable at the largest accessibility sizes (it used to clip the
    /// sparkles icon and become hard to hit at XXL+).
    @ScaledMetric(relativeTo: .body) private var fabSize: CGFloat = 58

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
        .overlay(alignment: .bottomTrailing) {
            if !services.hideTabBar && !showCreateSheet {
                aiFAB
                    .ignoresSafeArea(.keyboard)
                    .padding(.trailing, 18)
                    .padding(.bottom, 68)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: services.hideTabBar)
        .animation(.easeOut(duration: 0.15), value: showCreateSheet)
    }

    // MARK: - Tab View

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .id(homeTabId)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.inactiveIcon()) }
                .tag(AppTab.home)

            NavigationStack { TasksTabView() }
                .id(tasksTabId)
                .tabItem { Label(AppTab.tasks.title, systemImage: AppTab.tasks.inactiveIcon()) }
                .tag(AppTab.tasks)

            Color.clear
                .id(createTabId)
                // Hide the empty placeholder from VoiceOver — the tab item itself is
                // exposed by `TabView` so adding a second focusable element here just
                // landed users on an empty page when swiping the rotor.
                .accessibilityHidden(true)
                .tabItem { Label(AppTab.create.title, systemImage: AppTab.create.inactiveIcon()) }
                .tag(AppTab.create)

            NavigationStack { EmailInboxView() }
                .id(emailTabId)
                .tabItem { Label(AppTab.email.title, systemImage: AppTab.email.inactiveIcon()) }
                .tag(AppTab.email)

            // Resolve permission at render time so the tab switches the moment the
            // user grants/revokes access via Settings or the in-app prompt. The
            // earlier @State-only flag could go stale if the system callback fired
            // before the next `scenePhase` transition or `EKEventStoreChangedNotification`
            // arrival. We keep `calendarPermissionGranted` as a hint so onChange/onAppear
            // can still trigger refreshes, but use `canReadEvents()` for the actual
            // branch — same source of truth, no desync.
            NavigationStack {
                if calendarPermissionGranted || services.calendarService.canReadEvents() {
                    CalendarTabView()
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    CalendarPermissionView()
                        .background(AppTheme.backgroundTop)
                }
            }
            .id(calendarTabId)
            .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.inactiveIcon()) }
            .tag(AppTab.calendar)
        }
        .tint(Color(UIColor.label))
        .onChange(of: selectedTab) { old, new in
            guard new != old else { return }

            if new == .create {
                createSheetInitialType = createType(for: old)
                selectedTab = old
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { showCreateSheet = true }
                return
            }

            previousNavigationTab = new
            services.currentTab = new
            if new == .calendar {
                calendarPermissionGranted = services.calendarService.canReadEvents()
            }
        }
        .overlay {
            if showCreateSheet {
                CreateSheet(initialType: createSheetInitialType, isPresented: $showCreateSheet)
                    .zIndex(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: settingsBinding) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: aiChatBinding, onDismiss: {
            services.showsAIChat = false
        }) {
            AIChatView(currentTab: previousNavigationTab)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: composeEmailBinding, onDismiss: {
            services.composeEmailSeedBody = nil
            services.composeEmailSeedTo = nil
            services.composeEmailSeedCc = nil
            services.composeEmailSeedBcc = nil
            services.composeEmailSeedSubject = nil
            services.composeEmailSeedAttachments = []
        }) {
            EmailComposeView(
                to: services.composeEmailSeedTo,
                cc: services.composeEmailSeedCc,
                bcc: services.composeEmailSeedBcc,
                subject: services.composeEmailSeedSubject,
                body: services.composeEmailSeedBody,
                seededAttachments: services.composeEmailSeedAttachments
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .appSheetBackground()
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(item: $sheetTab) { tab in
            NavigationStack { sheetContent(for: tab) }
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .onChange(of: services.navigateTo) { _, newTab in
            guard let tab = newTab else { return }
            if tab == .meetings {
                sheetTab = .meetings
            } else {
                selectedTab = tab
            }
            services.navigateTo = nil
        }
        .onChange(of: services.showsComposeEmail) { _, isPresented in
            if !isPresented {
                services.composeEmailSeedBody = nil
                services.composeEmailSeedTo = nil
                services.composeEmailSeedCc = nil
                services.composeEmailSeedBcc = nil
                services.composeEmailSeedSubject = nil
                services.composeEmailSeedAttachments = []
            }
        }
        .onChange(of: services.requestCreateSheet) { _, requested in
            guard let requested else { return }
            createSheetInitialType = requested
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { showCreateSheet = true }
            services.requestCreateSheet = nil
        }
        .onChange(of: services.navigateToSheet) { _, tab in
            guard let tab else { return }
            if tab == .meetings {
                sheetTab = .meetings
            } else {
                selectedTab = tab
                sheetTab = nil
            }
            services.navigateToSheet = nil
        }
        .onAppear {
            if !visibleContentTabs.contains(selectedTab) {
                selectedTab = .home
            }
            calendarPermissionGranted = services.calendarService.canReadEvents()
            // Positive returning-user signal — see Keys.hasReachedMainTab
            // doc. Used by the startup-card migration so a fresh install
            // with a stale Keychain bearer can't silently skip the card.
            if !services.hasReachedMainTab {
                services.hasReachedMainTab = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                calendarPermissionGranted = services.calendarService.canReadEvents()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusCalendarAuthorizationDidChange)) { _ in
            calendarPermissionGranted = services.calendarService.canReadEvents()
        }
        // Pick up direct EventKit store changes (calendars added/removed, permission
        // toggled in Settings) so the tab swaps instantly rather than waiting for the
        // next scene-active transition.
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            calendarPermissionGranted = services.calendarService.canReadEvents()
        }
    }

    private var visibleContentTabs: Set<AppTab> {
        [.home, .tasks, .email, .calendar]
    }

    private var aiFAB: some View {
        Button {
            services.showsAIChat = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(aiGradient)
                .frame(width: fabSize, height: fabSize)
                .contentShape(Circle())
        }
        .buttonStyle(FABButtonStyle())
        .fabGlass()
        .accessibilityLabel("Open AI Assistant")
        .accessibilityIdentifier("ai.fab.open")
    }

    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA / 255.0, blue: 0xF5 / 255.0), location: 0.087),
                .init(color: Color(red: 0xEF / 255.0, green: 0, blue: 0xC2 / 255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38 / 255.0), location: 0.580),
                .init(color: Color(red: 0xF9 / 255.0, green: 0x9F / 255.0, blue: 0), location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }

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

    /// Subtle red-tinted capsule with an inline "Retry" CTA so the user has a clear
    /// action when the indicator surfaces — the silent grey pill used to read as
    /// background chrome and got ignored. Pressing Retry asks the path monitor to
    /// re-check connectivity and pings any registered reconnect handler so queued
    /// work flushes immediately rather than waiting for the next path change.
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
            Text("Offline")
                .font(.system(size: 12, weight: .semibold))
            Button {
                // Best-effort reconnect: trigger any onReconnect handler so callers
                // (sync, drafts) get a chance to re-attempt. The actual path status
                // will update via NWPathMonitor's normal callback.
                services.networkMonitor.onReconnect?()
            } label: {
                Text("Retry")
                    .font(.system(size: 12, weight: .semibold))
                    .underline()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry network connection")
        }
        .foregroundStyle(Color.red.opacity(0.95))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.red.opacity(0.10)))
                .overlay(Capsule().stroke(Color.red.opacity(0.25), lineWidth: 0.8))
        )
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
            // "Sign In Again" is the recommended action — using `.destructive` painted
            // it red, which read as "delete account" to a fair number of testers. No
            // role means it gets the default tint and Cancel is the single muted choice.
            Button("Sign In Again") {
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
