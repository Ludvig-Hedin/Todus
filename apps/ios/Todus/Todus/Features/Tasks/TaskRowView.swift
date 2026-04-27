import SwiftUI

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let task: TaskRecord
    let onMoveRequested: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        Button {
            onOpenDetails()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                // Checkbox — isolated tap target, vertically centered with the text block
                Button(action: { toggleCheckbox() }) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(task.completed ? task.status.tintColor : AppTheme.subtleText)
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 40)
                .contentShape(Rectangle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(task.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .tracking(-0.2)
                                    .lineSpacing(2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.primary.opacity(task.completed ? 0.45 : 1.0))
                                    .strikethrough(task.completed, color: .primary.opacity(0.25))

                                if task.parseState == .pending {
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.primary.opacity(0.6))
                                        .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                                }
                            }

                            if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                                Text(task.taskDescription)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText.opacity(0.95))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        statusTag(status: task.status)
                    }

                    metaChipsRow
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppTheme.rowFill, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onOpenDetails()
            } label: {
                Label("Edit", systemImage: "pencil")
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
            Divider()
            Button(role: .destructive) {
                services.captureService.delete(task, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                services.captureService.delete(task, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleCheckbox()
            } label: {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(Color.primary)

            Button {
                onMoveRequested()
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(AppTheme.secondaryAccent)

            Button {
                onOpenDetails()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.switchTint)
        }
    }

    // MARK: - Meta row (no status — status is trailing)

    @ViewBuilder
    private var metaChipsRow: some View {
        let showFolderChip = task.folder != nil && task.dueDate == nil
        if task.dueDate != nil || task.priority != .none || showFolderChip {
            HStack(spacing: 5) {
                if let dueDate = task.dueDate {
                    dueDateTag(dueDate)
                }
                if task.priority != .none {
                    priorityTag(task.priority)
                }
                if let folder = task.folder, task.dueDate == nil {
                    tag(title: folder.name, systemImage: "folder")
                }
            }
        }
    }

    // MARK: - Status Tag (tinted, higher contrast in light mode)

    private func statusTag(status: TaskStatus) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
                .font(.system(size: 8, weight: .bold))
            Text(status.title)
                .font(.system(size: 10, weight: .semibold))
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
            .font(.system(size: 10, weight: .semibold))
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
                .font(.system(size: 8, weight: .bold))
            Text(priority.title)
                .font(.system(size: 10, weight: .semibold))
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
            .font(.system(size: 10, weight: .semibold))
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
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            services.captureService.toggleCompletion(task, in: modelContext)
        }
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
