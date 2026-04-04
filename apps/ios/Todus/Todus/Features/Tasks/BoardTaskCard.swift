import SwiftUI

struct BoardTaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let task: TaskRecord
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(task.status.tintColor.opacity(0.42))
                    .frame(width: 4, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 5) {
                        Text(task.title)
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(-0.2)
                            .lineSpacing(1)
                            .foregroundStyle(.primary.opacity(task.completed ? 0.44 : 0.9))
                            .strikethrough(task.completed, color: .primary.opacity(0.2))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if task.priority != .none {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(priorityColor.opacity(0.9))
                                .padding(.top, 2)
                        }
                    }

                    if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                        Text(task.taskDescription)
                            .font(.system(size: 10, weight: .medium))
                            .tracking(-0.1)
                            .foregroundStyle(AppTheme.mutedText)
                            .lineSpacing(1)
                            .lineLimit(2)
                    }
                }
            }

            if task.dueDate != nil || task.folder != nil {
                HStack(spacing: 6) {
                    if let dueDate = task.dueDate {
                        boardMetaPill(
                            title: TaskDateFormatter.dueFormatter.string(from: dueDate),
                            systemImage: "calendar",
                            tint: dueDateColor(dueDate)
                        )
                    }

                    if let folder = task.folder {
                        boardMetaPill(
                            title: folder.name,
                            systemImage: "folder",
                            tint: AppTheme.mutedText
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder.opacity(0.9), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetails()
        }
        // Long-press context menu for quick actions
        .contextMenu {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    services.captureService.toggleCompletion(task, in: modelContext)
                }
            } label: {
                Label(task.completed ? "Restore" : "Mark as Done", systemImage: task.completed ? "arrow.uturn.backward" : "checkmark.circle")
            }

            // Quick status change submenu
            Menu {
                ForEach(TaskStatus.allCases) { targetStatus in
                    if targetStatus != task.status {
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                services.captureService.setStatus(task, status: targetStatus, in: modelContext)
                            }
                        } label: {
                            Label(targetStatus.title, systemImage: targetStatus.systemImage)
                        }
                    }
                }
            } label: {
                Label("Move to…", systemImage: "arrow.right.circle")
            }

            Divider()

            Button(role: .destructive) {
                services.captureService.delete(task, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    /// Priority flag color — orange for medium, red for high
    private var priorityColor: Color {
        switch task.priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return AppTheme.mutedText
        }
    }

    /// Due date text color — red if overdue, orange if today, else muted
    private func dueDateColor(_ date: Date) -> Color {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Color(red: 0.88, green: 0.65, blue: 0.20)
        } else if date < Date() {
            return Color(red: 0.85, green: 0.30, blue: 0.25)
        }
        return AppTheme.mutedText
    }

    private func boardMetaPill(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 9, weight: .semibold))
            .tracking(-0.08)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tint.opacity(0.07), in: Capsule())
    }
}
