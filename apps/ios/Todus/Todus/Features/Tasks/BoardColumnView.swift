import SwiftUI
import SwiftData

struct BoardColumnView: View {
    @Environment(\.modelContext) private var modelContext

    let captureService: TaskCaptureService
    let status: TaskStatus
    let tasks: [TaskRecord]
    let onOpenDetails: (TaskRecord) -> Void

    @State private var isTargeted = false
    @State private var isAddingTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                cards

                if !isAddingTask {
                    addTaskButton
                }
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
        .onTapGesture {
            if !isAddingTask { beginAddingTask() }
        }
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

            Button {
                beginAddingTask()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surfacePrimary.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 8) {
            if isAddingTask {
                inlineAddField
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

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

            Text("Add a task or drag one into this stage.")
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

    // MARK: - Inline Add Field

    private var inlineAddField: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.tintColor.opacity(0.34))
                .frame(width: 6, height: 6)

            TextField("Task name…", text: $newTaskTitle)
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.1)
                .focused($isNewTaskFocused)
                .submitLabel(.done)
                .onSubmit { commitNewTask() }

            if !newTaskTitle.isEmpty {
                Button { commitNewTask() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(status.tintColor)
                }
                .buttonStyle(.plain)
            }

            Button { cancelAddingTask() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 18, height: 18)
                    .background(AppTheme.surfaceSecondary, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Add Task Button

    private var addTaskButton: some View {
        Button { beginAddingTask() } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("Add task")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundStyle(.primary.opacity(0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(AppTheme.surfacePrimary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - Actions

    private func beginAddingTask() {
        withAnimation(.snappy(duration: 0.2)) { isAddingTask = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isNewTaskFocused = true }
    }

    private func cancelAddingTask() {
        withAnimation(.snappy(duration: 0.18)) {
            isAddingTask = false
            newTaskTitle = ""
            isNewTaskFocused = false
        }
    }

    private func commitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { cancelAddingTask(); return }
        withAnimation(.snappy(duration: 0.22)) {
            captureService.captureInStatus(title: title, status: status, folder: nil, in: modelContext)
            newTaskTitle = ""
        }
        isNewTaskFocused = true
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
