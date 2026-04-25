import SwiftUI

// MARK: - Sidebar

struct MacSidebarView: View {
    @Environment(MacAppServices.self) private var services
    @AppStorage("mac_compact_sidebar") private var compactSidebar = false
    @AppStorage("mac_show_unread_badge") private var showUnreadBadge = true

    @Binding var selection: MacPrimarySelection
    @Binding var isEmailExpanded: Bool
    @Binding var isCalendarExpanded: Bool
    let onOpenSettings: () -> Void
    let onCompose: () -> Void

    private var authService: AuthService { services.authService }
    /// Real task count from parent (SwiftData @Query)
    var taskCount: Int = 0
    /// Callback to open the create sheet
    var onCreateItem: (() -> Void)? = nil
    /// Callback when a day is tapped in the mini calendar
    var onCalendarDayTap: ((Date) -> Void)? = nil

    private var inboxUnreadCount: Int? {
        guard showUnreadBadge else { return nil }
        let count = services.emailService.threads.filter(\.unread).count
        return count > 0 ? count : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation items
            VStack(alignment: .leading, spacing: 2) {
                SidebarItemButton(
                    title: "Home",
                    systemImage: "house",
                    isSelected: selection == .home,
                    action: { selection = .home }
                )

                SidebarItemButton(
                    title: "Tasks",
                    systemImage: "checkmark.square",
                    isSelected: selection == .tasks,
                    badgeCount: taskCount > 0 ? taskCount : nil,
                    showAddOnHover: true,
                    onAdd: { onCreateItem?() },
                    action: { selection = .tasks }
                )

                // Email — expandable with sub-sections
                // Parent is NOT highlighted when expanded (only the child sub-link is)
                SidebarItemButton(
                    title: "Email",
                    systemImage: "envelope",
                    isSelected: isEmailSelected && !isEmailExpanded,
                    badgeCount: inboxUnreadCount,
                    trailingSystemImage: isEmailExpanded ? "chevron.down" : "chevron.right",
                    action: {
                        withAnimation(.snappy(duration: 0.18)) {
                            isEmailExpanded.toggle()
                        }
                        if !isEmailSelected {
                            selection = .email(.inbox)
                        }
                    }
                )

                if isEmailExpanded {
                    VStack(alignment: .leading, spacing: 1) {
                        // Primary folders: Inbox, Drafts, Sent
                        ForEach(EmailSection.allCases.filter(\.isPrimary), id: \.self) { section in
                            SidebarChildItemButton(
                                title: section.title,
                                systemImage: section.systemImage,
                                isSelected: selection == .email(section),
                                action: { selection = .email(section) }
                            )
                        }
                        // Divider between primary and secondary folders
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.leading, 36)
                            .padding(.trailing, 4)
                            .padding(.vertical, 3)
                        // Secondary folders: Archive, Snoozed, Spam, Trash
                        ForEach(EmailSection.allCases.filter { !$0.isPrimary }, id: \.self) { section in
                            SidebarChildItemButton(
                                title: section.title,
                                systemImage: section.systemImage,
                                isSelected: selection == .email(section),
                                action: { selection = .email(section) }
                            )
                        }

                        // Connected accounts — shown when there are multiple connections.
                        // Each row toggles that account's visibility in the email view.
                        if services.connectionsService.hasMultipleConnections {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 0.5)
                                .padding(.leading, 36)
                                .padding(.trailing, 4)
                                .padding(.vertical, 3)

                            ForEach(services.connectionsService.connections) { connection in
                                SidebarConnectionRow(
                                    connection: connection,
                                    isEnabled: services.connectionsService.enabledConnectionIds.contains(connection.id),
                                    isDisconnected: services.connectionsService.isDisconnected(connection.id),
                                    action: { services.connectionsService.toggleConnection(connection.id) }
                                )
                            }
                        }
                    }
                    // Use opacity-only so sub-items don't slide over sibling rows during animation
                    .transition(.opacity)
                }

                SidebarItemButton(
                    title: "Meetings",
                    systemImage: "video",
                    isSelected: selection == .meetings,
                    action: { selection = .meetings }
                )

                SidebarItemButton(
                    title: "Docs",
                    systemImage: "doc.text",
                    isSelected: selection == .docs,
                    action: { selection = .docs }
                )

