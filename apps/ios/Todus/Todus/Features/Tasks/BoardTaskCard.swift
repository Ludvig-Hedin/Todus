import SwiftUI

struct BoardTaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let task: TaskRecord
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.1)
                .lineSpacing(2)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                if let dueDate = task.dueDate {
                    Label(TaskDateFormatter.dueFormatter.string(from: dueDate), systemImage: "calendar")
                }

                if let folder = task.folder {
                    Label(folder.name, systemImage: "folder")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .tracking(-0.1)
            .foregroundStyle(AppTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 16, fill: AppTheme.surfacePrimary)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetails()
        }
        // Issue #9: Long-press context menu for quick actions on board cards
        .contextMenu {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    services.captureService.toggleCompletion(task, in: modelContext)
                }
            } label: {
                Label(task.completed ? "Restore" : "Mark as Done", systemImage: task.completed ? "arrow.uturn.backward" : "checkmark.circle")
            }

            Button(role: .destructive) {
                services.captureService.delete(task, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
