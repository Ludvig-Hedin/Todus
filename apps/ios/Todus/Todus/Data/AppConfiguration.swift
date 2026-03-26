import Foundation

struct AppConfiguration: Sendable {
    /// The unified backend URL (Cloudflare Workers with Better-Auth + TRPC)
    let backendURL: URL?

    // Legacy Supabase fields — kept for backward compatibility during migration
    let supabaseURL: URL?
    let supabaseAnonKey: String
    let parseFunctionPath: String
    let syncFunctionPath: String
    let upgradeFunctionPath: String
    let chatFunctionPath: String
    let primaryModel: String
    let fallbackModels: [String]

    /// Whether to use the local dev backend (http://localhost:8787) instead of production.
    /// Set via TodosConfig.plist USE_LOCAL_BACKEND = true, or toggle in Settings → Developer.
    /// When enabled, the app talks to your local Wrangler dev server for hot reload during development.
    static var useLocalBackend: Bool {
        get { UserDefaults.standard.bool(forKey: "Todus.useLocalBackend") }
        set { UserDefaults.standard.set(newValue, forKey: "Todus.useLocalBackend") }
    }

    /// Returns the effective backend URL, respecting the local dev override
    var effectiveBackendURL: URL {
        if AppConfiguration.useLocalBackend {
            return URL(string: "http://localhost:8787")!
        }
        return backendURL ?? URL(string: "https://api.todus.app")!
    }

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        // Try new TodosConfig.plist first, fall back to TaskAppConfig.plist
        let url = bundle.url(forResource: "TodosConfig", withExtension: "plist")
            ?? bundle.url(forResource: "TaskAppConfig", withExtension: "plist")

        guard
            let url,
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return .defaults
        }

        let backendURL = (plist["BACKEND_URL"] as? String).flatMap(URL.init(string:))
        let supabaseURL = (plist["SUPABASE_URL"] as? String).flatMap(URL.init(string:))
        let anonKey = plist["SUPABASE_ANON_KEY"] as? String ?? ""
        let parsePath = plist["PARSE_FUNCTION_PATH"] as? String ?? "parseTasks"
        let syncPath = plist["SYNC_FUNCTION_PATH"] as? String ?? "syncTasks"
        let upgradePath = plist["UPGRADE_FUNCTION_PATH"] as? String ?? "upgradeAnonymousUser"
        let chatPath = plist["CHAT_FUNCTION_PATH"] as? String ?? "chatAI"
        let primaryModel = plist["PRIMARY_MODEL"] as? String ?? "openai/gpt-5.4-mini"
        let fallbacks = (plist["FALLBACK_MODELS"] as? String ?? "google/gemini-3-flash-preview,openai/gpt-5.4-chat,moonshotai/kimi-k2.5,anthropic/claude-haiku-4-5")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return AppConfiguration(
            backendURL: backendURL,
            supabaseURL: supabaseURL,
            supabaseAnonKey: anonKey,
            parseFunctionPath: parsePath,
            syncFunctionPath: syncPath,
            upgradeFunctionPath: upgradePath,
            chatFunctionPath: chatPath,
            primaryModel: primaryModel,
            fallbackModels: fallbacks
        )
    }

    static let defaults = AppConfiguration(
        backendURL: URL(string: "https://api.todus.app"),
        supabaseURL: nil,
        supabaseAnonKey: "",
        parseFunctionPath: "parseTasks",
        syncFunctionPath: "syncTasks",
        upgradeFunctionPath: "upgradeAnonymousUser",
        chatFunctionPath: "chatAI",
        primaryModel: "openai/gpt-5.4-mini",
        fallbackModels: [
            "google/gemini-3-flash-preview",
            "openai/gpt-5.4-chat",
            "moonshotai/kimi-k2.5",
            "anthropic/claude-haiku-4-5"
        ]
    )

    var hasRemoteBackend: Bool {
        backendURL != nil
    }

    /// Legacy check for Supabase connectivity
    var hasSupabaseBackend: Bool {
        supabaseURL != nil && !supabaseAnonKey.isEmpty
    }

    var preferredModels: [String] {
        [primaryModel] + fallbackModels
    }
}
