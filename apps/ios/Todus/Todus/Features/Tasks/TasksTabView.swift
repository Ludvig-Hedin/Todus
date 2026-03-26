import SwiftUI
import SwiftData

/// The Tasks tab — extracted from the original MiniTaskApp RootView.
/// Contains the view mode picker, folder strip, search bar, and task list/board/table/calendar views.
struct TasksTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    @State private var composerText = ""
    @State private var searchText = ""
    @State private var taskSortOrder: TaskSortOrder = .newest

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: 12) {
                header
                    .padding(.horizontal, 16)

                if !folders.isEmpty {
                    folderStrip
                        .padding(.horizontal, 16)
                }

                searchSortBar
                    .padding(.horizontal, 16)

                Group {
                    switch services.selectedViewMode {
                    case .list:
                        InboxView(searchText: searchText, sortOrder: taskSortOrder)
                            .padding(.horizontal, 16)
                    case .board:
                        BoardView()
                    case .table:
                        TaskTableView()
                            .padding(.horizontal, 16)
                    case .calendar:
                        CalendarTaskView(searchText: searchText)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            CaptureComposer(text: $composerText) { attachmentNames, folder, dueDate in
                let raw = composerText
                composerText = ""
                withAnimation(.snappy(duration: 0.18)) {
                    services.captureService.capture(
                        rawComposerText: raw,
                        attachmentNames: attachmentNames,
                        selectedFolder: folder,
                        overrideDueDate: dueDate,
                        in: modelContext
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 60) // Extra space for the custom tab bar
            .background(.clear)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            viewModePicker

            Button {
                services.showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(TaskViewMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        services.selectedViewMode = mode
                    }
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            services.selectedViewMode == mode ? .primary : AppTheme.mutedText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            services.selectedViewMode == mode
                                ? AppTheme.surfaceSecondary
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Search + Sort Bar

    private var searchSortBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)

            TextField("Search tasks…", text: $searchText)
                .font(.system(size: 14, weight: .medium))
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 16)

            Menu {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        taskSortOrder = order
                    } label: {
                        Label(order.title, systemImage: taskSortOrder == order ? "checkmark" : order.systemImage)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            AppTheme.surfaceSecondary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Folder Strip

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    services.selectFolder(nil)
                } label: {
                    Text("All")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(services.selectedFolderID == nil ? AppTheme.accent.opacity(0.12) : AppTheme.surfacePrimary, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(services.selectedFolderID == nil ? AppTheme.accent.opacity(0.24) : AppTheme.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                ForEach(folders) { folder in
                    Button {
                        services.selectFolder(folder)
                    } label: {
                        Text(folder.name)
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(-0.1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(services.selectedFolderID == folder.id ? AppTheme.accent.opacity(0.12) : AppTheme.surfacePrimary, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(services.selectedFolderID == folder.id ? AppTheme.accent.opacity(0.24) : AppTheme.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

/// Helper to dismiss keyboard from any view
private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
