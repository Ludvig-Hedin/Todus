import Foundation
import Observation

/// Converts the compose editor's markdown into the HTML `mail.send` expects.
/// The compose body is always plain text (the editor stores raw markdown and the
/// signature block is plain), so escaping then converting is safe — there's no
/// existing HTML to clobber. Without this the backend wraps the raw markdown as
/// `text/html`, so recipients saw literal `**bold**` / `# heading` tokens and the
/// whole message collapsed onto one line (HTML eats newlines). Conservative
/// subset matching `MacMarkdownBodyEditor`: headings, bold, italic, blockquote,
/// bullet lists, links, and line breaks. Worst case the output is still valid,
/// escaped HTML — never worse than the raw-markdown status quo.
enum EmailBodyHTML {
    static func render(_ markdown: String) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        func inlineFormat(_ s: String) -> String {
            var t = escape(s)
            t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?<![\w*])_([^_\n]+)_(?![\w*])"#, with: "<em>$1</em>", options: .regularExpression)
            t = t.replacingOccurrences(of: #"\[([^\]]+)\]\((https?://[^\s)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
            return t
        }

        var html = ""
        var inList = false
        func closeListIfNeeded() {
            if inList { html += "</ul>"; inList = false }
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                if !inList { html += "<ul>"; inList = true }
                html += "<li>\(inlineFormat(String(trimmed.dropFirst(2))))</li>"
                continue
            }
            closeListIfNeeded()
            if trimmed.isEmpty {
                html += "<br>"
            } else if trimmed.hasPrefix("> ") {
                html += "<blockquote>\(inlineFormat(String(trimmed.dropFirst(2))))</blockquote>"
            } else if trimmed.first == "#" {
                var level = 0
                for ch in trimmed { if ch == "#" { level += 1 } else { break } }
                if (1...3).contains(level), trimmed.dropFirst(level).first == " " {
                    let content = String(trimmed.dropFirst(level + 1))
                    html += "<h\(level)>\(inlineFormat(content))</h\(level)>"
                } else {
                    html += "\(inlineFormat(line))<br>"
                }
            } else {
                html += "\(inlineFormat(line))<br>"
            }
        }
        closeListIfNeeded()
        return html
    }
}

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
    /// returned empty. Drives the inline "Updating" badge so the user knows fresh mail
    /// is still on its way, while the prior thread list stays visible underneath.
    var isReconciling = false
    var isLoadingThread = false
    var isSending = false
    // Default false — views call checkConnection() on appear to verify
    var hasConnection = false
    var isCheckingConnection = false
    var hasResolvedConnection = false
    /// True when the most recent `checkConnection` could NOT determine connection
    /// status (timeout / network / 5xx) rather than confirming "no connection".
    /// Lets the view show a retry affordance instead of wrongly prompting an
    /// already-connected user to "Connect Gmail".
    var connectionCheckFailed = false
    var errorMessage: String?
    /// True when a "load next page" request failed. Stops the paginator's
    /// `.onAppear` from immediately re-firing against the same cursor (a tight
    /// retry loop that hammered the backend) and drives an inline "Retry" footer.
    var paginationFailed = false
    var nextPageToken: String?
    var assistantNudges: [MailAssistantNudge] = []
    var assistantBriefing: AssistantBriefing?
    private var currentFolder = "inbox"
    private var cachedThreadsByFolder: [String: [EmailThread]] = [:]
    private var cachedAssistantNudgesByFolder: [String: [MailAssistantNudge]] = [:]
    private var cachedNextPageTokenByFolder: [String: String] = [:]
    private var lastConnectionCheckAt: Date?
    private let connectionCheckInterval: TimeInterval = 30
    /// Most recent **successful** `mail.forceSync`. Backend `forceReSync` is destructive
    /// (drops tables) so we coalesce repeat calls within this cooldown. Routine polls and
    /// didBecomeActive intentionally do not trigger sync — they re-read the backend DB,
    /// which is much cheaper and never produces an empty window. Only pull-to-refresh /
    /// refresh button / first-time inbox population pass `triggerSync: true`.
    private var lastForceSyncAt: Date?
    private static let forceSyncCooldown: TimeInterval = 120
    /// Detached, non-cancellable in-flight forceSync task. Detached so a loadThreads task
    /// that's been cancelled (e.g. user re-pulled while one was running) doesn't also kill
    /// the in-flight Gmail re-sync mutation.
    private var inflightForceSyncTask: Task<Bool, Never>?
    /// Hard deadline so `isReconciling` can never linger past a known ceiling even if the
    /// reconciliation loop's defer is delayed.
    private var reconciliationWatchdog: Task<Void, Never>?
    private static let reconciliationHardDeadline: TimeInterval = 60
    /// Background task that watches for the forceSync workflow to populate threads after a
    /// pull-to-refresh. Kept on the service so we can cancel it on sign-out / re-trigger.
    private var resyncReconciliationTask: Task<Void, Never>?
    /// Most recent successful `mail.rewatchGmail` mutation. Gmail push subscriptions expire
    /// after ~7 days, and a connection whose watch was lost gets stuck — no new mail
    /// arrives until the backend re-subscribes. We trigger a rewatch from the client when
    /// a refresh sees data older than `rewatchStaleThreshold` since the backend
    /// auto-rewatch only runs from `listThreads`, which won't catch the case where a
    /// client UI shows stale cache without ever hitting the backend.
    private var lastRewatchAt: Date?
    private static let rewatchCooldown: TimeInterval = 6 * 60 * 60
    private static let rewatchStaleThreshold: TimeInterval = 24 * 60 * 60

    /// In-memory thread detail cache. Populated during inbox enrichment (every
    /// `mail.get` response is stashed) AND on explicit thread open. Lets
    /// `MacEmailThreadView` paint instantly on second open and on first open
    /// when the row was prefetched during inbox load — matches iOS behavior.
    private var threadDetailCache: [String: (detail: EmailThreadDetail, at: Date)] = [:]
    /// Tracks in-flight detail fetches so a prefetch + user tap on the same id
    /// don't fire two backend round-trips.
    private var inflightDetailFetches: [String: Task<EmailThreadDetail?, Never>] = [:]
    private static let threadDetailTTL: TimeInterval = 60 * 5   // 5 min

    // MARK: - Init

    init(api: TodosAPIClient) {
        self.api = api
    }

    /// Clears all cached email state on sign-out so the next session starts fresh.
    func resetForSignOut() {
        resyncReconciliationTask?.cancel()
        resyncReconciliationTask = nil
        reconciliationWatchdog?.cancel()
        reconciliationWatchdog = nil
        inflightForceSyncTask?.cancel()
        inflightForceSyncTask = nil
        threads = []
        nextPageToken = nil
        errorMessage = nil
        hasConnection = false
        isCheckingConnection = false
        hasResolvedConnection = false
        isReconciling = false
        isLoadingThreads = false
        assistantNudges = []
        assistantBriefing = nil
        currentFolder = "inbox"
        cachedThreadsByFolder = [:]
        cachedAssistantNudgesByFolder = [:]
        cachedNextPageTokenByFolder = [:]
        lastConnectionCheckAt = nil
        lastForceSyncAt = nil
        lastRewatchAt = nil
        threadDetailCache.removeAll()
        for (_, task) in inflightDetailFetches { task.cancel() }
        inflightDetailFetches.removeAll()
    }

    /// Asks the backend to re-arm the Gmail PubSub watch + push subscription for the
    /// active connection. Cooldown-gated to avoid flooding the backend on repeat refreshes.
    private func triggerGmailRewatchIfStale() {
        if let last = lastRewatchAt,
           Date().timeIntervalSince(last) < Self.rewatchCooldown {
            return
        }
        lastRewatchAt = Date()
        Task { [api] in
            do {
                struct RewatchResponse: Decodable { let ok: Bool? }
                let _: RewatchResponse = try await api.trpcMutation("mail.rewatchGmail")
                AppLogger.shared.log("[EmailService] rewatchGmail kicked")
            } catch {
                AppLogger.shared.log("[EmailService] rewatchGmail failed: \(error)")
            }
        }
    }

    /// Hydrates the current mailbox surface from in-memory folder caches before a network refresh.
    /// This makes repeated folder switches feel instant instead of blanking while the request runs.
    func prepareFolder(_ folder: String) {
        currentFolder = folder
        threads = cachedThreadsByFolder[folder] ?? []
        assistantNudges = cachedAssistantNudgesByFolder[folder] ?? []
        nextPageToken = cachedNextPageTokenByFolder[folder]
        errorMessage = nil
    }

    /// Ensures the mailbox state for a folder is ready for display. Cached content is shown
    /// immediately; a refresh runs in the background unless the folder has never been loaded.
    ///
    /// First load passes `triggerSync: true` so a fresh-DB user gets actually-fresh data
    /// on entry instead of landing on an "No emails" empty state forever. Subsequent loads
    /// (when cached threads already exist) re-read the backend DB without triggering a
    /// destructive resync — the previous shape called forceSync on every folder visit,
    /// producing the "30s of stale emails after every navigation" symptom.
    func ensureMailboxReady(for folder: String) async {
        await checkConnection()
        guard hasConnection else { return }

        prepareFolder(folder)

        if threads.isEmpty {
            await loadThreads(folder: folder, refresh: true, triggerSync: true)
        } else {
            Task { [weak self] in
                await self?.loadThreads(folder: folder, refresh: true)
            }
        }
    }

    /// Polls `mail.listThreads` in the background after a forceSync that returned empty in
    /// foreground. When threads land, enriches them and updates `threads` in place — the user
    /// keeps seeing the previous inbox instead of staring at a spinner. Self-cancelling so
    /// repeated pull-to-refresh attempts don't stack.
    ///
    /// Drives `isReconciling` so the inline "Updating" badge is visible while we wait for
    /// the workflow, and the empty-state "No emails" placeholder is suppressed. A watchdog
    /// guarantees the badge clears within a hard ceiling regardless of loop progress.
    private func scheduleResyncReconciliation(
        folder: String,
        query: String?,
        input: ListThreadsInput
    ) {
        resyncReconciliationTask?.cancel()
        reconciliationWatchdog?.cancel()
        isReconciling = true

        reconciliationWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.reconciliationHardDeadline * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.isReconciling {
                self.isReconciling = false
                self.resyncReconciliationTask?.cancel()
                AppLogger.shared.log("[EmailService] reconciliation watchdog tripped")
            }
        }

        resyncReconciliationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isReconciling = false
                self.reconciliationWatchdog?.cancel()
                self.reconciliationWatchdog = nil
            }
            // ~50s worst case (10 attempts × 1s sleep + per-attempt 4s listThreads ceiling).
            // Per-call timeout is critical here — the previous shape had no ceiling, so a
            // single hung trpc query could keep the badge spinning past the 60s watchdog
            // before the loop even attempted the next iteration.
            for _ in 0..<10 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                do {
                    let resp: ListThreadsResponse = try await Self.withTimeout(seconds: 4) { [api = self.api] in
                        try await api.trpcQuery("mail.listThreads", input: input)
                    }
                    guard !resp.threads.isEmpty else { continue }
                    let enriched = try await Self.withTimeout(seconds: 12) { [weak self] in
                        guard let self else { return [] as [EmailThread] }
                        return await self.fetchThreadDetails(ids: resp.threads.map(\.id))
                    }
                    if Task.isCancelled { return }
                    if !enriched.isEmpty {
                        // Staleness guard: the workflow occasionally produces a slice
                        // strictly older than what we're already showing — drop it so
                        // the user doesn't see fresh mail flip back to month-old data.
                        // Only compute `incomingNewest` from threads with a parseable
                        // date — when *every* incoming row failed to parse a date (all
                        // `.distantPast`) we have no signal to compare and would otherwise
                        // wrongly drop a perfectly fresh page.
                        let displayed = self.currentFolder == folder ? self.threads : (self.cachedThreadsByFolder[folder] ?? [])
                        let currentNewest = displayed.map(\.date).max()
                        let incomingDated = enriched.filter { $0.date > .distantPast }
                        let incomingNewest = incomingDated.map(\.date).max()
                        if let cur = currentNewest, let inc = incomingNewest, inc < cur {
                            AppLogger.shared.log(
                                "[EmailService] reconciliation dropped stale snapshot: incomingNewest=\(inc) currentNewest=\(cur)"
                            )
                            return
                        }
                        if query == nil {
                            self.cachedThreadsByFolder[folder] = enriched
                            if let next = resp.nextPageToken {
                                self.cachedNextPageTokenByFolder[folder] = next
                            } else {
                                self.cachedNextPageTokenByFolder.removeValue(forKey: folder)
                            }
                        }
                        if self.currentFolder == folder {
                            self.threads = enriched
                            self.nextPageToken = resp.nextPageToken
                            self.errorMessage = nil
                        }
                    }
                    return
                } catch {
                    continue
                }
            }
            if !Task.isCancelled {
                AppLogger.shared.log("[EmailService] resyncReconciliation budget exhausted folder=\(folder)")
            }
        }
    }

    /// Asks the backend to re-sync threads from Gmail. Best-effort — actual thread population
    /// happens asynchronously inside a Cloudflare Workflow, so callers should follow up with
    /// a `mail.listThreads` retry loop. Returns `true` when the mutation actually completed
    /// successfully this call so callers know whether to enter the post-sync empty-list
    /// reconciliation path.
    ///
    /// Runs as an independent top-level Task so a loadThreads cancellation doesn't kill
    /// the mutation (`Task { ... }` started inside another task does NOT inherit cancellation).
    /// `lastForceSyncAt` is only stamped on success — a cancelled / timed-out / failed sync
    /// must not lock the cooldown against the next attempt.
    @discardableResult
    private func triggerServerSync(bypassCooldown: Bool = false) async -> Bool {
        if !bypassCooldown,
           let last = lastForceSyncAt,
           Date().timeIntervalSince(last) < Self.forceSyncCooldown {
            return false
        }
        if let existing = inflightForceSyncTask {
            return await existing.value
        }
        // Independent top-level Task: `Task { ... }` started from inside another task does
        // NOT inherit cancellation (structured cancellation only flows through TaskGroup
        // children). A loadThreads call that gets cancelled won't also cancel this
        // in-flight forceSync — the previous shape produced -999 cancellation errors that
        // locked the cooldown against a sync that never actually ran.
        // Inherits MainActor isolation from the enclosing context so capturing `api`
        // (a class) doesn't require Sendable conformance under Swift 6 strict concurrency.
        let task: Task<Bool, Never> = Task { [api] in
            do {
                return try await Self.withTimeout(seconds: 8) {
                    let _: EmailEmptyResponse = try await api.trpcMutation("mail.forceSync")
                    return true
                }
            } catch {
                AppLogger.shared.log("[EmailService] triggerServerSync error: \(error)")
                return false
            }
        }
        inflightForceSyncTask = task
        let success = await task.value
        if inflightForceSyncTask == task {
            inflightForceSyncTask = nil
        }
        if success {
            lastForceSyncAt = Date()
        }
        return success
    }

    // MARK: - Inbox

    /// Fetches threads for a given folder (default: inbox).
    /// Two-step process: get thread IDs from listThreads, then enrich each with mail.get.
    ///
    /// When `triggerSync` is true, kicks off a server-side Gmail re-sync first via `mail.forceSync`
    /// so new messages from the provider land in our DB before we list. The backend `listThreads`
    /// is otherwise a DB read and won't return new mail until something else triggers a sync.
    func loadThreads(
        folder: String = "inbox",
        query: String? = nil,
        refresh: Bool = false,
        triggerSync: Bool = false,
        bypassSyncCooldown: Bool = false
    ) async {
        // Early-out for "load next page" calls when there is no cursor — without this
        // an over-eager paginator `.onAppear` keeps firing empty cursored loads, racing
        // against the foreground refresh and burning quota.
        if refresh == false && query == nil && nextPageToken == nil { return }

        // Guard against a folder-switch race: a refresh dispatched for a folder the user
        // already navigated away from must not blow away the cursor that belongs to the
        // currently-displayed folder. We check `currentFolder == folder` BEFORE we
        // overwrite `currentFolder`, then update it so subsequent reads see the new
        // active folder.
        let isLoadingActiveFolder = currentFolder == folder
        // A "load next page" request: not a refresh, not a search, and a cursor exists.
        let isPaginate = (refresh == false && query == nil && nextPageToken != nil)
        currentFolder = folder
        if refresh && isLoadingActiveFolder { nextPageToken = nil }
        isLoadingThreads = true
        errorMessage = nil
        paginationFailed = false

        // Only enter the post-forceSync reconciliation path when we actually ran a forceSync
        // this call — coalesced calls under cooldown should fall straight through to a normal
        // listThreads response so the spinner doesn't kick on for routine polling.
        var didRunForceSync = false
        if triggerSync && query == nil {
            didRunForceSync = await triggerServerSync(bypassCooldown: bypassSyncCooldown)
        }

        do {
            let input = ListThreadsInput(
                folder: folder,
                q: query,
                // 50 first-page threads — covers a couple of days of mail for most users,
                // so the inbox lands full without needing to paginate immediately.
                maxResults: 50,
                cursor: refresh ? nil : nextPageToken
            )
            // Step 1: Get thread IDs from backend (15 s budget — fits the API client's three
            // internal retries with backoff comfortably and keeps the inbox spinner from
            // outlasting that ceiling on a hung backend).
            var response: ListThreadsResponse = try await Self.withTimeout(seconds: 15) { [api] in
                try await api.trpcQuery("mail.listThreads", input: input)
            }

            // After a forceSync the workflow is still populating tables. Try a couple of
            // quick re-reads in foreground for fast-resync cases, then hand off to a
            // background reconciliation task and stop the spinner so the prior inbox stays
            // visible without a multi-second wait.
            if didRunForceSync && response.threads.isEmpty {
                for _ in 0..<2 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    response = try await Self.withTimeout(seconds: 10) { [api] in
                        try await api.trpcQuery("mail.listThreads", input: input)
                    }
                    if !response.threads.isEmpty { break }
                }
                if response.threads.isEmpty {
                    scheduleResyncReconciliation(folder: folder, query: query, input: input)
                    isLoadingThreads = false
                    return
                }
            }

            // Step 2: Fetch full details for each thread in parallel (20 s ceiling).
            let threadIds = response.threads.map(\.id)
            let enrichedThreads = try await Self.withTimeout(seconds: 20) { [weak self] in
                guard let self else { return [] as [EmailThread] }
                return await self.fetchThreadDetails(ids: threadIds)
            }

            let mergedThreads: [EmailThread]
            if refresh {
                // Three cases on a refresh:
                //   1. Server empty + we had cached threads — keep cache, the resync
                //      window emptied the table briefly.
                //   2. Server returned threads strictly older than what we're displaying —
                //      drop them; this is the destructive-workflow regression where
                //      forceSync rebuilds the table from a stale Gmail history offset.
                //   3. Otherwise — use the fresh slice.
                let cachedThreads = cachedThreadsByFolder[folder] ?? []
                let displayed = currentFolder == folder ? threads : cachedThreads
                let currentNewest = displayed.map(\.date).max()
                // Only consider dated rows for staleness — if *every* incoming row failed
                // date parsing (all `.distantPast`) we have no signal to compare and would
                // otherwise wrongly classify a perfectly fresh page as stale.
                let incomingDated = enrichedThreads.filter { $0.date > .distantPast }
                let incomingNewest = incomingDated.map(\.date).max()
                let isStaleRefresh: Bool = {
                    guard let cur = currentNewest, let inc = incomingNewest else { return false }
                    return inc < cur
                }()

                if enrichedThreads.isEmpty, !cachedThreads.isEmpty {
                    mergedThreads = cachedThreads
                } else if isStaleRefresh {
                    AppLogger.shared.log(
                        "[EmailService] dropped stale refresh: incomingNewest=\(incomingNewest!) currentNewest=\(currentNewest!)"
                    )
                    mergedThreads = displayed
                } else {
                    mergedThreads = enrichedThreads
                }

                // Proactive Gmail watch recovery on the client when the refresh sees mail
                // older than a day. Gmail watches expire after ~7 days and a stuck connection
                // never gets new mail until something forces a re-subscribe — this is the
                // "macOS shows no emails" / "iOS stuck on 2-month-old mail" symptom.
                let referenceNewest = incomingNewest ?? currentNewest
                if let newest = referenceNewest {
                    let ageSeconds = Date().timeIntervalSince(newest)
                    if ageSeconds > Self.rewatchStaleThreshold {
                        triggerGmailRewatchIfStale()
                    }
                } else if enrichedThreads.isEmpty && displayed.isEmpty {
                    triggerGmailRewatchIfStale()
                }
            } else {
                // Dedupe by id so cursor-page overlap doesn't render the same thread twice.
                let existing = cachedThreadsByFolder[folder] ?? []
                let existingIds = Set(existing.map(\.id))
                let unique = enrichedThreads.filter { !existingIds.contains($0.id) }
                mergedThreads = existing + unique
            }

            if query == nil {
                cachedThreadsByFolder[folder] = mergedThreads
                if let nextPageToken = response.nextPageToken {
                    cachedNextPageTokenByFolder[folder] = nextPageToken
                } else {
                    cachedNextPageTokenByFolder.removeValue(forKey: folder)
                }
            }

            if currentFolder == folder {
                threads = mergedThreads
                nextPageToken = response.nextPageToken
            }
            // Pre-warm avatar URL cache for the threads we just received so the
            // rows render with the real avatar on first paint instead of
            // flashing initials → avatar.
            prewarmAvatars(for: enrichedThreads)
            // The inbox enrichment already populated `threadDetailCache` for
            // every thread it could load (via `assembleThreads`), so explicit
            // prefetch is only useful for the per-thread concurrent fallback
            // path. Still cheap — dedupe filters out anything already cached.
            prefetchThreadDetails(ids: enrichedThreads.map(\.id))
            if query == nil {
                await loadAssistantNudges(folder: folder)
            }
        } catch APIError.unauthorized {
            // Session expired (the API client already attempted one silent refresh and
            // set `authService.isSessionExpired`). Do NOT clobber `hasConnection` — that
            // misrouted to the "Connect Gmail" onboarding prompt for a user who is in
            // fact connected. Surface a session-expired message; the root view observes
            // `isSessionExpired` to drive re-auth.
            errorMessage = "Your session expired. Please sign in again."
            if isPaginate { paginationFailed = true }
            AppLogger.shared.log("[EmailService] loadThreads unauthorized")
        } catch is CancellationError {
            // Folder switch / view torn down — not a user-facing error.
            AppLogger.shared.log("[EmailService] loadThreads cancelled")
        } catch {
            if case EmailServiceError.timeout = error {
                errorMessage = "Mail is taking longer than usual. Tap retry."
                AppLogger.shared.log("[EmailService] loadThreads timed out")
            } else if let urlError = error as? URLError {
                errorMessage = "No internet connection."
                AppLogger.shared.log("[EmailService] loadThreads network error: \(urlError)")
            } else {
                errorMessage = "Failed to load emails. Please try again."
                AppLogger.shared.log("[EmailService] loadThreads error: \(error)")
            }
            if isPaginate { paginationFailed = true }
        }

        isLoadingThreads = false
    }

    /// Fetches full details for multiple threads via a single batched `mail.get` request.
    /// On batch failure, falls back to per-thread concurrent fetches so a transient failure
    /// doesn't blank the inbox.
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

    private func assembleThreads(ids: [String], results: [Result<GetThreadResponse, Error>]) -> [EmailThread] {
        var threads: [EmailThread] = []
        threads.reserveCapacity(ids.count)
        let now = Date()
        for (i, result) in results.enumerated() {
            switch result {
            case .success(let detail):
                // Stash full detail so opening the thread is zero-latency.
                threadDetailCache[ids[i]] = (detail, now)
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

            // Stash full detail so opening the thread is zero-latency.
            threadDetailCache[id] = (detail, Date())

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

    /// Returns a cached thread detail when present and fresh enough. Lets
    /// `MacEmailThreadView` paint instantly on second open without waiting on
    /// the `mail.get` round-trip.
    func cachedThreadDetail(id: String) -> EmailThreadDetail? {
        guard let entry = threadDetailCache[id] else { return nil }
        if Date().timeIntervalSince(entry.at) > Self.threadDetailTTL {
            threadDetailCache.removeValue(forKey: id)
            return nil
        }
        return entry.detail
    }

    /// Fetches a single thread with all messages. Cache-first: a fresh hit
    /// returns immediately and kicks a silent background refresh so the cached
    /// copy self-heals if it grew stale during a long-open thread session.
    func loadThread(id: String) async -> EmailThreadDetail? {
        if let cached = cachedThreadDetail(id: id) {
            // Self-heal in background so a slightly-stale entry doesn't linger
            // across a long thread view session. Errors swallowed; the cached
            // view stays on screen.
            Task { [weak self] in _ = await self?.fetchThreadDetail(id: id, updateLoadingState: false) }
            return cached
        }

        isLoadingThread = true
        errorMessage = nil
        defer { isLoadingThread = false }

        return await fetchThreadDetail(id: id, updateLoadingState: true)
    }

    /// Warms the in-memory cache for the first N inbox threads so user clicks
    /// land on pre-fetched data. Fire-and-forget; failures are silently
    /// ignored. Called after a successful `loadThreads` for the inbox.
    func prefetchThreadDetails(ids: [String], limit: Int = 8) {
        let toFetch = ids
            .prefix(limit)
            .filter { cachedThreadDetail(id: $0) == nil && inflightDetailFetches[$0] == nil }
        for id in toFetch {
            Task { [weak self] in _ = await self?.fetchThreadDetail(id: id, updateLoadingState: false) }
        }
    }

    /// Shared fetch path used by both `loadThread` and prefetch. Dedupes
    /// concurrent fetches of the same id so a prefetch and a user-driven open
    /// don't fire two API calls. 20s watchdog so a hung backend cannot keep
    /// the thread spinner alive past a sane ceiling.
    @discardableResult
    private func fetchThreadDetail(id: String, updateLoadingState: Bool) async -> EmailThreadDetail? {
        if let existing = inflightDetailFetches[id] {
            return await existing.value
        }

        let task = Task<EmailThreadDetail?, Never> { [weak self] in
            guard let self else { return nil }
            let fetchTask = Task { () -> GetThreadResponse in
                let input = GetThreadInput(id: id)
                return try await self.api.trpcQuery("mail.get", input: input)
            }
            let watchdog = Task { [fetchTask] in
                try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
                fetchTask.cancel()
            }
            defer { watchdog.cancel() }

            do {
                let detail = try await fetchTask.value
                self.threadDetailCache[id] = (detail, Date())
                return detail
            } catch is CancellationError {
                AppLogger.shared.log("[EmailService] loadThread(\(id)) cancelled — likely 20s watchdog timeout")
                if updateLoadingState {
                    self.errorMessage = "Thread is taking too long to load. Try again."
                }
                return nil
            } catch let urlError as URLError where urlError.code == .cancelled {
                AppLogger.shared.log("[EmailService] loadThread(\(id)) URLSession cancelled by watchdog")
                if updateLoadingState {
                    self.errorMessage = "Thread is taking too long to load. Try again."
                }
                return nil
            } catch {
                AppLogger.shared.log("[EmailService] loadThread(\(id)) failed: \(error)")
                if updateLoadingState {
                    self.errorMessage = Self.friendlyThreadLoadMessage(for: error)
                }
                return nil
            }
        }
        inflightDetailFetches[id] = task
        let result = await task.value
        inflightDetailFetches.removeValue(forKey: id)
        return result
    }

    /// Pre-warms the avatar cache for a slice of inbox threads. Fire-and-
    /// forget. Mirrors iOS so rows render with the real avatar on first paint
    /// instead of flashing initials → avatar.
    func prewarmAvatars(for threads: [EmailThread], limit: Int = 50) {
        let slice = Array(threads.prefix(limit))
        Task { @MainActor in
            for thread in slice {
                await MacAvatarCache.shared.resolveIfNeeded(
                    email: thread.from.email,
                    name: thread.from.name,
                    api: api
                )
            }
        }
    }

    /// Same translation pipeline as the iOS app: surface the backend's tRPC error
    /// message when present so a transient shard miss or a re-sync window doesn't
    /// surface as a generic "Failed to load thread."
    private static func friendlyThreadLoadMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return "Sign in expired. Please sign in again."
            case .httpError(let code, _) where code == 404:
                return "This thread is no longer available."
            case .httpError(let code, let body) where (500..<600).contains(code):
                if let detail = parseTRPCErrorMessage(body) {
                    return "Mail service: \(detail). Try again."
                }
                return "Mail service is unavailable. Try again in a moment."
            case .httpError(_, let body):
                if let detail = parseTRPCErrorMessage(body) {
                    return detail
                }
            default:
                break
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Thread is taking too long to load. Pull to retry."
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Reconnect and try again."
            default:
                break
            }
        }
        return "Failed to load thread."
    }

    /// Parses a tRPC HTTP error body of shape
    /// `{ "error": { "json": { "message": "..." } } }` and returns the message string,
    /// or nil if the body isn't a tRPC envelope.
    private static func parseTRPCErrorMessage(_ body: String?) -> String? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = obj["error"] as? [String: Any],
              let json = err["json"] as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }

    func loadAssistant(threadId: String) async -> AssistantThreadContext? {
        do {
            return try await api.trpcQuery("assistant.getThreadContext", input: AssistantThreadInput(threadId: threadId))
        } catch {
            AppLogger.shared.log("[EmailService] loadAssistant error: \(error)")
            return nil
        }
    }

    func loadAssistantNudges(folder: String = "inbox") async {
        do {
            let response: AssistantOpenLoopsResponse = try await api.trpcQuery(
                "assistant.listOpenLoops",
                input: AssistantOpenLoopsInput(limit: 20)
            )
            let nudges = Self.buildNudges(from: response.loops)
            cachedAssistantNudgesByFolder[folder] = nudges
            if currentFolder == folder {
                assistantNudges = nudges
            }
        } catch {
            if error.isURLCancellation { return }
            AppLogger.shared.log("[EmailService] loadAssistantNudges error: \(error)")
        }
    }

    func loadAssistantBriefing() async -> AssistantBriefing? {
        do {
            let briefing: AssistantBriefing = try await api.trpcQuery("assistant.getBriefing")
            assistantBriefing = briefing
            return briefing
        } catch {
            if error.isURLCancellation { return nil }
            AppLogger.shared.log("[EmailService] loadAssistantBriefing error: \(error)")
            return nil
        }
    }

    // MARK: - Briefing trust loop
    //
    // Per-row dismiss / snooze / done actions for the Home briefing. The user's
    // biggest complaint with the briefing is that misclassified rows (Voi receipt
    // as "Needs You") have no removal path — the screen feels permanently noisy.
    // These mutations let the user prune wrong rows immediately and feed the
    // classifier a `wrong` / `completed` signal at the same time.

    func dismissBriefingOpenLoop(id: String, threadId: String?, feedback: String = "wrong") async {
        removeOpenLoopLocally(id: id)
        do {
            let _: AssistantSimpleSuccess = try await api.trpcMutation(
                "assistant.dismissOpenLoop",
                input: AssistantOpenLoopIdInput(openLoopId: id)
            )
        } catch {
            AppLogger.shared.log("[EmailService] dismissBriefingOpenLoop error: \(error)")
        }
        await recordAssistantFeedback(targetType: "open_loop", targetId: id, feedback: feedback)
    }

    func completeBriefingOpenLoop(id: String, threadId: String?) async {
        removeOpenLoopLocally(id: id)
        await recordAssistantFeedback(targetType: "open_loop", targetId: id, feedback: "completed")
    }

    func snoozeBriefingOpenLoop(id: String, threadId: String?, until: Date) async {
        removeOpenLoopLocally(id: id)
        let iso = ISO8601DateFormatter().string(from: until)
        do {
            let _: AssistantSimpleSuccess = try await api.trpcMutation(
                "assistant.snoozeOpenLoop",
                input: AssistantSnoozeOpenLoopInput(openLoopId: id, until: iso)
            )
        } catch {
            AppLogger.shared.log("[EmailService] snoozeBriefingOpenLoop error: \(error)")
        }
    }

    func dismissBriefingPreparedAction(id: String, threadId: String?, feedback: String = "wrong") async {
        removePreparedActionLocally(id: id)
        do {
            let _: AssistantSimpleSuccess = try await api.trpcMutation(
                "assistant.dismissPreparedAction",
                input: AssistantPreparedActionIdInput(actionId: id)
            )
        } catch {
            AppLogger.shared.log("[EmailService] dismissBriefingPreparedAction error: \(error)")
        }
        await recordAssistantFeedback(targetType: "prepared_action", targetId: id, feedback: feedback)
    }

    func recordAssistantFeedback(targetType: String, targetId: String, feedback: String, note: String? = nil) async {
        do {
            let _: AssistantSimpleSuccess = try await api.trpcMutation(
                "assistant.recordFeedback",
                input: AssistantFeedbackInput(
                    targetType: targetType,
                    targetId: targetId,
                    feedback: feedback,
                    note: note
                )
            )
        } catch {
            AppLogger.shared.log("[EmailService] recordAssistantFeedback error: \(error)")
        }
    }

    private func removeOpenLoopLocally(id: String) {
        guard var briefing = assistantBriefing else { return }
        briefing = AssistantBriefing(
            generatedAt: briefing.generatedAt,
            today: AssistantBriefing.Today(
                nextEvent: briefing.today.nextEvent,
                topTask: briefing.today.topTask,
                urgentReply: (briefing.today.urgentReply?.id == id) ? nil : briefing.today.urgentReply
            ),
            topPriorities: briefing.topPriorities.filter { $0.id != id },
            needsYou: briefing.needsYou.filter { $0.id != id },
            waitingOn: briefing.waitingOn.filter { $0.id != id },
            prepared: briefing.prepared,
            upcomingMeetings: briefing.upcomingMeetings,
            changedSinceLastTime: briefing.changedSinceLastTime
        )
        assistantBriefing = briefing
    }

    private func removePreparedActionLocally(id: String) {
        guard var briefing = assistantBriefing else { return }
        briefing = AssistantBriefing(
            generatedAt: briefing.generatedAt,
            today: briefing.today,
            topPriorities: briefing.topPriorities.filter { $0.id != id },
            needsYou: briefing.needsYou,
            waitingOn: briefing.waitingOn,
            prepared: briefing.prepared.filter { $0.id != id },
            upcomingMeetings: briefing.upcomingMeetings,
            changedSinceLastTime: briefing.changedSinceLastTime
        )
        assistantBriefing = briefing
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
        defer {
            isCheckingConnection = false
            hasResolvedConnection = true
        }

        do {
            // Bound the connection check so a hung network can't trap the inbox indefinitely
            // — the inbox view's `.task` awaits this, and without a ceiling the user sits
            // on the connection-checking placeholder until URLSession's default timeout
            // (~60s+) eventually fires.
            let response: ConnectionsResponse = try await Self.withTimeout(seconds: 8) { [api] in
                try await api.trpcQuery("connections.list")
            }
            // Only a *successful* response is authoritative about connection state.
            hasConnection = !response.connections.isEmpty
            connectionCheckFailed = false
            lastConnectionCheckAt = now
        } catch {
            // Couldn't verify (timeout / offline / 5xx). Do NOT downgrade a
            // previously-confirmed connection to the "Connect Gmail" prompt — that
            // parked connected users on the onboarding state on any flaky network.
            // Mark the failure so the view can offer a retry instead. `hasConnection`
            // is left untouched: if it was true it stays true (inbox keeps loading);
            // if it was never resolved it stays false but the failure flag routes the
            // view to a retry state rather than the connect prompt.
            connectionCheckFailed = true
            AppLogger.shared.log("[EmailService] checkConnection failed (status unknown): \(error)")
        }
    }

    /// Errors specific to EmailService's internal orchestration.
    private enum EmailServiceError: Error {
        /// `withTimeout` budget elapsed before `operation` produced a result.
        case timeout
    }

    /// Race `operation` against a wall-clock timer. If `operation` doesn't complete within
    /// `seconds`, it's cancelled and `EmailServiceError.timeout` is thrown. Used to bound
    /// network calls so a hung backend can never trap the UI past a known ceiling.
    private static func withTimeout<T: Sendable>(
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
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw EmailServiceError.timeout
            }
            return first
        }
    }

    /// Initiates Gmail OAuth connection. Mirrors the web app's
    /// `authClient.linkSocial({ provider: 'google' })` flow: always opens a fresh
    /// Google OAuth consent session via the native link-social bridge so the
    /// backend's `account.create.after` / `account.update.after` hooks persist a
    /// connection row for the current user. We then poll `connections.list`
    /// until the row appears (the hook runs asynchronously after the redirect).
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
        let maxAttempts = 12
        while attempt < maxAttempts {
            await checkConnection(force: true)
            if hasConnection { break }
            attempt += 1
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
        }

        if hasConnection {
            await loadThreads(refresh: true)
            return true
        }

        errorMessage = "Still connecting — refresh in a moment to confirm."
        return false
    }

    // MARK: - Actions

    func sendEmail(_ draft: EmailDraft) async -> Bool {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            // Forward the optional from-connection so multi-account sends actually leave
            // from the picked inbox. Empty strings collapse to nil so we don't pin sends
            // to a blank account id when the field was never populated — mirrors the
            // same normalization MacDraftService applies for the compose flow.
            let normalizedConnectionId = draft.fromConnectionId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedFromEmail = draft.fromEmail?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let input = SendEmailInput(
                to: draft.to.map { SendRecipient(email: $0) },
                cc: draft.cc.isEmpty ? nil : draft.cc.map { SendRecipient(email: $0) },
                bcc: draft.bcc.isEmpty ? nil : draft.bcc.map { SendRecipient(email: $0) },
                subject: draft.subject,
                message: EmailBodyHTML.render(draft.body),
                threadId: draft.replyToThreadId,
                isForward: draft.isForward ? true : nil,
                connectionId: (normalizedConnectionId?.isEmpty ?? true) ? nil : normalizedConnectionId,
                fromEmail: (normalizedFromEmail?.isEmpty ?? true) ? nil : normalizedFromEmail
            )
            let response: SendResponse = try await api.trpcMutation("mail.send", input: input)
            // The backend returns HTTP 200 for recoverable failures (undo-send /
            // scheduled-send KV write, invalid scheduleAt) as `{ success: false,
            // error }` — the SAME shape as a success `{ success: true }`, so it
            // decodes into `SendResponse` either way and the only signal is the
            // `success` value (matches iOS's `SendResponse`). Without this guard a
            // failed send reports as sent, the compose sheet closes, and the
            // autosaved draft is cleared — silently losing the user's message.
            guard response.success else {
                errorMessage = response.error ?? "Failed to send email."
                return false
            }
            return true
        } catch {
            errorMessage = "Failed to send email."
            return false
        }
    }

    /// Apply read state to both the visible list and the folder cache so a
    /// folder switch doesn't re-hydrate the unread dot from the stale cache.
    private func applyReadState(ids: [String], unread: Bool) {
        let mutate: (EmailThread) -> EmailThread = { t in
            EmailThread(
                id: t.id, subject: t.subject,
                snippet: t.snippet, from: t.from,
                date: t.date, unread: unread,
                messageCount: t.messageCount, labels: t.labels
            )
        }
        for i in threads.indices where ids.contains(threads[i].id) {
            threads[i] = mutate(threads[i])
        }
        var cache = cachedThreadsByFolder[currentFolder] ?? []
        for i in cache.indices where ids.contains(cache[i].id) {
            cache[i] = mutate(cache[i])
        }
        cachedThreadsByFolder[currentFolder] = cache

        // A thread opened from search (or any surface not in the current
        // `threads` list) only lives in `threadDetailCache`. Patch its
        // `hasUnread` flag too so re-opening it — or returning to a list that
        // reads from the cache — reflects the read state instead of showing a
        // stale unread dot.
        for id in ids {
            guard let entry = threadDetailCache[id] else { continue }
            let d = entry.detail
            let patched = EmailThreadDetail(
                messages: d.messages,
                latest: d.latest,
                hasUnread: !unread,
                totalReplies: d.totalReplies,
                labels: d.labels
            )
            threadDetailCache[id] = (patched, entry.at)
        }
    }

    /// Optimistically toggle the STARRED label per thread so the star UI flips
    /// immediately (the row reads `labels.contains("STARRED")`).
    private func applyStarState(ids: [String]) {
        let mutate: (EmailThread) -> EmailThread = { t in
            var labels = t.labels
            if labels.contains("STARRED") {
                labels.removeAll { $0 == "STARRED" }
            } else {
                labels.append("STARRED")
            }
            return EmailThread(
                id: t.id, subject: t.subject,
                snippet: t.snippet, from: t.from,
                date: t.date, unread: t.unread,
                messageCount: t.messageCount, labels: labels
            )
        }
        for i in threads.indices where ids.contains(threads[i].id) {
            threads[i] = mutate(threads[i])
        }
        var cache = cachedThreadsByFolder[currentFolder] ?? []
        for i in cache.indices where ids.contains(cache[i].id) {
            cache[i] = mutate(cache[i])
        }
        cachedThreadsByFolder[currentFolder] = cache
    }

    /// Reverts the `threadDetailCache` `hasUnread` flag for `ids` on an
    /// optimistic-action rollback. Keeps the detail cache (which drives
    /// search-opened threads) in sync with the list/cache snapshot restore.
    private func revertDetailCacheReadState(ids: [String], unread: Bool) {
        for id in ids {
            guard let entry = threadDetailCache[id] else { continue }
            let d = entry.detail
            let patched = EmailThreadDetail(
                messages: d.messages,
                latest: d.latest,
                hasUnread: unread,
                totalReplies: d.totalReplies,
                labels: d.labels
            )
            threadDetailCache[id] = (patched, entry.at)
        }
    }

    func markAsRead(ids: [String]) async {
        // Optimistic apply, rollback on failure.
        let snapshot = threads.filter { ids.contains($0.id) }
        applyReadState(ids: ids, unread: false)
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsRead", input: IdsInput(ids: ids))
        } catch {
            // Restore prior unread state from snapshot (only flips ones we changed).
            for s in snapshot {
                if let i = threads.firstIndex(where: { $0.id == s.id }) {
                    threads[i] = s
                }
                if var cache = cachedThreadsByFolder[currentFolder],
                   let j = cache.firstIndex(where: { $0.id == s.id }) {
                    cache[j] = s
                    cachedThreadsByFolder[currentFolder] = cache
                }
            }
            // Search-opened threads only live in the detail cache — revert there too.
            revertDetailCacheReadState(ids: ids, unread: true)
            errorMessage = "Could not mark as read. Please try again."
            AppLogger.shared.log("[EmailService] markAsRead error: \(error)")
        }
    }

    func markAsUnread(ids: [String]) async {
        let snapshot = threads.filter { ids.contains($0.id) }
        applyReadState(ids: ids, unread: true)
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsUnread", input: IdsInput(ids: ids))
        } catch {
            for s in snapshot {
                if let i = threads.firstIndex(where: { $0.id == s.id }) {
                    threads[i] = s
                }
                if var cache = cachedThreadsByFolder[currentFolder],
                   let j = cache.firstIndex(where: { $0.id == s.id }) {
                    cache[j] = s
                    cachedThreadsByFolder[currentFolder] = cache
                }
            }
            // Search-opened threads only live in the detail cache — revert there too.
            revertDetailCacheReadState(ids: ids, unread: false)
            errorMessage = "Could not mark as unread. Please try again."
            AppLogger.shared.log("[EmailService] markAsUnread error: \(error)")
        }
    }

    /// Remove ids from both the visible list and the folder cache so the
    /// removed threads don't reappear after a folder switch.
    private func removeThreads(ids: [String]) -> [EmailThread] {
        let snapshot = threads.filter { ids.contains($0.id) }
        threads.removeAll { ids.contains($0.id) }
        var cache = cachedThreadsByFolder[currentFolder] ?? []
        cache.removeAll { ids.contains($0.id) }
        cachedThreadsByFolder[currentFolder] = cache
        return snapshot
    }

    /// Restore previously removed threads on optimistic-action rollback,
    /// preserving original date order.
    private func restoreThreadSnapshot(_ snapshot: [EmailThread]) {
        guard !snapshot.isEmpty else { return }
        threads.append(contentsOf: snapshot)
        threads.sort { $0.date > $1.date }
        var cache = cachedThreadsByFolder[currentFolder] ?? []
        cache.append(contentsOf: snapshot)
        cache.sort { $0.date > $1.date }
        cachedThreadsByFolder[currentFolder] = cache
    }

    func archiveThreads(ids: [String]) async {
        let snapshot = removeThreads(ids: ids)
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkArchive", input: IdsInput(ids: ids))
        } catch {
            restoreThreadSnapshot(snapshot)
            errorMessage = "Could not archive. Please try again."
            AppLogger.shared.log("[EmailService] archiveThreads error: \(error)")
        }
    }

    func deleteThreads(ids: [String]) async {
        let snapshot = removeThreads(ids: ids)
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkDelete", input: IdsInput(ids: ids))
        } catch {
            restoreThreadSnapshot(snapshot)
            errorMessage = "Could not delete. Please try again."
            AppLogger.shared.log("[EmailService] deleteThreads error: \(error)")
        }
    }

    func toggleStar(ids: [String]) async {
        // Optimistic apply, rollback on failure — previously the star only
        // changed after a full refresh, so the action looked like a no-op.
        let snapshot = threads.filter { ids.contains($0.id) }
        applyStarState(ids: ids)
        do {
            let _: SuccessResponse = try await api.trpcMutation("mail.toggleStar", input: IdsInput(ids: ids))
        } catch {
            for s in snapshot {
                if let i = threads.firstIndex(where: { $0.id == s.id }) {
                    threads[i] = s
                }
                if var cache = cachedThreadsByFolder[currentFolder],
                   let j = cache.firstIndex(where: { $0.id == s.id }) {
                    cache[j] = s
                    cachedThreadsByFolder[currentFolder] = cache
                }
            }
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
    let isForward: Bool?
    /// Which connected account to send from. Optional — older backends that don't
    /// understand this field fall back to the user's default connection.
    /// Matches the field name `MacDraftService.SendInput` uses on the wire so both
    /// send paths stay aligned for multi-account users.
    let connectionId: String?
    /// Email of the account to send from. This is the field `mail.send` reads to
    /// select the sending account (`connectionId` is not in its schema), so this
    /// is what actually routes a multi-account send.
    let fromEmail: String?
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

// MARK: - Briefing trust-loop inputs/outputs

private struct AssistantOpenLoopIdInput: Encodable {
    let openLoopId: String
}

private struct AssistantSnoozeOpenLoopInput: Encodable {
    let openLoopId: String
    let until: String
}

private struct AssistantPreparedActionIdInput: Encodable {
    let actionId: String
}

private struct AssistantFeedbackInput: Encodable {
    let targetType: String
    let targetId: String
    let feedback: String
    let note: String?
}

private struct AssistantSimpleSuccess: Decodable {
    let success: Bool
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

    private enum CodingKeys: String, CodingKey {
        case messages, latest, hasUnread, totalReplies, labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode messages element-by-element so a single malformed message (e.g.
        // missing `id`) is dropped instead of aborting the entire thread decode and
        // surfacing as a hard "couldn't load thread" error screen.
        self.messages = (try? container.decode([FailableDecodable<EmailMessage>].self, forKey: .messages))?
            .compactMap(\.value) ?? []
        self.latest = (try? container.decodeIfPresent(EmailMessage.self, forKey: .latest)) ?? nil
        self.hasUnread = try container.decodeIfPresent(Bool.self, forKey: .hasUnread)
        self.totalReplies = try container.decodeIfPresent(Int.self, forKey: .totalReplies)
        self.labels = try container.decodeIfPresent([ThreadLabel].self, forKey: .labels)
    }

    /// Synthesised initializer for tests / cache assembly that build a response directly.
    init(messages: [EmailMessage], latest: EmailMessage? = nil, hasUnread: Bool? = nil,
         totalReplies: Int? = nil, labels: [ThreadLabel]? = nil) {
        self.messages = messages
        self.latest = latest
        self.hasUnread = hasUnread
        self.totalReplies = totalReplies
        self.labels = labels
    }
}

/// Wraps a `Decodable` element so a decode failure yields `nil` instead of
/// throwing — lets an array decode survive individual malformed elements.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
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
    /// Present on recoverable failures (`success == false`). Surfaced to the user.
    let error: String?
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
