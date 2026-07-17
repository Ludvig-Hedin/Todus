import Foundation
import SwiftData

// MARK: - Proposal model

/// One suggested move produced by the organize pass. Value type consumed by
/// `OrganizeReviewSheet`; nothing is applied until the user taps Apply.
struct OrganizeProposal: Identifiable {
    enum Destination: Hashable {
        case existing(folderID: UUID, name: String)
        case newFolder(name: String)

        var displayName: String {
            switch self {
            case .existing(_, let name): return name
            case .newFolder(let name): return name
            }
        }

        var isNewFolder: Bool {
            if case .newFolder = self { return true }
            return false
        }
    }

    enum Source { case rule, ai }

    let taskID: UUID
    let taskTitle: String
    let destination: Destination
    let source: Source
    var isAccepted: Bool = true

    var id: UUID { taskID }
}

// MARK: - Wire types (tasks.organize)

private struct OrganizeTaskInput: Encodable {
    let id: String
    let title: String
    let description: String
}

private struct OrganizeFolderInput: Encodable {
    let id: String
    let name: String
}

private struct OrganizeRequest: Encodable {
    let tasks: [OrganizeTaskInput]
    let folders: [OrganizeFolderInput]
}

private struct OrganizeResponse: Decodable {
    struct Assignment: Decodable {
        let taskId: String
        let folderId: String?
        let newFolderName: String?
    }

    let assignments: [Assignment]
}

// MARK: - Organize logic

