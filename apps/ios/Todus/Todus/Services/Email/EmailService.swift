import Foundation
import Observation

/// Email service that wraps TodosAPIClient for email-specific TRPC calls.
/// Manages inbox state, thread loading, and email actions (send, archive, read/unread).
@MainActor
@Observable
final class EmailService {
    private let api: TodosAPIClient

    // MARK: - State

    var threads: [EmailThread] = []
    var isLoadingThreads = false
    var isLoadingThread = false
    var isSending = false
    var hasConnection = true
    var errorMessage: String?
    var nextPageToken: String?

    // MARK: - Init

    init(api: TodosAPIClient) {
        self.api = api
    }

    // MARK: - Inbox

    /// Fetches threads for a given folder (default: inbox).
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
            let response: ListThreadsResponse = try await api.trpcQuery("mail.listThreads", input: input)

            // The backend returns minimal thread objects — we need to enrich with snippet/from/date.
            // For MVP, map the raw thread data into our EmailThread model.
            let newThreads = response.threads.map { raw in
                EmailThread(
                    id: raw.id,
                    subject: raw.subject ?? "",
                    snippet: raw.snippet ?? "",
                    from: EmailSender(
                        name: raw.senderName ?? raw.senderEmail ?? "Unknown",
                        email: raw.senderEmail ?? ""
                    ),
                    date: raw.date ?? Date(),
                    unread: raw.unread ?? false,
                    messageCount: raw.messageCount ?? 1,
                    labels: raw.labels ?? []
                )
            }

            if refresh {
                threads = newThreads
            } else {
                threads.append(contentsOf: newThreads)
            }
            nextPageToken = response.nextPageToken
        } catch let error as APIError where error.errorDescription?.contains("Session expired") == true {
            hasConnection = false
        } catch {
            errorMessage = "Failed to load emails."
        }

        isLoadingThreads = false
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

// Response types

struct ListThreadsResponse: Decodable {
    let threads: [RawThread]
    let nextPageToken: String?
}

/// Raw thread from the backend — fields may be sparse depending on provider.
struct RawThread: Decodable {
    let id: String
    let subject: String?
    let snippet: String?
    let senderName: String?
    let senderEmail: String?
    let date: Date?
    let unread: Bool?
    let messageCount: Int?
    let labels: [String]?
}

/// Full thread detail with messages, returned by mail.get
struct GetThreadResponse: Decodable {
    let messages: [EmailMessage]
    let hasUnread: Bool?
    let totalReplies: Int?
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
