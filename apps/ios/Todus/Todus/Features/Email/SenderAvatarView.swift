import SwiftUI
import CryptoKit
import ImageIO
import UIKit

// MARK: - Avatar API DTOs

private struct AvatarInput: Encodable {
    let email: String
    let name: String?
}

private struct AvatarResponse: Decodable {
    let email: String
    let domain: String
    let primary: Primary?
    let fallbackUrls: [String]

    struct Primary: Decodable {
        let source: String  // "google" | "bimi" | "favicon" | "none"
        let url: String?
        let svgContent: String?
    }
}

// Domains of free personal email providers. Brand-favicon lookup is skipped for these —
// fetching their favicon would return the provider's own logo (Gmail's G, Outlook's O),
// not the individual sender's avatar. Gravatar handles personal addresses instead.
private let freeEmailProviderDomains: Set<String> = [
    "gmail.com", "googlemail.com",
    "outlook.com", "hotmail.com", "live.com", "msn.com",
    "yahoo.com", "yahoo.co.uk", "yahoo.fr", "yahoo.de", "yahoo.co.jp", "yahoo.com.br",
    "icloud.com", "me.com", "mac.com",
    "protonmail.com", "proton.me", "protonmail.ch",
    "zohomail.com", "zoho.com",
    "yandex.com", "yandex.ru",
    "mail.ru", "bk.ru", "inbox.ru", "list.ru",
    "gmx.com", "gmx.net", "gmx.de", "gmx.at",
    "aol.com", "aol.co.uk",
    "fastmail.com", "fastmail.fm",
    "hey.com",
    "tutanota.com", "tutamail.com",
]

// MARK: - Avatar Cache

/// Persistent avatar URL cache with TTL, last-successful memoization, and disk-backed storage.
///
/// Why persistent: avatar URL resolution is expensive (backend API + favicon HEAD requests).
/// Without persistence, every cold start re-resolves every sender. With it, we hit zero
/// network on cold start for senders we've seen before.
///
/// Why @Observable: SwiftUI views read `resolvedURLs` directly and re-render automatically
/// when a new entry arrives — the view transitions from initials → real avatar without any
/// manual signaling.
///
/// PERFORMANCE NOTE: Only `resolvedURLs` is observable. `lastSuccessful`, `resolvedAt`,
/// `inFlight`, and `saveTask` are explicitly `@ObservationIgnored` so the per-row
/// `recordSuccess(...)` write fired from `AsyncImage.onAppear` does NOT invalidate every
/// email row that previously read `candidates(for:)`. Before this fix every scroll-induced
/// image success caused a full inbox re-render cascade — a measured main-thread hang source.
/// Disk I/O is dispatched to a background queue so JSON encode/decode never blocks the UI.
@MainActor
@Observable
final class AvatarCache {
    static let shared = AvatarCache()

    /// email → ordered list of image URLs to try, best source first.
    /// Reading this property triggers a SwiftUI re-render when it changes — this is the
    /// only dict that SHOULD invalidate views (new sender resolved → row picks up URL).
    var resolvedURLs: [String: [URL]] = [:]

    /// email → URL that successfully rendered last time. Tried first on next render so
    /// repeat displays skip the failing prefix of the candidate list.
    /// `@ObservationIgnored` — mutations here must NOT invalidate every consumer of
    /// `candidates(for:)`; that would re-render every visible email row.
    @ObservationIgnored private var lastSuccessful: [String: URL] = [:]

    /// email → when this entry was resolved. Used to apply TTL. Not observed.
    @ObservationIgnored private var resolvedAt: [String: Date] = [:]

    /// Tracks in-progress fetches so concurrent rows for the same sender don't double-fetch.
    @ObservationIgnored private var inFlight: Set<String> = []

    /// Successful resolutions stick around for 30 days. Long enough to survive vacation;
    /// short enough that brand logo refreshes propagate.
    private static let successTTL: TimeInterval = 60 * 60 * 24 * 30

    /// Empty/failed resolutions are retried after 5 minutes. Without this, a single
    /// transient backend failure would leave the avatar permanently absent for the session.
    private static let emptyTTL: TimeInterval = 60 * 5

    /// Cap on disk entries — avoids unbounded growth for users who burn through inbox.
    private static let maxEntries = 5000

