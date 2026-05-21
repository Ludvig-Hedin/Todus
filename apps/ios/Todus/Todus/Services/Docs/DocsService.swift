import Foundation
import Observation

/// Loads and mutates server-backed docs via tRPC (`docs.*`).
/// Mirrors the macOS `MacDocsService` API so the same backend protocol is exercised on iOS.
///
/// Published state (`@Observable`):
/// - `workspaces`: all workspaces for the signed-in user
/// - `allDocs`: every doc across every workspace (filter with `listDocs(forWorkspaceId:)`)
/// - `isLoading`: true while a refresh is in flight
/// - `lastError`: localized message of the most recent failure (cleared on next refresh)
@MainActor
@Observable
final class DocsService {
    private weak var apiClient: TodosAPIClient?

    private(set) var workspaces: [DocWorkspaceDTO] = []
    private(set) var allDocs: [DocRecordDTO] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// Set once we attempt to auto-create the Personal workspace so we do not
    /// race a second refresh into double-creating it.
    private var didAttemptCreatePersonal = false
    /// Suppress repeated log spam when the backend hasn't been migrated yet.
    private var didLogDocsUnavailable = false

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Loading

    /// Reloads workspaces + docs. Auto-creates a "Personal" workspace on the
    /// first run if the user has none. Safe to call repeatedly.
    func refresh() async {
        guard let client = apiClient else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let ws: DocWorkspacesListResponse = try await client.trpcQuery("docs.workspaces.list")
            var list = ws.workspaces.sorted { $0.name < $1.name }

            if !didAttemptCreatePersonal {
                // Skip creation when the server already has any workspace whose
                // name matches "Personal" case-insensitively — covers (a) web or
                // macOS having created one, (b) a previous iOS install that
                // already auto-created, (c) the user manually creating one
                // before iOS first opens Docs.
                let alreadyHasPersonal = list.contains { ws in
                    ws.name.compare("Personal", options: .caseInsensitive) == .orderedSame
                }
                if list.isEmpty && !alreadyHasPersonal {
                    didAttemptCreatePersonal = true
                    do {
                        let created: DocWorkspaceMutationResponse = try await client.trpcMutation(
                            "docs.workspaces.create",
                            input: DocWorkspaceCreateInput(name: "Personal", emoji: nil)
                        )
                        list = [created.workspace]
                    } catch {
                        // Server may reject with 409 / 422 if a Personal workspace
                        // was created server-side between our list + create calls.
                        // Refetch and continue with whatever the server has.
                        AppLogger.shared.log("[DocsService] Personal workspace create raced — refetching: \(error)")
                        let refreshed: DocWorkspacesListResponse = try await client.trpcQuery("docs.workspaces.list")
                        list = refreshed.workspaces.sorted { $0.name < $1.name }
                    }
                } else if alreadyHasPersonal {
                    // Mark attempted so we don't retry on every refresh; nothing
                    // to create — Personal already exists somewhere.
                    didAttemptCreatePersonal = true
                }
            }

            workspaces = list

            let docs: DocListResponse = try await client.trpcQuery(
                "docs.list",
                input: DocsListInput()
            )
            allDocs = docs.docs
            didLogDocsUnavailable = false
        } catch {
            if Self.isCancellation(error) { return }
            if case let APIError.httpError(statusCode, _) = error, statusCode == 412 {
                lastError = "Docs aren't available on this server yet."
                if !didLogDocsUnavailable {
                    didLogDocsUnavailable = true
                    AppLogger.shared.log("[DocsService] docs unavailable on server (HTTP 412 — pending migrations)")
                }
                return
            }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.log("[DocsService] refresh failed: \(error)")
        }
    }

    /// Convenience used by the create-doc flow when the user hasn't refreshed yet.
    func ensurePersonalWorkspaceIfEmpty() async {
        if !workspaces.isEmpty { return }
        await refresh()
    }

    // MARK: - Listing / filtering

    /// All docs for a workspace (or all docs if `workspaceId` is nil), ordered by
    /// stored `order` then creation time so the iOS sidebar mirrors the macOS one.
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

    /// Top-level docs (no parent) within a workspace.
    func rootDocs(forWorkspaceId workspaceId: String) -> [DocRecordDTO] {
        listDocs(forWorkspaceId: workspaceId).filter { $0.parentId == nil }
    }

    /// Direct children of a doc inside a workspace.
    func children(ofParentId parentId: String, workspaceId: String) -> [DocRecordDTO] {
        listDocs(forWorkspaceId: workspaceId).filter { $0.parentId == parentId }
    }

    /// Starred docs across all workspaces — newest update first.
    var starredDocs: [DocRecordDTO] {
        allDocs.filter(\.isStarred).sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - CRUD

    /// Fetches a doc by id. Returns the cached copy when available so the editor
    /// can render immediately; falls back to the server otherwise.
    func getDoc(id: String) async -> DocRecordDTO? {
        if let cached = allDocs.first(where: { $0.id == id }) { return cached }
        guard let client = apiClient else { return nil }
        do {
            let r: SingleDocResponse = try await client.trpcQuery(
                "docs.get",
                input: DocGetInput(id: id)
            )
            upsert(r.doc)
            return r.doc
        } catch {
            if Self.isCancellation(error) { return nil }
            AppLogger.shared.log("[DocsService] getDoc: \(error)")
            return nil
        }
    }

    /// Creates a new doc in the given workspace (and optional parent). Refreshes if
    /// no workspaces are loaded yet — matches the macOS auto-create behaviour.
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

    /// Creates a doc inside the first workspace, ensuring one exists first.
    /// Used by the `+` button in the iOS list shell.
    func createNewDocument(title: String = "Untitled") async throws -> DocRecordDTO {
        guard apiClient != nil else { throw URLError(.userAuthenticationRequired) }
        if workspaces.isEmpty {
            await refresh()
        }
        guard let w = workspaces.first else {
            let hint = lastError ?? "Unable to load workspaces. Please check your connection."
            throw NSError(
                domain: "DocsService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: hint]
            )
        }
        return try await createDoc(workspaceId: w.id, parentId: nil, title: title)
    }

    /// Updates a doc with the provided patch. Returns the server's authoritative copy.
    func updateDoc(_ input: DocUpdateInput) async throws -> DocRecordDTO {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let r: DocMutationResponse = try await client.trpcMutation("docs.update", input: input)
        upsert(r.doc)
        return r.doc
    }

    /// Convenience wrapper for the common title-only rename path.
    func renameDoc(id: String, title: String) async throws -> DocRecordDTO {
        try await updateDoc(DocUpdateInput(id: id, title: title))
    }

    /// Toggles the starred state and persists.
    func setStarred(id: String, isStarred: Bool) async throws -> DocRecordDTO {
        try await updateDoc(DocUpdateInput(id: id, isStarred: isStarred))
    }

    /// Toggles starred based on the cached value.
    @discardableResult
    func togglePin(id: String) async throws -> DocRecordDTO {
        let current = allDocs.first(where: { $0.id == id })?.isStarred ?? false
        return try await setStarred(id: id, isStarred: !current)
    }

    /// Moves a doc to a new parent (pass `nil` for root).
    @discardableResult
    func moveDoc(id: String, parentId: String?) async throws -> DocRecordDTO {
        try await updateDoc(DocUpdateInput(id: id, parentId: parentId))
    }

    /// Deletes a doc and removes it from the local cache.
    func deleteDoc(id: String) async throws {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let _: DocDeleteSuccess = try await client.trpcMutation(
            "docs.delete",
            input: DocDeleteInput(id: id)
        )
        allDocs.removeAll { $0.id == id }
    }

    /// Server-side full-text search. Returns docs but does not mutate `allDocs`.
    func search(_ query: String) async throws -> [DocRecordDTO] {
        guard let client = apiClient else { throw URLError(.userAuthenticationRequired) }
        let r: DocSearchResponse = try await client.trpcQuery(
            "docs.search",
            input: DocSearchInput(query: query)
        )
        return r.docs
    }

    // MARK: - Internals

    /// Inserts or replaces a doc in the local cache without re-fetching the whole list.
    private func upsert(_ d: DocRecordDTO) {
        if let i = allDocs.firstIndex(where: { $0.id == d.id }) {
            allDocs[i] = d
        } else {
            allDocs.append(d)
        }
    }

    /// SwiftUI tears down `.task` modifiers on dismiss, which surfaces as URLError.cancelled
    /// or Swift's `CancellationError`. Filter those — they aren't real failures.
    private static func isCancellation(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if error is CancellationError { return true }
        return false
    }
}
