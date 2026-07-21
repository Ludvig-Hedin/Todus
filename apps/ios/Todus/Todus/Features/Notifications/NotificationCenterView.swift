import SwiftUI
import SwiftData

/// AI-powered notification center sheet — shows a digest of tasks due,
/// upcoming events, and important emails, generated on-demand by the AI backend.
struct NotificationCenterView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    // Tasks — SwiftData live query (incomplete only)
    @Query(filter: #Predicate<TaskRecord> { task in
        !task.completed
    }, sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var digestService: NotificationDigestService?
    @State private var events: [CalendarEvent] = []
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.sheetBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let service = digestService {
                            if service.isLoading {
                                loadingView
                            } else if let error = service.errorMessage {
                                errorView(error)
                            } else if service.items.isEmpty {
                                emptyView
                            } else {
                                notificationsList(service.items)
                            }
                        } else {
                            loadingView
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadDigest()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                shimmerRow
            }
        }
        .padding(.top, 12)
    }

    private var shimmerRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
                    .frame(height: 14)
                    .frame(maxWidth: 200)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
                    .frame(height: 12)
                    .frame(maxWidth: 280)
            }

            Spacer()
        }
        .padding(14)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .redacted(reason: .placeholder)
        .shimmer()
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("All caught up")
                .font(.system(size: 17, weight: .semibold))
            Text("No notifications right now")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.orange)
            Text("Couldn't load notifications")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await loadDigest() }
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Notifications List

    private func notificationsList(_ items: [NotificationItem]) -> some View {
        let grouped = Dictionary(grouping: items, by: \.type)
        // Display order: tasks due → events → emails → reminders
        let orderedTypes: [NotificationType] = [.taskDue, .event, .importantEmail, .reminder]

        return ForEach(orderedTypes, id: \.self) { type in
            if let typeItems = grouped[type], !typeItems.isEmpty {
                notificationSection(type: type, items: typeItems)
            }
        }
    }

    private func notificationSection(type: NotificationType, items: [NotificationItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(type.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppTheme.surfaceSecondary, in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    notificationRow(item)
                }
            }
        }
    }

    private func notificationRow(_ item: NotificationItem) -> some View {
        Button {
            handleNotificationTap(item)
        } label: {
            HStack(spacing: 12) {
                // Priority indicator
                Circle()
                    .fill(priorityColor(item.priority))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .help(item.title)
                        .accessibilityLabel(item.title)

                    Text(item.description)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "high": return .red
        case "medium": return .orange
        case "low": return .secondary
        default: return .secondary
        }
    }

    private func handleNotificationTap(_ item: NotificationItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
        // Navigate to the relevant tab based on notification type
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch item.type {
            case .taskDue:
                services.navigateTo = .tasks
            case .event:
                services.navigateTo = .calendar
            case .importantEmail:
                services.navigateTo = .email
            case .reminder:
                services.navigateTo = .tasks
            }
        }
    }

    private func loadDigest() async {
        let service = NotificationDigestService(
            configuration: services.configuration,
            authService: services.authService
        )
        digestService = service

        // Load calendar events
        if services.calendarService.canReadEvents() {
            events = await services.calendarService.todaysEvents()
                .sorted { $0.startDate < $1.startDate }
        }

        await service.fetchDigest(
            tasks: allTasks,
            events: events,
            emailThreads: services.emailService.threads
        )
    }
}

// MARK: - Shimmer Effect

/// Simple shimmer animation modifier for loading placeholders.
private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.12),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .animation(
                    reduceMotion ? nil : .linear(duration: 1.5).repeatForever(autoreverses: false),
                    value: phase
                )
            )
            .clipped()
            // Reduce Motion: static placeholder, no sweeping highlight (TD-11).
            .onAppear { if !reduceMotion { phase = 400 } }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
