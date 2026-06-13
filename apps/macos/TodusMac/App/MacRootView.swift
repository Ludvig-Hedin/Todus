import SwiftUI
import SwiftData

// MARK: - Navigation Model

enum EmailSection: String, CaseIterable, Hashable {
    // Primary folders — shown at the top of the expanded email group.
    // `drafts` maps to the backend folder key "draft" (singular, matches
    // FOLDERS.DRAFT + iOS); the implicit "drafts" raw value silently bypassed
    // the backend's draft-listing special case and showed an empty/wrong list.
    case inbox, drafts = "draft", sent
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

// MARK: - Floating Panel Shell

/// Thin wrapper that owns resize-gesture state and applies `.frame()`/`.offset()`/shadow
/// to the floating AI panel. Because only this view reads `geo.liveSize`/`geo.liveOffset`,
/// `MacAssistantPanel` is NOT re-rendered on every drag/resize frame — only layout is updated.
private struct FloatingPanelShell<Content: View>: View {
    let geo: FloatingPanelGeometry
    @Binding var floatingSize: CGSize
    @Binding var floatingOffset: CGSize
    var onCommit: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var resizeDragStart: CGSize?
    @State private var isResizing: Bool = false

    private let minW: CGFloat = 320, maxW: CGFloat = 800
    private let minH: CGFloat = 400, maxH: CGFloat = 900
    private let edgeHit: CGFloat = 5, cornerHit: CGFloat = 16

    // MARK: Resize gesture helpers

    private enum ResizePart {
        case top, bottom, leading, trailing
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    private func clamp(_ size: CGSize) -> CGSize {
        CGSize(
            width:  min(max(size.width,  minW), maxW),
            height: min(max(size.height, minH), maxH)
        )
    }

    private func resizeGesture(_ part: ResizePart) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if resizeDragStart == nil {
                    resizeDragStart = geo.liveSize
                    isResizing = true
                }
                let s = resizeDragStart ?? geo.liveSize
                let t = v.translation
                let new: CGSize
                switch part {
                case .top:           new = CGSize(width: s.width,           height: s.height - t.height)
                case .bottom:        new = CGSize(width: s.width,           height: s.height + t.height)
                case .leading:       new = CGSize(width: s.width - t.width, height: s.height)
                case .trailing:      new = CGSize(width: s.width + t.width, height: s.height)
                case .topLeading:    new = CGSize(width: s.width - t.width, height: s.height - t.height)
                case .topTrailing:   new = CGSize(width: s.width + t.width, height: s.height - t.height)
                case .bottomLeading: new = CGSize(width: s.width - t.width, height: s.height + t.height)
                case .bottomTrailing:new = CGSize(width: s.width + t.width, height: s.height + t.height)
                }
                let clamped = clamp(new)
                if clamped != geo.liveSize {
                    var t = Transaction(animation: nil)
                    t.disablesAnimations = true
                    withTransaction(t) { geo.liveSize = clamped }
                }
            }
            .onEnded { _ in
                floatingSize = geo.liveSize
                resizeDragStart = nil
                isResizing = false
                onCommit?()
            }
    }

