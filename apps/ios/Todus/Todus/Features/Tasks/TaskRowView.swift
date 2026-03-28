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
            HStack(alignment: .top, spacing: 10) {
                // Checkbox — isolated tap target
                Button(action: { toggleCheckbox() }) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(task.completed ? task.status.tintColor : AppTheme.subtleText)
                }
                .buttonStyle(.plain)
                // Apple HIG: minimum 44x44pt tap target for accessibility
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                // Content area
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 14, weight: .medium))
                            .tracking(-0.2)
                            .lineSpacing(2)
                            .foregroundStyle(.primary.opacity(task.completed ? 0.45 : 1.0))
                            .strikethrough(task.completed, color: .primary.opacity(0.2))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // AI parsing indicator
                        if task.parseState == .pending {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.blue.opacity(0.6))
                                .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                        }
                    }

                    // Description — skip if empty or duplicates title
                    if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                        Text(task.taskDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(2)
                    }

                    // Metadata tags
                    HStack(spacing: 5) {
                        if let dueDate = task.dueDate {
                            dueDateTag(dueDate)
                        }

                        if let folder = task.folder {
                            tag(title: folder.name, systemImage: "folder")
                        }

                        if task.priority != .none {
                            priorityTag(task.priority)
                        }

                        statusTag(status: task.status)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppTheme.rowFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
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
            .tint(Color.blue)

            Button {
                onMoveRequested()
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(AppTheme.secondaryAccent)
        }
    }

    // MARK: - Status Tag (tinted)

    /// Status pill with tinted bg + icon, matching the column accent color
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
        .background(status.tintColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(status.tintColor.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Due Date Tag (color-coded)

    private func dueDateTag(_ dueDate: Date) -> some View {
        let color = dueDateColor(dueDate)
        return Label(TaskDateFormatter.dueFormatter.string(from: dueDate), systemImage: "calendar")
            .font(.system(size: 10, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(color.opacity(0.10), lineWidth: 0.5)
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
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Generic Tag

    private func tag(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(AppTheme.mutedText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 0.5)
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
