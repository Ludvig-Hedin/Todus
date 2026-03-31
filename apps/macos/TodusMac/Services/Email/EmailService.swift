import Foundation
import Observation

/// Email service that wraps TodosAPIClient for email-specific TRPC calls.
/// Manages inbox state, thread loading, and email actions (send, archive, read/unread).
///
/// The backend `mail.listThreads` only returns thread IDs (not sender/subject/snippet).
/// To get full thread details, we call `mail.get` for each thread — same approach as the web app.
@MainActor
@Observable
final class EmailService {
    private let api: TodosAPIClient

    // MARK: - State

    var threads: [EmailThread] = []
    var isLoadingThreads = false
    var isLoadingThread = false
    var isSending = false
    // Default false — views call checkConnection() on appear to verify
    var hasConnection = false
    var errorMessage: String?
    var nextPageToken: String?

    // MARK: - Init

    init(api: TodosAPIClient) {
        self.api = api
    }

    /// Clears all cached email state on sign-out so the next session starts fresh.
    func resetForSignOut() {
        threads = []
        nextPageToken = nil
        errorMessage = nil
        hasConnection = false
    }

    // MARK: - Inbox

    /// Fetches threads for a given folder (default: inbox).
    /// Two-step process: get thread IDs from listThreads, then enrich each with mail.get.
    func loadThreads(folder: String = "inbox", query: String? = nil, refresh: Bool = false) async {
        if refresh { nextPageToken = nil }
        isLoadingThreads = true
        errorMessage = nil

        do {
            let input = ListThreadsInput(
                folder: folder,
                q: query,
                maxResults: 30,
                cursor: refresh ? nil : nextPageToken
            )
            // Step 1: Get thread IDs from backend
            let response: ListThreadsResponse = try await api.trpcQuery("mail.listThreads", input: input)

            // Step 2: Fetch full details for each thread in parallel
            let threadIds = response.threads.map(\.id)
            let enrichedThreads = await fetchThreadDetails(ids: threadIds)

            if refresh {
                threads = enrichedThreads
            } else {
                threads.append(contentsOf: enrichedThreads)
            }
            nextPageToken = response.nextPageToken
        } catch let error as APIError where error.errorDescription?.contains("Session expired") == true {
            hasConnection = false
        } catch {
            errorMessage = "Failed to load emails."
            print("[EmailService] loadThreads error: \(error)")
        }

        isLoadingThreads = false
    }

    /// Fetches full details for multiple threads in parallel via mail.get.
    /// Batches requests into groups of 8 to reduce connection contention.
    private func fetchThreadDetails(ids: [String]) async -> [EmailThread] {
        let batchSize = 8
        var allResults = [(Int, EmailThread?)]()
        allResults.reserveCapacity(ids.count)

        for batchStart in stride(from: 0, to: ids.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, ids.count)
            let batchIds = Array(ids[batchStart..<batchEnd])

            let batchResults: [(Int, EmailThread?)] = await withTaskGroup(of: (Int, EmailThread?).self) { group in
                for (localIndex, id) in batchIds.enumerated() {
                    let globalIndex = batchStart + localIndex
                    group.addTask {
                        await self.fetchSingleThread(id: id, index: globalIndex)
                    }
                }
                var collected = [(Int, EmailThread?)]()
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            allResults.append(contentsOf: batchResults)
        }

        return allResults.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }

    /// Fetches a single thread's details and builds an EmailThread summary from the latest message.
    private func fetchSingleThread(id: String, index: Int) async -> (Int, EmailThread?) {
        do {
            let input = GetThreadInput(id: id)
            let detail: GetThreadResponse = try await api.trpcQuery("mail.get", input: input)

            // Use the latest non-draft message for the thread summary
            guard let latest = detail.latest ?? detail.messages.last else {
                return (index, nil)
            }

            let thread = EmailThread(
                id: id,
                subject: latest.subject,
                snippet: latest.plainText ?? "",
                from: latest.from,
                date: latest.date,
                unread: detail.hasUnread ?? false,
                messageCount: detail.totalReplies ?? detail.messages.count,
                labels: detail.labels?.map(\.name) ?? []
            )
            return (index, thread)
        } catch {
            print("[EmailService] Failed to fetch thread \(id): \(error)")
            return (index, nil)
        }
    }

    /// Fetches a single thread with all messages.
    func loadThread(id: String) async -> EmailThreadDetail? {
        isLoadingThread = true
        errorMessage = nil

        defer { isLoadingThread = false }

        do {
            let input = GetThreadInput(id: id)
            let response: GetThreadResponse = try await api.trpcQuery("mail.get", input: input)
            return response
        } catch {
            errorMessage = "Failed to load thread."
            return nil
        }
    }

