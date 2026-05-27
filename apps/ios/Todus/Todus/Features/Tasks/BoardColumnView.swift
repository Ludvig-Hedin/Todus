import SwiftUI
import SwiftData
import UIKit

struct BoardColumnView: View {
    @Environment(\.modelContext) private var modelContext

    let captureService: TaskCaptureService
    let status: TaskStatus
    let tasks: [TaskRecord]
    let onOpenDetails: (TaskRecord) -> Void

    @State private var isTargeted = false
    /// Inline quick-add state for the column. Tapping the `+` in the header
    /// (or the empty-column row) reveals a TextField so the user can capture
    /// straight into this status without leaving the board view. (UX P3.)
    @State private var isQuickAdding = false
    @State private var quickAddText = ""
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    cards
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
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

            // Quick-add affordance — discoverable on every column so users
            // can capture into Done/In-Progress without dragging from another
            // column. Was previously drop-only. (UX P3.)
            Button {
                isQuickAdding = true
                quickAddFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task to \(status.title)")
        }
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 8) {
            if isQuickAdding {
                quickAddRow
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

    /// Inline composer that creates a task directly in this column's status
    /// (UX P3). Submits on return; cancels on empty submit / escape blur.
    private var quickAddRow: some View {
        HStack(spacing: 6) {
            TextField("New task", text: $quickAddText)
                .focused($quickAddFocused)
                .submitLabel(.done)
                .onSubmit { submitQuickAdd() }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))

            Button {
                isQuickAdding = false
                quickAddText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.mutedText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
    }

    private func submitQuickAdd() {
        let trimmed = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isQuickAdding = false
            quickAddText = ""
            return
        }
        captureService.captureInStatus(title: trimmed, status: status, in: modelContext)
        quickAddText = ""
        // Keep adding mode active so the user can capture several in a row.
        quickAddFocused = true
    }

    private var emptyColumnState: some View {
        // Now actionable — tap to start an inline add. Drop-target still works
        // (`.dropDestination` is on the whole column). (UX P3.)
        Button {
            isQuickAdding = true
            quickAddFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Tap + or drag here")
                    .font(.system(size: 12, weight: .regular))
            }
            .foregroundStyle(AppTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }



    // MARK: - Background

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
    }

    private var backgroundFill: Color {
        isTargeted ? status.tintColor.opacity(0.07) : AppTheme.surfacePrimary
    }

    private var backgroundStroke: Color {
        isTargeted ? status.tintColor.opacity(0.2) : AppTheme.cardBorder
    }



    // MARK: - Drop Handling

    private func handleDrop(items: [String], location _: CGPoint) -> Bool {
        var didMoveAny = false
        for item in items {
            guard let taskID = UUID(uuidString: item),
                  let task = tasksInApp.first(where: { $0.id == taskID }) else { continue }
            // Skip the haptic when the drop lands in the same column the task
            // already lived in — only confirm a *real* status change.
            if task.status != status { didMoveAny = true }
            withAnimation(AppTheme.Motion.base) {
                captureService.setStatus(task, status: status, in: modelContext)
            }
        }
        if didMoveAny {
            // Medium impact = "mutation committed" — matches the weight used
            // elsewhere when a status changes (see TaskRowView toggle).
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        isTargeted = false
        return true
    }

    private func handleTargeting(_ targeted: Bool) {
        withAnimation(AppTheme.Motion.fast) { isTargeted = targeted }
    }
}
