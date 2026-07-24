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
    /// Unsynced-task count captured when the session-expired banner is tapped —
    /// signing in again wipes local data, so the confirm warns before deleting
    /// tasks that never reached the server (TD-03).
    @State private var sessionExpiredUnsyncedCount = 0
    @State private var calendarPermissionGranted = false

    @State private var homeTabId = UUID()
    @State private var tasksTabId = UUID()
    @State private var emailTabId = UUID()
    @State private var calendarTabId = UUID()
    @State private var docsTabId = UUID()
    @State private var meetingsTabId = UUID()

    @State private var sheetTab: AppTab? = nil

    /// Transient banner shown when a just-captured task is rolled back because
    /// its sync to the backend failed (offline, server error, or expired
    /// session). Without this the rollback deleted the user's task silently —
    /// `TaskCaptureService` published `lastRollbackCount`/`lastRollbackAt` for a
    /// banner that never existed. Auto-dismisses after a few seconds.
    @State private var captureFailureVisible = false
    @State private var captureFailureCount = 0
    @State private var captureFailureDismiss: Task<Void, Never>? = nil

    /// Transient banner shown when a bulk-capture paste exceeded
    /// `TaskCaptureService.maxBulkCaptureLines` and extra lines were silently dropped.
    /// `TaskCaptureService` publishes `lastTruncatedCount`/`lastTruncatedAt` for this
    /// banner, mirroring the capture-failure banner above. Auto-dismisses after a few
    /// seconds.
    @State private var captureTruncatedVisible = false
    @State private var captureTruncatedCount = 0
    @State private var captureTruncatedDismiss: Task<Void, Never>? = nil

    /// Transient success toast for CreateSheet captures ("Task added to Inbox").
    /// Driven by `services.captureSuccessMessage` — a dateless task capture was
    /// previously invisible from Home, leaving a "did that work?" moment on the
    /// app's core flow.
    @State private var captureSuccessToast: ToastMessage? = nil

    @ScaledMetric(relativeTo: .body) private var fabSize: CGFloat = 58

    /// Vertical room a scroll view needs at its bottom edge so the last row stays
    /// tappable above the floating FABs. Imported by `HomeView` (and any future
    /// FAB-overlapping tab) via `MainTabView.fabClearance` so the two layouts
    /// can't drift apart.
    ///
    /// Math: `fabSize` (58) + the overlay's `.padding(.bottom, 68)` separation
    /// from the native tab bar = 126, rounded down to 120 for a tight look with
    /// a small visual buffer above the FABs.
    static let fabClearance: CGFloat = 120

    // MARK: - Body

    /// Any transient top banner active — drives the top safe-area inset so the
    /// stack reserves space instead of overlaying the nav/toolbar row.
    private var anyTopBannerVisible: Bool {
        !services.networkMonitor.isConnected
            || services.authService.isSessionExpired
            || captureFailureVisible
            || captureTruncatedVisible
    }

    var body: some View {
        tabView
        // Stacked transient banners — VStack keeps them from overlapping when
        // more than one is active (e.g. offline + capture failure). Rendered as
        // a top safeAreaInset so they reserve space and push each tab's
        // nav/toolbar row down instead of covering the title and trailing
        // buttons (TD-25).
        .safeAreaInset(edge: .top, spacing: 0) {
            if anyTopBannerVisible {
                VStack(spacing: 6) {
                    if !services.networkMonitor.isConnected {
                        offlineBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if services.authService.isSessionExpired {
                        sessionExpiredBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if captureFailureVisible {
                        captureFailureBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if captureTruncatedVisible {
                        captureTruncatedBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: services.networkMonitor.isConnected)
        .animation(.easeInOut(duration: 0.3), value: services.authService.isSessionExpired)
        .animation(.easeInOut(duration: 0.3), value: captureFailureVisible)
        .animation(.easeInOut(duration: 0.3), value: captureTruncatedVisible)
        // Success confirmation for CreateSheet captures — sits above the FABs.
        .toast($captureSuccessToast, bottomInset: Self.fabClearance)
        .onChange(of: services.captureSuccessMessage) { _, newValue in
            guard let message = newValue else { return }
            services.captureSuccessMessage = nil
            captureSuccessToast = .success(message)
        }
        .onChange(of: services.captureService.lastRollbackAt) { _, newValue in
            guard newValue != nil else { return }
            captureFailureCount = services.captureService.lastRollbackCount
            captureFailureVisible = true
            captureFailureDismiss?.cancel()
            captureFailureDismiss = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                captureFailureVisible = false
            }
        }
        .onChange(of: services.captureService.lastTruncatedAt) { _, newValue in
            guard newValue != nil else { return }
            captureTruncatedCount = services.captureService.lastTruncatedCount
            captureTruncatedVisible = true
            captureTruncatedDismiss?.cancel()
            captureTruncatedDismiss = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                captureTruncatedVisible = false
            }
        }
        // Single overlay for both FABs. The VStack + ignoresSafeArea anchors to the
        // real screen bottom, not the keyboard-adjusted bottom, so FABs stay fixed
        // in place when the keyboard is shown (e.g. email search bar focused).
        .overlay {
            // FABs stay pinned while scrolling — only the tab bar hides on scroll.
            // (Previously gated on `hideTabBar`, which made both FABs vanish mid-scroll.)
            if !showCreateSheet {
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

    /// Tabs shown in the bar, in the user's chosen order (home-first, max 4 —
    /// enforced by TabBarCustomizationView.save() and the AppServices loader).
    private var barTabs: [AppTab] {
        let chosen = services.tabBarTabs.filter { AppTab.contentTabs.contains($0) }
        return chosen.isEmpty ? AppTab.defaultNavTabs : chosen
    }

    private var tabView: some View {
        // Keep every destination as a real Tab. With more than five items,
        // UIKit supplies its native More list for the overflow. This matters:
        // hiding the extra Tab content made programmatic selections render a
        // blank page, while trying to hide only the tab item produced a nested
        // second More screen.
        TabView(selection: $selectedTab) {
            ForEach(barTabs) { tab in
                Tab(value: tab) {
                    tabRoot(for: tab)
                } label: {
                    Label(tab.title, systemImage: tab.inactiveIcon())
                }
            }

            ForEach(AppTab.contentTabs.filter { !barTabs.contains($0) }) { tab in
                Tab(value: tab) {
                    tabRoot(for: tab)
                } label: {
                    Label(tab.title, systemImage: tab.inactiveIcon())
                }
            }

            Tab(value: AppTab.more) {
                SettingsView(showsDone: false)
            } label: {
                Label(AppTab.more.title, systemImage: AppTab.more.inactiveIcon())
            }
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
            services.composeEmailSeedFromConnectionId = nil
        }) {
            EmailComposeView(
                to: services.composeEmailSeedTo,
                cc: services.composeEmailSeedCc,
                bcc: services.composeEmailSeedBcc,
                subject: services.composeEmailSeedSubject,
                body: services.composeEmailSeedBody,
                seededAttachments: services.composeEmailSeedAttachments,
                fromConnectionId: services.composeEmailSeedFromConnectionId
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
                services.composeEmailSeedFromConnectionId = nil
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
            // Seed tab context from the restored `selectedTab` (@SceneStorage).
            // `onChange(of: selectedTab)` only fires on a *change*, not on the
            // restored initial value, so without this the AI chat context chip
            // and suggestions stayed `.home` after a relaunch onto another tab.
            previousNavigationTab = selectedTab
            services.currentTab = selectedTab
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
        Set(AppTab.contentTabs).union([.more])
    }

    /// Root view for a content tab. Kept in one place so direct and native-More
    /// selections render identically.
    @ViewBuilder
    private func tabRoot(for tab: AppTab) -> some View {
        switch tab {
        case .calendar:
            // Resolve permission at render time so the tab switches the moment
            // the user grants/revokes access via Settings or the in-app prompt.
            NavigationStack {
                // Google events come from the backend and don't need EventKit —
                // a Gmail-connected user who declined Apple Calendar access must
                // not be walled out of the whole tab with their events hidden.
                if calendarPermissionGranted
                    || services.calendarService.canReadEvents()
                    || services.connectionsService.connections.contains(where: { $0.providerId == "google" }) {
                    CalendarTabView()
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    CalendarPermissionView()
                        .background(AppTheme.backgroundTop)
                }
            }
            .id(calendarTabId)
        case .tasks:
            NavigationStack { TasksTabView() }
                .id(tasksTabId)
        case .home:
            NavigationStack { HomeView() }
                .id(homeTabId)
        case .email:
            NavigationStack { EmailInboxView() }
                .id(emailTabId)
        case .docs:
            // DocsListView owns its own NavigationStack/SplitView — don't nest.
            DocsListView()
                .id(docsTabId)
        case .meetings:
            NavigationStack { MeetingsListView() }
                .id(meetingsTabId)
        case .create, .ai, .more:
            EmptyView()
        }
    }

    // MARK: - FABs

    private var createFAB: some View {
        Button {
            AppHaptic.light.play()
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
            AppHaptic.light.play()
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
    }

    // MARK: - Capture Failure Banner

    /// Shown briefly when a captured task was rolled back after its sync failed.
    /// Tells the user the task was NOT saved so they can re-enter it, instead of
    /// the previous silent deletion.
    private var captureFailureBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(captureFailureCount > 1
                 ? "Couldn’t save \(captureFailureCount) tasks — check your connection"
                 : "Couldn’t save your task — check your connection")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.92), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Capture Truncated Banner

    /// Shown briefly when a bulk paste exceeded the per-submission line cap and the
    /// extra lines were dropped. Tells the user only the first N were captured so they
    /// know to re-paste the rest, instead of the previous silent drop.
    private var captureTruncatedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 12, weight: .semibold))
            Text("Captured first \(TaskCaptureService.maxBulkCaptureLines) — \(captureTruncatedCount) more weren't added")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.92), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Session Expired Banner

    private var sessionExpiredBanner: some View {
        Button {
            sessionExpiredUnsyncedCount = services.unsyncedTaskCount()
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
        .confirmationDialog("Your session has expired", isPresented: $showSessionExpiredConfirm, titleVisibility: .visible) {
            // Destructive when unsynced tasks exist — signing in again wipes
            // local data, deleting tasks that never reached the server (TD-03).
            Button("Sign In Again", role: sessionExpiredUnsyncedCount > 0 ? .destructive : nil) {
                services.authService.isSessionExpired = false
                services.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if sessionExpiredUnsyncedCount > 0 {
                Text(sessionExpiredUnsyncedCount == 1
                    ? "1 task hasn't synced yet and will be deleted."
                    : "\(sessionExpiredUnsyncedCount) tasks haven't synced yet and will be deleted.")
            }
        }
    }
}

// MARK: - FAB helpers

extension View {
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

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
