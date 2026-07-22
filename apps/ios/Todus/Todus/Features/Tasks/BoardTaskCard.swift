import SwiftUI

struct BoardTaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let task: TaskRecord
    let onOpenDetails: () -> Void

    /// Drives the destructive-delete confirmation dialog — the board card was
    /// the only task surface whose context-menu Delete fired immediately.
    @State private var showDeleteConfirmation = false

    /// Desktop-style row: status icon, title, meta chips, trailing chevron (matches macOS `MacTaskRow` on the board).
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.status.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(task.completed ? AppTheme.mutedText : task.status.tintColor)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary.opacity(task.completed ? 0.5 : 0.95))
                        .strikethrough(task.completed, color: .primary.opacity(0.2))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(task.title)
                        .accessibilityLabel("Task: \(task.title)")
                }

                if task.dueDate != nil || task.priority != .none || task.folder != nil {
                    HStack(spacing: 4) {
                        if let dueDate = task.dueDate {
                            boardMetaPill(
                                title: TaskDateFormatter.shortDate.string(from: dueDate),
                                systemImage: "calendar",
                                tint: dueDateColor(dueDate)
                            )
                        }
                        if task.priority != .none {
                            boardMetaPill(
                                title: task.priority.title,
                                systemImage: "flag.fill",
                                tint: priorityColor
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

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .stroke(AppTheme.cardBorder.opacity(0.85), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetails()
        }
        // Long-press context menu for quick actions
        .contextMenu {
            Button {
                onOpenDetails()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                AppHaptic.light.play()
                withAnimation(AppTheme.Motion.base) {
                    services.captureService.toggleCompletion(task, in: modelContext)
                }
            } label: {
                Label(task.completed ? "Restore" : "Mark as Done", systemImage: task.completed ? "arrow.uturn.backward" : "checkmark.circle")
            }

            Divider()

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
                let box = task.completed ? "- [x]" : "- [ ]"
                UIPasteboard.general.string = "\(box) \(task.title)"
            } label: {
                Label("Copy as Markdown", systemImage: "checkmark.square")
            }
            Button {
                AppHaptic.light.play()
                services.captureService.captureInStatus(
                    title: task.title,
                    status: task.status,
                    folder: task.folder,
                    in: modelContext
                )
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            // Priority submenu — same as list row so the surface parity holds.
            Menu {
                ForEach(AppTaskPriority.allCases) { p in
                    Button {
                        guard p != task.priority else { return }
                        AppHaptic.light.play()
                        withAnimation(AppTheme.Motion.fast) {
                            services.captureService.updatePriority(task, priority: p, in: modelContext)
                        }
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

            // Quick status change submenu
            Menu {
                ForEach(TaskStatus.allCases) { targetStatus in
                    if targetStatus != task.status {
                        Button {
                            withAnimation(AppTheme.Motion.base) {
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
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                services.captureService.delete(task, in: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(task.title)\" will be deleted. This can't be undone.")
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
            .font(.system(size: 11, weight: .semibold))
            .tracking(-0.08)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tint.opacity(0.07), in: Capsule())
    }
}
