import SwiftUI
import SwiftData

struct BoardColumnView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let status: TaskStatus
    let tasks: [TaskRecord]
    let onOpenDetails: (TaskRecord) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            cards
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 272)
        .frame(minHeight: 420, alignment: .top)
        .background(backgroundShape.fill(backgroundFill))
        .overlay(backgroundShape.stroke(backgroundStroke, lineWidth: 1))
        .dropDestination(for: String.self, action: handleDrop(items:location:), isTargeted: handleTargeting(_:))
    }

    @Query(sort: \TaskRecord.createdAt, order: .reverse)
    private var tasksInApp: [TaskRecord]

    private var header: some View {
        HStack {
            Text(status.title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.1)
            Spacer()
            Text(String(tasks.count))
                .font(.system(size: 11, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(AppTheme.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var cards: some View {
        VStack(spacing: 10) {
            ForEach(tasks) { task in
                BoardTaskCard(task: task) {
                    onOpenDetails(task)
                }
                    .draggable(task.id.uuidString)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var backgroundFill: Color {
        isTargeted ? AppTheme.accent.opacity(0.08) : AppTheme.surfaceSecondary
    }

    private var backgroundStroke: Color {
        isTargeted ? AppTheme.accent.opacity(0.18) : AppTheme.cardBorder
    }

    private func handleDrop(items: [String], location _: CGPoint) -> Bool {
        for item in items {
            guard let taskID = UUID(uuidString: item), let task = tasksInApp.first(where: { $0.id == taskID }) else {
                continue
            }
            services.captureService.setStatus(task, status: status, in: modelContext)
        }
        isTargeted = false
        return true
    }

    private func handleTargeting(_ targeted: Bool) {
        isTargeted = targeted
    }
}
