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
                .padding(.top, 12)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                cards
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(status.tintColor.opacity(0.08))

                Image(systemName: status.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(status.tintColor.opacity(0.92))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(status.title)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.25)
                        .foregroundStyle(.primary.opacity(0.9))

                    Text("\(tasks.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.surfacePrimary.opacity(0.9), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.cardBorder.opacity(0.8), lineWidth: 0.75)
                        )
                }

                Text(columnSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing here yet")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(.primary.opacity(0.78))

            Text("Drag a task into this stage.")
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(AppTheme.mutedText)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(AppTheme.surfacePrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.cardBorder.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }



    // MARK: - Background

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var backgroundFill: Color {
        isTargeted ? status.tintColor.opacity(0.07) : AppTheme.surfaceSecondary.opacity(0.76)
    }

    private var backgroundStroke: Color {
        isTargeted ? status.tintColor.opacity(0.18) : AppTheme.cardBorder
    }

    private var columnSubtitle: String {
        switch status {
        case .todo:
            return "Ready to pick up next"
        case .doing:
            return "Active focus right now"
        case .done:
            return "Finished and out of the way"
        }
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
