import SwiftUI

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
@MainActor
@Observable
final class AvatarCache {
    static let shared = AvatarCache()

    /// email → ordered list of image URLs to try, best source first.
    /// Reading this property triggers a SwiftUI re-render when it changes.
    var resolvedURLs: [String: [URL]] = [:]

    /// email → URL that successfully rendered last time. Tried first on next render so
    /// repeat displays skip the failing prefix of the candidate list.
    private var lastSuccessful: [String: URL] = [:]

    /// email → when this entry was resolved. Used to apply TTL.
    private var resolvedAt: [String: Date] = [:]

    /// Tracks in-progress fetches so concurrent rows for the same sender don't double-fetch.
    private var inFlight: Set<String> = []

    /// Successful resolutions stick around for 30 days. Long enough to survive vacation;
    /// short enough that brand logo refreshes propagate.
    private static let successTTL: TimeInterval = 60 * 60 * 24 * 30

    /// Empty/failed resolutions are retried after 5 minutes. Without this, a single
    /// transient backend failure would leave the avatar permanently absent for the session.
    private static let emptyTTL: TimeInterval = 60 * 5

    /// Cap on disk entries — avoids unbounded growth for users who burn through inbox.
    private static let maxEntries = 5000

    /// Debounced disk write — coalesces rapid updates (e.g. 50 row appearances on inbox load).
    private var saveTask: Task<Void, Never>?

    private static let cacheFileURL: URL? = {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("sender-avatar-cache.json")
    }()

    private init() {
        loadFromDisk()
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
        persistToDisk()
    }

    // MARK: - Backend fetch

    private func fetchCandidateURLs(email: String, name: String, api: TodosAPIClient) async -> [URL] {
        var urls: [URL] = []

        do {
            let input = AvatarInput(email: email, name: name.isEmpty ? nil : name)
            let response: AvatarResponse = try await api.trpcQuery("avatar.getByEmail", input: input)

            // Primary source first (best quality) — skip BIMI SVGs (iOS has no native SVG renderer).
            if let primary = response.primary,
               primary.source != "bimi",
               let urlStr = primary.url,
               let url = URL(string: urlStr),
               !urls.contains(url) {
                urls.append(url)
            }

            for urlStr in response.fallbackUrls {
                if let url = URL(string: urlStr), !urls.contains(url) {
                    urls.append(url)
                }
            }
        } catch {
            // Backend failure → fall through to local fallbacks below. The empty-TTL
            // ensures we'll retry the backend in 5 minutes rather than waiting for restart.
        }

        // Local deterministic fallbacks always appended — Google's s2 favicon service has
        // near-100% coverage for any real domain, so the chain almost always resolves.
        for fallback in localFallbackURLs(email: email) where !urls.contains(fallback) {
            urls.append(fallback)
        }

        return urls
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Includes root-domain and `www.` variants to improve hit rate on transactional senders.
    private func localFallbackURLs(email: String) -> [URL] {
        guard let domain = domainFromEmail(email), !domain.isEmpty else { return [] }

        var hostCandidates: [String] = [domain]
        if let root = rootDomain(from: domain), root != domain {
            hostCandidates.append(root)
        }

        for host in Array(hostCandidates) where !host.hasPrefix("www.") {
            hostCandidates.append("www.\(host)")
        }

        var candidates: [URL] = []
        // Google's favicon service has the best coverage (same source Gmail uses), so we
        // prioritize it. apple-touch-icon (higher-res) next, then standard fallbacks.
        for host in hostCandidates {
            let rawURLs = [
                "https://www.google.com/s2/favicons?domain=\(host)&sz=128",
                "https://\(host)/apple-touch-icon.png",
                "https://\(host)/favicon.ico",
                "https://icons.duckduckgo.com/ip3/\(host).ico"
            ]
            for raw in rawURLs {
                if let url = URL(string: raw), !candidates.contains(url) {
                    candidates.append(url)
                }
            }
        }

        return candidates
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

    private struct PersistedShape: Codable {
        let resolvedURLs: [String: [URL]]
        let lastSuccessful: [String: URL]
        let resolvedAt: [String: Date]
    }

    private func loadFromDisk() {
        guard let url = Self.cacheFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistedShape.self, from: data) else {
            return
        }

        // Drop expired entries on load — keeps the in-memory state honest from the start.
        let now = Date()
        var validURLs: [String: [URL]] = [:]
        var validAt: [String: Date] = [:]
        for (email, when) in decoded.resolvedAt {
            let urls = decoded.resolvedURLs[email] ?? []
            let ttl = urls.isEmpty ? Self.emptyTTL : Self.successTTL
            if now.timeIntervalSince(when) < ttl {
                validURLs[email] = urls
                validAt[email] = when
            }
        }
        self.resolvedURLs = validURLs
        self.resolvedAt = validAt
        self.lastSuccessful = decoded.lastSuccessful.filter { validURLs[$0.key] != nil }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            // Coalesce rapid successive writes into a single disk hit.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.persistToDisk()
        }
    }