                // Calendar — expandable with sub-sections
                // Parent is NOT highlighted when expanded (only the child sub-link is)
                SidebarItemButton(
                    title: "Calendar",
                    systemImage: "calendar",
                    isSelected: isCalendarSelected && !isCalendarExpanded,
                    trailingSystemImage: isCalendarExpanded ? "chevron.down" : "chevron.right",
                    action: {
                        withAnimation(.snappy(duration: 0.18)) {
                            isCalendarExpanded.toggle()
                        }
                        if !isCalendarSelected {
                            selection = .calendar(.all)
                        }
                    }
                )

                if isCalendarExpanded {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(CalendarSection.allCases, id: \.self) { section in
                            SidebarChildItemButton(
                                title: section.title,
                                isSelected: selection == .calendar(section),
                                action: { selection = .calendar(section) }
                            )
                        }
                    }
                    .transition(.opacity)
                }
            }

            Spacer(minLength: 12)

            // Context-specific sidebar footer based on active view
            sidebarFooter(for: selection)

            // Connected account indicators — small colored circles for multi-account switching.
            // Shown only when there are 2+ connections. Tapping toggles visibility.
            if services.connectionsService.hasMultipleConnections {
                ConnectionAvatarsRow(connectionsService: services.connectionsService)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            // Separator above user area
            Rectangle()
                .fill(.quaternary)
                .frame(height: 0.5)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
                .padding(.top, 10)

            // User row — avatar + name menu + gear icon pinned right
            HStack(spacing: 6) {
                // Avatar — profile image or initial
                if let imageURLString = authService.userImage,
                   let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                        default:
                            avatarCircle
                        }
                    }
                } else {
                    avatarCircle
                }

                // Name — menu trigger. tint(.primary.opacity(0.5)) prevents the
                // borderlessButton disclosure chevron from rendering in blue accent color.
                Menu {
                    Button("Profile") { onOpenSettings() }
                    Divider()
                    Button("Log Out", role: .destructive) {
                        services.signOut()
                    }
                } label: {
                    Text(displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .menuStyle(.borderlessButton)
                .tint(.primary.opacity(0.45))
                .buttonStyle(.plain)
                .interactiveHitTarget(expansion: 6)
                .pointerStyle(.link)

                Spacer(minLength: 0)

                // Gear icon pinned to trailing edge
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.primary)
                        .opacity(0.3)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .interactiveHitTarget(expansion: 6)
                .focusEffectDisabled()
                .pointerStyle(.link)
                .help("Settings")
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, compactSidebar ? 6 : 8)
        .padding(.vertical, compactSidebar ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
        // Hidden keyboard handlers — wire ⌥↑/⌥↓ to step through the visible sidebar
        // rows. A custom VStack of buttons (vs List(selection:)) doesn't get
        // arrow-key navigation for free, and binding bare arrows would steal them
        // from text fields and message lists. ⌥+arrow is the conservative pick:
        // it never conflicts with text editing or in-list navigation.
        .background {
            Group {
                Button("") { stepSelection(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.option])
                Button("") { stepSelection(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.option])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .task {
            // Load connections on sidebar appear for multi-account support
            await services.connectionsService.loadConnections()
        }
    }

    /// All sidebar rows in visible order — used by the arrow-key handlers to
    /// step through selections. Mirrors the order of the buttons rendered in `body`,
    /// expanding email / calendar children only when their group is open.
    private var orderedSelections: [MacPrimarySelection] {
        var rows: [MacPrimarySelection] = [.home, .tasks]
        // Email parent + (optional) children
        rows.append(.email(.inbox))
        if isEmailExpanded {
            // Primary first (inbox/drafts/sent), then secondary (archive/snoozed/spam/bin).
            // Drop .inbox here so we don't duplicate the parent row's selection target.
            for section in EmailSection.allCases.filter(\.isPrimary) where section != .inbox {
                rows.append(.email(section))
            }
            for section in EmailSection.allCases.filter({ !$0.isPrimary }) {
                rows.append(.email(section))
            }
        }
        rows.append(.meetings)
        rows.append(.docs)
        // Calendar parent + (optional) children
        rows.append(.calendar(.all))
        if isCalendarExpanded {
            for section in CalendarSection.allCases where section != .all {
                rows.append(.calendar(section))
            }
        }
        return rows
    }

    private func stepSelection(by delta: Int) {
        let rows = orderedSelections
        guard !rows.isEmpty else { return }
        let currentIndex = rows.firstIndex(of: selection) ?? 0
        let next = (currentIndex + delta + rows.count) % rows.count
        selection = rows[next]
    }

    // MARK: - Footer per view

    @ViewBuilder
    private func sidebarFooter(for selection: MacPrimarySelection) -> some View {
        switch selection.category {
        case "email":
            emailFooter
        case "calendar":
            calendarFooter
        case "tasks":
            tasksFooter
        default:
            EmptyView()
        }
    }

    // Email footer: compose shortcut only — labels removed (not connected to real data)
    private var emailFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onCompose) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("New Message")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .interactiveHitTarget(expansion: 6)
            .focusEffectDisabled()
            .pointerStyle(.link)
        }
        .padding(.horizontal, 10)
        .transition(.opacity)
    }

    // Calendar footer: mini month grid only — hardcoded calendar sources removed
    private var calendarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mini month calendar
            MiniCalendarView { date in
                // Navigate to calendar section — the date itself is visual-only
                // since MacCalendarView owns its own selectedDate state
                onCalendarDayTap?(date)
            }
        }
        .padding(.horizontal, 10)
        .transition(.opacity)
    }

    // Tasks footer: removed non-functional Quick Filters — MacTasksView has its own filter toolbar
    private var tasksFooter: some View {
        EmptyView()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
            .padding(.bottom, 2)
    }

    private var isEmailSelected: Bool {
        if case .email = selection { return true }
        return false
    }

    private var isCalendarSelected: Bool {
        if case .calendar = selection { return true }
        return false
    }

    /// Display name for the user row — falls back through name → email → "Guest"
    private var displayName: String {
        if let name = authService.userName, !name.isEmpty { return name }
        if let email = authService.userEmail, !email.isEmpty { return email }
        return authService.isAuthenticated ? "User" : "Guest"
    }

    /// First letter of user's name (not email) for the avatar circle
    private var userInitial: String {
        if let name = authService.userName, !name.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        if let email = authService.userEmail, !email.isEmpty {
            return String(email.prefix(1)).uppercased()
        }
        return "?"
    }

    /// Small avatar circle with initial letter
    private var avatarCircle: some View {
        Circle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 22, height: 22)
            .overlay(
                Text(userInitial)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .opacity(0.5)
            )
    }
}

