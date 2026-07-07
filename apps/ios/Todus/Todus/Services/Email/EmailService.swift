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
    /// The folder whose threads are currently in `threads`. Used to decide whether an
    /// incoming refresh result should be guarded against "stale (older than current)"
    /// rejection. When switching folders (inbox → archive), the archive's newest thread is
    /// virtually always older than the inbox's newest, so the stale-guard would otherwise
    /// drop the entire folder switch.
    private(set) var loadedFolder: String?
    /// The query whose results are currently in `threads` (nil = no search). Same role as
    /// `loadedFolder` for the search → no-search transition.
    private(set) var loadedQuery: String?
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
    /// Most recent **successful** `mail.forceSync` mutation. The backend `forceReSync` is
    /// destructive — it drops local DB tables before re-syncing from Gmail — so we coalesce
    /// repeat calls within this cooldown to avoid back-to-back empty-inbox windows. Only the
    /// caller paths that explicitly want a Gmail re-sync (pull-to-refresh, header refresh
    /// button, first-time inbox population) pass `triggerSync: true`; routine polls and
    /// scenePhase changes just re-read the backend DB, which is far cheaper and never wipes
    /// the visible inbox.
    private var lastForceSyncAt: Date?
    /// 2-minute cooldown — long enough to coalesce a flurry of user pulls or refresh-button
    /// taps (the destructive sync takes ~30s server-side so even back-to-back pulls inside
    /// 2m would still leave the user staring at an empty window), short enough that a
    /// genuinely spaced-out refresh always triggers a fresh pull.
    private static let forceSyncCooldown: TimeInterval = 120
    /// In-flight `mail.forceSync` mutation. Held as a detached, non-cancellable task so a
    /// loadThreads task being cancelled by a newer pull-to-refresh doesn't also kill the
    /// just-started Gmail re-sync — the previous behaviour was producing -999 cancellations
    /// that left `lastForceSyncAt` set without the workflow ever running, locking the
    /// cooldown for a sync that never happened.
    private var inflightForceSyncTask: Task<Bool, Never>?
    /// Background task that watches for the forceSync workflow to populate threads after a
    /// pull-to-refresh. Kept on the service so we can cancel it on sign-out / re-trigger.
    private var resyncReconciliationTask: Task<Void, Never>?
    /// Hard upper bound on how long `isReconciling` can stay true. The reconciliation loop
    /// already self-terminates, but a watchdog guarantees the inline "Updating" badge can
    /// never linger past this ceiling even if cancellation/defer is delayed by an
    /// actor-reentrancy edge case.
    private var reconciliationWatchdog: Task<Void, Never>?
    private static let reconciliationHardDeadline: TimeInterval = 120
    /// Tracks the most recent in-flight `loadThreads` call so a new pull-to-refresh can
    /// cancel a stuck previous call (e.g. one waiting on a hung mail.forceSync). Without
    /// this, repeat pulls during a hang pile up concurrent network tasks.
    private var inflightLoadThreadsTask: Task<Void, Never>?
    /// Tracks the most recent avatar-prewarm fan-out so a new refresh can cancel a stuck
    /// prior fan-out instead of letting them pile up. Each prewarm calls AvatarCache.
    /// resolveIfNeeded for every unique sender — back-to-back refreshes without this
    /// produced unbounded URLSession fan-out, which (combined with the per-call retry
    /// budget) was a candidate for the post-refresh crash.
    private var avatarPrewarmTask: Task<Void, Never>?
    /// Maximum concurrent avatar resolutions in a single prewarm pass. AvatarCache already
    /// dedupes within a pass, but unbounded fanout across 50 senders saturated URLSession
    /// under poor connectivity. 4 keeps the cache warm without monopolizing the connection
    /// pool the inbox itself needs.
    private static let avatarPrewarmConcurrency = 4
    /// Monotonically increases on every `loadThreads` invocation. Each call captures the
    /// generation and only flips shared state (`isLoadingThreads`, `errorMessage`) on its
    /// way out if it's still the latest. Prevents an older cancelled call's `defer` from
    /// clobbering state set by a newer call already in flight.
    private var loadGeneration: UInt64 = 0
    /// Most recent successful `mail.rewatchGmail` call. Gmail push subscriptions expire
    /// after ~7 days, and a connection whose watch was lost gets stuck — no new mail
    /// arrives until something forces a re-subscribe. We trigger a rewatch on the client
    /// side when an inbox refresh sees mail older than a day, since that's a strong
    /// signal continuous sync is broken. Cooldown prevents flooding the backend on
    /// every load.
    private var lastRewatchAt: Date?
    private static let rewatchCooldown: TimeInterval = 6 * 60 * 60
    /// Inbox age past which we assume the Gmail watch has expired and proactively trigger
    /// a re-subscribe. Conservative — short network outages don't trip this, but the
    /// "stuck at 2-month-old emails" symptom does.
    private static let rewatchStaleThreshold: TimeInterval = 24 * 60 * 60

    // MARK: - Cache keys

    /// UserDefaults keys for the inbox thread cache.
    /// Only inbox is cached — other folders are small/infrequent enough to skip.
    ///
    /// Bumped to v2 in 2026-05-21: threads stuck at top due to stale receivedOn dates.
    /// Bumped to v3 in 2026-05-27: one-shot bust to clear any lingering stale threads
    /// (e.g. "Make's access to your Google Account" pinned at top for months). v2 is
    /// explicitly cleared in `init` so all users get a fresh load from the backend.
    private static let cacheDataKey      = "email_inbox_threads_v3"
    private static let cacheTimestampKey = "email_inbox_threads_v3_ts"
    private static let legacyCacheDataKey      = "email_inbox_threads_v2"
    private static let legacyCacheTimestampKey = "email_inbox_threads_v2_ts"
    /// Stale-after duration: refresh from network after 5 minutes, but still show cached data instantly
    private static let cacheMaxAge: TimeInterval = 300

    // MARK: - Init

    init(api: TodosAPIClient) {
        self.api = api
        // One-shot migration: drop legacy inbox caches so returning users get a clean
        // first paint from the current backend response. Safe to run on every launch —
        // UserDefaults.removeObject is a no-op when the key is absent.
        // v1 → v2: stale receivedOn dates caused threads stuck at top (2026-05-21)
        // v2 → v3: one-shot bust for any other lingering stale threads (2026-05-27)
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheDataKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheTimestampKey)
        UserDefaults.standard.removeObject(forKey: "email_inbox_threads_v1")
        UserDefaults.standard.removeObject(forKey: "email_inbox_threads_v1_ts")
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
        triggerSync: Bool = false,
        bypassSyncCooldown: Bool = false
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
                triggerSync: triggerSync,
                bypassSyncCooldown: bypassSyncCooldown
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
        triggerSync: Bool,
        bypassSyncCooldown: Bool = false
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
            // Server-side re-sync first when the caller asked for fresh provider data
            // (pull-to-refresh, refresh button, first-launch inbox). Decoupled into a
            // detached Task that survives loadThreads cancellation: the previous shape ran
            // the mutation as a child of `performLoadThreads`, so a new pull-to-refresh
            // cancelling the prior loadThreads would also cancel the in-flight forceSync,
            // leaving `lastForceSyncAt` set with -999 errors and the cooldown locked
            // against a sync that never actually happened.
            //
            // `didRunForceSync` is only true when the mutation actually completed
            // successfully this call, so the empty-list reconciliation path doesn't kick on
            // for cooldown-coalesced or no-op (triggerSync=false) calls.
            let (_, didRunForceSync) = await runServerSyncIfNeeded(
                triggerSync: triggerSync,
                query: query,
                bypassCooldown: bypassSyncCooldown
            )

            try Task.checkCancellation()

            let input = ListThreadsInput(
                folder: folder,
                q: query,
                // 50 instead of 30 — first page already covers a couple of days of mail
                // for most users, so the inbox feels "full" without immediately needing
                // to paginate. The backend's per-shard fetch + thread-detail batch handle
                // 50 comfortably (no measurable latency change vs. 30 in profiling).
                maxResults: 50,
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
            if didRunForceSync && response.threads.isEmpty {
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

            // A newer load (higher generation) has superseded us — don't apply
            // stale results (threads / errorMessage / nextPageToken) over the
            // fresh run's state. The `defer` already gen-gates the spinner; this
            // guards every state write below the same way. Without it a slow
            // superseded run could clobber a successful newer load.
            guard loadGeneration == myGen else { return }

            if refresh {
                // Drop strictly-older refresh results — the backend's destructive forceSync
                // workflow occasionally rebuilds the table from a stale Gmail history offset,
                // briefly returning a slice of mail older than what's already displayed.
                // Without this guard, a user who just saw fresh mail would see it replaced
                // by month-old threads on the next polling tick (the "sometimes I see latest,
                // then refresh and it's old again" regression). Comparison is on the newest
                // message date — Gmail history strictly grows, so a refresh whose newest is
                // older than ours is, by definition, a stale workflow snapshot.
                //
                // Skip the guard on folder/query transitions: an Archive listing is
                // legitimately older than the Inbox; comparing across them would silently
                // drop every folder switch (the "folder picker does nothing" bug).
                let isSameContext = (loadedFolder == folder) && (loadedQuery == query)
                let currentNewest = threads.map(\.date).max()
                let incomingNewest = enrichedThreads.map(\.date).max()
                let isStaleRefresh: Bool = {
                    guard isSameContext else { return false }
                    guard let cur = currentNewest, let inc = incomingNewest else { return false }
                    return inc < cur
                }()

                // Proactive Gmail watch recovery. If the refresh result is older than a day
                // (or the prior cached inbox already was), the push subscription that drives
                // continuous sync has almost certainly expired — ask the backend to re-arm
                // it. Cooldown-gated so this fires at most every few hours per app session.
                let referenceNewest = incomingNewest ?? currentNewest
                if let newest = referenceNewest {
                    let ageSeconds = Date().timeIntervalSince(newest)
                    if ageSeconds > Self.rewatchStaleThreshold {
                        triggerGmailRewatchIfStale()
                    }
                } else if enrichedThreads.isEmpty && threads.isEmpty {
                    // Refresh returned nothing and we have nothing cached — strong signal
                    // the backend's continuous sync has been broken for long enough that
                    // there's no fresh row at all. Force a rewatch.
                    triggerGmailRewatchIfStale()
                }

                if isStaleRefresh {
                    let inc = incomingNewest.map { "\($0)" } ?? "nil"
                    let cur = currentNewest.map { "\($0)" } ?? "nil"
                    // Count what we silently discard vs. keep so dropped refreshes are
                    // observable in telemetry rather than vanishing without a trace.
                    AppLogger.shared.log("[EmailService] dropped stale refresh: incoming=\(inc) current=\(cur) dropped=\(enrichedThreads.count) kept=\(threads.count)")
                    // Treat as no-op — keep the displayed inbox, no error noise.
                    errorMessage = nil
                } else if !isSameContext {
                    // Folder/query switch — always replace, even with an empty list, so the
                    // user sees the correct (possibly empty) folder content rather than the
                    // prior folder's threads bleeding through.
                    threads = enrichedThreads
                    loadedFolder = folder
                    loadedQuery = query
                } else if !enrichedThreads.isEmpty {
                    threads = enrichedThreads
                    loadedFolder = folder
                    loadedQuery = query
                } else if threads.isEmpty {
                    errorMessage = "Couldn't load emails. Pull to refresh to try again."
                } else {
                    errorMessage = "Couldn't fetch new mail. Pull to refresh to try again."
                }
                // Cache the first page only when we accepted the refresh — caching a stale
                // slice would re-bake the regression into the next cold start.
                if folder == "inbox" && query == nil && !isStaleRefresh && !enrichedThreads.isEmpty {
                    saveCachedThreads(enrichedThreads)
                }
            } else {
                // Re-sort after merge so a newer thread that arrived on a later page
                // doesn't land below older first-page rows. `mergePages` deliberately
                // appends new ids at the end (its contract is pinned by
                // EmailServiceTests.testPaginationDedupePreservesNewerVersion), so the
                // date-desc ordering is applied here at the call site rather than inside
                // the pure merge function.
                threads = EmailService.mergePages(existing: threads, incoming: enrichedThreads)
                    .sorted { $0.date > $1.date }
                loadedFolder = folder
                loadedQuery = query
            }
            // Pre-warm avatar cache for the threads we just received so rows render with
            // the real avatar on first paint instead of flashing initials → avatar.
            prewarmAvatars(for: enrichedThreads)
            // Pre-fetch full thread details for the top of the list so tapping a row paints
            // instantly instead of waiting on a 500ms–2s `mail.get` round trip. Fire-and-
            // forget — failures are silent and re-tried on actual user open.
            prefetchThreadDetails(ids: enrichedThreads.map(\.id))
            nextPageToken = response.nextPageToken
            if query == nil {
                await loadAssistantNudges(folder: folder)
            }
        } catch is CancellationError {
            // Superseded by a newer load — keep quiet, the newer run owns the UI now.
        } catch APIError.unauthorized {
            // Auth failure — stop trying to load until the user re-authenticates.
            // Gen-gated: a stale superseded run must not flip a newer run's state.
            if loadGeneration == myGen { hasConnection = false }
        } catch EmailServiceError.timeout {
            // Treat timeout the same as a transient network error: surface a recovery
            // CTA without blowing away whatever cached threads we already had on screen.
            if loadGeneration == myGen {
                errorMessage = "Refreshing took too long. Pull to refresh to try again."
            }
            AppLogger.shared.log("[EmailService] loadThreads timed out")
        } catch {
            if let urlError = error as? URLError {
                if loadGeneration == myGen { errorMessage = "No internet connection." }
                AppLogger.shared.log("[EmailService] loadThreads network error: \(urlError)")
            } else {
                if loadGeneration == myGen { errorMessage = "Failed to load emails. Please try again." }
                AppLogger.shared.log("[EmailService] loadThreads error: \(error)")
            }
        }
    }

    /// Runs a server-side sync as a detached, non-cancellable task with cooldown-coalescing.
    ///
    /// Prefers `mail.softSync` (non-destructive: lists newest thread IDs from Gmail and
    /// upserts each via per-thread sync). Falls back to `mail.forceSync` (destructive:
    /// drops tables + restarts workflow) only when softSync fails or times out — the
    /// destructive path produces multi-second empty-inbox windows that the user sees
    /// even with cached data underneath, so we avoid it whenever possible.
    ///
    /// Returns `true` only when sync actually completed successfully this call. The
    /// `didRunDestructiveResync` flag controls whether `performLoadThreads` gates the
    /// post-sync empty-list reconciliation path on its result — softSync paths don't
    /// need reconciliation because the existing inbox stayed visible the whole time
    /// and the DB already has the new rows when we list.
    ///
    /// - Detached so a parent loadThreads cancellation (newer pull-to-refresh supersedes the
    ///   prior one) doesn't kill the in-flight Gmail re-sync mutation.
    /// - `lastForceSyncAt` is only stamped on success — a failed/cancelled sync must
    ///   not lock the cooldown against a future retry, which was the previous bug.
    /// - Concurrent callers within the same wall-clock attempt are coalesced onto the same
    ///   detached task so a flurry of triggerSync callers don't produce N concurrent
    ///   resyncs server-side.
    private func runServerSyncIfNeeded(
        triggerSync: Bool,
        query: String?,
        bypassCooldown: Bool
    ) async -> (success: Bool, didRunDestructiveResync: Bool) {
        guard triggerSync, query == nil else { return (false, false) }
        if !bypassCooldown,
           let last = lastForceSyncAt,
           Date().timeIntervalSince(last) < Self.forceSyncCooldown {
            return (false, false)
        }
        // Coalesce: if a sync is already running, attach to it instead of starting a new one.
        if let existing = inflightForceSyncTask {
            // Coalesced caller didn't observe destructive run vs. soft — assume soft path
            // for reconciliation gating; the in-flight task's own caller handles the
            // destructive case if it happened.
            return (await existing.value, false)
        }
        // Independent top-level Task: a `Task { ... }` started inside another task does
        // NOT inherit cancellation (structured cancellation only flows through TaskGroup
        // children and `async let`). A new pull-to-refresh that cancels the prior
        // loadThreads will therefore not also cancel this in-flight sync — the bug
        // that was producing -999 cancellation errors and locking the cooldown.
        let task: Task<Bool, Never> = Task { [api] in
            // 1. Try non-destructive softSync first (12s budget — 20 per-thread syncs
            //    typically complete within 4-8s; the cap leaves headroom for slow networks).
            let softInput = SoftSyncInput(folder: "inbox", maxResults: 20)
            do {
                let result: SoftSyncResponse = try await withThrowingTaskGroup(of: SoftSyncResponse.self) { group in
                    group.addTask {
                        try await api.trpcMutation("mail.softSync", input: softInput)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 12 * 1_000_000_000)
                        throw EmailServiceError.timeout
                    }
                    defer { group.cancelAll() }
                    guard let first = try await group.next() else {
                        throw EmailServiceError.timeout
                    }
                    return first
                }
                if result.ok != false && result.synced > 0 {
                    AppLogger.shared.log("[EmailService] softSync ok synced=\(result.synced) failed=\(result.failed)")
                    return true
                }
                // Fall through to forceSync if softSync returned 0 synced threads — that
                // usually means the DB is empty / shards missing and we need the destructive
                // workflow to rebuild them.
                AppLogger.shared.log("[EmailService] softSync returned 0 synced — falling back to forceSync")
            } catch {
                AppLogger.shared.log("[EmailService] softSync failed (\(error)) — falling back to forceSync")
            }
            // 2. Destructive fallback. Drops tables + restarts workflow. The reconciliation
            //    path picks up afterwards once the workflow populates fresh threads.
            do {
                return try await withThrowingTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        let _: EmailEmptyResponse = try await api.trpcMutation("mail.forceSync")
                        return true
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 8 * 1_000_000_000)
                        throw EmailServiceError.timeout
                    }
                    defer { group.cancelAll() }
                    guard let first = try await group.next() else { return false }
                    return first
                }
            } catch {
                AppLogger.shared.log("[EmailService] forceSync fallback error: \(error)")
                return false
            }
        }
        inflightForceSyncTask = task
        let success = await task.value
        if inflightForceSyncTask == task {
            inflightForceSyncTask = nil
        }
        if success {
            // Only stamp the cooldown when the mutation actually completed — failed or
            // cancelled syncs must not block the next attempt.
            lastForceSyncAt = Date()
        }
        // We don't know from the detached task whether soft or destructive won. Conservative:
        // assume destructive so the empty-list reconciliation path still kicks on for the
        // empty-DB case. False positives just produce a brief extra poll, no user impact.
        return (success, success)
    }

    /// Asks the backend to re-arm the Gmail PubSub watch + push subscription for the
    /// active connection. Gmail watches expire after ~7 days, and a connection whose
    /// watch was lost (cron miss, IAM blip, deleted subscription) gets stuck — no new
    /// mail arrives until something forces a re-subscribe.
    ///
    /// Started as an independent top-level Task so a refresh cancellation doesn't kill the
    /// mutation. Cooldown-gated so repeated stale loads in the same session don't flood
    /// `subscribe_queue`. Fire and forget — the actual mail recovery happens on the next
    /// pull/poll once the new watch is in place.
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
        reconciliationWatchdog?.cancel()
        isReconciling = true

        // Belt-and-suspenders: guarantee `isReconciling` flips back to false within a hard
        // ceiling. The reconciliation loop already self-terminates, but if its defer is
        // delayed (actor reentrancy edge case) the user can't be left staring at a spinner.
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

            // ~90s worst case: 20 attempts × 1.5s sleep + per-attempt 5s listThreads timeout.
            // Each iteration short-circuits on first non-empty response, so fast resyncs
            // resolve in 1–3s. The destructive forceSync workflow regularly needs 30-60s
            // to populate the first page (Gmail threads.list + per-thread fetch + DB
            // upsert), so the previous 30s budget routinely exhausted before the workflow
            // delivered — leaving the user looking at a stale cached inbox with no
            // recovery short of another pull-to-refresh.
            for _ in 0..<20 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                do {
                    let resp: ListThreadsResponse = try await self.withTimeout(seconds: 5) { [api = self.api] in
                        try await api.trpcQuery("mail.listThreads", input: input)
                    }
                    guard !resp.threads.isEmpty else { continue }
                    let enriched = try await self.withTimeout(seconds: 12) { [weak self] in
                        guard let self else { return [] as [EmailThread] }
                        return await self.fetchThreadDetails(ids: resp.threads.map(\.id))
                    }
                    if Task.isCancelled { return }
                    if !enriched.isEmpty {
                        // Same staleness guard as the foreground refresh: if the workflow
                        // finished but produced a slice strictly older than what we're
                        // already showing, drop it. Otherwise the user pulls, sees fresh
                        // mail briefly, then watches it flip back to month-old data once
                        // reconciliation lands its first non-empty (but stale) response.
                        let currentNewest = self.threads.map(\.date).max()
                        let incomingNewest = enriched.map(\.date).max()
                        if let cur = currentNewest, let inc = incomingNewest, inc < cur {
                            AppLogger.shared.log(
                                "[EmailService] reconciliation dropped stale snapshot: incomingNewest=\(inc) currentNewest=\(cur)"
                            )
                            return
                        }
                        self.threads = enriched
                        self.nextPageToken = resp.nextPageToken
                        if folder == "inbox" && query == nil {
                            self.saveCachedThreads(enriched)
                        }
                        self.prewarmAvatars(for: enriched)
                        // Clear any lingering error from a previous cycle now that fresh
                        // threads landed — we don't want the inbox to still claim a fetch
                        // failed once the data arrived.
                        self.errorMessage = nil
                    }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    // Network blip or per-attempt timeout — keep trying within budget.
                    continue
                }
            }
            // Budget exhausted without ever seeing fresh threads. Stay quiet rather than
            // surfacing a scary error — the next 60s poll will catch up, and showing
            // "Couldn't fetch new mail" while the prior inbox is happily on screen reads
            // as broken to the user.
            if !Task.isCancelled {
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

        // Populate from disk cache immediately so the inbox shows content without a
        // skeleton. The view only enters loadingState when `isLoadingThreads &&
        // threads.isEmpty`, so having cached threads bypasses the skeleton entirely.
        if threads.isEmpty {
            threads = loadCachedThreads() ?? []
            if !threads.isEmpty {
                loadedFolder = "inbox"
                loadedQuery = nil
                prewarmAvatars(for: threads)
            }
        }

        // Always re-read the backend DB on app entry — Gmail-style behaviour. The previous
        // `isCacheStale()` gate (skip refresh when cache is < 5 min old) was the cause of
        // "I open the app and see month-old mail with no refresh attempt" because the
        // cache file's `Date()` timestamp resets on every save, so a returning user almost
        // always lands inside the staleness window with no network fetch firing at all.
        // Cached threads stay visible underneath while this background refresh runs, so
        // there's no skeleton-flash on entry. Routine refresh path → no destructive
        // forceSync; the backend's continuous sync brings in new mail.
        if threads.isEmpty {
            // No cache yet: fetch synchronously AND trigger a Gmail re-sync so a fresh-DB
            // user actually gets data on first paint instead of an empty inbox.
            await loadThreads(refresh: true, triggerSync: true)
        } else {
            // Cache paints immediately. Fire a background refresh with `triggerSync: true`
            // so the soft-sync path pulls newest mail from Gmail and updates the inbox
            // in place — without this, returning users with a stale backend DB stay
            // pinned to month-old cached threads until they manually pull-to-refresh.
            // Cooldown gates the actual sync, so repeated cold starts within 2 minutes
            // don't flood the backend.
            Task { [weak self] in
                await self?.loadThreads(refresh: true, triggerSync: true)
            }
        }
    }

    func resetForSignOut() {
        resyncReconciliationTask?.cancel()
        resyncReconciliationTask = nil
        reconciliationWatchdog?.cancel()
        reconciliationWatchdog = nil
        inflightLoadThreadsTask?.cancel()
        inflightLoadThreadsTask = nil
        inflightForceSyncTask?.cancel()
        inflightForceSyncTask = nil
        avatarPrewarmTask?.cancel()
        avatarPrewarmTask = nil
        threads = []
        loadedFolder = nil
        loadedQuery = nil
        threadDetailCache.removeAll()
        for (_, task) in inflightDetailFetches { task.cancel() }
        inflightDetailFetches.removeAll()
        isLoadingThreads = false
        isReconciling = false
        isLoadingThread = false
        isSending = false
        hasConnection = false
        isCheckingConnection = false
        hasResolvedConnection = false
        errorMessage = nil
        nextPageToken = nil
        lastForceSyncAt = nil
        lastRewatchAt = nil
        assistantNudges = []
        assistantBriefing = nil
        // Clear disk cache so the next user session starts clean
        UserDefaults.standard.removeObject(forKey: Self.cacheDataKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheTimestampKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheDataKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheTimestampKey)
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
    ///
    /// The shared `TodosAPIClient` does up to 3 attempts on a 30s timeout (≈90s
    /// worst case before a network failure surfaces). Threads that take that
    /// long to return are almost always a backend hang — the inbox already has
    /// thread summaries cached, so the perceived "loads forever then errors"
    /// is a thread-detail fetch that the user has zero feedback on. We pair the
    /// request with a 20s watchdog and surface a more honest error message so
    /// users can retry instead of waiting 90s on a stale network.
    /// In-memory thread detail cache. Lets EmailThreadView paint instantly on second open
    /// and lets `prefetchThreadDetails` warm the top of the inbox so the user's most
    /// likely taps are zero-latency.
    private var threadDetailCache: [String: (detail: EmailThreadDetail, at: Date)] = [:]
    /// Track in-flight detail fetches to dedupe (prefetch + user tap landing on same id).
    private var inflightDetailFetches: [String: Task<EmailThreadDetail?, Never>] = [:]
    private static let threadDetailTTL: TimeInterval = 60 * 5   // 5 min

    func cachedThreadDetail(id: String) -> EmailThreadDetail? {
        guard let entry = threadDetailCache[id] else { return nil }
        if Date().timeIntervalSince(entry.at) > Self.threadDetailTTL {
            threadDetailCache.removeValue(forKey: id)
            return nil
        }
        return entry.detail
    }

    func loadThread(id: String) async -> EmailThreadDetail? {
        // Instant return on cache hit — the EmailThreadView refreshes silently if it wants.
        if let cached = cachedThreadDetail(id: id) {
            // Fire a background refresh so the cached copy doesn't grow stale during
            // a long-open thread session. Errors are swallowed; the cached view stays.
            Task { [weak self] in _ = await self?.fetchThreadDetail(id: id, updateLoadingState: false) }
            return cached
        }

        isLoadingThread = true
        errorMessage = nil
        defer { isLoadingThread = false }

        return await fetchThreadDetail(id: id, updateLoadingState: false)
    }

    /// Warms the in-memory cache for the first N inbox threads so user taps land on
    /// pre-fetched data. Fire-and-forget; failures are silently ignored.
    /// Called after a successful `loadThreads` for the inbox.
    func prefetchThreadDetails(ids: [String], limit: Int = 8) {
        let toFetch = ids
            .prefix(limit)
            .filter { cachedThreadDetail(id: $0) == nil && inflightDetailFetches[$0] == nil }
        for id in toFetch {
            Task { [weak self] in _ = await self?.fetchThreadDetail(id: id, updateLoadingState: false) }
        }
    }

    /// Shared fetch path used by both `loadThread` and prefetch. Dedupes concurrent fetches
    /// of the same id so a prefetch and a user-driven open don't fire two API calls.
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
                    self.errorMessage = "Thread is taking too long to load. Pull to retry."
                }
                return nil
            } catch let urlError as URLError where urlError.code == .cancelled {
                AppLogger.shared.log("[EmailService] loadThread(\(id)) URLSession cancelled by watchdog")
                if updateLoadingState {
                    self.errorMessage = "Thread is taking too long to load. Pull to retry."
                }
                return nil
            } catch {
                AppLogger.shared.log("[EmailService] loadThread(\(id)) failed: \(error)")
                if updateLoadingState {
                    self.errorMessage = self.friendlyThreadLoadMessage(for: error)
                }
                return nil
            }
        }
        inflightDetailFetches[id] = task
        let result = await task.value
        inflightDetailFetches.removeValue(forKey: id)
        return result
    }

    private func friendlyThreadLoadMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return "Sign in expired. Please sign in again."
            case .httpError(let code, _) where code == 404:
                return "This thread is no longer available."
            case .httpError(let code, let body) where (500..<600).contains(code):
                // Surface the tRPC-encoded backend message when present so a transient
                // shard miss ("Thread <id> not found") or a re-sync window
                // ("Thread fetch timed out") shows the actual cause instead of a
                // generic blob. Falls back to a friendly default when the body isn't
                // a tRPC error envelope.
                if let detail = Self.parseTRPCErrorMessage(body) {
                    return "Mail service: \(detail). Try again."
                }
                return "Mail service is unavailable. Try again in a moment."
            case .httpError(_, let body):
                if let detail = Self.parseTRPCErrorMessage(body) {
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
    /// `{ "error": { "json": { "message": "...", "code": -32603, ... } } }`
    /// and returns the message string, or nil if the body isn't a tRPC envelope.
    /// Keeps best-effort: any decode failure returns nil so callers fall back.
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

    // MARK: - Briefing trust loop
    //
    // These mutations let the user dismiss / snooze / mark-done a briefing row
    // when the AI surfaced something irrelevant (e.g. a Voi receipt as
    // "Needs You"). We optimistically remove the item from the local briefing
    // so the row disappears immediately, then fire-and-forget the server call —
    // the next briefing refresh will reconcile if anything went wrong.

    /// Dismiss an open-loop row ("Not a reply" / "Skip"). Removes locally and on the server.
    /// `feedback` is forwarded to `assistant.recordFeedback` so the classifier learns from it.
    func dismissBriefingOpenLoop(id: String, threadId: String?, feedback: String = "wrong") async {
        removeOpenLoopLocally(id: id, threadId: threadId)
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

    /// Mark an open-loop row as done. Same as dismiss but with `completed` feedback so the
    /// classifier doesn't penalize the suggestion — the user just handled it elsewhere.
    func completeBriefingOpenLoop(id: String, threadId: String?) async {
        removeOpenLoopLocally(id: id, threadId: threadId)
        await recordAssistantFeedback(targetType: "open_loop", targetId: id, feedback: "completed")
    }

    /// Snooze an open-loop row until a future date. Removes locally and persists server-side.
    func snoozeBriefingOpenLoop(id: String, threadId: String?, until: Date) async {
        removeOpenLoopLocally(id: id, threadId: threadId)
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

    /// Dismiss a prepared-action row ("Not now" on a Draft ready item).
    func dismissBriefingPreparedAction(id: String, threadId: String?, feedback: String = "wrong") async {
        removePreparedActionLocally(id: id, threadId: threadId)
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

    /// Records "helpful" / "not_helpful" / "too_noisy" / "wrong" / "completed" feedback for
    /// a briefing item. Best-effort — failures are logged, not surfaced.
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

    private func removeOpenLoopLocally(id: String, threadId: String?) {
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
        AssistantPersistedCache.saveBriefing(briefing)
    }

    private func removePreparedActionLocally(id: String, threadId: String?) {
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
        AssistantPersistedCache.saveBriefing(briefing)
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
    ///
    /// Cancels any prior in-flight prewarm so back-to-back refreshes don't pile up parallel
    /// fan-outs (each iterating every unique sender), and caps concurrency so a 50-sender
    /// page doesn't saturate URLSession's connection pool while a refresh's own listThreads/
    /// mail.get traffic is in flight.
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
        guard !unique.isEmpty else { return }
        let api = self.api
        let concurrency = Self.avatarPrewarmConcurrency

        // Replace any prior fan-out — its work was for an older thread set and would just
        // compete for connections with the fresh inbox.
        avatarPrewarmTask?.cancel()
        let task = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                var iterator = unique.makeIterator()
                // Seed up to `concurrency` workers, then add a new one each time one
                // finishes (sliding window). Bounded fan-out avoids saturating URLSession
                // while still letting AvatarCache dedupe concurrent calls per-sender.
                var inFlight = 0
                while inFlight < concurrency, let sender = iterator.next() {
                    group.addTask {
                        await AvatarCache.shared.resolveIfNeeded(
                            email: sender.email,
                            name: sender.name,
                            api: api
                        )
                    }
                    inFlight += 1
                }
                while await group.next() != nil {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let sender = iterator.next() {
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
        avatarPrewarmTask = task
    }

    // MARK: - Thread Cache

    /// Returns cached inbox threads if the cache exists, regardless of age.
    /// Callers decide whether to also trigger a network refresh.
    ///
    /// Drops any cached thread with a date that's clearly bogus — more than a day in
    /// the future, or earlier than year 2000. Without this, a single cached row with a
    /// `Date.distantFuture`/`Date()` placeholder (left over from a stale sync that
    /// fell back to "now" because the backend couldn't parse `receivedOn`) anchors
    /// `currentNewest` past every real incoming row, which trips `isStaleRefresh`
    /// and keeps the bogus row pinned at the top of the inbox forever.
    private func loadCachedThreads() -> [EmailThread]? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheDataKey) else { return nil }
        guard let decoded = try? JSONDecoder().decode([EmailThread].self, from: data) else { return nil }
        let now = Date()
        let futureCutoff = now.addingTimeInterval(24 * 60 * 60)
        let pastCutoff = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01 UTC
        return decoded.filter { $0.date < futureCutoff && $0.date > pastCutoff }
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
            PerformanceTrace.endInterval(
                PerformanceTrace.checkEmailConnection,
                trace,
                message: "EmailService.checkConnection end connected=\(hasConnection)"
            )
        }
        do {
            // Bound the connection check so a hung network can't trap the inbox indefinitely
            // — `ensureInitialInboxLoaded` awaits this, and without a ceiling the user sits
            // on the skeleton with no recovery path until the URLSession default timeout
            // (~60s+) eventually fires.
            let response: ConnectionsResponse = try await withTimeout(seconds: 8) { [api] in
                try await api.trpcQuery("connections.list")
            }
            hasConnection = !response.connections.isEmpty
            lastConnectionCheckAt = now
            // Only mark resolved on a SUCCESSFUL check — a timeout/throw must not
            // flip this true, or the cooldown guard would skip the next re-check and
            // strand a connected user on the connect screen.
            hasResolvedConnection = true
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

    /// Best-effort current Gmail connection count from the backend. Returns nil on
    /// any failure (network, timeout, decode) so callers can fall back rather than
    /// treating "couldn't read" as "zero connections". Bounded so a hung network
    /// can't trap the connect flow.
    private func currentConnectionCount() async -> Int? {
        do {
            let response: ConnectionsResponse = try await withTimeout(seconds: 8) { [api] in
                try await api.trpcQuery("connections.list")
            }
            return response.connections.count
        } catch {
            return nil
        }
    }

    /// Initiates Gmail OAuth connection and waits for the backend connection row.
    /// Google sign-in authenticates the Todus account, while link-social grants
    /// Gmail scopes and persists the email connection used by the mail UI.
    @discardableResult
    func connectGmail(authService: AuthService) async -> Bool {
        errorMessage = nil

        // Snapshot the current connection count BEFORE linking so the multi-account
        // path can verify a brand-new connection actually landed (rather than
        // returning true after a blind sleep). Best-effort: nil means we couldn't
        // read the count and will fall back to the connected-bool check.
        let priorConnectionCount = await currentConnectionCount()

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
        // Multi-account path: if the user already had a connection, `hasConnection` is
        // already true, so the bool check below can't tell whether the NEW account
        // actually linked. Poll the connection count until it grows past the snapshot
        // taken before linking — this catches the "tapped add account, OAuth completed,
        // but the new row never landed" failure instead of silently reporting success.
        if hasConnection {
            if let prior = priorConnectionCount {
                var attempt = 0
                let maxAttempts = 12  // 12 × 500ms = 6 seconds max
                var landed = false
                while attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    // Poll the count directly — `hasConnection` is already true here so
                    // checkConnection() can't signal the NEW account; the count growing
                    // past the pre-link snapshot is the real "it landed" signal.
                    if let now = await currentConnectionCount(), now > prior {
                        landed = true
                        break
                    }
                    attempt += 1
                }
                if !landed {
                    errorMessage =
                        "Could not link your Gmail account. Make sure you granted access to Gmail and try again."
                    return false
                }
            } else {
                // Couldn't read a baseline count — fall back to the previous behaviour:
                // give the fire-and-forget backend hook ~1.5 s to write the new row
                // before performConnectGmail calls connectionsService.loadConnections().
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
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

    /// Send an email. Pass `fromEmail` when the user picked a specific
    /// connected mailbox via the composer's From row; the backend will route
    /// the send through that connection instead of the active default.
    /// `attachmentNames` are AttachmentService filenames uploaded inline as
    /// base64 (the server's `serializedFileSchema`).
    func sendEmail(_ draft: EmailDraft, fromEmail: String? = nil, attachmentNames: [String] = []) async -> Bool {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            // RFC 5322 `In-Reply-To` / `References` headers chain replies into the
            // original thread on every mail client — without them, non-Gmail
            // recipients (Apple Mail, Outlook, plain SMTP) see a brand-new thread.
            // Wraps in angle brackets if the source id doesn't already have them.
            var headers: [String: String] = [:]
            if let mid = draft.replyToMessageId, !mid.isEmpty {
                let wrapped = mid.hasPrefix("<") ? mid : "<\(mid)>"
                headers["In-Reply-To"] = wrapped
                headers["References"] = wrapped
            }
            // Load attachment bytes from disk into the server's serialized-file
            // wire format. A file that vanished (deleted externally) is skipped
            // rather than failing the whole send.
            let serializedAttachments: [SerializedAttachment] = attachmentNames.compactMap { filename in
                let url = AttachmentService.shared.url(for: filename)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return SerializedAttachment(
                    name: filename,
                    type: AttachmentService.shared.mimeType(for: filename),
                    size: data.count,
                    lastModified: Int(Date().timeIntervalSince1970 * 1000),
                    base64: data.base64EncodedString()
                )
            }

            let input = SendEmailInput(
                to: draft.to.map { SendRecipient(email: $0) },
                cc: draft.cc.isEmpty ? nil : draft.cc.map { SendRecipient(email: $0) },
                bcc: draft.bcc.isEmpty ? nil : draft.bcc.map { SendRecipient(email: $0) },
                subject: draft.subject,
                // The composer produces plain text with light Markdown from its
                // formatting toolbar; recipients' clients render `message` as
                // HTML, so convert (bold/italic/headers/bullets + <br>) instead
                // of shipping literal `**bold**` markers.
                message: Self.composeBodyToHTML(draft.body),
                attachments: serializedAttachments.isEmpty ? nil : serializedAttachments,
                threadId: draft.replyToThreadId,
                fromEmail: fromEmail,
                headers: headers.isEmpty ? nil : headers,
                isForward: draft.isForward ? true : nil,
                originalMessage: draft.isForward ? draft.originalMessage : nil
            )
            let _: SendResponse = try await api.trpcMutation("mail.send", input: input)
            return true
        } catch {
            // Surface the underlying message if available — saves the user from
            // guessing whether the failure was network, validation, or backend.
            if let apiError = error as? APIError {
                switch apiError {
                case .httpError(_, let body):
                    if let body, !body.isEmpty {
                        errorMessage = "Failed to send: \(body.prefix(140))"
                    } else {
                        errorMessage = "Failed to send email."
                    }
                default:
                    errorMessage = "Failed to send email."
                }
            } else {
                errorMessage = "Failed to send email."
            }
            return false
        }
    }

    /// Server-backed thread search that does NOT touch `threads` — used by
    /// global search so results include mail that isn't loaded in the inbox
    /// (the debounced inbox search overwrites `threads`, which is destructive
    /// for a cross-tab overlay).
    func searchThreadsServer(query: String, limit: Int = 25) async -> [EmailThread] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasConnection, !trimmed.isEmpty else { return [] }
        do {
            let input = ListThreadsInput(folder: "inbox", q: trimmed, maxResults: limit, cursor: nil)
            let response: ListThreadsResponse = try await withTimeout(seconds: 12) { [api] in
                try await api.trpcQuery("mail.listThreads", input: input)
            }
            let ids = response.threads.map(\.id)
            guard !ids.isEmpty else { return [] }
            return await fetchThreadDetails(ids: ids)
        } catch {
            AppLogger.shared.log("[EmailService] searchThreadsServer failed: \(error.localizedDescription)")
            return []
        }
    }

    /// One attachment of a message, with its content as base64 (server
    /// `mail.getMessageAttachments`).
    struct MessageAttachmentContent: Decodable {
        let filename: String
        let mimeType: String
        let size: Int
        let attachmentId: String
        /// Base64 attachment bytes. Gmail uses base64url; normalize before decoding.
        let body: String

        var decodedData: Data? {
            var normalized = body
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while normalized.count % 4 != 0 { normalized.append("=") }
            return Data(base64Encoded: normalized)
        }
    }

    /// Fetch the full attachment payloads for a message (used by the thread
    /// view's attachment cards to open/preview received files).
    func fetchMessageAttachments(messageId: String) async throws -> [MessageAttachmentContent] {
        struct Input: Encodable { let messageId: String }
        return try await api.trpcQuery("mail.getMessageAttachments", input: Input(messageId: messageId))
    }

    /// Converts the iOS composer's plain-text-with-light-Markdown body into
    /// simple HTML. If the body already looks like HTML (e.g. an AI-generated
    /// draft), it passes through unchanged.
    static func composeBodyToHTML(_ body: String) -> String {
        let lower = body.lowercased()
        if lower.contains("<p") || lower.contains("<div") || lower.contains("<br") || lower.contains("<html") {
            return body
        }

        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        func inlineMarkdown(_ s: String) -> String {
            var out = s
            for (pattern, template) in [
                (#"\*\*(.+?)\*\*"#, "<b>$1</b>"),
                (#"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, "<i>$1</i>"),
            ] {
                out = out.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
            }
            return out
        }

        let htmlLines = body.components(separatedBy: "\n").map { rawLine -> String in
            let line = escape(rawLine)
            if line.hasPrefix("# ") { return "<h1>\(inlineMarkdown(String(line.dropFirst(2))))</h1>" }
            if line.hasPrefix("## ") { return "<h2>\(inlineMarkdown(String(line.dropFirst(3))))</h2>" }
            if line.hasPrefix("• ") || line.hasPrefix("- ") {
                return "&bull; \(inlineMarkdown(String(line.dropFirst(2))))<br>"
            }
            if line.isEmpty { return "<br>" }
            return "\(inlineMarkdown(line))<br>"
        }
        return "<div>\(htmlLines.joined())</div>"
    }

    /// Restores the given thread snapshots into `threads` without disturbing
    /// rows that other mutations may have changed in the meantime.
    /// - If a snapshot's id is still in the list, the row is replaced in place.
    /// - If a snapshot was removed (archive/delete rollback), it's re-inserted
    ///   at a position consistent with the current list's date ordering.
    private func restoreThreadSnapshots(_ snapshots: [EmailThread]) {
        guard !snapshots.isEmpty else { return }
        let snapshotById = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        var rebuilt: [EmailThread] = []
        rebuilt.reserveCapacity(threads.count + snapshots.count)
        var seen = Set<String>()
        for t in threads {
            if let snap = snapshotById[t.id] {
                rebuilt.append(snap)
            } else {
                rebuilt.append(t)
            }
            seen.insert(t.id)
        }
        for snap in snapshots where !seen.contains(snap.id) {
            let insertIndex = rebuilt.firstIndex { $0.date < snap.date } ?? rebuilt.endIndex
            rebuilt.insert(snap, at: insertIndex)
            seen.insert(snap.id)
        }
        threads = rebuilt
    }

    /// Drops cached thread details for the given ids so the next open re-fetches
    /// fresh state. The list mutations below update `threads` (unread / star /
    /// labels) but would otherwise leave a stale `EmailThreadDetail` in
    /// `threadDetailCache`, so opening a just-read or just-starred thread showed
    /// the pre-mutation state until the cache TTL expired.
    private func invalidateThreadDetail(ids: [String]) {
        for id in ids { threadDetailCache.removeValue(forKey: id) }
    }

    /// Marks the given threads as read. Returns `true` on success so call sites
    /// can gate side effects (e.g. dismissing a thread view) on the result.
    ///
    /// `silent: true` suppresses writes to the shared `errorMessage` on failure —
    /// used by background reads (e.g. opening a thread auto-marks it read) where
    /// surfacing the error would poison unrelated UI that watches `errorMessage`.
    @discardableResult
    func markAsRead(ids: [String], silent: Bool = false) async -> Bool {
        // Capture only the affected rows so a rollback doesn't undo unrelated
        // mutations that landed in the meantime.
        let snapshots = threads.filter { ids.contains($0.id) }
        for i in threads.indices where ids.contains(threads[i].id) {
            threads[i] = EmailThread(
                id: threads[i].id, subject: threads[i].subject,
                snippet: threads[i].snippet, from: threads[i].from,
                date: threads[i].date, unread: false,
                messageCount: threads[i].messageCount, labels: threads[i].labels
            )
        }
        invalidateThreadDetail(ids: ids)
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsRead", input: IdsInput(ids: ids))
            return true
        } catch {
            restoreThreadSnapshots(snapshots)
            if !silent {
                errorMessage = "Could not mark as read. Please try again."
            }
            AppLogger.shared.log("[EmailService] markAsRead error: \(error)")
            return false
        }
    }

    /// Marks the given threads as unread. Returns `true` on success so call sites
    /// can gate dismissal on the result.
    @discardableResult
    func markAsUnread(ids: [String]) async -> Bool {
        let snapshots = threads.filter { ids.contains($0.id) }
        for i in threads.indices where ids.contains(threads[i].id) {
            threads[i] = EmailThread(
                id: threads[i].id, subject: threads[i].subject,
                snippet: threads[i].snippet, from: threads[i].from,
                date: threads[i].date, unread: true,
                messageCount: threads[i].messageCount, labels: threads[i].labels
            )
        }
        invalidateThreadDetail(ids: ids)
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.markAsUnread", input: IdsInput(ids: ids))
            return true
        } catch {
            restoreThreadSnapshots(snapshots)
            errorMessage = "Could not mark as unread. Please try again."
            AppLogger.shared.log("[EmailService] markAsUnread error: \(error)")
            return false
        }
    }

    /// Archives the given threads. Returns `true` on success so call sites can
    /// gate side effects (e.g. dismissing a thread view) on the result rather
    /// than fragile shared-errorMessage diffing.
    @discardableResult
    func archiveThreads(ids: [String]) async -> Bool {
        let snapshots = threads.filter { ids.contains($0.id) }
        threads.removeAll { ids.contains($0.id) }
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkArchive", input: IdsInput(ids: ids))
            return true
        } catch {
            restoreThreadSnapshots(snapshots)
            errorMessage = "Could not archive. Please try again."
            AppLogger.shared.log("[EmailService] archiveThreads error: \(error)")
            return false
        }
    }

    /// Deletes (moves to Trash) one or more threads. Returns whether the API call succeeded
    /// — callers like EmailThreadView use the result to decide whether to dismiss.
    @discardableResult
    func deleteThreads(ids: [String]) async -> Bool {
        let snapshots = threads.filter { ids.contains($0.id) }
        threads.removeAll { ids.contains($0.id) }
        do {
            let _: EmailEmptyResponse = try await api.trpcMutation("mail.bulkDelete", input: IdsInput(ids: ids))
            return true
        } catch {
            restoreThreadSnapshots(snapshots)
            errorMessage = "Could not delete. Please try again."
            AppLogger.shared.log("[EmailService] deleteThreads error: \(error)")
            return false
        }
    }

    /// Toggles the star (Gmail STARRED label) for the given threads. Returns
    /// `true` on success so view-local optimistic state (e.g. the EmailThreadView
    /// star button) can roll itself back when the mutation fails.
    @discardableResult
    func toggleStar(ids: [String]) async -> Bool {
        // Optimistically flip the Gmail STARRED label in the local cache so the
        // star icon / swipe label updates immediately (`EmailThread.isStarredInLabels`
        // reads `labels`); roll back if the server call fails. Mirrors
        // markAsRead/markAsUnread. Previously this only hit the server, so the
        // star never changed in the list until a full reload.
        let snapshots = threads.filter { ids.contains($0.id) }
        let isStarredLabel: (String) -> Bool = { name in
            let n = name.uppercased(); return n == "STARRED" || n == "\\STARRED"
        }
        for i in threads.indices where ids.contains(threads[i].id) {
            var newLabels = threads[i].labels
            if newLabels.contains(where: isStarredLabel) {
                newLabels.removeAll(where: isStarredLabel)
            } else {
                newLabels.append("STARRED")
            }
            threads[i] = EmailThread(
                id: threads[i].id, subject: threads[i].subject,
                snippet: threads[i].snippet, from: threads[i].from,
                date: threads[i].date, unread: threads[i].unread,
                messageCount: threads[i].messageCount, labels: newLabels
            )
        }
        invalidateThreadDetail(ids: ids)
        do {
            let _: SuccessResponse = try await api.trpcMutation("mail.toggleStar", input: IdsInput(ids: ids))
            return true
        } catch {
            restoreThreadSnapshots(snapshots)
            errorMessage = "Could not update star. Please try again."
            AppLogger.shared.log("[EmailService] toggleStar error: \(error)")
            return false
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
    /// API call succeeds. Returns `true` on success so callers can gate
    /// dismissing the thread view on the result.
    @discardableResult
    func markAsSpam(ids: [String]) async -> Bool {
        guard !ids.isEmpty else { return true }
        let success = await modifyLabels(threadIds: ids, add: ["SPAM"], remove: ["INBOX"])
        if success {
            threads.removeAll { ids.contains($0.id) }
        } else {
            errorMessage = "Could not report spam. Please try again."
        }
        return success
    }

    /// Pure pagination merge — used by `performLoadThreads` and pinned by
    /// `EmailServiceTests.testPaginationDedupePreservesNewerVersion`. Extracted
    /// so the dedupe contract is unit-testable without spinning up the full
    /// service + API client + URLProtocol stack.
    ///
    /// Semantics:
    /// - Existing threads are preserved in order.
    /// - For each incoming thread whose id already exists, replace IN PLACE
    ///   when the incoming snapshot is "newer" (later date OR flipped unread
    ///   flag OR labels differ as a set). Otherwise drop the duplicate.
    /// - Incoming ids not seen before are appended at the end.
    static func mergePages(existing: [EmailThread], incoming: [EmailThread]) -> [EmailThread] {
        var merged = existing
        var indexById: [String: Int] = [:]
        indexById.reserveCapacity(merged.count)
        for (i, t) in merged.enumerated() { indexById[t.id] = i }
        var appended: [EmailThread] = []
        appended.reserveCapacity(incoming.count)
        for newer in incoming {
            if let idx = indexById[newer.id] {
                let existingRow = merged[idx]
                let labelsChanged = Set(existingRow.labels) != Set(newer.labels)
                if newer.date > existingRow.date
                    || newer.unread != existingRow.unread
                    || labelsChanged {
                    merged[idx] = newer
                }
            } else {
                appended.append(newer)
            }
        }
        merged.append(contentsOf: appended)
        return merged
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

private struct SoftSyncInput: Encodable {
    let folder: String
    let maxResults: Int
}

private struct SoftSyncResponse: Decodable {
    let synced: Int
    let failed: Int
    let total: Int
    let ok: Bool?
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

/// Wire format for `mail.send` attachments — the server's `serializedFileSchema`.
struct SerializedAttachment: Encodable {
    let name: String
    let type: String
    let size: Int
    let lastModified: Int
    let base64: String
}

private struct SendEmailInput: Encodable {
    let to: [SendRecipient]
    let cc: [SendRecipient]?
    let bcc: [SendRecipient]?
    let subject: String
    let message: String
    /// Binary attachments, matching the server's `serializedFileSchema`
    /// ({ name, type, size, lastModified, base64 }).
    let attachments: [SerializedAttachment]?
    let threadId: String?
    /// Address of the connected mailbox to send from. When nil the backend
    /// uses the active connection — but multi-account users picking a
    /// non-default From in the composer rely on this being plumbed through.
    let fromEmail: String?
    /// Outgoing MIME headers. Used to inject `In-Reply-To` / `References` on
    /// replies so non-Gmail recipients (Apple Mail, Outlook, plain SMTP) chain
    /// the reply into the original thread instead of starting a new one.
    let headers: [String: String]?
    /// Forward marker — server adds the quoted original via `originalMessage`.
    let isForward: Bool?
    let originalMessage: String?
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

    private enum CodingKeys: String, CodingKey {
        case messages, latest, hasUnread, totalReplies, labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode messages element-by-element so a single malformed message
        // (e.g. missing id, unparseable shape) doesn't blank the entire thread
        // and leave the user staring at "Could not load thread" with no recovery.
        if container.contains(.messages) {
            var arrayContainer = try container.nestedUnkeyedContainer(forKey: .messages)
            var decoded: [EmailMessage] = []
            decoded.reserveCapacity(arrayContainer.count ?? 0)
            while !arrayContainer.isAtEnd {
                if let message = try? arrayContainer.decode(EmailMessage.self) {
                    decoded.append(message)
                } else {
                    // Skip the bad element so iteration continues. `decodeNil`
                    // advances the cursor when the value is null; `decode(JSONValue)`
                    // is used otherwise to consume the slot of the failed message.
                    if (try? arrayContainer.decodeNil()) != true {
                        _ = try? arrayContainer.decode(JSONValue.self)
                    }
                }
            }
            self.messages = decoded
        } else {
            self.messages = []
        }
        self.latest = try container.decodeIfPresent(EmailMessage.self, forKey: .latest)
        self.hasUnread = try container.decodeIfPresent(Bool.self, forKey: .hasUnread)
        self.totalReplies = try container.decodeIfPresent(Int.self, forKey: .totalReplies)
        self.labels = try container.decodeIfPresent([ThreadLabel].self, forKey: .labels)
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

