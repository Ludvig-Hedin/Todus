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
                // Checkbox has its own isolated tap target — doesn't conflict with row tap
                Button(action: { toggleCheckbox() }) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(task.completed ? Color.blue : AppTheme.subtleText)
                }
                .buttonStyle(.plain)
                // Apple HIG: minimum 44x44pt tap target for accessibility
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                // Content area — entire row opens details when tapped
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 14, weight: .medium))
                            .tracking(-0.2)
                            .lineSpacing(2)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Issue #8: Show shimmer indicator when AI is still parsing
                        if task.parseState == .pending {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.blue.opacity(0.6))
                                .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                        }
                    }

                    // Guard: don't render description if empty or if it duplicates the title
                    // (can happen for Reminders-imported tasks where notes == title).
                    if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                        Text(task.taskDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        if let dueDate = task.dueDate {
                            tag(title: TaskDateFormatter.dueFormatter.string(from: dueDate), systemImage: "calendar")
                        }

                        if let folder = task.folder {
                            tag(title: folder.name, systemImage: "folder")
                        }

                        if task.priority != .none {
                            tag(title: task.priority.title, systemImage: "flag")
                        }

                        statusTag(status: task.status)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Ensure the full HStack area (including Spacer) is tappable
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppTheme.rowFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.rowStroke, lineWidth: 1)
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

    // Returns a status-specific icon for clearer visual representation
    private func statusTag(status: TaskStatus) -> some View {
        let (icon, title) = statusIconAndLabel(status)
        return Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(AppTheme.mutedText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }

    // Returns clear icons and shortened labels for task status
    private func statusIconAndLabel(_ status: TaskStatus) -> (icon: String, label: String) {
        switch status {
        case .todo:
            return ("circle", "Todo")
        case .doing:
            return ("circle.dashed", "Doing")
        case .done:
            return ("checkmark.circle", "Done")
        }
    }

    private func tag(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(AppTheme.mutedText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }

    private func toggleCheckbox() {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            services.captureService.toggleCompletion(task, in: modelContext)
        }
    }
}