// MARK: - Sidebar Item (Primary)

private struct SidebarItemButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var badgeCount: Int? = nil
    var trailingSystemImage: String? = nil
    var showAddOnHover: Bool = false
    var onAdd: (() -> Void)? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        // The row is a fixed-height HStack. The trailing slot uses a ZStack overlay
        // so the + button and badge/chevron occupy the same space — no layout shift on hover.
        HStack(spacing: 8) {
            // Main tap target: icon + title.
            // contentShape(Rectangle()) ensures the transparent area of the label is also tappable —
            // without this, only the text/icon pixels register clicks, which breaks navigation.
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
                        .frame(width: 18)

                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .interactiveHitTarget(expansion: 6)
            .focusEffectDisabled()
            .pointerStyle(.link)

            // Trailing slot — fixed width 20pt; overlays + on hover above badge/chevron.
            // ZStack keeps height constant regardless of which child is visible.
            ZStack {
                // Badge or chevron (always rendered, hidden when + is shown)
                Group {
                    if let badgeCount, let trailingSystemImage {
                        HStack(spacing: 4) {
                            Text("\(badgeCount)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Image(systemName: trailingSystemImage)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    } else if let badgeCount {
                        Text("\(badgeCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else if let trailingSystemImage {
                        Image(systemName: trailingSystemImage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(showAddOnHover && isHovered ? 0 : 1)

                // + button (only for items with showAddOnHover)
                if showAddOnHover {
                    Button {
                        onAdd?()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.primary.opacity(0.06), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .interactiveHitTarget(expansion: 6)
                    .focusEffectDisabled()
                    .pointerStyle(.link)
                    .opacity(isHovered ? 1 : 0)
                }
            }
            .frame(width: badgeCount != nil && trailingSystemImage != nil ? 34 : 20, height: 20)
            .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(fillColor)
        )
        .contentShape(Capsule(style: .continuous))
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
    }

    private var fillColor: Color {
        if isSelected { return Color.primary.opacity(0.07) }
        if isHovered { return Color.primary.opacity(0.04) }
        return .clear
    }
}

// MARK: - Sidebar Item (Child / Indented)

private struct SidebarChildItemButton: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = systemImage {
                    // Icon slot — fixed width keeps text left-edges aligned across all rows
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.4))
                        .frame(width: 14, alignment: .center)
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.6))

                Spacer(minLength: 0)
            }
            // Indent from left: 26pt fixed + optional icon width keeps text aligned with title-only rows
            .padding(.leading, systemImage != nil ? 26 : 36)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(fillColor)
            )
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
        .interactiveHitTarget(expansion: 6)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
    }

    private var fillColor: Color {
        if isSelected { return Color.primary.opacity(0.07) }
        if isHovered { return Color.primary.opacity(0.04) }
        return .clear
    }
}

