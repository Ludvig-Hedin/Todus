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
    /// True while a background reconciliation poll is running after a forceSync that
    /// returned empty. The inbox keeps showing the prior threads while this is true,
    /// and the "Updating" badge stays visible so the user knows fresh mail is still on its way.
    var isReconciling = false
    var isLoadingThread = false
    var isSending = false
    // Initialized from the persisted last-known value below — we treat the persisted bit
    // as authoritative until a fresh `checkConnection` resolves, so the inbox doesn't
    // briefly show "Connect Gmail" on cold start for an already-connected user.
    var hasConnection = false
    var isCheckingConnection = false
    /// True once `checkConnection` has produced a result this launch. Treated as already-resolved
    /// when we have a persisted positive connection state from the previous launch — the prior
    /// answer is overwhelmingly stable and gives us a clean first paint.
    var hasResolvedConnection = false
    var errorMessage: String?
    var nextPageToken: String?
    var assistantNudges: [MailAssistantNudge] = []
    var assistantBriefing: AssistantBriefing?
    private var lastConnectionCheckAt: Date?
    private let connectionCheckInterval: TimeInterval = 30
    private static let hasConnectionDefaultsKey = "email_has_connection_v1"
    /// Background task that watches for the forceSync workflow to populate threads after a
    /// pull-to-refresh. Kept on the service so we can cancel it on sign-out / re-trigger.
    private var resyncReconciliationTask: Task<Void, Never>?
    /// Tracks the most recent in-flight `loadThreads` call so a new pull-to-refresh can
    /// cancel a stuck previous call (e.g. one waiting on a hung mail.forceSync). Without
    /// this, repeat pulls during a hang pile up concurrent network tasks.
    private var inflightLoadThreadsTask: Task<Void, Never>?
    /// Monotonically increases on every `loadThreads` invocation. Each call captures the
    /// generation and only flips shared state (`isLoadingThreads`, `errorMessage`) on its
    /// way out if it's still the latest. Prevents an older cancelled call's `defer` from
    /// clobbering state set by a newer call already in flight.
    private var loadGeneration: UInt64 = 0

    // MARK: - Cache keys

    /// UserDefaults keys for the inbox thread cache.
    /// Only inbox is cached — other folders are small/infrequent enough to skip.
    private static let cacheDataKey      = "email_inbox_threads_v1"
    private static let cacheTimestampKey = "email_inbox_threads_v1_ts"
    /// Stale-after duration: refresh from network after 5 minutes, but still show cached data instantly
    private static let cacheMaxAge: TimeInterval = 300

    // MARK: - Init

    init(api: TodosAPIClient) {
        self.api = api
        // Trust the prior session's verdict for the very first paint. The background
        // `checkConnection` call still runs and corrects the state if it changed, but
        // we avoid flashing "Connect Gmail" for users who are already linked.
        if UserDefaults.standard.bool(forKey: Self.hasConnectionDefaultsKey) {
            self.hasConnection = true
            self.hasResolvedConnection = true
        }
        // Restore assistant briefing + nudges from disk so Home renders real content
        // on cold launch instead of flashing skeletons or "you're caught up" placeholders.
        if let cachedBriefing = AssistantPersistedCache.loadBriefing() {
            self.assistantBriefing = cachedBriefing
        }
        if let cachedNudges = AssistantPersistedCache.loadNudges() {
            self.assistantNudges = cachedNudges
        }
    }

    // MARK: - Inbox

    /// Fetches threads for a given folder (default: inbox).
    /// Two-step process: get thread IDs from listThreads, then enrich each with mail.get.
    ///
    /// When `triggerSync` is true, kicks off a server-side Gmail re-sync first via `mail.forceSync`
    /// so new messages from the provider land in our DB before we list. Use this for explicit
    /// user-driven refreshes (pull-to-refresh, scene foreground) — the backend `listThreads` is
    /// otherwise a DB read and won't return new mail until something else triggers a sync.
    ///
    /// Repeat invocations cancel the previous in-flight call so a stuck refresh (e.g. backend
    /// workflow hanging) can't trap newer pulls behind it. The actual work runs in a tracked
    /// child Task; the public function awaits it so `.refreshable { … }` callers still see the
    /// pull-to-refresh spinner stay until the load completes.
    func loadThreads(
        folder: String = "inbox",
        query: String? = nil,
        refresh: Bool = false,
        triggerSync: Bool = false
    ) async {
        // Skip duplicate loads only for non-refresh, non-search calls (pagination /
        // initial-load races). Explicit user refreshes always start a new run that
        // cancels the previous one below.
        if isLoadingThreads && !refresh && query == nil {
            return
        }

        // Cancel any prior in-flight call so its hung network awaits unblock and its
        // results don't race ours. The cancelled task's `defer` is generation-gated, so
        // it won't clobber the state we're about to set.
        inflightLoadThreadsTask?.cancel()

        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoadThreads(
                folder: folder,
                query: query,
                refresh: refresh,
                triggerSync: triggerSync
            )
        }
        inflightLoadThreadsTask = task
        await task.value
        // Only clear if we're still the most recent — a newer call may have replaced us.
        if inflightLoadThreadsTask == task {
            inflightLoadThreadsTask = nil
        }
    }

    /// Actual load implementation. Always-balanced state via `defer`, generation-gated so a
    /// stale cancelled run can't unset state belonging to a newer run, and wall-clock-bounded
    /// network calls so a hung backend workflow can't trap the spinner indefinitely.
    private func performLoadThreads(
        folder: String,
        query: String?,
        refresh: Bool,
        triggerSync: Bool
    ) async {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.loadThreads,
            message: "EmailService.loadThreads begin folder=\(folder) refresh=\(refresh) triggerSync=\(triggerSync)"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.loadThreads,
                trace,
                message: "EmailService.loadThreads end folder=\(folder) count=\(threads.count)"
            )
        }

        loadGeneration &+= 1
        let myGen = loadGeneration

        if refresh { nextPageToken = nil }
        isLoadingThreads = true
        errorMessage = nil

        // Always-balanced state: no matter how we exit (return, throw, cancellation), this
        // fires. Gen-gated so an older cancelled run doesn't clobber a newer run's spinner.
        defer {
            if loadGeneration == myGen {
                isLoadingThreads = false
            }
        }

        do {
            // Server-side re-sync first when the caller asked for fresh provider data.
            // forceSync drops local thread tables and kicks off an async workflow that
            // re-fetches from Gmail — see apps/server/src/lib/server-utils.ts. The workflow
            // runs async, so we poll listThreads below with a small retry budget so the
            // just-emptied tables have time to refill before we declare the inbox empty.
            //
            // Capped at 8 seconds wall-clock — the call is best-effort (we follow up with
            // listThreads either way) and a hung mutation must never trap the UI.
            if triggerSync && query == nil {
                try? await withTimeout(seconds: 8) { [api] in
                    do {
                        let _: EmailEmptyResponse = try await api.trpcMutation("mail.forceSync")
                    } catch {
                        AppLogger.shared.log("[EmailService] triggerServerSync error: \(error)")
                    }
                }
            }

            try Task.checkCancellation()

            let input = ListThreadsInput(
                folder: folder,
                q: query,
                maxResults: 30,
                cursor: refresh ? nil : nextPageToken
            )
            // Step 1: Get thread IDs from backend (15 s budget — three internal retries
            // with backoff at the API client layer fit comfortably under that).
            var response: ListThreadsResponse = try await withTimeout(seconds: 15) { [api] in
                try await api.trpcQuery("mail.listThreads", input: input)
            }

            // After a forceSync the workflow is still populating tables. Try a couple of
            // quick re-reads in foreground for fast-resync cases, then hand off to a
            // background reconciliation task and stop the spinner so the prior inbox stays
            // visible without a multi-second wait.
            if triggerSync && response.threads.isEmpty {
                for _ in 0..<2 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    try Task.checkCancellation()
                    response = try await withTimeout(seconds: 10) { [api] in
                        try await api.trpcQuery("mail.listThreads", input: input)
                    }
                    if !response.threads.isEmpty { break }
                }
                if response.threads.isEmpty {
                    scheduleResyncReconciliation(folder: folder, query: query, input: input)
                    return
                }
            }

            try Task.checkCancellation()

            // Step 2: Fetch full details for each thread in parallel (20 s ceiling — batched
            // mail.get for 30 threads is normally well under 5 s but we leave headroom for
            // the per-thread fallback path).
            let threadIds = response.threads.map(\.id)
            let enrichedThreads = try await withTimeout(seconds: 20) { [weak self] in
                guard let self else { return [] as [EmailThread] }
                return await self.fetchThreadDetails(ids: threadIds)
            }

            if refresh {
                if !enrichedThreads.isEmpty {
                    threads = enrichedThreads
                } else if threads.isEmpty {
                    // No prior list to preserve and the fresh fetch came back empty —
                    // surface the failure so the user gets a retry CTA instead of a
                    // silently empty inbox.
                    errorMessage = "Couldn't load emails. Pull to refresh to try again."
                } else {
                    // We have a prior list; the user pulled and got nothing new, but
                    // their existing inbox is still valid. Tell them so they don't think
                    // the refresh did nothing.
                    errorMessage = "Couldn't fetch new mail. Pull to refresh to try again."
                }
                // Cache the first page of inbox results so the next launch shows content
                // immediately (no skeleton) while the background refresh completes.
                if folder == "inbox" && query == nil && !enrichedThreads.isEmpty {
                    saveCachedThreads(enrichedThreads)
                }
            } else {
                threads.append(contentsOf: enrichedThreads)
            }
            // Pre-warm avatar cache for the threads we just received so rows render with
            // the real avatar on first paint instead of flashing initials → avatar.
            prewarmAvatars(for: enrichedThreads)
            nextPageToken = response.nextPageToken
            if query == nil {
                await loadAssistantNudges(folder: folder)
            }
        } catch is CancellationError {
            // Superseded by a newer load — keep quiet, the newer run owns the UI now.
        } catch APIError.unauthorized {
            // Auth failure — stop trying to load until the user re-authenticates
            hasConnection = false
        } catch EmailServiceError.timeout {
            // Treat timeout the same as a transient network error: surface a recovery
            // CTA without blowing away whatever cached threads we already had on screen.
            errorMessage = "Refreshing took too long. Pull to refresh to try again."
            AppLogger.shared.log("[EmailService] loadThreads timed out")
        } catch {
            if let urlError = error as? URLError {
                errorMessage = "No internet connection."
                AppLogger.shared.log("[EmailService] loadThreads network error: \(urlError)")
            } else {
                errorMessage = "Failed to load emails. Please try again."
                AppLogger.shared.log("[EmailService] loadThreads error: \(error)")
            }
        }
    }

    /// Polls `mail.listThreads` in the background after a forceSync that returned empty in
    /// foreground. When threads land, enriches them and updates `threads` in place — the user
    /// keeps seeing the previous inbox instead of staring at a spinner. Self-cancelling so
    /// repeated pull-to-refresh attempts don't stack.
    ///
    /// Drives `isReconciling` so the inline "Updating" badge stays visible while we wait for
    /// the workflow, and surfaces an `errorMessage` if the budget exhausts without success —
    /// silent failure here was the cause of "pulled to refresh, only old emails appeared".
    private func scheduleResyncReconciliation(
        folder: String,
        query: String?,
        input: ListThreadsInput
    ) {
        resyncReconciliationTask?.cancel()
        isReconciling = true
        resyncReconciliationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isReconciling = false }

            // Up to ~12s of additional waiting for the Gmail re-sync workflow to populate.
            for _ in 0..<12 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                do {
                    let resp: ListThreadsResponse = try await self.withTimeout(seconds: 8) { [api = self.api] in
                        try await api.trpcQuery("mail.listThreads", input: input)
                    }
                    guard !resp.threads.isEmpty else { continue }
                    let enriched = try await self.withTimeout(seconds: 15) { [weak self] in
                        guard let self else { return [] as [EmailThread] }
                        return await self.fetchThreadDetails(ids: resp.threads.map(\.id))
                    }
                    if Task.isCancelled { return }
                    if !enriched.isEmpty {
                        self.threads = enriched
                        self.nextPageToken = resp.nextPageToken
                        if folder == "inbox" && query == nil {
                            self.saveCachedThreads(enriched)
                        }
                        self.prewarmAvatars(for: enriched)
                    }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    // Network blip or per-attempt timeout — keep trying within budget.
                    continue
                }
            }
            // Budget exhausted without ever seeing fresh threads. Don't leave the user
            // wondering why their pull didn't surface anything new.
            if !Task.isCancelled {
                self.errorMessage = "Couldn't fetch new mail. Pull to refresh to try again."
                AppLogger.shared.log("[EmailService] resyncReconciliation budget exhausted folder=\(folder)")
            }
        }
    }

    // MARK: - Internal Helpers

    /// Errors specific to EmailService's internal orchestration.
    private enum EmailServiceError: Error {
        /// `withTimeout` budget elapsed before `operation` produced a result.
        case timeout
    }

    /// Race `operation` against a wall-clock timer. If `operation` doesn't complete within
    /// `seconds`, it's cancelled and `EmailServiceError.timeout` is thrown. Used to bound
    /// network calls so a backend that holds a connection open (e.g. a slow Gmail re-sync
    /// workflow) can never trap the UI past a known ceiling.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw EmailServiceError.timeout
            }
            // Whichever task wins, cancel the other before returning.
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw EmailServiceError.timeout
            }
            return first
        }
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
            // Pre-warm avatar cache for cached threads too — same first-paint reasoning.
            if !threads.isEmpty { prewarmAvatars(for: threads) }
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
        resyncReconciliationTask?.cancel()
        resyncReconciliationTask = nil
        inflightLoadThreadsTask?.cancel()
        inflightLoadThreadsTask = nil
        threads = []
        isLoadingThreads = false
        isReconciling = false
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
        UserDefaults.standard.removeObject(forKey: Self.hasConnectionDefaultsKey)
        AssistantPersistedCache.clearAll()
    }

    /// Fetches full details for multiple threads via a single batched `mail.get` request.
    /// On batch failure (network, server error), falls back to the per-thread concurrent path
    /// so a transient failure doesn't blank the inbox.
    private func fetchThreadDetails(ids: [String]) async -> [EmailThread] {
        guard !ids.isEmpty else { return [] }

        do {
            let inputs = ids.map { GetThreadInput(id: $0) }
            let results: [Result<GetThreadResponse, Error>] =
                try await api.trpcBatchQuery("mail.get", inputs: inputs)
            return assembleThreads(ids: ids, results: results)
        } catch {
            AppLogger.shared.log("[EmailService] Batch mail.get failed; falling back to per-thread: \(error)")
            return await fetchThreadDetailsConcurrent(ids: ids)
        }
    }

    /// Builds `EmailThread` summaries from batch results, preserving order via the input index.
    /// Per-thread failures are logged and dropped; the rest of the inbox still renders.
    private func assembleThreads(ids: [String], results: [Result<GetThreadResponse, Error>]) -> [EmailThread] {
        var threads: [EmailThread] = []
        threads.reserveCapacity(ids.count)
        for (i, result) in results.enumerated() {
            switch result {
            case .success(let detail):
                guard let latest = detail.latest ?? detail.messages.last else { continue }
                threads.append(EmailThread(
                    id: ids[i],
                    subject: latest.subject,
                    snippet: latest.plainText ?? "",
                    from: latest.from,
                    date: latest.date,
                    unread: detail.hasUnread ?? false,
                    messageCount: detail.totalReplies ?? detail.messages.count,
                    labels: detail.labels?.map(\.name) ?? []
                ))
            case .failure(let err):
                AppLogger.shared.log("[EmailService] thread \(ids[i]) failed in batch: \(err)")
            }
        }
        return threads.sorted { $0.date > $1.date }
    }

    /// Fallback path used when the batch endpoint itself fails. Fans out N concurrent calls
    /// in groups of 8 to avoid URLSession connection saturation.
    private func fetchThreadDetailsConcurrent(ids: [String]) async -> [EmailThread] {
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

        return allResults.sorted { $0.0 < $1.0 }.compactMap(\.1).sorted { $0.date > $1.date }
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
            AppLogger.shared.log("[EmailService] loadThread(\(id)) failed: \(error)")
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
            let nudges = Self.buildNudges(from: response.loops)
            assistantNudges = nudges
            AssistantPersistedCache.saveNudges(nudges)
        } catch {
            AppLogger.shared.log("[EmailService] loadAssistantNudges error: \(error)")
        }
    }

    func loadAssistantBriefing() async -> AssistantBriefing? {
        do {
            let briefing: AssistantBriefing = try await api.trpcQuery("assistant.getBriefing")
            assistantBriefing = briefing
            AssistantPersistedCache.saveBriefing(briefing)
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

    // MARK: - Avatar Prewarm

    /// Resolves avatar URLs for the given threads in the background so the inbox renders
    /// with real avatars on first paint. AvatarCache deduplicates concurrent fetches and
    /// honors TTL, so this is cheap to call repeatedly.
    private func prewarmAvatars(for threads: [EmailThread]) {
        guard !threads.isEmpty else { return }
        // De-dupe by sender — multiple threads from the same person should fire one fetch.
        var seen = Set<String>()
        let unique: [(email: String, name: String)] = threads.compactMap { t in
            let key = t.from.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return (key, t.from.name)
        }
        let api = self.api
        Task { @MainActor in
            // Fan out so we're not bottlenecked on a serial chain — AvatarCache
            // dedupes concurrent calls per-sender internally.
            await withTaskGroup(of: Void.self) { group in
                for sender in unique {
                    group.addTask {
                        await AvatarCache.shared.resolveIfNeeded(
                            email: sender.email,
                            name: sender.name,
                            api: api
                        )
                    }
                }
            }
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
            UserDefaults.standard.set(hasConnection, forKey: Self.hasConnectionDefaultsKey)
        } catch {
            // Network failure during a re-check shouldn't flip a previously-connected user
            // back to the connect screen — that's the most common failure mode and produces
            // a jarring flash. Only mark disconnected if we never resolved before.
            if !hasResolvedConnection {
                hasConnection = false
            }
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
            // Surface specific user-facing messages so the connect screen can
            // distinguish "user backed out" from "no network" from "something else".
            errorMessage = friendlyGmailConnectMessage(for: error, authService: authService)
            return false
        }

        // Poll until a connection exists. The backend hook that creates the connection row
        // runs fire-and-forget after Better Auth processes the OAuth callback, so the row
        // may not appear immediately.
        //
        // Multi-account path: if the user already had a connection, hasConnection is already
        // true and we don't need to poll — but we do sleep briefly so the new row has time
        // to land before the caller calls loadConnections().
        if hasConnection {
            // User already had at least one connection — give the hook ~1.5 s to write the
            // new row before performConnectGmail calls connectionsService.loadConnections().
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } else {
            var attempt = 0
            let maxAttempts = 12  // 12 × 500ms = 6 seconds max
            while attempt < maxAttempts {
                await checkConnection(force: true)
                if hasConnection { break }
                attempt += 1
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
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

    /// Maps a Gmail-connect error to a friendly, specific message:
    /// - User cancelled the OAuth flow → tell them they didn't grant access.
    /// - Network/URLError → tell them the connection failed.
    /// - Anything else → fall back to the generic "could not link" copy.
    private func friendlyGmailConnectMessage(for error: any Error, authService: AuthService) -> String {
        // User dismissed the sheet or cancelled inside Google's flow.
        if let authError = error as? AuthService.AuthError, case .cancelled = authError {
            return "You didn't grant access. Try again to continue."
        }
        let nsError = error as NSError
        if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
           nsError.code == 1 /* canceledLogin */ {
            return "You didn't grant access. Try again to continue."
        }
        if let urlError = error as? URLError {
            AppLogger.shared.log("[EmailService] connectGmail URL error: \(urlError.code)")
            return "Couldn't reach Gmail. Check your connection."
        }
        return authService.lastErrorMessage
            ?? "Could not open Google sign-in. Please try again."
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

    /// Deletes (moves to Trash) one or more threads. Returns whether the API call succeeded
    /// — callers like EmailThreadView use the result to decide whether to dismiss.
    @discardableResult
    func deleteThreads(ids: [String]) async -> Bool {
        let priorThreads = threads
        threads.removeAll { ids.contains($0.id) }
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkDelete", input: IdsInput(ids: ids))
            return true
        } catch {
            threads = priorThreads
            errorMessage = "Could not delete. Please try again."
            AppLogger.shared.log("[EmailService] deleteThreads error: \(error)")
            return false
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

    // MARK: - Labels

    /// Fetches every label the user has — used by the Edit Labels sheet.
    func listLabels() async throws -> [EmailLabel] {
        try await api.trpcQuery("labels.list") as [EmailLabel]
    }

    /// Adds and/or removes Gmail labels on one or more threads. Used by the Edit
    /// Labels sheet and the "Report spam" action.
    @discardableResult
    func modifyLabels(threadIds: [String], add: [String] = [], remove: [String] = []) async -> Bool {
        guard !add.isEmpty || !remove.isEmpty else { return true }
        let ids = threadIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return true }
        do {
            let _: SuccessResponse = try await api.trpcMutation(
                "mail.modifyLabels",
                input: ModifyLabelsInput(threadId: ids, addLabels: add, removeLabels: remove)
            )
            return true
        } catch {
            errorMessage = "Could not update labels."
            AppLogger.shared.log("[EmailService] modifyLabels error: \(error)")
            return false
        }
    }

    @discardableResult
    func modifyLabels(threadId: String, add: [String] = [], remove: [String] = []) async -> Bool {
        await modifyLabels(threadIds: [threadId], add: add, remove: remove)
    }

    /// Adds the SPAM label and removes INBOX so Gmail moves threads out of
    /// the user's view, then prunes local inbox state only after a single batch
    /// API call succeeds.
    func markAsSpam(ids: [String]) async {
        guard !ids.isEmpty else { return }
        let success = await modifyLabels(threadIds: ids, add: ["SPAM"], remove: ["INBOX"])
        if success {
            threads.removeAll { ids.contains($0.id) }
        } else {
            errorMessage = "Could not report spam. Please try again."
        }
    }
}

struct EmailLabel: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
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

private struct ModifyLabelsInput: Encodable {
    let threadId: [String]
    let addLabels: [String]
    let removeLabels: [String]
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

