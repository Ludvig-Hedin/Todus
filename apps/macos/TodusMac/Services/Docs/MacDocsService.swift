import Foundation
import Observation

/// Loads and mutates server-backed docs via tRPC (`docs.*`).
@MainActor
@Observable
final class MacDocsService {
    private weak var apiClient: TodosAPIClient?

    private(set) var workspaces: [DocWorkspaceDTO] = []
    private(set) var allDocs: [DocRecordDTO] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private var didAttemptCreatePersonal = false
    private var didLogDocsUnavailable = false

    // MARK: - UI Bridge Properties

    /// Set by MacDocEditorPane when a doc is open; cleared on disappear.
    /// Allows MacAssistantPanel to show the doc title in the context pill.
    var currentOpenDocId: String? = nil

    /// Set by MacAssistantPanel when user taps "Insert into doc".
    /// MacDocEditorPane observes this and inserts via JS, then clears it.
    var pendingDocInsert: String? = nil

    /// Snapshot of doc content taken before an AI edit.
    /// Used by the session-level revert button in MacDocEditorPane.
    var preAIEditSnapshot: DocJSONValue? = nil

    /// True while the revert button should be visible in the editor chrome.
    var hasUnrevertedAIEdit: Bool = false

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    func refresh() async {
        guard let client = apiClient else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let ws: DocWorkspacesListResponse = try await client.trpcQuery("docs.workspaces.list")
            var list = ws.workspaces.sorted { $0.name < $1.name }

            if list.isEmpty, !didAttemptCreatePersonal {
                didAttemptCreatePersonal = true
                let created: DocWorkspaceMutationResponse = try await client.trpcMutation(
                    "docs.workspaces.create",
                    input: DocWorkspaceCreateInput(name: "Personal", emoji: nil)
                )
                list = [created.workspace]
            }

            workspaces = list

            let docs: DocListResponse = try await client.trpcQuery("docs.list", input: DocsListInput())
            allDocs = docs.docs
            didLogDocsUnavailable = false
        } catch {
            if error.isURLCancellation { return }
            if case let APIError.httpError(statusCode, _) = error, statusCode == 412 {
                lastError = "Docs aren’t available on this server yet."
                if !didLogDocsUnavailable {
                    didLogDocsUnavailable = true
                    AppLogger.shared.log("[MacDocsService] docs unavailable on server (HTTP 412 — pending Drizzle migrations)")
                }
                return
            }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.log("[MacDocsService] refresh failed: \(error)")
        }
    }

    /// Creates a page in the first workspace, refreshing (and auto-creating Personal) when needed.
    func createNewDocument(title: String = "Untitled") async throws -> DocRecordDTO {
        guard apiClient != nil else {
            throw URLError(.userAuthenticationRequired)
        }
        if workspaces.isEmpty {
            // Keep `didAttemptCreatePersonal` sticky for the session — refresh() guards
            // against double-creating a Personal workspace via the same flag. Resetting
            // it here would race the refresh and yield duplicate workspaces.
            await refresh()
        }
        guard let w = workspaces.first else {
            let hint = lastError ?? "Unable to load workspaces. Please check your connection."
            throw NSError(
                domain: "MacDocsService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: hint]
            )
        }
        return try await createDoc(workspaceId: w.id, parentId: nil, title: title)
    }

    func ensurePersonalWorkspaceIfEmpty() async {
        if !workspaces.isEmpty { return }
        await refresh()
    }

    func listDocs(forWorkspaceId workspaceId: String?) -> [DocRecordDTO] {
        let filtered: [DocRecordDTO]
        if let workspaceId {
            filtered = allDocs.filter { $0.workspaceId == workspaceId }
        } else {
            filtered = allDocs
        }
        return filtered.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            return a.createdAt < b.createdAt
        }
    }

    func rootDocs(forWorkspaceId workspaceId: String) -> [DocRecordDTO] {
        listDocs(forWorkspaceId: workspaceId).filter { $0.parentId == nil }
    }

    func children(ofParentId parentId: String, workspaceId: String) -> [DocRecordDTO] {
        listDocs(forWorkspaceId: workspaceId).filter { $0.parentId == parentId }
    }

    var starredDocs: [DocRecordDTO] {
        allDocs.filter(\.isStarred).sorted { $0.updatedAt > $1.updatedAt }
    }

    func getDoc(id: String) async -> DocRecordDTO? {
        if let d = allDocs.first(where: { $0.id == id }) { return d }
        guard let client = apiClient else { return nil }
        do {
            let r: SingleDocResponse = try await client.trpcQuery("docs.get", input: DocGetInput(id: id))
            upsert(r.doc)
            return r.doc
        } catch {
            AppLogger.shared.log("[MacDocsService] getDoc: \(error)")
            return nil
        }
    }

    func createDoc(workspaceId: String?, parentId: String?, title: String?) async throws -> DocRecordDTO {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let input = DocCreateInput(
            workspaceId: workspaceId,
            parentId: parentId,
            title: title ?? "Untitled",
            emoji: nil
        )
        let r: DocMutationResponse = try await client.trpcMutation("docs.create", input: input)
        upsert(r.doc)
        return r.doc
    }

    func updateDoc(_ input: DocUpdateInput) async throws -> DocRecordDTO {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let r: DocMutationResponse = try await client.trpcMutation("docs.update", input: input)
        upsert(r.doc)
        return r.doc
    }

    func deleteDoc(id: String) async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let _: DocDeleteSuccess = try await client.trpcMutation("docs.delete", input: DocDeleteInput(id: id))
        allDocs.removeAll { $0.id == id }
    }

    func search(_ query: String) async throws -> [DocRecordDTO] {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let r: DocSearchResponse = try await client.trpcQuery("docs.search", input: DocSearchInput(query: query))
        return r.docs
    }

    private func upsert(_ d: DocRecordDTO) {
        if let i = allDocs.firstIndex(where: { $0.id == d.id }) {
            allDocs[i] = d
        } else {
            allDocs.append(d)
        }
    }
}