    /// Debounced disk write — coalesces rapid updates (e.g. 50 row appearances on inbox load).
    /// One task at a time: while it's sleeping, `scheduleSave()` just flips `dirty` instead
    /// of cancelling + reallocating a new Task. Avoids ~100 Task allocations per inbox refresh.
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false

    /// True once `bootstrap()` has hydrated the in-memory cache from disk. Used to make
    /// `bootstrap()` idempotent so we don't re-decode the cache on every call.
    @ObservationIgnored private var didBootstrap = false

    /// Serial background queue for all disk I/O. JSON encode/decode and atomic file
    /// writes run here, never on the main thread. Mirrors the pattern in `AppLogger`.
    /// `nonisolated` so the queue can be dispatched onto from any actor context.
    nonisolated private static let diskQueue = DispatchQueue(
        label: "com.todus.avatarCache.disk",
        qos: .utility
    )

    /// Marked `nonisolated` so the background `diskQueue` helpers can read the URL
    /// without crossing back to the MainActor.
    nonisolated private static let cacheFileURL: URL? = {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("sender-avatar-cache.json")
    }()

    private init() {
        // Disk hydration is deferred to `bootstrap()` so first access of `AvatarCache.shared`
        // (e.g. during inbox row body evaluation) does not synchronously decode up to
        // 5000 JSON entries on the main thread.
    }

    // MARK: - Public API

    /// Returns candidate URLs for an email, ordered with last-known-good URL first.
    /// Returns nil if not yet resolved.
    func candidates(for email: String) -> [URL]? {
        let key = normalizedEmail(email)
        guard let urls = resolvedURLs[key] else { return nil }
        // Surface the last-successful URL first so we don't re-walk failing prefixes.
        if let preferred = lastSuccessful[key],
           let idx = urls.firstIndex(of: preferred), idx > 0 {
            var reordered = urls
            reordered.remove(at: idx)
            reordered.insert(preferred, at: 0)
            return reordered
        }
        return urls
    }

    /// Fetches and caches avatar URLs for the given sender unless a fresh entry exists.
    /// Deduplicates concurrent calls for the same email.
    func resolveIfNeeded(email: String, name: String, api: TodosAPIClient) async {
        let key = normalizedEmail(email)
        guard !key.isEmpty, !inFlight.contains(key) else { return }

        // Honor TTL — short for empty results so transient failures don't stick.
        if let when = resolvedAt[key] {
            let urls = resolvedURLs[key] ?? []
            let ttl = urls.isEmpty ? Self.emptyTTL : Self.successTTL
            if Date().timeIntervalSince(when) < ttl {
                return
            }
        }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let urls = await fetchCandidateURLs(email: key, name: name, api: api)
        resolvedURLs[key] = urls
        resolvedAt[key] = Date()
        scheduleSave()
    }

    /// Records that `url` rendered successfully for `email`. Future renders try this URL
    /// first, persisted across launches.
    func recordSuccess(email: String, url: URL) {
        let key = normalizedEmail(email)
        guard lastSuccessful[key] != url else { return }
        lastSuccessful[key] = url
        scheduleSave()
    }

    func flushPendingSaves() {
        saveTask?.cancel()
        saveTask = nil
        dirty = false
        let snapshot = makeSnapshot()
        Self.diskQueue.async {
            Self.writeToDisk(snapshot)
        }
    }

