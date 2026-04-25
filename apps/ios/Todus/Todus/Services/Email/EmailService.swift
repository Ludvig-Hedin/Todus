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
    var isCheckingConnection = false
    var hasResolvedConnection = false
    var errorMessage: String?
    var nextPageToken: String?
    var assistantNudges: [MailAssistantNudge] = []
    var assistantBriefing: AssistantBriefing?
    private var lastConnectionCheckAt: Date?
    private let connectionCheckInterval: TimeInterval = 30

    // MARK: - Cache keys

    /// UserDefaults keys for the inbox thread cache.
    /// Only inbox is cached — other folders are small/infrequent enough to skip.
    private static let cacheDataKey      = "email_inbox_threads_v1"
    private static let cacheTimestampKey = "email_inbox_threads_v1_ts"
    /// Stale-after duration: refresh from network after 1 hour, but still show cached data
    private static let cacheMaxAge: TimeInterval = 3600

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
                // Cache the first page of inbox results so the next launch shows content
                // immediately (no skeleton) while the background refresh completes.
                if folder == "inbox" && query == nil {
                    saveCachedThreads(enrichedThreads)
                }
            } else {
                threads.append(contentsOf: enrichedThreads)
            }
            nextPageToken = response.nextPageToken
            if query == nil {
                await loadAssistantNudges(folder: folder)
            }
        } catch APIError.unauthorized {
            // Auth failure — stop trying to load until the user re-authenticates
            hasConnection = false
        } catch {
            if let urlError = error as? URLError {
                errorMessage = "No internet connection."
                AppLogger.shared.log("[EmailService] loadThreads network error: \(urlError)")
            } else {
                errorMessage = "Failed to load emails. Please try again."
                AppLogger.shared.log("[EmailService] loadThreads error: \(error)")
            }
        }

        isLoadingThreads = false
    }

    func ensureInitialInboxLoaded() async {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.loadThreads,
            message: "EmailService.ensureInitialInboxLoaded begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.loadThreads,
                trace,
                message: "EmailService.ensureInitialInboxLoaded end"
            )
        }
        await checkConnection()
        guard hasConnection else { return }

        // Populate from disk cache immediately so the inbox shows content without a skeleton.
        // The view only enters loadingState when `isLoadingThreads && threads.isEmpty`,
        // so having cached threads bypasses the skeleton entirely.
        if threads.isEmpty {
            threads = loadCachedThreads() ?? []
        }

        if threads.isEmpty {
            // No cache yet: fetch synchronously so the inbox populates on first launch.
            await loadThreads(refresh: true)
        } else if isCacheStale() {
            // Show stale cache immediately, then refresh in the background.
            Task { [weak self] in
                await self?.loadThreads(refresh: true)
            }
        }
    }

    func resetForSignOut() {
        threads = []
        isLoadingThreads = false
        isLoadingThread = false
        isSending = false
        hasConnection = false
        isCheckingConnection = false
        hasResolvedConnection = false
        errorMessage = nil
        nextPageToken = nil
        assistantNudges = []
        assistantBriefing = nil
        // Clear disk cache so the next user session starts clean
        UserDefaults.standard.removeObject(forKey: Self.cacheDataKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheTimestampKey)
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

    func loadAssistant(threadId: String) async -> AssistantThreadContext? {
        do {
            return try await api.trpcQuery("assistant.getThreadContext", input: AssistantThreadInput(threadId: threadId))
        } catch {
            AppLogger.shared.log("[EmailService] loadAssistant error: \(error)")
            return nil
        }
    }

    /// Throwing variant — surfaces the error so callers (e.g. Summarize button) can show details.
    func loadAssistantThrowing(threadId: String) async throws -> AssistantThreadContext {
        try await api.trpcQuery("assistant.getThreadContext", input: AssistantThreadInput(threadId: threadId))
    }

    func loadAssistantNudges(folder: String = "inbox") async {
        do {
            let response: AssistantOpenLoopsResponse = try await api.trpcQuery(
                "assistant.listOpenLoops",
                input: AssistantOpenLoopsInput(limit: 20)
            )
            assistantNudges = Self.buildNudges(from: response.loops)
        } catch {
            AppLogger.shared.log("[EmailService] loadAssistantNudges error: \(error)")
        }
    }

    func loadAssistantBriefing() async -> AssistantBriefing? {
        do {
            let briefing: AssistantBriefing = try await api.trpcQuery("assistant.getBriefing")
            assistantBriefing = briefing
            return briefing
        } catch {
            AppLogger.shared.log("[EmailService] loadAssistantBriefing error: \(error)")
            return nil
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

    // MARK: - Thread Cache

    /// Returns cached inbox threads if the cache exists, regardless of age.
    /// Callers decide whether to also trigger a network refresh.
    private func loadCachedThreads() -> [EmailThread]? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheDataKey) else { return nil }
        return try? JSONDecoder().decode([EmailThread].self, from: data)
    }

    private func isCacheStale() -> Bool {
        guard let savedDate = UserDefaults.standard.object(forKey: Self.cacheTimestampKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(savedDate) > Self.cacheMaxAge
    }

    /// Persists the inbox thread list to UserDefaults as JSON.
    /// Called after each successful first-page inbox fetch.
    private func saveCachedThreads(_ threads: [EmailThread]) {
        guard let data = try? JSONEncoder().encode(threads) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheDataKey)
        UserDefaults.standard.set(Date(), forKey: Self.cacheTimestampKey)
    }

    // MARK: - Connections

    /// Check if the user has any email connections (Gmail/Outlook).
    /// Pass `force: true` during the connect-gmail flow to bypass the 30s cache —
    /// the backend hook that creates the connection runs asynchronously after OAuth,
    /// so callers polling for a just-created connection must skip the cache.
    func checkConnection(force: Bool = false) async {
        let now = Date()
        if !force,
           let lastConnectionCheckAt,
           now.timeIntervalSince(lastConnectionCheckAt) < connectionCheckInterval,
           hasResolvedConnection {
            return
        }

        isCheckingConnection = true

        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.checkEmailConnection,
            message: "EmailService.checkConnection begin"
        )
        defer {
            isCheckingConnection = false
            hasResolvedConnection = true
            PerformanceTrace.endInterval(
                PerformanceTrace.checkEmailConnection,
                trace,
                message: "EmailService.checkConnection end connected=\(hasConnection)"
            )
        }
        do {
            let response: ConnectionsResponse = try await api.trpcQuery("connections.list")
            hasConnection = !response.connections.isEmpty
            lastConnectionCheckAt = now
        } catch {
            hasConnection = false
        }
    }

    /// Initiates Gmail OAuth connection and waits for the backend connection row.
    /// Google sign-in authenticates the Todus account, while link-social grants
    /// Gmail scopes and persists the email connection used by the mail UI.
    @discardableResult
    func connectGmail(authService: AuthService) async -> Bool {
        errorMessage = nil

        do {
            if authService.isAuthenticated {
                try await authService.linkSocialAccount(provider: "google")
            } else {
                await authService.signInWithGoogle()
                if !authService.isAuthenticated {
                    errorMessage = authService.lastErrorMessage
                        ?? "Sign in was not completed. Please try again."
                    return false
                }
            }
        } catch {
            errorMessage = authService.lastErrorMessage
                ?? "Could not open Google sign-in. Please try again."
            return false
        }

        var attempt = 0
        let maxAttempts = 6
        while attempt < maxAttempts {
            await checkConnection(force: true)
            if hasConnection { break }
            attempt += 1
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if hasConnection {
            await loadThreads(refresh: true)
            return true
        }

        errorMessage =
            "Could not link your Gmail account. Make sure you granted access to Gmail and try again."
        return false
    }

    // MARK: - Actions

    func sendEmail(_ draft: EmailDraft) async -> Bool {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let input = SendEmailInput(
                to: draft.to.map { SendRecipient(email: $0) },
                cc: draft.cc.isEmpty ? nil : draft.cc.map { SendRecipient(email: $0) },
                bcc: draft.bcc.isEmpty ? nil : draft.bcc.map { SendRecipient(email: $0) },
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
        // Capture prior state for rollback if the network call fails
        let priorThreads = threads
        // Optimistic update first so the UI feels instant
        for i in threads.indices where ids.contains(threads[i].id) {
            threads[i] = EmailThread(
                id: threads[i].id, subject: threads[i].subject,
                snippet: threads[i].snippet, from: threads[i].from,
                date: threads[i].date, unread: false,
                messageCount: threads[i].messageCount, labels: threads[i].labels
            )
        }
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsRead", input: IdsInput(ids: ids))
        } catch {
            // Roll back optimistic state and surface the failure
            threads = priorThreads
            errorMessage = "Could not mark as read. Please try again."
            AppLogger.shared.log("[EmailService] markAsRead error: \(error)")
        }
    }

    func markAsUnread(ids: [String]) async {
        let priorThreads = threads
        for i in threads.indices where ids.contains(threads[i].id) {
            threads[i] = EmailThread(
                id: threads[i].id, subject: threads[i].subject,
                snippet: threads[i].snippet, from: threads[i].from,
                date: threads[i].date, unread: true,
                messageCount: threads[i].messageCount, labels: threads[i].labels
            )
        }
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsUnread", input: IdsInput(ids: ids))
        } catch {
            threads = priorThreads
            errorMessage = "Could not mark as unread. Please try again."
            AppLogger.shared.log("[EmailService] markAsUnread error: \(error)")
        }
    }

    func archiveThreads(ids: [String]) async {
        let priorThreads = threads
        // Optimistically remove from list first so swipe action feels immediate
        threads.removeAll { ids.contains($0.id) }
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkArchive", input: IdsInput(ids: ids))
        } catch {
            // Restore the threads we removed if the server rejected the archive
            threads = priorThreads
            errorMessage = "Could not archive. Please try again."
            AppLogger.shared.log("[EmailService] archiveThreads error: \(error)")
        }
    }

    func deleteThreads(ids: [String]) async {
        let priorThreads = threads
        threads.removeAll { ids.contains($0.id) }
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkDelete", input: IdsInput(ids: ids))
        } catch {
            threads = priorThreads
            errorMessage = "Could not delete. Please try again."
            AppLogger.shared.log("[EmailService] deleteThreads error: \(error)")
        }
    }

    func toggleStar(ids: [String]) async {
        // No local star field on EmailThread today, but capture the snapshot anyway
        // so any future label-based optimistic update can be rolled back.
        let priorThreads = threads
        do {
            let _: SuccessResponse = try await api.trpcMutation("mail.toggleStar", input: IdsInput(ids: ids))
        } catch {
            threads = priorThreads
            errorMessage = "Could not update star. Please try again."
            AppLogger.shared.log("[EmailService] toggleStar error: \(error)")
        }
    }
}

