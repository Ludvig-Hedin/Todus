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
    // Default false — EmailInboxView calls checkConnection() on appear to verify
    var hasConnection = false
    var errorMessage: String?
    var nextPageToken: String?
    var assistantNudges: [MailAssistantNudge] = []

    // MARK: - Init

    init(api: TodosAPIClient) {
        self.api = api
    }

    // MARK: - Inbox

    /// Fetches threads for a given folder (default: inbox).
    /// Two-step process: get thread IDs from listThreads, then enrich each with mail.get.
    func loadThreads(folder: String = "inbox", query: String? = nil, refresh: Bool = false) async {
        if isLoadingThreads && !refresh && query == nil {
            return
        }

        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.loadThreads,
            message: "EmailService.loadThreads begin folder=\(folder) refresh=\(refresh)"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.loadThreads,
                trace,
                message: "EmailService.loadThreads end folder=\(folder) count=\(threads.count)"
            )
        }

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
            if query == nil {
                await loadAssistantNudges(folder: folder)
            }
        } catch let error as APIError where error.errorDescription?.contains("Session expired") == true {
            hasConnection = false
        } catch {
            errorMessage = "Failed to load emails."
            AppLogger.shared.log("[EmailService] loadThreads error: \(error)")
        }

        isLoadingThreads = false
    }

    func ensureInitialInboxLoaded() async {
        await checkConnection()
        guard hasConnection else { return }
        guard threads.isEmpty else { return }
        await loadThreads(refresh: true)
    }

    func resetForSignOut() {
        threads = []
        isLoadingThreads = false
        isLoadingThread = false
        isSending = false
        hasConnection = false
        errorMessage = nil
        nextPageToken = nil
        assistantNudges = []
    }

    /// Fetches full details for multiple threads in parallel via mail.get.
    /// Returns EmailThread summary objects built from each thread's latest message.
    /// Batches requests into groups of 8 to reduce connection contention and memory pressure.
    /// Previously all 30 requests fired simultaneously, causing URLSession connection saturation.
    private func fetchThreadDetails(ids: [String]) async -> [EmailThread] {
        let batchSize = 8
        var allResults = [(Int, EmailThread?)]()
        allResults.reserveCapacity(ids.count)

        // Process in batches to avoid overwhelming URLSession with 30+ concurrent requests
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
            AppLogger.shared.log("[EmailService] Failed to fetch thread \(id): \(error)")
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

    func loadAssistant(threadId: String) async -> MailAssistantThread? {
        do {
            return try await api.trpcQuery("mailAssistant.getThread", input: AssistantThreadInput(threadId: threadId))
        } catch {
            AppLogger.shared.log("[EmailService] loadAssistant error: \(error)")
            return nil
        }
    }

    func loadAssistantNudges(folder: String = "inbox") async {
        do {
            let response: MailAssistantNudgesResponse = try await api.trpcQuery(
                "mailAssistant.getInboxNudges",
                input: MailAssistantNudgesInput(folder: folder)
            )
            assistantNudges = response.nudges
        } catch {
            AppLogger.shared.log("[EmailService] loadAssistantNudges error: \(error)")
        }
    }

    func createAssistantTask(threadId: String, suggestion: MailAssistantSuggestedTask) async -> Bool {
        do {
            let _: MailAssistantTaskCreateResponse = try await api.trpcMutation(
                "mailAssistant.createTaskFromSuggestion",
                input: MailAssistantCreateTaskInput(threadId: threadId, task: suggestion)
            )
            return true
        } catch {
            AppLogger.shared.log("[EmailService] createAssistantTask error: \(error)")
            return false
        }
    }

    func createAssistantEvent(threadId: String, suggestion: MailAssistantSuggestedEvent) async -> Bool {
        guard suggestion.startAt != nil, suggestion.endAt != nil else { return false }

        do {
            let _: MailAssistantEventCreateResponse = try await api.trpcMutation(
                "mailAssistant.createEventFromSuggestion",
                input: MailAssistantCreateEventInput(threadId: threadId, event: suggestion)
            )
            return true
        } catch {
            AppLogger.shared.log("[EmailService] createAssistantEvent error: \(error)")
            return false
        }
    }

    func generateAssistantDraft(threadId: String) async -> MailAssistantDraftResult? {
        do {
            return try await api.trpcMutation(
                "mailAssistant.generateDraft",
                input: MailAssistantDraftInput(threadId: threadId, openInComposer: true)
            )
        } catch {
            AppLogger.shared.log("[EmailService] generateAssistantDraft error: \(error)")
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
            // Update local state
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

// These match the TRPC input shapes on the backend

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

private struct AssistantThreadInput: Encodable {
    let threadId: String
}

private struct MailAssistantDraftInput: Encodable {
    let threadId: String
    let openInComposer: Bool
}

private struct MailAssistantNudgesInput: Encodable {
    let folder: String
}

private struct MailAssistantCreateTaskInput: Encodable {
    let threadId: String
    let task: MailAssistantSuggestedTask
}

private struct MailAssistantCreateEventInput: Encodable {
    let threadId: String
    let event: MailAssistantSuggestedEvent
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
/// Matches IGetThreadResponseSchema from the backend.
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

private struct MailAssistantNudgesResponse: Decodable {
    let nudges: [MailAssistantNudge]
}

private struct MailAssistantTaskCreateResponse: Decodable {
    let task: AssistantTaskRecord
}

private struct AssistantTaskRecord: Decodable {
    let id: String
}

private struct MailAssistantEventCreateResponse: Decodable {
    let id: String
    let htmlLink: String?
}

private struct SuccessResponse: Decodable {
    let success: Bool?
}

/// Accepts any JSON response without requiring specific fields
private struct EmailEmptyResponse: Decodable {}
