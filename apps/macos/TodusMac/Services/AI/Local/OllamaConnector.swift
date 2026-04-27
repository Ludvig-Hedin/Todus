import Foundation
import Observation
import OSLog

// MARK: - OllamaConnector
//
// macOS-only. Detects a running Ollama daemon at `localhost:11434`, lists the
// models the user has already pulled, and exposes them in the Local Models UI
// as a separate "Connected (Ollama)" section. The connector itself does not
// run inference — that's `OllamaInferenceService`. It just answers two
// questions for the rest of the app:
//
//   • Is Ollama running on this Mac right now?
//   • What models has the user pulled?
//
// The probe runs on a 1-second timeout so a missing daemon never delays UI.

struct OllamaInstalledModel: Identifiable, Hashable {
    /// Ollama tag (e.g. "llama3.2:3b"). Used as both id and as the model id
    /// passed to `/api/chat`.
    let id: String
    let displayName: String
    let sizeBytes: Int64
    let modifiedAt: Date?

    /// Best-effort mapping of an Ollama tag back to a curated catalog entry,
    /// so the UI can render a familiar display name + description when the
    /// tag matches what we ship in `LocalModelCatalog`. Returns nil for
    /// custom-pulled models we don't know about.
    var curatedModel: LocalModel? {
        LocalModelCatalog.match(modelString: id)
    }
}

@MainActor
@Observable
final class OllamaConnector {
    /// True once the latest probe succeeded. Drives the visibility of the
    /// "Connected (Ollama)" section in `MacLocalModelsView`.
    private(set) var isReachable: Bool = false

    /// Models the daemon currently lists via `GET /api/tags`. Sorted by
    /// modifiedAt descending so the most recently used model lands at the top.
    private(set) var installedModels: [OllamaInstalledModel] = []

    /// Last probe error message — surfaced as a footer on the Local Models
    /// screen if the user expected Ollama to be running but it isn't.
    private(set) var lastError: String?

    /// User-configurable base URL. Defaults to the standard Ollama install
    /// location; persisted in UserDefaults so power users can point at a
    /// remote daemon (e.g. a beefier home server) if they want to.
    var baseURL: URL {
        get {
            if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
               let url = URL(string: raw) {
                return url
            }
            return URL(string: "http://localhost:11434")!
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: Self.defaultsKey)
        }
    }

    private static let defaultsKey = "mac_ollama_base_url"
    private let log = Logger(subsystem: "com.todus.macos", category: "OllamaConnector")
    private var probeTask: Task<Void, Never>?

    init() {
        // Kick off an initial probe — fire-and-forget. The UI re-renders
        // when `isReachable` flips, so there's no need for the caller to await.
        refresh()
    }

    /// Trigger a fresh probe + tag fetch. Cancels any in-flight probe so back-
    /// to-back calls (e.g. on settings open) don't pile up.
    func refresh() {
        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            await self?.probeNow()
        }
    }

    private func probeNow() async {
        let url = baseURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        req.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                isReachable = false
                lastError = "Ollama responded with an unexpected status."
                installedModels = []
                return
            }

            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            installedModels = decoded.models
                .map { tag in
                    OllamaInstalledModel(
                        id: tag.name,
                        displayName: humanize(tag.name),
                        sizeBytes: tag.size ?? 0,
                        modifiedAt: tag.modifiedAt
                    )
                }
                .sorted { (a, b) in
                    // Most-recently-used first; nil dates fall to the back.
                    switch (a.modifiedAt, b.modifiedAt) {
                    case let (lhs?, rhs?): return lhs > rhs
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return a.displayName < b.displayName
                    }
                }
            isReachable = true
            lastError = nil
        } catch {
            isReachable = false
            lastError = (error as? URLError)?.code == .cannotConnectToHost
                ? "Ollama isn't running on this Mac."
                : error.localizedDescription
            installedModels = []
        }
    }

    /// Friendlier display name. We keep the tag as the canonical id but turn
    /// "llama3.2:3b" → "Llama 3.2 3B" when we recognize the family.
    private func humanize(_ tag: String) -> String {
        if let curated = LocalModelCatalog.match(modelString: tag) {
            return curated.displayName
        }
        return tag
    }

    // MARK: - Decoding

    private struct TagsResponse: Decodable {
        let models: [Tag]
    }

    private struct Tag: Decodable {
        let name: String
        let size: Int64?
        let modifiedAt: Date?

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case modifiedAt = "modified_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try c.decode(String.self, forKey: .name)
            self.size = try c.decodeIfPresent(Int64.self, forKey: .size)
            // Ollama returns RFC 3339 timestamps. ISO8601DateFormatter handles
            // both with-and-without fractional seconds in iOS 16+/macOS 13+.
            if let raw = try c.decodeIfPresent(String.self, forKey: .modifiedAt) {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                self.modifiedAt = f.date(from: raw)
                    ?? ISO8601DateFormatter().date(from: raw)
            } else {
                self.modifiedAt = nil
            }
        }
    }
}