private extension EmailService {
    static func buildNudges(from loops: [AssistantOpenLoop]) -> [MailAssistantNudge] {
        let queueCopy: [String: (AssistantNudgeType, String, String)] = [
            "needs_you": (.replyNeeded, "Needs reply", "Threads where you appear to be the next blocker."),
            "waiting_on": (.followUp, "Waiting on others", "Conversations you already moved forward and are now waiting on."),
            "scheduling": (.meetingRequest, "Scheduling", "Threads that look like meeting coordination or follow-up scheduling."),
            "drafts_ready": (.draftReady, "Drafts ready", "Prepared replies or thread drafts ready for review."),
            "likely_dropped": (.followUp, "Likely dropped", "Open loops that are at risk of slipping without explicit tracking."),
        ]

        let grouped = Dictionary(grouping: loops.filter { $0.status == "open" }, by: \.queue)
        return grouped.compactMap { queue, queueLoops in
            guard let metadata = queueCopy[queue] else { return nil }
            let threadIds = Array(Set(queueLoops.compactMap(\.threadId)))
            return MailAssistantNudge(
                type: metadata.0,
                title: metadata.1,
                description: metadata.2,
                count: queueLoops.count,
                threadIds: threadIds,
                id: "assistant-\(queue)"
            )
        }
        .sorted { $0.count > $1.count }
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
    let cc: [SendRecipient]?
    let bcc: [SendRecipient]?
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

private struct AssistantOpenLoopsInput: Encodable {
    let limit: Int
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

private struct AssistantOpenLoopsResponse: Decodable {
    let loops: [AssistantOpenLoop]
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