extension TaskCaptureService {
    /// Builds move proposals for every unfiled open task: instant rule layer
    /// (folder-name word match) first, then the `tasks.organize` AI endpoint
    /// for the rest. Offline / unauthenticated → rules-only. Mutates nothing.
    func proposeOrganization(in context: ModelContext) async -> [OrganizeProposal] {
        let folders = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
        let allTasks = (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []
        let unfiled = allTasks
            .filter { $0.folder == nil && $0.status != .done }
            .sorted { $0.createdAt > $1.createdAt }
        guard !unfiled.isEmpty else { return [] }

        var proposals: [OrganizeProposal] = []
        var needsAI: [TaskRecord] = []

        for task in unfiled {
            if let folder = ruleMatch(task: task, folders: folders) {
                proposals.append(OrganizeProposal(
                    taskID: task.id,
                    taskTitle: task.title,
                    destination: .existing(folderID: folder.id, name: folder.name),
                    source: .rule
                ))
            } else {
                needsAI.append(task)
            }
        }

        if !needsAI.isEmpty {
            proposals.append(contentsOf: await aiProposals(for: needsAI, folders: folders))
        }
        return proposals
    }

    /// Applies the accepted subset: creates proposed folders (get-or-create so
    /// two proposals sharing a name land in one folder) and moves each task
    /// through the normal offline-queued `move`. Returns how many tasks moved.
    func applyProposals(_ proposals: [OrganizeProposal], in context: ModelContext) -> Int {
        let accepted = proposals.filter(\.isAccepted)
        guard !accepted.isEmpty else { return 0 }

        var createdByName: [String: FolderRecord] = [:]
        var moved = 0
        for proposal in accepted {
            guard let task = fetchTask(proposal.taskID, in: context), task.folder == nil else { continue }
            let destination: FolderRecord?
            switch proposal.destination {
            case .existing(let folderID, _):
                destination = fetchFolder(folderID, in: context)
            case .newFolder(let name):
                let key = name.lowercased()
                if let cached = createdByName[key] {
                    destination = cached
                } else {
                    destination = createFolder(named: name, in: context)
                    if let folder = destination { createdByName[key] = folder }
                }
            }
            guard let folder = destination else { continue }
            task.suggestedFolderID = nil
            move(task, to: folder, in: context)
            moved += 1
        }
        return moved
    }

    // MARK: Per-task suggestion (on create)

    /// One-shot folder suggestion for a freshly enriched, unfiled task.
    /// Existing folders only — a single capture never proposes new folders.
    /// Sets `suggestedFolderID`; the row renders the accept/dismiss chip.
    func suggestFolder(for task: TaskRecord, in context: ModelContext) async {
        guard task.folder == nil, task.suggestedFolderID == nil else { return }
        let folders = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
        guard !folders.isEmpty else { return }

        if let match = ruleMatch(task: task, folders: folders) {
            task.suggestedFolderID = match.id
            try? context.save()
            AppLogger.shared.log("TaskOrganize: rule-suggested folder \(match.name) for task \(task.id)")
            return
        }

        let request = OrganizeRequest(
            tasks: [OrganizeTaskInput(
                id: task.id.uuidString,
                title: task.title,
                description: String(task.taskDescription.prefix(300))
            )],
            folders: folders.map { OrganizeFolderInput(id: $0.id.uuidString, name: $0.name) }
        )
        guard
            let response: OrganizeResponse = try? await apiClient.trpcMutation("tasks.organize", input: request),
            let assignment = response.assignments.first,
            let folderIDString = assignment.folderId,
            let folderID = UUID(uuidString: folderIDString),
            folders.contains(where: { $0.id == folderID })
        else { return }

        // The user may have filed the task while the request was in flight.
        guard task.folder == nil else { return }
        task.suggestedFolderID = folderID
        try? context.save()
    }

    /// Row chip "✓": move to the suggested folder.
    func acceptSuggestion(for task: TaskRecord, in context: ModelContext) {
        guard let folderID = task.suggestedFolderID else { return }
        task.suggestedFolderID = nil
        guard let folder = fetchFolder(folderID, in: context) else {
            try? context.save()
            return
        }
        move(task, to: folder, in: context)
    }

    /// Row chip "✕": clear the suggestion, never re-suggest.
    func dismissSuggestion(for task: TaskRecord, in context: ModelContext) {
        task.suggestedFolderID = nil
        try? context.save()
    }

    // MARK: Rule layer

    /// Deterministic match: a folder wins when its full name (multi-word) or
    /// its name as a whole word (single-word) appears in the task text.
    private func ruleMatch(task: TaskRecord, folders: [FolderRecord]) -> FolderRecord? {
        let haystack = "\(task.title) \(task.taskDescription)".lowercased()
        let words = Set(
            haystack
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        for folder in folders {
            let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name.count >= 2 else { continue }
            if name.contains(" ") {
                if haystack.contains(name) { return folder }
            } else if words.contains(name) {
                return folder
            }
        }
        return nil
    }

    // MARK: AI layer

    private func aiProposals(for tasks: [TaskRecord], folders: [FolderRecord]) async -> [OrganizeProposal] {
        let batch = Array(tasks.prefix(100))
        let request = OrganizeRequest(
            tasks: batch.map {
                OrganizeTaskInput(
                    id: $0.id.uuidString,
                    title: $0.title,
                    description: String($0.taskDescription.prefix(300))
                )
            },
            folders: folders.map { OrganizeFolderInput(id: $0.id.uuidString, name: $0.name) }
        )

        do {
            let response: OrganizeResponse = try await apiClient.trpcMutation("tasks.organize", input: request)
            let tasksByID = Dictionary(uniqueKeysWithValues: batch.map { ($0.id.uuidString.lowercased(), $0) })
            var out: [OrganizeProposal] = []
            for assignment in response.assignments {
                guard let task = tasksByID[assignment.taskId.lowercased()] else { continue }
                if let folderIDString = assignment.folderId,
                   let folderID = UUID(uuidString: folderIDString),
                   let folder = folders.first(where: { $0.id == folderID }) {
                    out.append(OrganizeProposal(
                        taskID: task.id,
                        taskTitle: task.title,
                        destination: .existing(folderID: folder.id, name: folder.name),
                        source: .ai
                    ))
                } else if let newName = assignment.newFolderName?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !newName.isEmpty {
                    out.append(OrganizeProposal(
                        taskID: task.id,
                        taskTitle: task.title,
                        destination: .newFolder(name: newName),
                        source: .ai
                    ))
                }
            }
            return out
        } catch {
            AppLogger.shared.log("TaskOrganize: remote organize failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Fetch helpers

    private func fetchTask(_ id: UUID, in context: ModelContext) -> TaskRecord? {
        let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchFolder(_ id: UUID, in context: ModelContext) -> FolderRecord? {
        let descriptor = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
