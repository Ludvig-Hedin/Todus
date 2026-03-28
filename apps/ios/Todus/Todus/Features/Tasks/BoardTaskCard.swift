import SwiftUI

struct BoardTaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let task: TaskRecord
    let onOpenDetails: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Thin left-edge color indicator — status at a glance without reading text
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(task.status.tintColor.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 5) {
                // Title row with optional priority flag
                HStack(spacing: 4) {
                    if task.priority != .none {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(priorityColor)
                    }

                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(-0.15)
                        .lineSpacing(1.5)
                        .foregroundStyle(.primary.opacity(task.completed ? 0.45 : 0.88))
                        .strikethrough(task.completed, color: .primary.opacity(0.2))
                        .lineLimit(3)
                }

                // Metadata row
                if task.dueDate != nil || task.folder != nil {
                    HStack(spacing: 5) {
                        if let dueDate = task.dueDate {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(TaskDateFormatter.dueFormatter.string(from: dueDate))
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(dueDateColor(dueDate))
                        }

                        if let folder = task.folder {
                            HStack(spacing: 3) {
                                Image(systemName: "folder")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(folder.name)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.mutedText)
                        }
                    }
                    .tracking(-0.1)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
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
}
