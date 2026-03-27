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

/// In-memory cache for resolved sender avatar URLs.
///
/// @Observable ensures SwiftUI views re-render automatically when a new cache entry
/// arrives — the view transitions from initials → real avatar without any manual signaling.
@MainActor
@Observable
final class AvatarCache {
    static let shared = AvatarCache()

    // email → ordered list of image URLs to try, best source first
    var resolvedURLs: [String: [URL]] = [:]

    // Tracks in-progress fetches so concurrent rows for the same sender don't double-fetch
    private var inFlight: Set<String> = []

    private init() {}

    /// Returns cached candidate URLs for an email, or nil if not yet resolved.
    func candidates(for email: String) -> [URL]? {
        resolvedURLs[normalizedEmail(email)]
    }

    /// Fetches and caches avatar URLs for the given sender if not already resolved.
    /// Deduplicates concurrent calls for the same email address.
    func resolveIfNeeded(email: String, name: String, api: TodosAPIClient) async {
        let normalized = normalizedEmail(email)
        guard resolvedURLs[normalized] == nil, !inFlight.contains(normalized) else { return }
        inFlight.insert(normalized)
        defer { inFlight.remove(normalized) }

        let urls = await fetchCandidateURLs(email: normalized, name: name, api: api)
        // Even an empty list is stored so we don't retry failed lookups on every render
        resolvedURLs[normalized] = urls
    }

    // MARK: - Backend fetch

    private func fetchCandidateURLs(email: String, name: String, api: TodosAPIClient) async -> [URL] {
        var urls: [URL] = []

        do {
            let input = AvatarInput(email: email, name: name.isEmpty ? nil : name)
            let response: AvatarResponse = try await api.trpcQuery("avatar.getByEmail", input: input)

            // Primary source first (best quality) — skip BIMI SVGs (iOS has no native SVG renderer)
            if let primary = response.primary,
               primary.source != "bimi",
               let urlStr = primary.url,
               let url = URL(string: urlStr),
               !urls.contains(url) {
                urls.append(url)
            }

            // Backend-resolved fallbacks (domain favicon, apple-touch-icon, etc.)
            for urlStr in response.fallbackUrls {
                if let url = URL(string: urlStr), !urls.contains(url) {
                    urls.append(url)
                }
            }
        } catch {
            // Backend failed — fall through to local fallbacks below.
        }

        // Local deterministic domain-based fallbacks come after backend URLs so higher-quality
        // backend-resolved images are tried first, but we always have local fallbacks as a safety net.
        for fallback in localFallbackURLs(email: email) {
            if !urls.contains(fallback) {
                urls.append(fallback)
            }
        }

        return urls
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Includes root-domain and subdomain variants to improve hit rate on transactional domains.
    private func localFallbackURLs(email: String) -> [URL] {
        guard let domain = domainFromEmail(email), !domain.isEmpty else { return [] }

        var hostCandidates: [String] = [domain]
        if let root = rootDomain(from: domain), root != domain {
            hostCandidates.append(root)
        }

        for host in Array(hostCandidates) {
            if !host.hasPrefix("www.") {
                hostCandidates.append("www.\(host)")
            }
        }

        var candidates: [URL] = []
        for host in hostCandidates {
            let rawURLs = [
                "https://\(host)/favicon.ico",
                "https://\(host)/apple-touch-icon.png",
                "https://icons.duckduckgo.com/ip3/\(host).ico",
                "https://www.google.com/s2/favicons?domain=\(host)&sz=128"
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

    // Best-effort root domain extraction with common multi-part TLD handling.
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
///   1. Google People API contact photo (if sender is in user's contacts)
///   2. Domain brand favicon/icon (e.g. supabase.com → Supabase logo)
///   3. Additional favicon fallbacks (apple-touch-icon, /favicon.ico, www. variant, etc.)
///   4. Initials + deterministic color circle
///
/// Sub-domain emails (e.g. auth.supabase.com) are resolved to their root domain by the
/// backend, so you still get the Supabase logo even for transactional senders.
///
/// Results are stored in AvatarCache for the session lifetime to avoid repeated API calls.
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
        // Direct property access on @Observable triggers re-render when cache is populated
        let candidates: [URL] = AvatarCache.shared.resolvedURLs[normalizedEmail] ?? []

        ZStack {
            initialsCircle

            if urlIndex < candidates.count {
                AsyncImage(url: candidates[urlIndex]) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        // Keep initials visible while moving to the next URL.
                        // Use .onAppear instead of .task to avoid re-running on identity changes
                        // which could cause infinite loops when the view re-renders.
                        initialsCircle
                            .onAppear { urlIndex += 1 }
                    case .empty:
                        // Still loading — keep initials visible to avoid blank cells.
                        initialsCircle
                    @unknown default:
                        initialsCircle
                    }
                }
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
            .blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan, .brown, .green
        ]
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let seed = !normalized.isEmpty ? normalized : name
        let idx = StableAvatarColorIndex.index(seed: seed, paletteCount: colors.count)
        return colors[idx]
    }
}
