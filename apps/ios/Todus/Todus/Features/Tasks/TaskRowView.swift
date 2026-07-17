import SwiftUI
import SwiftData
import UIKit

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let task: TaskRecord
    let onMoveRequested: () -> Void
    let onOpenDetails: () -> Void

    @State private var showSnoozeOptions = false
    /// Drives the destructive-delete confirmation dialog so the context-menu
    /// Delete matches the explicit confirm flow used by `TaskTableView`.
    /// (UX P2.)
    @State private var showDeleteConfirmation = false

    var body: some View {
        Button {
            onOpenDetails()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                // Checkbox — isolated tap target, vertically centered with the text block.
                // Frame stays 40×40 for the HIG minimum hit area; only the glyph size
                // changes.
                Button(action: { toggleCheckbox() }) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(task.completed ? task.status.tintColor : AppTheme.subtleText)
                }
                .buttonStyle(.plain)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .accessibilityLabel(task.completed ? "Mark task incomplete" : "Mark task complete")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(task.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .tracking(-0.2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.primary.opacity(task.completed ? 0.45 : 1.0))
                                    .strikethrough(task.completed, color: .primary.opacity(0.25))

                                if task.parseState == .pending {
                                    HStack(spacing: 3) {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 9, weight: .semibold))
                                            .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                                        Text("Setting up…")
                                            .font(.system(size: 10, weight: .semibold))
                                            .tracking(-0.1)
                                    }
                                    .foregroundStyle(Color.primary.opacity(0.55))
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("AI is analyzing task details")
                                }
                            }

                            if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                                Text(task.taskDescription)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppTheme.mutedText.opacity(0.95))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // The default "Todo" pill carried zero information and
                        // repeated on every row — pure noise. Status renders
                        // only for non-default states. (Tasks UX overhaul.)
                        if task.status != .todo {
                            statusTag(status: task.status)
                        }
                    }

                    metaChipsRow
                    suggestionChipRow
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppTheme.rowFill, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        // Long-press-and-move drags the task onto a folder card (Tasks tab
        // footer) or the Inbox strip (folder detail). Payload is the task UUID
        // string; drop targets validate it. Coexists with the context menu:
        // hold shows the menu, hold-and-move starts the drag.
        .draggable(task.id.uuidString)
        .contextMenu {
            Button {
                onOpenDetails()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                UIPasteboard.general.string = task.title
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
            if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                Button {
                    UIPasteboard.general.string = task.taskDescription
                } label: {
                    Label("Copy description", systemImage: "text.quote")
                }
            }
            Button {
                UIPasteboard.general.string = markdownChecklistRepresentation()
            } label: {
                Label("Copy as Markdown", systemImage: "checkmark.square")
            }
            Button {
                duplicateTask()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Menu {
                ForEach(AppTaskPriority.allCases) { p in
                    Button {
                        setPriority(p)
                    } label: {
                        if p == task.priority {
                            Label(p.title, systemImage: "checkmark")
                        } else {
                            Text(p.title)
                        }
                    }
                }
            } label: {
                Label("Priority", systemImage: "flag")
            }
            Menu {
                // Use the shared SnoozeOption.menuOptions so labels stay in sync
                // between the context menu and the swipe-action confirmation dialog.
                // (UX P9.)
                ForEach(SnoozeOption.menuOptions, id: \.option) { entry in
                    Button(entry.label) { snooze(to: entry.option.date()) }
                }
            } label: {
                Label("Snooze", systemImage: "moon.zzz")
            }
            Button {
                onMoveRequested()
            } label: {
                Label("Move to folder", systemImage: "folder")
            }
            Button {
                toggleCheckbox()
            } label: {
                Label(task.completed ? "Mark as incomplete" : "Mark complete", systemImage: "checkmark.circle")
            }
            if task.emailThreadId != nil {
                Button {
                    openSourceEmail()
                } label: {
                    Label("Open source email", systemImage: "envelope")
                }
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // Trailing swipe is now Snooze (non-destructive). Delete moves to context menu only —
        // a one-tap full-swipe destructive action on a list row was the leading cause of
        // accidental deletions in usability testing. (UX assessment QW7 + QW8.)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                showSnoozeOptions = true
            } label: {
                Label("Snooze", systemImage: "moon.zzz")
            }
            .tint(AppTheme.switchTint)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleCheckbox()
            } label: {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(Color(UIColor.systemGreen))

            Button {
                onMoveRequested()
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(Color(UIColor.systemGray))

            Button {
                onOpenDetails()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.switchTint)
        }
        .confirmationDialog("Snooze until…", isPresented: $showSnoozeOptions, titleVisibility: .visible) {
            // Reuse the shared list so context menu + swipe dialog stay in sync.
            // (UX P9.)
            ForEach(SnoozeOption.menuOptions, id: \.option) { entry in
                Button(entry.label) { snooze(to: entry.option.date()) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                services.captureService.delete(task, in: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(task.title)\" will be removed.")
        }
    }

    // MARK: - Meta row (no status — status is trailing)

    @ViewBuilder
    private var metaChipsRow: some View {
        let hasOrigin = task.emailThreadId != nil
        let hasFolder = task.folder != nil
        let hasDue = task.dueDate != nil
        let hasPriority = task.priority != .none
        if hasOrigin || hasDue || hasPriority || hasFolder {
            HStack(spacing: 5) {
                if hasOrigin {
                    originTag
                }
                if let dueDate = task.dueDate {
                    dueDateTag(dueDate)
                }
                if hasPriority {
                    priorityTag(task.priority)
                }
                // Folder + due-date now coexist on the same row instead of swapping.
                // Hiding folder when a due-date exists made the chip blink in/out as
                // dates changed and lost folder context exactly when the row was busiest.
                if let folder = task.folder {
                    tag(title: folder.name, systemImage: "folder")
                        .help(folder.name)
                        .accessibilityLabel("Folder: \(folder.name)")
                }
            }
        }
    }

    // MARK: - Folder suggestion chip (accept / dismiss)

    /// Quiet AI suggestion for unfiled captures: "→ Work  ✓ ✕". Rendered only
    /// while `suggestedFolderID` is set and the task is still unfiled. Accept
    /// moves the task; dismiss clears the suggestion for good.
    @ViewBuilder
    private var suggestionChipRow: some View {
        // Folder name resolved synchronously (one fetch by unique id, and only
        // for rows that carry a suggestion). An async `.task` fetch inside the
        // chip never fired: the chip rendered EmptyView until the name loaded,
        // and SwiftUI doesn't run task/onAppear modifiers on EmptyView.
        if task.folder == nil,
           let suggestedID = task.suggestedFolderID,
           let folderName = folderName(for: suggestedID) {
            TaskFolderSuggestionChip(
                folderName: folderName,
                onAccept: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(AppTheme.Motion.base) {
                        services.captureService.acceptSuggestion(for: task, in: modelContext)
                    }
                },
                onDismiss: {
                    withAnimation(AppTheme.Motion.fast) {
                        services.captureService.dismissSuggestion(for: task, in: modelContext)
                    }
                }
            )
        }
    }

    private func folderName(for id: UUID) -> String? {
        let descriptor = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor).first)?.name
    }

    // MARK: - Email-origin Tag (rebuilds trust when AI extracted the task)

    private var originTag: some View {
        Button {
            openSourceEmail()
        } label: {
            Label("Email", systemImage: "envelope.fill")
                .font(.system(size: 11, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(AppTheme.secondaryAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.secondaryAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                        .stroke(AppTheme.secondaryAccent.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Tag (tinted, higher contrast in light mode)

    private func statusTag(status: TaskStatus) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(status.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(-0.1)
        }
        .foregroundStyle(status.tintColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                .stroke(status.tintColor.opacity(0.22), lineWidth: 0.5)
        )
    }

    // MARK: - Due Date Tag (color-coded)

    private func dueDateTag(_ dueDate: Date) -> some View {
        let color = dueDateColor(dueDate)
        return Label(TaskDateFormatter.dueFormatter.string(from: dueDate), systemImage: "calendar")
            .font(.system(size: 11, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 0.5)
            )
    }

    // MARK: - Priority Tag

    private func priorityTag(_ priority: AppTaskPriority) -> some View {
        let color = priorityColor(priority)
        return HStack(spacing: 3) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9, weight: .bold))
            Text(priority.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(-0.1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                .stroke(color.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Generic Tag

    private func tag(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(Color.secondary.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppTheme.surfaceSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
                    .stroke(AppTheme.cardBorder.opacity(0.9), lineWidth: 0.5)
            )
    }

    // MARK: - Helpers

    private func toggleCheckbox() {
        // Light tap on every checkbox press; a celebratory success notification
        // when the transition is open → done. (UX P1.)
        let willBecomeDone = !task.completed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(AppTheme.Motion.base) {
            services.captureService.toggleCompletion(task, in: modelContext)
        }
        if willBecomeDone {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func snooze(to date: Date) {
        withAnimation(AppTheme.Motion.base) {
            services.captureService.snooze(task, until: date, in: modelContext)
        }
    }

    /// Renders the task as a GitHub-Flavored-Markdown checklist line — pasteable
    /// into Notion, Linear, Slack, etc. without losing the "open task" semantic.
    private func markdownChecklistRepresentation() -> String {
        let box = task.completed ? "- [x]" : "- [ ]"
        if !task.taskDescription.isEmpty && task.taskDescription != task.title {
            return "\(box) \(task.title)\n  \(task.taskDescription)"
        }
        return "\(box) \(task.title)"
    }

    private func duplicateTask() {
        services.captureService.captureInStatus(
            title: task.title,
            status: task.status,
            folder: task.folder,
            in: modelContext
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func setPriority(_ priority: AppTaskPriority) {
        guard priority != task.priority else { return }
        withAnimation(AppTheme.Motion.fast) {
            task.priority = priority
            task.updatedAt = .now
            task.syncState = .pendingUpload
            // Surface save errors instead of swallowing — a failed persist here
            // would leave a phantom in-memory priority change that's lost on next
            // launch. Matches TaskCaptureService.capture's error handling.
            do {
                try modelContext.save()
            } catch {
                AppLogger.shared.log("TaskRowView.setPriority: save failed: \(error.localizedDescription)")
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openSourceEmail() {
        guard let threadId = task.emailThreadId else { return }
        services.pendingEmailThreadId = threadId
        services.navigateTo = .email
    }

    private func dueDateColor(_ date: Date) -> Color {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Color(red: 0.88, green: 0.65, blue: 0.20)
        } else if date < Date() {
            return Color(red: 0.85, green: 0.30, blue: 0.25)
        }
        return AppTheme.mutedText
    }

    private func priorityColor(_ priority: AppTaskPriority) -> Color {
        switch priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return AppTheme.mutedText
        }
    }
}

/// The "→ Folder ✓ ✕" suggestion chip. Pure presentation — the parent
/// resolves the folder name so this never renders empty.
private struct TaskFolderSuggestionChip: View {
    let folderName: String
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .semibold))
                Text("Move to \(folderName)?")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.1)
                    .lineLimit(1)
            }
            .foregroundStyle(AppTheme.secondaryAccent)

            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.secondaryAccent)
                    .frame(width: 26, height: 22)
                    .background(AppTheme.secondaryAccent.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Move to \(folderName)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 26, height: 22)
                    .background(AppTheme.surfaceSecondary.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(AppTheme.secondaryAccent.opacity(0.07), in: Capsule())
        .overlay(
            Capsule().stroke(AppTheme.secondaryAccent.opacity(0.15), lineWidth: 0.5)
        )
    }
}

/// Snooze presets matching the task-row sheet and context menu.
/// Centralised so iOS + macOS can reuse the same time-of-day rules.
enum SnoozeOption: Hashable {
    case tonight
    case tomorrow
    case weekend
    case nextWeek

    /// Single source of truth for snooze labels. Previously the context menu
    /// said "Tonight" while the swipe-action sheet said "Tonight (8 pm)" —
    /// same enum, different copy. Now both surfaces consume this list so
    /// drift is impossible. (UX P9.)
    ///
    /// Computed (not a stored `let`) so the "Tonight" label tracks `.tonight.date()`'s
    /// actual behavior: before 8pm it resolves to tonight, at/after 8pm `.date()` rolls
    /// to tomorrow — the label previously always said "Tonight (8 pm)" even when the
    /// resulting snooze was tomorrow. Call-site syntax (`SnoozeOption.menuOptions`, no
    /// parens) is unchanged so other call sites (CalendarTaskView) keep working as-is.
    static var menuOptions: [(option: SnoozeOption, label: String)] {
        [
            (.tonight, tonightLabel()),
            (.tomorrow, "Tomorrow morning"),
            (.weekend, "This weekend"),
            (.nextWeek, "Next week"),
        ]
    }

    /// Mirrors the `.tonight` branch of `date(now:calendar:)`: before 8pm today,
    /// snoozing resolves to tonight at 8pm; at/after 8pm it rolls to tomorrow 8pm.
    private static func tonightLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        let candidate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)
            ?? now.addingTimeInterval(4 * 3600)
        return candidate > now ? "Tonight at 8 pm" : "Tomorrow at 8 pm"
    }

    func date(now: Date = .now, calendar: Calendar = .current) -> Date {
        switch self {
        case .tonight:
            let candidate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)
                ?? now.addingTimeInterval(4 * 3600)
            if candidate <= now {
                return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .weekend:
            // Nearest UPCOMING weekend day (Saturday OR Sunday) still in the future, at 9am.
            // (B-033.) Invoked Saturday afternoon → this Sunday 9am (not next Saturday);
            // Sunday before 9am → this Sunday; Sunday after 9am → next Saturday.
            return SnoozeOption.nextWeekendMorning(now: now, calendar: calendar)
        case .nextWeek:
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)
                ?? now.addingTimeInterval(7 * 86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek) ?? nextWeek
        }
    }

    /// Returns the nearest upcoming weekend morning (Saturday or Sunday at 9am) that is
    /// strictly in the future. If neither this week's Saturday nor Sunday 9am is still
    /// ahead (e.g. late Sunday), rolls forward to next Saturday. (B-033.)
    /// Kept in sync with the macOS mirror in `TodusMac/Domain/SnoozeOption.swift`.
    static func nextWeekendMorning(now: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: now) // Sunday = 1, Saturday = 7
        let daysUntilSaturday = ((7 - weekday) + 7) % 7       // 0 when today is Saturday
        let daysUntilSunday = ((1 - weekday) + 7) % 7         // 0 when today is Sunday

        func morning(daysAhead: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: daysAhead, to: now)
                ?? now.addingTimeInterval(Double(daysAhead) * 86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }

        let candidates = [morning(daysAhead: daysUntilSaturday), morning(daysAhead: daysUntilSunday)]
        if let soonest = candidates.filter({ $0 > now }).min() {
            return soonest
        }
        // Both this-week candidates have passed (late Sunday) → next Saturday 9am.
        return morning(daysAhead: daysUntilSaturday + 7)
    }
}