    private func resizeCursor(_ part: ResizePart, hovering: Bool) {
        if hovering {
            switch part {
            case .top, .bottom:                             NSCursor.resizeUpDown.set()
            case .leading, .trailing:                       NSCursor.resizeLeftRight.set()
            case .topLeading:     NSCursor.frameResize(position: .topLeft, directions: .all).set()
            case .bottomTrailing: NSCursor.frameResize(position: .bottomRight, directions: .all).set()
            case .topTrailing:    NSCursor.frameResize(position: .topRight, directions: .all).set()
            case .bottomLeading:  NSCursor.frameResize(position: .bottomLeft, directions: .all).set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: Resize strips

    @ViewBuilder private func edgeStrip(_ part: ResizePart, axis: Axis) -> some View {
        let isH = axis == .horizontal
        Color.clear
            .frame(width: isH ? edgeHit : nil, height: isH ? nil : edgeHit)
            .frame(maxWidth: isH ? nil : .infinity, maxHeight: isH ? .infinity : nil)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture(part))
            .onHover { resizeCursor(part, hovering: $0) }
    }

    @ViewBuilder private func cornerView(_ part: ResizePart) -> some View {
        Color.clear
            .frame(width: cornerHit, height: cornerHit)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture(part))
            .onHover { resizeCursor(part, hovering: $0) }
    }

    var body: some View {
        content()
            .frame(width: geo.liveSize.width, height: geo.liveSize.height)
            .shadow(color: .black.opacity(isResizing ? 0 : 0.18), radius: 20, x: 0, y: 8)
            // Edge resize strips (corners excluded so they don't overlap)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Spacer().frame(width: cornerHit)
                    edgeStrip(.top, axis: .vertical)
                    Spacer().frame(width: cornerHit)
                }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 0) {
                    Spacer().frame(width: cornerHit)
                    edgeStrip(.bottom, axis: .vertical)
                    Spacer().frame(width: cornerHit)
                }
            }
            .overlay(alignment: .leading) {
                VStack(spacing: 0) {
                    Spacer().frame(height: cornerHit)
                    edgeStrip(.leading, axis: .horizontal)
                    Spacer().frame(height: cornerHit)
                }
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: 0) {
                    Spacer().frame(height: cornerHit)
                    edgeStrip(.trailing, axis: .horizontal)
                    Spacer().frame(height: cornerHit)
                }
            }
            .overlay(alignment: .topLeading)    { cornerView(.topLeading) }
            .overlay(alignment: .topTrailing)   { cornerView(.topTrailing) }
            .overlay(alignment: .bottomLeading) { cornerView(.bottomLeading) }
            .overlay(alignment: .bottomTrailing){ cornerView(.bottomTrailing) }
            .offset(geo.liveOffset)
            .onAppear {
                geo.liveSize   = floatingSize
                geo.liveOffset = floatingOffset
            }
            .onChange(of: floatingSize) { _, newSize in
                guard resizeDragStart == nil, newSize != geo.liveSize else { return }
                geo.liveSize = newSize
            }
            .onChange(of: floatingOffset) { _, newOffset in
                if geo.liveOffset != newOffset { geo.liveOffset = newOffset }
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
    /// Live floating geometry — owned by `FloatingPanelShell`, shared with `MacAssistantPanel`
    /// for header-drag. Not @AppStorage; disk sync happens only on gesture end.
    @State private var floatingGeo = FloatingPanelGeometry()
    /// Committed size/offset — synced to disk; used to initialise `floatingGeo` on appear.
    @State private var committedFloatSize: CGSize = CGSize(width: 400, height: 560)
    @State private var committedFloatOffset: CGSize = .zero
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

    private func loadAssistantFloatLayoutIfNeeded() {
        guard !didLoadAssistantFloatLayout else { return }
        didLoadAssistantFloatLayout = true
        let d = UserDefaults.standard
        let w  = d.double(forKey: "mac_assistant_floating_width")
        let h  = d.double(forKey: "mac_assistant_floating_height")
        let ox = d.double(forKey: "mac_assistant_floating_offset_x")
        let oy = d.double(forKey: "mac_assistant_floating_offset_y")
        committedFloatSize   = CGSize(width: w > 0 ? w : 400, height: h > 0 ? h : 560)
        committedFloatOffset = CGSize(width: ox, height: oy)
    }

    private func syncAssistantFloatLayoutToDisk() {
        let d = UserDefaults.standard
        d.set(floatingGeo.liveSize.width,    forKey: "mac_assistant_floating_width")
        d.set(floatingGeo.liveSize.height,   forKey: "mac_assistant_floating_height")
        d.set(floatingGeo.liveOffset.width,  forKey: "mac_assistant_floating_offset_x")
        d.set(floatingGeo.liveOffset.height, forKey: "mac_assistant_floating_offset_y")
        committedFloatSize   = floatingGeo.liveSize
        committedFloatOffset = floatingGeo.liveOffset
    }

    /// Thread ID to open immediately when navigating to the email inbox from Home.
    /// Cleared by MacEmailInboxView after consumption so re-entering inbox doesn't reopen it.
    @State private var pendingEmailThreadId: String? = nil
    @State private var isComposePresented = false
    @State private var isCreatePresented = false
    @State private var isSearchPresented = false
    @State private var isNotificationsPresented = false
    @State private var selectedEmailThread: IdentifiableString? = nil
    /// Drives the `MacSharedConversationView` sheet when a `todus://share?slug=…`
    /// deep link arrives via `Notification.Name.todusOpenSharedConversation`.
    /// Wrapped in `IdentifiableString` so we can use `.sheet(item:)` cleanly.
    @State private var sharedConversationSlug: IdentifiableString? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var calendarViewMode: String = "Week"
    @State private var calendarSelectedDate: Date = Date()
    @State private var composeEmailSeedBody: String = ""
    @State private var composeEmailSeedTo: String = ""
    @State private var composeEmailSeedSubject: String = ""
    @State private var hasBootstrappedAuthState = false
    @State private var hasAppliedStartupSelection = false
    /// Gates the `fetchUserProfile` + `loadSharedAIProfile` task so it runs once per
    /// authenticated session instead of every `isAuthenticated` flip. Without this,
    /// transient auth-state changes during background refresh re-fire the profile
    /// fetch and clobber unsaved Settings edits (e.g. `customInstructions`).
    /// Reset by the `showsOnboarding` change handler so re-login refreshes correctly.
    @State private var didFetchProfileForSession = false

    // Accent color — drives .tint() on root so SwiftUI controls update immediately
    @AppStorage("mac_accent_color") private var accentColorKey = "blue"

    var body: some View {
        Group {
            if !hasBootstrappedAuthState {
                // Always show the restoring spinner until the bootstrap task completes —
                // including for users with no persisted token. The view is brief in that
                // case (one frame), but it prevents a flash of the sign-in screen on
                // every cold launch while AuthService finishes preloading from the
                // Keychain off the main actor.
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
            } else if !services.hasSeenWelcomeTour {
                // Optional product explainer with prominent Skip — one-shot per
                // install. Final step before the main shell.
                MacWelcomeTourView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                // Authenticated or guest → show main app shell
                mainAppView
                    .transition(.opacity)
                    .onAppear {
                        // Mark the user as having reached the main shell so the
                        // welcome-tour migration in MacAppServices.init can flag
                        // returning users on the next launch.
                        if !services.hasReachedMainShell {
                            services.hasReachedMainShell = true
                        }
                    }
            }
        }
        // Allow users to select and copy text anywhere in the app.
        .textSelection(.enabled)
        // Disable system focus rings on buttons/cards — keeps keyboard focus without blue chrome.
        .focusEffectDisabled()
        // Primary text tint so symbols and controls are not system / accent blue.
        .tint(Color.primary)
        .animation(MacTheme.Motion.slow, value: services.authService.showsOnboarding)
        .animation(MacTheme.Motion.slow, value: services.authService.isAuthenticated)
        .animation(MacTheme.Motion.slow, value: services.hasConfiguredGmailPrompt)
        .animation(MacTheme.Motion.slow, value: services.hasConfiguredCalendarPrompt)
        .animation(MacTheme.Motion.slow, value: services.hasConfiguredRemindersPrompt)
        .animation(MacTheme.Motion.slow, value: services.hasConfiguredStartupViewPrompt)
        .animation(MacTheme.Motion.slow, value: services.hasConfiguredNotificationsPrompt)
        .animation(MacTheme.Motion.slow, value: services.hasConfiguredDefaultMailPrompt)
        .animation(MacTheme.Motion.slow, value: services.hasSeenWelcomeTour)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let onboardingStep = onboardingStep {
                HStack {
                    Spacer()
                    Text("\(onboardingStep) of \(onboardingTotalSteps)")
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
            guard !isComposePresented else { return }
            let hasField = p.to != nil || p.subject != nil || p.body != nil
            guard hasField else { return }
            composeEmailSeedTo = p.to ?? ""
            composeEmailSeedSubject = p.subject ?? ""
            composeEmailSeedBody = p.body ?? ""
            withAnimation(MacTheme.Motion.base) { isComposePresented = true }
            services.pendingMailto = nil
        }
        .task {
            guard !hasBootstrappedAuthState else { return }

            // Wait for the persisted session to actually restore before flipping the
            // bootstrap flag — otherwise users with a valid Keychain token see a
            // momentary sign-in flash while restorePersistedSession is in flight.
            if services.authService.hasPersistedBearerToken {
                _ = await services.authService.restorePersistedSession()
            }
            hasBootstrappedAuthState = true
        }
        .task(id: hasBootstrappedAuthState) {
            // Validate session on launch — but DON'T sign out on failure.
            // attemptSilentRefresh() returns false for both expired tokens AND
            // network errors (offline, DNS hiccup). Signing out here would
            // destroy a valid Keychain-stored session during a transient outage.
            // Instead, just refresh isSessionExpired so the UI can show a banner.
            // Actual sign-out on 401 is handled reactively by the API client.
            //
            // Keyed on `hasBootstrappedAuthState` so it RE-RUNS once the bootstrap
            // task flips the flag. Without the id it fired once on appear — before
            // restorePersistedSession() finished and before the flag was set — so
            // the guard always failed and the launch refresh never actually ran.
            guard hasBootstrappedAuthState, services.authService.isAuthenticated else { return }
            _ = await services.authService.attemptSilentRefresh()
        }
        .task(id: services.authService.isAuthenticated) {
            // Fetch user profile (name, avatar, email) ONCE per authenticated session.
            // The `didFetchProfileForSession` gate prevents transient auth-state flips
            // (e.g. background token refresh) from re-firing the fetch and clobbering
            // unsaved Settings edits via `loadSharedAIProfile`. Reset on sign-out so
            // a subsequent sign-in still triggers a refresh.
            guard services.authService.isAuthenticated else { return }
            guard !didFetchProfileForSession else { return }
            await services.authService.fetchUserProfile()
            await services.loadSharedAIProfile()
            didFetchProfileForSession = true
        }
        .onChange(of: services.authService.showsOnboarding) { _, showsLogin in
            guard showsLogin else { return }
            // Reset the per-session fetch gate so the next sign-in re-fetches the
            // profile and shared AI prefs (otherwise a sign-out → sign-in cycle in
            // the same app session would leave the new user with stale data).
            didFetchProfileForSession = false
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
                        withAnimation(MacTheme.Motion.base) { isCreatePresented = false }
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
                        withAnimation(MacTheme.Motion.base) { isComposePresented = false }
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
                // Draggable resize divider — 1pt visual line with an 8pt invisible grab zone.
                // `withTransaction { disablesAnimations }` prevents implicit animations from
                // interpolating intermediate widths on every drag frame (was the lag source).
                ZStack {
                    Color.clear.frame(width: 8)
                    Rectangle()
                        .fill(MacTheme.cardBorder)
                        .frame(width: 1)
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if sidePaneDragStartWidth == nil { sidePaneDragStartWidth = CGFloat(sidePaneWidth) }
                            let start = sidePaneDragStartWidth ?? CGFloat(sidePaneWidth)
                            let proposed = start - value.translation.width
                            var txn = Transaction()
                            txn.disablesAnimations = true
                            withTransaction(txn) {
                                sidePaneWidth = Double(max(280, min(600, proposed)))
                            }
                        }
                        .onEnded { _ in sidePaneDragStartWidth = nil }
                )

                MacAssistantPanel(
                    isPresented: $isAssistantPresented,
                    displayMode: assistantDisplayModeBinding,
                    currentSelection: selection
                )
                .frame(width: CGFloat(sidePaneWidth))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(MacTheme.Motion.base, value: isAssistantPresented && assistantDisplayMode == .sidepane)
        .animation(MacTheme.Motion.base, value: isCreatePresented)
        .animation(MacTheme.Motion.base, value: isComposePresented)
        // Floating mode — overlay panel positioned bottom-right, wrapped in FloatingPanelShell
        // so only the shell re-renders per drag/resize frame (not MacAssistantPanel).
        .overlay(alignment: .bottomTrailing) {
            if isAssistantPresented && assistantDisplayMode == .floating {
                FloatingPanelShell(
                    geo: floatingGeo,
                    floatingSize: $committedFloatSize,
                    floatingOffset: $committedFloatOffset,
                    onCommit: syncAssistantFloatLayoutToDisk
                ) {
                    MacAssistantPanel(
                        isPresented: $isAssistantPresented,
                        displayMode: assistantDisplayModeBinding,
                        geo: floatingGeo,
                        onHeaderDragCommit: syncAssistantFloatLayoutToDisk,
                        currentSelection: selection
                    )
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(MacTheme.Motion.base, value: isAssistantPresented && assistantDisplayMode == .floating)
        // Full-screen mode — panel covers the entire content area
        .overlay {
            if isAssistantPresented && assistantDisplayMode == .full {
                MacAssistantPanel(
                    isPresented: $isAssistantPresented,
                    displayMode: assistantDisplayModeBinding,
                    currentSelection: selection
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .animation(MacTheme.Motion.base, value: isAssistantPresented && assistantDisplayMode == .full)
        .onChange(of: selection) { _, newValue in
            // Persist sidebar selection so the next launch restores the same view.
            selectionStorageKey = newValue.storageKey
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { syncAssistantFloatLayoutToDisk() }
        }
        .onChange(of: assistantDisplayModeRaw) { _, newMode in
            syncAssistantFloatLayoutToDisk()
            // When switching away from window mode back to floating/sidepane,
            // re-show the panel in the main window.
            if newMode != AssistantDisplayMode.window.rawValue && !isAssistantPresented {
                isAssistantPresented = true
            }
            // When switching to window mode, open the detached window.
            if newMode == AssistantDisplayMode.window.rawValue && isAssistantPresented {
                openWindow(id: "ai-chat")
            }
        }
        .onAppear {
            loadAssistantFloatLayoutIfNeeded()
            applyStartupSelectionIfNeeded()
            // If last session left mode as .window, open the window again.
            if assistantDisplayMode == .window && isAssistantPresented {
                openWindow(id: "ai-chat")
            }
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
                        withAnimation(MacTheme.Motion.base) {
                            isAssistantPresented = true
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if !services.networkMonitor.isConnected {
                    HStack(spacing: 5) {
                        Image(systemName: "wifi.slash")
                            .imageScale(.small)
                            .fontWeight(.medium)
                        Text("Offline — changes sync when reconnected")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(MacTheme.Motion.slow, value: services.networkMonitor.isConnected)
            .animation(MacTheme.Motion.base, value: isAssistantPresented)
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
                        MacNotificationCenterView(onOpen: { relatedId, type in
                            // Route the notification tap to the relevant tab so the popover
                            // never silently dismisses without context. Email rows that carry
                            // a threadId open the thread sheet directly; everything else
                            // falls back to the matching tab landing surface.
                            switch type {
                            case .taskDue, .reminder:
                                selection = .tasks
                            case .importantEmail:
                                if let threadId = relatedId, !threadId.isEmpty {
                                    selectedEmailThread = IdentifiableString(value: threadId)
                                } else {
                                    selection = .email(.inbox)
                                }
                            case .event:
                                selection = .calendar(.all)
                            }
                        })
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
                            withAnimation(MacTheme.Motion.base) {
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
                    withAnimation(MacTheme.Motion.base) {
                        columnVisibility = columnVisibility == .detailOnly
                            ? .automatic : .detailOnly
                    }
                }
                .keyboardShortcut("b", modifiers: .command)

                // ⌘L — Toggle AI Assistant (not just open — toggle so it can be closed too)
                Button("") {
                    withAnimation(MacTheme.Motion.base) {
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
        // Shared AI conversation viewer — opened by `todus://share?slug=…` deep links
        // dispatched as `Notification.Name.todusOpenSharedConversation` from
        // `TodusMacApp.dispatchValidatedURL`.
        .sheet(item: $sharedConversationSlug) { wrapper in
            MacSharedConversationView(slug: wrapper.value)
                .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 640)
        }
        // MARK: - NotificationCenter deep-link routing
        //
        // `MacAppDelegate` / `TodusMacApp` translate deep links and notification
        // taps into `Notification.Name` posts. We observe them here so the root
        // view can flip selection state, present sheets, or surface the AI panel
        // without `MacAppServices` needing to know about routing.
        .onReceive(NotificationCenter.default.publisher(for: .todusOpenSharedConversation)) { note in
            if let slug = note.object as? String, !slug.isEmpty {
                sharedConversationSlug = IdentifiableString(value: slug)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusOpenEmailThread)) { note in
            guard let threadId = note.object as? String, !threadId.isEmpty else { return }
            pendingEmailThreadId = threadId
            // If we're not on email, switch to it (the inbox consumes the pending
            // id on appear). If we're already on email, the inbox reacts to the
            // changed `initialThreadId` via `.onChange` — no view recreation
            // needed (the old selection-toggle hack coalesced into a no-op).
            if selection.category != "email" {
                selection = .email(.inbox)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusNavigateToEmail)) { _ in
            if selection.category != "email" {
                selection = .email(.inbox)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusOpenAIConversation)) { note in
            // Always open the assistant panel so the user has a visible target,
            // even if no conversation id was supplied (e.g. unknown category).
            services.showsAssistantPanel = true
            let conversationIdString =
                (note.userInfo?["conversationId"] as? String)
                ?? (note.object as? String)
            guard let raw = conversationIdString, !raw.isEmpty,
                  let uuid = UUID(uuidString: raw) else { return }
            // Only load if the saved conversation actually exists locally —
            // otherwise leave the panel in its current state to avoid wiping
            // an in-flight chat.
            if let saved = services.aiChatService.savedConversations.first(where: { $0.id == uuid }) {
                services.aiChatService.loadConversation(saved)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusNavigateToTasks)) { _ in
            selection = .tasks
        }
        // `.todusCompleteTask` is informational — the underlying SwiftData
        // `@Query` re-renders automatically once the task row's `completed`
        // flag flips, so the UI requires no explicit action here.
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
        if !services.hasSeenWelcomeTour { return 6 }
        return nil
    }

    /// Total number of onboarding steps shown — keep in sync with the if/else chain
    /// in `body` and the numbered branches in `onboardingStep`. Currently: Gmail,
    /// Calendar, Reminders, Startup view, Notifications, Welcome tour (6).
    private var onboardingTotalSteps: Int { 6 }

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
            MacHomeView(
                onNavigate: { selection = $0 },
                onNavigateEmailThread: { threadId in
                    // Navigate to inbox and open the thread inline (no modal sheet).
                    pendingEmailThreadId = threadId
                    selection = .email(.inbox)
                }
            )
        case .tasks:
            MacTasksView(onCreateItem: { isCreatePresented = true })
        case .email(let section):
            MacEmailInboxView(
                folder: section.rawValue,
                initialThreadId: pendingEmailThreadId,
                onInitialThreadConsumed: { pendingEmailThreadId = nil }
            )
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
