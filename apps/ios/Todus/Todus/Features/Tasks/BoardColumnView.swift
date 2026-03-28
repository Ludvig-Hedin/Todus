import SwiftUI
import SwiftData

struct BoardColumnView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let status: TaskStatus
    let tasks: [TaskRecord]
    let onOpenDetails: (TaskRecord) -> Void

    @State private var isTargeted = false
    @State private var isAddingTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFocused: Bool

    var body: some View {
        // Plain VStack — no inner ScrollView. The outer BoardView ScrollView([.horizontal, .vertical])
        // + .fixedSize(vertical: true) on the HStack lets columns grow to their natural height,
        // and the outer scroll view handles overflow in both directions.
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            VStack(spacing: 7) {
                cards

                if !isAddingTask {
                    addTaskButton
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 260)
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
        HStack(spacing: 6) {
            Image(systemName: status.systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(status.tintColor)

            Text(status.title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(.primary.opacity(0.82))

            Text("\(tasks.count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(status.tintColor.opacity(0.7))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(status.tintColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            Spacer()

            Button {
                beginAddingTask()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.tintColor.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(status.tintColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(status.tintColor.opacity(0.10), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 7) {
            if isAddingTask {
                inlineAddField
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            ForEach(tasks) { task in
                BoardTaskCard(task: task) {
                    onOpenDetails(task)
                }
                .draggable(task.id.uuidString)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Inline Add Field

    private var inlineAddField: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.tintColor.opacity(0.3))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(status.tintColor.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Add Task Button

    private var addTaskButton: some View {
        Button { beginAddingTask() } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("Add task")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.1)
            }
            .foregroundStyle(status.tintColor.opacity(0.50))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(status.tintColor.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(status.tintColor.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Background

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var backgroundFill: Color {
        isTargeted ? status.tintColor.opacity(0.08) : status.tintColor.opacity(0.025)
    }

    private var backgroundStroke: Color {
        isTargeted ? status.tintColor.opacity(0.22) : status.tintColor.opacity(0.08)
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
            services.captureService.captureInStatus(title: title, status: status, folder: nil, in: modelContext)
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
                services.captureService.setStatus(task, status: status, in: modelContext)
            }
        }
        isTargeted = false
        return true
    }

    private func handleTargeting(_ targeted: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) { isTargeted = targeted }
    }
}
