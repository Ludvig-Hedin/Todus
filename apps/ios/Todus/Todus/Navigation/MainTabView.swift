import EventKit
import SwiftUI
import UIKit

/// Root navigation shell backed by the native iOS `TabView` with a custom
/// compact icon-only tab bar rendered via `safeAreaInset`.
///
/// Tab order: Docs · Tasks · Home · Email · Calendar · Meetings
///
/// Two floating action buttons sit above the tab bar:
///   • Left  — create FAB (plus icon) opens `CreateSheet`
///   • Right — AI FAB (sparkles) opens `AIChatView`
struct MainTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @SceneStorage("selectedTab") private var selectedTab: AppTab = .home
    /// Last real tab — used as context hint for AI chat.
    @State private var previousNavigationTab: AppTab = .home

    @State private var showCreateSheet = false
    @State private var createSheetInitialType: CreateItemType = .auto
    @State private var showSessionExpiredConfirm = false
    @State private var calendarPermissionGranted = false

    @State private var homeTabId = UUID()
    @State private var tasksTabId = UUID()
    @State private var emailTabId = UUID()
    @State private var calendarTabId = UUID()
    @State private var docsTabId = UUID()
    @State private var meetingsTabId = UUID()

    @State private var sheetTab: AppTab? = nil

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
        // Single overlay for both FABs. The VStack + ignoresSafeArea anchors to the
        // real screen bottom, not the keyboard-adjusted bottom, so FABs stay fixed
        // in place when the keyboard is shown (e.g. email search bar focused).
        .overlay {
            if !services.hideTabBar && !showCreateSheet {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        createFAB
                            .padding(.leading, 18)
                        Spacer()
                        aiFAB
                            .padding(.trailing, 18)
                    }
                    .padding(.bottom, 68)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: services.hideTabBar)
        .animation(.easeOut(duration: 0.15), value: showCreateSheet)
    }

    // MARK: - Tab View

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            // Resolve permission at render time so the tab switches the moment the
            // user grants/revokes access via Settings or the in-app prompt.
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

            NavigationStack { TasksTabView() }
                .id(tasksTabId)
                .tabItem { Label(AppTab.tasks.title, systemImage: AppTab.tasks.inactiveIcon()) }
                .tag(AppTab.tasks)

            NavigationStack { HomeView() }
                .id(homeTabId)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.inactiveIcon()) }
                .tag(AppTab.home)

            NavigationStack { EmailInboxView() }
                .id(emailTabId)
                .tabItem { Label(AppTab.email.title, systemImage: AppTab.email.inactiveIcon()) }
                .tag(AppTab.email)

            DocsListView()
                .id(docsTabId)
                .tabItem { Label(AppTab.docs.title, systemImage: AppTab.docs.inactiveIcon()) }
                .tag(AppTab.docs)

            NavigationStack { MeetingsListView() }
                .id(meetingsTabId)
                .tabItem { Label(AppTab.meetings.title, systemImage: AppTab.meetings.inactiveIcon()) }
                .tag(AppTab.meetings)
        }
        .tint(Color(UIColor.label))
        .toolbar(services.hideTabBar ? .hidden : .visible, for: .tabBar)
        .onChange(of: selectedTab) { old, new in
            guard new != old else { return }
            previousNavigationTab = new
            services.currentTab = new
            if new == .calendar {
                calendarPermissionGranted = services.calendarService.canReadEvents()
            }
            // Reset tab bar visibility when switching tabs
            if services.hideTabBar {
                services.hideTabBar = false
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
            selectedTab = tab
            services.navigateTo = nil
        }
        .onChange(of: services.navigateToSheet) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            services.navigateToSheet = nil
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
            withAnimation(.easeOut(duration: 0.22)) { showCreateSheet = true }
            services.requestCreateSheet = nil
        }
        .onAppear {
            if !visibleContentTabs.contains(selectedTab) {
                selectedTab = .home
            }
            calendarPermissionGranted = services.calendarService.canReadEvents()
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
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            calendarPermissionGranted = services.calendarService.canReadEvents()
        }
    }

    private var visibleContentTabs: Set<AppTab> {
        [.home, .tasks, .email, .calendar, .docs, .meetings]
    }

    // MARK: - FABs

    private var createFAB: some View {
        Button {
            createSheetInitialType = createType(for: selectedTab)
            withAnimation(.easeOut(duration: 0.22)) {
                showCreateSheet = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(UIColor.label))
                .frame(width: fabSize, height: fabSize)
                .contentShape(Circle())
        }
        .buttonStyle(FABButtonStyle())
        .fabGlass()
        .accessibilityLabel("Create new item")
        .accessibilityIdentifier("create.fab.open")
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
        case .ai:
            AIChatView(currentTab: previousNavigationTab)
        default:
            EmptyView()
        }
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
            Text("Offline")
                .font(.system(size: 12, weight: .semibold))
            Button {
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