    // MARK: - Connections

    /// Check if the user has any email connections (Gmail/Outlook).
    func checkConnection() async {
        do {
            let response: ConnectionsResponse = try await api.trpcQuery("connections.list")
            hasConnection = !response.connections.isEmpty
        } catch {
            hasConnection = false
        }
    }

    /// Initiates Gmail OAuth connection by re-triggering Google sign-in.
    /// Google sign-in grants auth + mail scopes; after OAuth the connection is checked.
    func connectGmail(authService: AuthService) async {
        await authService.signInWithGoogle()
        await checkConnection()
        if hasConnection {
            await loadThreads(refresh: true)
        }
    }

    // MARK: - Actions

    func sendEmail(_ draft: EmailDraft) async -> Bool {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let input = SendEmailInput(
                to: draft.to.map { SendRecipient(email: $0) },
                subject: draft.subject,
                message: draft.body,
                threadId: draft.replyToThreadId
            )
            let _: SendResponse = try await api.trpcMutation("mail.send", input: input)
            return true
        } catch {
            errorMessage = "Failed to send email."
            return false
        }
    }

    func markAsRead(ids: [String]) async {
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsRead", input: IdsInput(ids: ids))
            for i in threads.indices where ids.contains(threads[i].id) {
                threads[i] = EmailThread(
                    id: threads[i].id, subject: threads[i].subject,
                    snippet: threads[i].snippet, from: threads[i].from,
                    date: threads[i].date, unread: false,
                    messageCount: threads[i].messageCount, labels: threads[i].labels
                )
            }
        } catch {}
    }

    func markAsUnread(ids: [String]) async {
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsUnread", input: IdsInput(ids: ids))
            for i in threads.indices where ids.contains(threads[i].id) {
                threads[i] = EmailThread(
                    id: threads[i].id, subject: threads[i].subject,
                    snippet: threads[i].snippet, from: threads[i].from,
                    date: threads[i].date, unread: true,
                    messageCount: threads[i].messageCount, labels: threads[i].labels
                )
            }
        } catch {}
    }

    func archiveThreads(ids: [String]) async {
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkArchive", input: IdsInput(ids: ids))
            threads.removeAll { ids.contains($0.id) }
        } catch {}
    }

    func deleteThreads(ids: [String]) async {
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkDelete", input: IdsInput(ids: ids))
            threads.removeAll { ids.contains($0.id) }
        } catch {}
    }

    func toggleStar(ids: [String]) async {
        do {
            let _: SuccessResponse = try await api.trpcMutation("mail.toggleStar", input: IdsInput(ids: ids))
        } catch {}
    }
}

// MARK: - Request/Response DTOs

private struct ListThreadsInput: Encodable {
    let folder: String
    let q: String?
    let maxResults: Int
    let cursor: String?
}

private struct GetThreadInput: Encodable {
    let id: String
}

private struct IdsInput: Encodable {
    let ids: [String]
}

private struct SendRecipient: Encodable {
    let email: String
    let name: String? = nil
}

private struct SendEmailInput: Encodable {
    let to: [SendRecipient]
    let subject: String
    let message: String
    let threadId: String?
}

// Response types

/// Backend listThreads returns minimal thread objects — just IDs, no sender/subject.
struct ListThreadsResponse: Decodable {
    let threads: [RawThread]
    let nextPageToken: String?
}

/// Minimal thread from listThreads — only has id and historyId.
struct RawThread: Decodable {
    let id: String
    let historyId: String?
}

/// Full thread detail with messages, returned by mail.get.
struct GetThreadResponse: Decodable {
    let messages: [EmailMessage]
    let latest: EmailMessage?
    let hasUnread: Bool?
    let totalReplies: Int?
    let labels: [ThreadLabel]?

    struct ThreadLabel: Decodable {
        let id: String
        let name: String
    }
}

/// Alias for readability in thread detail views
typealias EmailThreadDetail = GetThreadResponse

struct ConnectionsResponse: Decodable {
    let connections: [EmailConnection]
}

struct EmailConnection: Decodable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let picture: String?
}

private struct SendResponse: Decodable {
    let success: Bool
}

private struct SuccessResponse: Decodable {
    let success: Bool?
}

/// Accepts any JSON response without requiring specific fields
private struct EmailEmptyResponse: Decodable {}