// MARK: - Mini Calendar

/// Compact month grid shown in the calendar sidebar footer.
/// Days are tappable — tapping a day calls `onSelectDay` with the Date.
private struct MiniCalendarView: View {
    var onSelectDay: ((Date) -> Void)? = nil

    private let calendar = Calendar.current
    private let today = Date()
    @State private var selectedDay: Int? = nil

    // Derive single-letter weekday headers from locale, rotated to match firstWeekday
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    private var monthName: String {
        today.formatted(.dateTime.month(.wide).year())
    }

    private var daysInMonth: Range<Int> {
        calendar.range(of: .day, in: .month, for: today)!
    }

    private var firstWeekdayOffset: Int {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }

    private var todayDay: Int {
        calendar.component(.day, from: today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monthName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.6))

            // Weekday headers
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 2
            ) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                // Empty cells before the 1st
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Text("")
                        .frame(maxWidth: .infinity)
                }

                // Day numbers — tappable
                ForEach(Array(daysInMonth), id: \.self) { day in
                    let isToday = day == todayDay
                    let isSelected = day == selectedDay
                    Text("\(day)")
                        .font(.system(size: 10, weight: (isToday || isSelected) ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : isSelected ? MacTheme.textPrimary : .primary.opacity(0.55))
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(isToday ? Color.accentColor.opacity(0.15) : isSelected ? Color.primary.opacity(0.08) : .clear)
                        )
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .pointerStyle(.link)
                        .onTapGesture {
                            selectedDay = day
                            // Build the tapped Date and notify parent
                            if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
                               let date = calendar.date(bySetting: .day, value: day, of: monthStart) {
                                onSelectDay?(date)
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Connection Account Row (Email Sub-item)

/// A child row under the Email section showing a connected account.
/// Tapping toggles the account's visibility in email views.
private struct SidebarConnectionRow: View {
    let connection: ConnectionAccount
    let isEnabled: Bool
    let isDisconnected: Bool
    let action: () -> Void

    @State private var isHovered = false

    /// Parse the connection's hex color into a SwiftUI Color
    private var dotColor: Color {
        Color(hex: connection.displayColor) ?? .primary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Colored dot indicating the account
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        // Strikethrough overlay when disconnected (needs re-auth)
                        isDisconnected
                            ? Circle().stroke(Color.red.opacity(0.6), lineWidth: 1)
                            : nil
                    )

                // Account email, truncated to fit the sidebar
                Text(connection.email)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary.opacity(isEnabled ? 0.6 : 0.3))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                // Checkmark when enabled
                if isEnabled {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 36)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
            )
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.35)
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .animation(.easeOut(duration: 0.15), value: isEnabled)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Connection Avatars Row (Footer)

/// A horizontal row of small colored avatar circles for each connection.
/// Shown in the sidebar footer when there are multiple accounts.
private struct ConnectionAvatarsRow: View {
    let connectionsService: ConnectionsService

    var body: some View {
        HStack(spacing: 4) {
            ForEach(connectionsService.connections) { connection in
                let isEnabled = connectionsService.enabledConnectionIds.contains(connection.id)
                let dotColor = Color(hex: connection.displayColor) ?? .primary

                Button {
                    connectionsService.toggleConnection(connection.id)
                } label: {
                    // Small avatar circle with initial and colored ring
                    ZStack {
                        Circle()
                            .fill(dotColor.opacity(0.15))
                            .frame(width: 20, height: 20)

                        // Initial letter
                        Text(connectionInitial(connection))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(dotColor)

                        // Colored ring for enabled connections
                        Circle()
                            .stroke(dotColor, lineWidth: isEnabled ? 1.5 : 0)
                            .frame(width: 20, height: 20)
                    }
                    .opacity(isEnabled ? 1.0 : 0.35)
                    .animation(.easeOut(duration: 0.15), value: isEnabled)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .pointerStyle(.link)
                .help(connection.email)
            }

            Spacer(minLength: 0)
        }
    }

    /// First letter of the connection's name or email for the avatar
    private func connectionInitial(_ connection: ConnectionAccount) -> String {
        if let name = connection.name, !name.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return String(connection.email.prefix(1)).uppercased()
    }
}

// MARK: - Color Hex Initializer

extension Color {
    /// Creates a Color from a hex string (e.g. "#007AFF" or "007AFF").
    /// Returns nil if the hex string is invalid.
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6,
              let rgb = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