    private func persistToDisk() {
        guard let fileURL = Self.cacheFileURL else { return }

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

        let snapshot = PersistedShape(
            resolvedURLs: resolvedURLs,
            lastSuccessful: lastSuccessful,
            resolvedAt: resolvedAt
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - Stable avatar color index (matches web `getAvatarColorIndex`)

/// Same algorithm as `getAvatarColorIndex` in `apps/mail/components/ui/bimi-avatar.tsx`.
/// Uses UTF-16 code units (JS `charCodeAt`) and JavaScript `<<` / `ToInt32` semantics — **not**
/// `String.hashValue`, which is unstable across launches and OS versions.
private enum StableAvatarColorIndex {
    static func index(seed: String, paletteCount: Int) -> Int {
        precondition(paletteCount > 0, "paletteCount must be positive")
        var hash: Double = 0
        for unit in seed.utf16 {
            let c = Double(unit)
            let h32 = Int32(truncatingIfNeeded: Int64(hash))
            let left = h32 &<< 5
            let sub = Double(left) - hash
            hash = c + sub
        }
        let mag = abs(Int64(hash)) % Int64(paletteCount)
        return Int(mag)
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

    /// Index into the current candidates list. Advances when AsyncImage fails to load a URL,
    /// giving a waterfall effect: try best → next → next → initials.
    @State private var urlIndex: Int = 0

    var body: some View {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Direct property access on @Observable triggers re-render when cache is populated.
        // Use `candidates(for:)` to apply last-successful reordering.
        let candidates: [URL] = AvatarCache.shared.candidates(for: normalizedEmail) ?? []

        // Initials always render as the base layer. The actual avatar image fades in on top
        // when it loads — eliminates the initials-then-avatar pop-in that happens with a
        // bare AsyncImage swap. The user only ever sees a smooth fade.
        ZStack {
            initialsCircle

            if urlIndex < candidates.count {
                let currentURL = candidates[urlIndex]
                AsyncImage(url: currentURL, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack {
                            // White backdrop keeps transparent brand logos legible.
                            Circle().fill(Color.white)
                            image
                                .resizable()
                                .scaledToFill()
                        }
                        .transition(.opacity)
                        .onAppear {
                            AvatarCache.shared.recordSuccess(email: normalizedEmail, url: currentURL)
                        }
                    case .failure:
                        // Transparent placeholder while we advance to the next candidate.
                        // Initials remain visible underneath via the ZStack base layer.
                        Color.clear
                            .onAppear {
                                if urlIndex < candidates.count {
                                    urlIndex += 1
                                }
                            }
                    case .empty:
                        // Still loading — initials are already visible underneath, so render
                        // a transparent placeholder rather than re-stacking initials.
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                // Keying by URL forces SwiftUI to treat each candidate as a fresh AsyncImage,
                // so the .empty → .success/.failure transition fires cleanly per URL and the
                // failure-driven .onAppear isn't suppressed by view-identity reuse.
                .id(currentURL)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: normalizedEmail) {
            // Reset index when email changes (e.g. the same list cell is reused for a new sender)
            urlIndex = 0
            await AvatarCache.shared.resolveIfNeeded(
                email: normalizedEmail,
                name: name,
                api: services.apiClient
            )
        }
        .onChange(of: candidates.count) { _, newCount in
            // If candidates arrive (or refresh) after we exhausted the previous list,
            // restart the waterfall so we don't stay stuck on initials.
            if urlIndex >= newCount && newCount > 0 {
                urlIndex = 0
            }
        }
    }

    // MARK: - Initials fallback

    private var initialsCircle: some View {
        Text(initials)
            .font(.system(size: size * 0.325, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarColor, in: Circle())
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

    /// Deterministic color derived from the sender email (stable across name changes and app
    /// launches). Uses the same string hash as `BimiAvatar` on web — not `String.hashValue`.
    private var avatarColor: Color {
        let colors: [Color] = [
            .brown, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan, .gray, .green
        ]
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let seed = !normalized.isEmpty ? normalized : name
        let idx = StableAvatarColorIndex.index(seed: seed, paletteCount: colors.count)
        return colors[idx]
    }
}