    /// Hydrate the in-memory cache from disk. Decodes the persisted blob off the main
    /// thread, then publishes a single mutation to `resolvedURLs` so SwiftUI sees one
    /// invalidation instead of N. Safe to call multiple times — second call is a no-op.
    ///
    /// Call this from app startup (after the first interactive frame) and from background
    /// → foreground transitions if you suspect the in-memory copy went stale.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.avatarCacheBootstrap,
            message: "AvatarCache.bootstrap begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.avatarCacheBootstrap,
                trace,
                message: "AvatarCache.bootstrap end"
            )
        }

        let snapshot = await withCheckedContinuation { (cont: CheckedContinuation<PersistedShape?, Never>) in
            Self.diskQueue.async {
                cont.resume(returning: Self.readFromDisk())
            }
        }

        guard let snapshot else { return }

        // Drop expired entries before publishing.
        let now = Date()
        var validURLs: [String: [URL]] = [:]
        var validAt: [String: Date] = [:]
        for (email, when) in snapshot.resolvedAt {
            let urls = snapshot.resolvedURLs[email] ?? []
            let ttl = urls.isEmpty ? Self.emptyTTL : Self.successTTL
            if now.timeIntervalSince(when) < ttl {
                validURLs[email] = urls
                validAt[email] = when
            }
        }

        // Single observable write so SwiftUI rerenders only once for the whole hydration.
        resolvedURLs = validURLs
        resolvedAt = validAt
        lastSuccessful = snapshot.lastSuccessful.filter { validURLs[$0.key] != nil }
    }

    // MARK: - Backend fetch

    private func fetchCandidateURLs(email: String, name: String, api: TodosAPIClient) async -> [URL] {
        // Resolution order: real Google contact photos first (highest fidelity when
        // available), then Clearbit/icon.horse brand logos, then backend cheerio-extracted
        // URLs, then any backend non-Google primary, then local favicon fallbacks.
        var urls: [URL] = []
        var contactPhoto: URL? = nil
        var nonGooglePrimary: URL? = nil
        var backendFallbacks: [URL] = []

        do {
            let input = AvatarInput(email: email, name: name.isEmpty ? nil : name)
            let response: AvatarResponse = try await api.trpcQuery("avatar.getByEmail", input: input)

            if let primary = response.primary,
               primary.source != "bimi",  // BIMI is SVG — iOS has no native SVG renderer.
               let urlStr = primary.url,
               let url = URL(string: urlStr) {
                if primary.source == "google" {
                    contactPhoto = url
                } else {
                    nonGooglePrimary = url
                }
            }

            for urlStr in response.fallbackUrls {
                if let url = URL(string: urlStr) {
                    backendFallbacks.append(url)
                }
            }
        } catch {
            // Backend failure → fall through to local deterministic fallbacks. The empty-TTL
            // ensures we retry the backend in 5 minutes rather than waiting for relaunch.
        }

        if let cp = contactPhoto, !urls.contains(cp) { urls.append(cp) }

        // Clearbit/icon.horse sources first — highest fidelity brand logos, reliable 404
        // for unknowns. Backend cheerio-extracted URLs added afterward as supplemental.
        for fb in localFallbackURLs(email: email) where !urls.contains(fb) {
            urls.append(fb)
        }

        if let np = nonGooglePrimary, !urls.contains(np) { urls.append(np) }
        for fb in backendFallbacks where !urls.contains(fb) {
            urls.append(fb)
        }

        // .ico URLs are intentionally kept — UIImage on iOS 17+ decodes ICO containers
        // reliably, and for transactional brands (resend, kivra, etc.) that ship only
        // `/favicon.ico` they're often the only fallback that actually serves an image.
        // The AsyncImage failure cascade in `body` advances past any URL that fails to
        // decode, so leaving them in costs nothing while preventing initials-only renders.
        return urls
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Includes root-domain and `www.` variants to improve hit rate on transactional senders.
    /// (e.g. `noreply@notifications.resend.com` falls back to `resend.com`.)
    private func localFallbackURLs(email: String) -> [URL] {
        guard let domain = domainFromEmail(email), !domain.isEmpty else { return [] }

        // For personal email providers, skip brand-favicon lookup entirely.
        // The backend already provides a Gravatar URL in fallbackUrls for these.
        if freeEmailProviderDomains.contains(domain) {
            return gravatarURL(email: email).map { [$0] } ?? []
        }

        // Build host candidates: root domain first (best brand-logo hit rate),
        // then original domain (for sub-domain transactional senders), then www. variants.
        var rootHost: String? = rootDomain(from: domain)
        if rootHost == domain { rootHost = nil } // already at root

        var hostCandidates: [String] = []
        if let root = rootHost {
            hostCandidates.append(root)
        }
        hostCandidates.append(domain)
        // Add www. variants for each non-www host
        for host in Array(hostCandidates) where !host.hasPrefix("www.") {
            hostCandidates.append("www.\(host)")
        }
        // Deduplicate while preserving insertion order
        var seen = Set<String>()
        hostCandidates = hostCandidates.filter { seen.insert($0).inserted }

        var candidates: [URL] = []
        // Cap on how many favicon/logo URLs we'll ever attempt per logoless sender.
        // Without it the assembled list reaches 10+ candidates (Clearbit ×N hosts,
        // Gravatar, icon.horse/DDG ×N, apple-touch/favicon.ico ×N), and the
        // AsyncImage failure waterfall fires a GET for each on scroll. 4 keeps the
        // highest-quality sources (Clearbit, then one favicon API) while bounding
        // network fan-out. Applied via `.prefix(4)` on the final deduped list.
        let maxCandidates = 4

        // 1. Clearbit: high-quality brand logos, returns proper 404 (not a globe).
        //    Covers Anthropic, Ryanair, Apple, OpenAI, Cursor, Sky Showtime, and thousands more.
        //    Only try non-www hosts — Clearbit resolves by root domain internally.
        for host in hostCandidates where !host.hasPrefix("www.") {
            if let url = URL(string: "https://logo.clearbit.com/\(host)?size=256") {
                candidates.append(url)
            }
        }

        // 2. Gravatar: covers individuals with a registered Gravatar on brand domains
        if let grav = gravatarURL(email: email), !candidates.contains(grav) {
            candidates.append(grav)
        }

        // 3. icon.horse and DuckDuckGo: reliable favicon APIs, return 404 on failure
        for host in hostCandidates where !host.hasPrefix("www.") {
            if let url = URL(string: "https://icon.horse/icon/\(host)"),
               !candidates.contains(url) {
                candidates.append(url)
            }
            if let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
               !candidates.contains(url) {
                candidates.append(url)
            }
        }

        // 4. Apple touch icons and favicon.ico — broad compatibility fallbacks.
        //    Google s2 is intentionally excluded: it returns a generic globe PNG (HTTP 200)
        //    for unknown domains, which AsyncImage accepts as success and displays — hiding
        //    the sender's real initials behind a meaningless globe icon.
        for host in hostCandidates {
            let rawURLs = [
                "https://\(host)/apple-touch-icon-precomposed.png",
                "https://\(host)/apple-touch-icon.png",
                "https://\(host)/favicon.ico",
            ]
            for raw in rawURLs {
                if let url = URL(string: raw), !candidates.contains(url) {
                    candidates.append(url)
                }
            }
        }

        // Cap the waterfall — keeps the highest-quality candidates first (Clearbit,
        // then the first favicon API) and drops the long tail so a logoless sender
        // can't trigger 10+ favicon GETs as it scrolls into view.
        return Array(candidates.prefix(maxCandidates))
    }

    /// Computes the SHA-256 Gravatar URL for the given email (CryptoKit, iOS 13+).
    /// `d=404` ensures Gravatar returns HTTP 404 when no avatar exists, so AsyncImage
    /// sees `.failure` and the waterfall advances to the next candidate rather than
    /// displaying Gravatar's default mystery-person image.
    private func gravatarURL(email: String) -> URL? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let hash = SHA256.hash(data: Data(normalized.utf8))
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://www.gravatar.com/avatar/\(hashString)?s=256&d=404&r=g")
    }

    private func domainFromEmail(_ email: String) -> String? {
        guard let at = email.lastIndex(of: "@"), at < email.index(before: email.endIndex) else {
            return nil
        }
        let domain = email[email.index(after: at)...]
        let cleaned = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Best-effort root domain extraction with common multi-part TLD handling.
    private func rootDomain(from domain: String) -> String? {
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }

        if parts.count >= 3 {
            let tld = parts.suffix(2).joined(separator: ".")
            let commonSecondLevelTLDs: Set<String> = [
                "co.uk", "org.uk", "gov.uk", "ac.uk", "com.au", "co.jp", "com.br", "co.in"
            ]
            if commonSecondLevelTLDs.contains(tld) {
                return parts.suffix(3).joined(separator: ".")
            }
        }

        return parts.suffix(2).joined(separator: ".")
    }

    // MARK: - Persistence

    /// `Sendable` so the snapshot can cross from the main actor to `diskQueue` without
    /// touching the live mutable dicts on the actor.
    fileprivate struct PersistedShape: Codable, Sendable {
        let resolvedURLs: [String: [URL]]
        let lastSuccessful: [String: URL]
        let resolvedAt: [String: Date]
    }

    private func scheduleSave() {
        dirty = true
        // Reuse the in-flight debounce window instead of cancelling + reallocating —
        // a busy inbox refresh fires `scheduleSave()` ~100 times per second and the
        // old cancel-and-recreate pattern produced unbounded Task churn on main.
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            guard self.dirty else { return }
            self.dirty = false
            self.persistOffMain()
        }
    }

    /// Capture an in-memory snapshot on main, hand it off to `diskQueue` for the
    /// expensive JSON encode + atomic write. The trim step still mutates the live
    /// dicts (so the cap is enforced) but only does cheap dictionary work on main.
    private func persistOffMain() {
        // Trim if over cap — drop oldest by resolvedAt timestamp.
        if resolvedURLs.count > Self.maxEntries {
            let sorted = resolvedAt.sorted { $0.value < $1.value }
            let toDrop = sorted.prefix(resolvedURLs.count - Self.maxEntries)
            for (key, _) in toDrop {
                resolvedURLs.removeValue(forKey: key)
                resolvedAt.removeValue(forKey: key)
                lastSuccessful.removeValue(forKey: key)
            }
        }

        let snapshot = makeSnapshot()
        Self.diskQueue.async {
            Self.writeToDisk(snapshot)
        }
    }

    private func makeSnapshot() -> PersistedShape {
        PersistedShape(
            resolvedURLs: resolvedURLs,
            lastSuccessful: lastSuccessful,
            resolvedAt: resolvedAt
        )
    }

    /// Background-queue helpers. Both run off the main thread — never call from main.
    nonisolated private static func readFromDisk() -> PersistedShape? {
        guard let url = Self.cacheFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedShape.self, from: data)
    }

    nonisolated private static func writeToDisk(_ snapshot: PersistedShape) {
        guard let fileURL = Self.cacheFileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}


