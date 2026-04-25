import SwiftUI
import SwiftData

struct BoardColumnView: View {
    @Environment(\.modelContext) private var modelContext

    let captureService: TaskCaptureService
    let status: TaskStatus
    let tasks: [TaskRecord]
    let onOpenDetails: (TaskRecord) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            VStack(spacing: 6) {
                cards
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 272)
        .background(backgroundShape.fill(backgroundFill))
        .overlay(backgroundShape.stroke(backgroundStroke, lineWidth: 1))
        .clipShape(backgroundShape)
        .dropDestination(for: String.self, action: handleDrop(items:location:), isTargeted: handleTargeting(_:))
        .contentShape(Rectangle())
    }

    @Query(sort: \TaskRecord.createdAt, order: .reverse)
    private var tasksInApp: [TaskRecord]

    // MARK: - Header

    /// Aligned with macOS `MacBoardColumn` — compact icon, uppercase stage label, count badge.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: status.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.tintColor)

            Text(status.title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .tracking(0.6)

            if !tasks.isEmpty {
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 8) {


            if tasks.isEmpty {
                emptyColumnState
            } else {
                ForEach(tasks) { task in
                    BoardTaskCard(task: task) {
                        onOpenDetails(task)
                    }
                    .draggable(task.id.uuidString)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var emptyColumnState: some View {
        Text("Drop a task here")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }



    // MARK: - Background

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
    }

    private var backgroundFill: Color {
        isTargeted ? status.tintColor.opacity(0.07) : AppTheme.surfaceSecondary.opacity(0.9)
    }

    private var backgroundStroke: Color {
        isTargeted ? status.tintColor.opacity(0.2) : AppTheme.cardBorder
    }



    // MARK: - Drop Handling

    private func handleDrop(items: [String], location _: CGPoint) -> Bool {
        for item in items {
            guard let taskID = UUID(uuidString: item),
                  let task = tasksInApp.first(where: { $0.id == taskID }) else { continue }
            withAnimation(.snappy(duration: 0.22)) {
                captureService.setStatus(task, status: status, in: modelContext)
            }
        }
        isTargeted = false
        return true
    }

    private func handleTargeting(_ targeted: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) { isTargeted = targeted }
    }
}