// MARK: - Downsampling Avatar Image Loader

/// Loads avatar images through the shared `AvatarDiskCache`, downsampling to the
/// display size via ImageIO so we decode a thumbnail-sized bitmap instead of the
/// raw (often 256–512px) source. The previous `AsyncImage` path decoded full-size
/// images on the main thread for every row and bypassed the on-disk image cache
/// entirely (only the URL list was cached). This consolidates both: disk hit →
/// instant decode; miss → fetch, downsample, persist, return.
///
/// Keyed by the **source URL** (matching `CachedAvatarImage`), so a logo cached
/// for one sender is reused for another sender on the same domain.
enum AvatarImageLoader {

    /// In-memory decoded-image cache. Disk gives us the bytes back cheaply, but
    /// re-decoding the same JPEG on every scroll-in still costs CPU; an
    /// `NSCache` of already-decoded `UIImage`s keeps hot rows instant and is
    /// evicted automatically under memory pressure. Keyed by "diskKey@px".
    // nonisolated(unsafe): NSCache is documented thread-safe for concurrent access;
    // the Swift 6 checker can't see that for a non-Sendable Cocoa type.
    private nonisolated(unsafe) static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    /// Returns a downsampled `UIImage` for `url` at `pointSize`, or nil on failure
    /// (caller advances the waterfall). Disk + network + decode all happen off the
    /// main thread inside a detached task; only the cache key math runs on the caller.
    static func load(url: URL, pointSize: CGFloat, scale: CGFloat) async -> UIImage? {
        let maxPixel = max(1, Int((pointSize * scale).rounded()))
        let diskKey = AvatarDiskCache.key(for: url.absoluteString)
        let memoryKey = "\(diskKey)@\(maxPixel)" as NSString

        if let cached = memoryCache.object(forKey: memoryKey) {
            return cached
        }

        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            // 1. Disk hit — decode the persisted (already-small) bytes, downsampling
            //    again defensively in case a legacy full-size blob is present.
            if let data = AvatarDiskCache.read(key: diskKey),
               let downsampled = downsample(data: data, maxPixel: maxPixel) {
                return downsampled
            }

            // 2. Miss — fetch, downsample, persist the downsampled JPEG so future
            //    cold starts (and the legacy `CachedAvatarImage`) stay small.
            guard let (data, response) = try? await URLSession.shared.data(from: url) else {
                return nil
            }
            // Reject obvious non-success HTTP responses so a 404 HTML body isn't
            // decoded into a broken image (the waterfall must advance instead).
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let downsampled = downsample(data: data, maxPixel: maxPixel) else {
                return nil
            }
            // Persist the downsampled bytes (JPEG) rather than the raw source so the
            // on-disk cache stays compact. Quality 0.9 is visually lossless at avatar size.
            if let encoded = downsampled.jpegData(compressionQuality: 0.9) {
                AvatarDiskCache.write(encoded, key: diskKey)
            }
            return downsampled
        }.value

        if let image {
            memoryCache.setObject(image, forKey: memoryKey)
        }
        return image
    }

    /// ImageIO thumbnail downsample — decodes directly to `maxPixel` so we never
    /// inflate a full-size bitmap. `kCGImageSourceCreateThumbnailFromImageAlways`
    /// forces a thumbnail even when the source embeds none.
    private static func downsample(data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Sender Avatar View

/// Displays a sender's avatar with automatic remote resolution and graceful fallbacks.
///
/// Resolution priority:
///   1. Last-known-good URL (memoized per sender across launches)
///   2. Google People API contact photo (if sender is in user's contacts)
///   3. Domain brand favicon/icon (e.g. supabase.com → Supabase logo)
///   4. Additional favicon fallbacks (apple-touch-icon, /favicon.ico, www. variant, DDG)
///   5. Initials + deterministic color circle
///
/// Sub-domain emails (e.g. auth.supabase.com) are resolved to their root domain by the
/// backend, so you still get the Supabase logo even for transactional senders.
///
/// Results are persisted in AvatarCache with TTL — cold starts hit zero network for
/// previously-seen senders.
struct SenderAvatarView: View {
    let email: String
    let name: String
    /// Diameter of the avatar circle. Defaults to 40 (inbox list size).
    var size: CGFloat = 40

    @Environment(AppServices.self) private var services

    /// Index into the snapshotted candidates list. Advances when AsyncImage fails to load a URL,
    /// giving a waterfall effect: try best → next → next → initials.
    @State private var urlIndex: Int = 0
    /// Snapshot of the resolved candidate URLs for the current email. Frozen against
    /// reordering (recordSuccess moves the winner to the front in the cache); only
    /// re-adopted when the list *grows*, so a stable `urlIndex` never points at a
    /// different URL mid-display (which caused avatar flicker).
    @State private var resolvedCandidates: [URL] = []

    var body: some View {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let registrySpec = SenderIconRegistry.icon(for: normalizedEmail)

        if let spec = registrySpec, let slug = spec.slug {
            // Bundled brand icon — instant, zero network, no flash, crisp at any scale.
            // SVG path → brand-color circle + tinted glyph.
            ZStack {
                Circle().fill(spec.background)
                Image("sender-icon-\(slug)")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(spec.foreground)
                    .padding(size * 0.25)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            // Network waterfall — covers both:
            //   • No registry hit → neutral gray initials base layer.
            //   • Letter-only registry hit (slug == nil) → brand-tinted initials base
            //     layer, then the SAME favicon waterfall on top. These senders
            //     (office/azure/monday/beehiiv/…) previously short-circuited to a gray
            //     circle and never tried the network, so they looked worse than unknown
            //     senders. Falling through lets a real favicon win when one exists, with
            //     the brand-colored initial as the graceful base.
            let liveCandidates: [URL] = AvatarCache.shared.candidates(for: normalizedEmail) ?? []
            ZStack {
                initialsCircle(brand: registrySpec)

                if urlIndex < resolvedCandidates.count {
                    let currentURL = resolvedCandidates[urlIndex]
                    // Downsampling, disk-cached loader replaces the raw AsyncImage:
                    // decodes a thumbnail-sized bitmap off-main and reuses the shared
                    // `AvatarDiskCache`. The waterfall is preserved — `onFailure`
                    // advances `urlIndex` exactly as the old `.failure` branch did,
                    // and `onSuccess` records the winner for reorder-on-next-launch.
                    WaterfallAvatarImage(
                        url: currentURL,
                        size: size,
                        isPhoto: Self.isPersonPhoto(currentURL),
                        onSuccess: {
                            AvatarCache.shared.recordSuccess(email: normalizedEmail, url: currentURL)
                        },
                        onFailure: {
                            if urlIndex < resolvedCandidates.count {
                                urlIndex += 1
                            }
                        }
                    )
                    // Keying by URL forces SwiftUI to treat each candidate as a fresh
                    // load so the failure-driven advance fires cleanly per URL.
                    .id(currentURL)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .task(id: normalizedEmail) {
                urlIndex = 0
                // Adopt any already-cached candidates immediately (common path), then
                // resolve and adopt the network result if it added more.
                resolvedCandidates = AvatarCache.shared.candidates(for: normalizedEmail) ?? []
                await AvatarCache.shared.resolveIfNeeded(
                    email: normalizedEmail,
                    name: name,
                    api: services.apiClient
                )
                let resolved = AvatarCache.shared.candidates(for: normalizedEmail) ?? []
                if resolved.count > resolvedCandidates.count {
                    resolvedCandidates = resolved
                }
            }
            .onChange(of: liveCandidates) { _, newCandidates in
                // Adopt the resolved list on first populate or when it grows, but ignore
                // pure reorders (same count) so recordSuccess can't shift urlIndex onto
                // a different URL and cause flicker.
                if newCandidates.count > resolvedCandidates.count {
                    resolvedCandidates = newCandidates
                }
            }
        }
    }

    /// True for real person photos (Google profile photos, Gravatar).
    /// These are rendered full-bleed/fill. All other sources (brand logos, favicons)
    /// are fitted with padding to prevent transparent-edge artifacts.
    private static func isPersonPhoto(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.hasSuffix("googleusercontent.com") || host.hasSuffix("gravatar.com")
    }

    // MARK: - Initials fallback

    /// Initials avatar used as the base layer under the favicon waterfall.
    ///
    /// - `brand == nil` → neutral muted avatar (gray circle + white initials),
    ///   matching Notion Mail's restrained style for unknown senders.
    /// - `brand != nil` (a letter-only registry hit) → brand-tinted circle + glyph,
    ///   so senders like office/azure/monday read as their brand color while the
    ///   favicon waterfall loads on top (and replaces it if a real logo resolves).
    private func initialsCircle(brand: SenderIconSpec? = nil) -> some View {
        let background = brand?.background ?? Color(UIColor.systemGray2)
        let foreground = brand?.foreground ?? .white
        return Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
    }

    /// Up to two initials extracted from the display name, or a single letter from the email.
    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        let base = name.isEmpty ? email : name
        // Skip non-alphabetic prefixes (e.g. email addresses starting with a digit)
        if let first = base.first(where: { $0.isLetter }) {
            return String(first).uppercased()
        }
        return "?"
    }

}

// MARK: - Waterfall Avatar Image

/// Renders a single candidate URL through `AvatarImageLoader` (downsampling +
/// disk cache). Reports success/failure to the parent so the existing waterfall
/// (advance `urlIndex` on failure) and last-known-good memoization keep working
/// unchanged. While loading, renders nothing — the initials base layer shows
/// through, matching the old `.empty`/`.failure` (Color.clear) behaviour.
///
/// The person-photo-vs-brand-logo treatment is identical to the previous
/// `AsyncImage` path: photos fill edge-to-edge; brand logos sit on a white
/// circle with padding so dark/monochrome logos stay visible in dark mode.
private struct WaterfallAvatarImage: View {
    let url: URL
    let size: CGFloat
    let isPhoto: Bool
    let onSuccess: () -> Void
    let onFailure: () -> Void

    @State private var image: UIImage?
    /// Guards against double-firing the failure callback if the task re-runs.
    @State private var didReport = false

    var body: some View {
        Group {
            if let image {
                ZStack {
                    Circle().fill(isPhoto ? Color.clear : Color.white)
                    if isPhoto {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(size * 0.16)
                    }
                }
                .transition(.opacity)
            } else {
                // Loading or failed — show nothing; the initials base layer is visible.
                Color.clear
            }
        }
        .task(id: url) {
            // Reset for a fresh URL (the parent keys this view by URL via `.id`,
            // but `.task(id:)` is the canonical place to re-arm).
            didReport = false
            // `.task` runs on the main actor; `UIScreen.main.scale` is read directly
            // here (same access pattern as `SheetPresentationChrome`).
            let scale = UIScreen.main.scale
            let loaded = await AvatarImageLoader.load(url: url, pointSize: size, scale: scale)
            guard !Task.isCancelled else { return }
            if let loaded {
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
                if !didReport { didReport = true; onSuccess() }
            } else {
                if !didReport { didReport = true; onFailure() }
            }
        }
    }
}
