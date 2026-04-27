import Foundation

// MARK: - LocalModelCatalog
//
// Curated catalog of on-device AI models surfaced in Settings → Local Models.
// Pure data — no SwiftUI / UIKit / AppKit imports so this file is identical
// between the iOS and macOS apps. Keep both copies in sync until the catalog
// is extracted into the planned `packages/swift-localai` SPM package.
//
// All models run entirely on the user's device and never call /api/ai/chat,
// which is what makes the "no plan credits used" guarantee architectural.

enum LocalModelFamily: String, Codable, Hashable {
    case llama
    case qwen
    case gemma
    case ministral
    case phi
    case appleFM
}

enum LocalModelRuntime: String, Codable, Hashable {
    /// MLX Swift loading quantized weights from HuggingFace mlx-community.
    case mlx
    /// Apple Foundation Models (Apple Intelligence) — built into the OS, no download.
    case appleFM
    /// User's locally-running Ollama daemon (macOS only).
    case ollama
}

enum LocalModelPlatform: String, Codable, Hashable {
    case iOS
    case macOS
}

enum LocalModelCapability: String, Codable, Hashable {
    case chat
    case summarize
    case draft
    case reason
    case code
}

struct LocalModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let family: LocalModelFamily
    let parameters: String
    let tagline: String
    let description: String
    let strengths: [String]
    let runtime: LocalModelRuntime
    /// HuggingFace repo (org/name) for MLX-runtime models.
    let mlxRepo: String?
    /// Tag for Ollama-runtime models (macOS only). Used to call `localhost:11434/api/pull`.
    let ollamaTag: String?
    let downloadSizeMB: Int
    let ramRequiredGB: Double
    let platforms: Set<LocalModelPlatform>
    let supportsToolUse: Bool
    let goodFor: [LocalModelCapability]
    /// License short name shown in the detail sheet (e.g. "Apache 2.0", "Llama 3 Community").
    let license: String
}

enum LocalModelCatalog {
    // MARK: - Apple Foundation Models (zero-download)

    static let appleIntelligence = LocalModel(
        id: "apple-foundation",
        displayName: "Apple Intelligence",
        family: .appleFM,
        parameters: "~3B",
        tagline: "Built into your device. Zero download.",
        description: "Apple's on-device language model, available on iOS 26+ and macOS 26+ when Apple Intelligence is enabled. Tuned for short replies, drafting, and summarization.",
        strengths: ["Fastest start-up", "Always available", "Zero download"],
        runtime: .appleFM,
        mlxRepo: nil,
        ollamaTag: nil,
        downloadSizeMB: 0,
        ramRequiredGB: 0,
        platforms: [.iOS, .macOS],
        supportsToolUse: false,
        goodFor: [.chat, .summarize, .draft],
        license: "Apple"
    )

    // MARK: - Llama 3.2

    static let llama3_2_1B = LocalModel(
        id: "llama-3.2-1b",
        displayName: "Llama 3.2 1B",
        family: .llama,
        parameters: "1B",
        tagline: "Tiny and fast. Great for quick replies.",
        description: "Meta's smallest Llama 3.2 instruction-tuned model. Runs comfortably on any modern iPhone or iPad.",
        strengths: ["Smallest download", "Fastest tokens"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
        ollamaTag: "llama3.2:1b",
        downloadSizeMB: 700,
        ramRequiredGB: 1.5,
        platforms: [.iOS, .macOS],
        supportsToolUse: false,
        goodFor: [.chat, .summarize],
        license: "Llama 3.2 Community"
    )

    static let llama3_2_3B = LocalModel(
        id: "llama-3.2-3b",
        displayName: "Llama 3.2 3B",
        family: .llama,
        parameters: "3B",
        tagline: "Balanced quality and speed.",
        description: "Meta's mid-size Llama 3.2 instruction-tuned model. A solid all-rounder for chat, drafting, and short summaries.",
        strengths: ["Balanced quality", "Reasonable size"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        ollamaTag: "llama3.2:3b",
        downloadSizeMB: 1800,
        ramRequiredGB: 3.0,
        platforms: [.iOS, .macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft],
        license: "Llama 3.2 Community"
    )

    // MARK: - Qwen 3

    static let qwen3_0_6B = LocalModel(
        id: "qwen-3-0.6b",
        displayName: "Qwen 3 0.6B",
        family: .qwen,
        parameters: "0.6B",
        tagline: "Smallest in the catalog. Lightning fast.",
        description: "Alibaba's tiniest Qwen 3 model. Best when you need instant replies on a small device.",
        strengths: ["Tiniest download", "Lowest RAM"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Qwen3-0.6B-4bit",
        ollamaTag: "qwen3:0.6b",
        downloadSizeMB: 400,
        ramRequiredGB: 1.0,
        platforms: [.iOS, .macOS],
        supportsToolUse: false,
        goodFor: [.chat],
        license: "Apache 2.0"
    )

    static let qwen3_1_7B = LocalModel(
        id: "qwen-3-1.7b",
        displayName: "Qwen 3 1.7B",
        family: .qwen,
        parameters: "1.7B",
        tagline: "Great default for most iPhones.",
        description: "A strong all-rounder at a small size. Works well for chat, summaries, and short drafts on most modern phones.",
        strengths: ["Strong reasoning for its size", "Fits on most phones"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Qwen3-1.7B-4bit",
        ollamaTag: "qwen3:1.7b",
        downloadSizeMB: 1100,
        ramRequiredGB: 2.0,
        platforms: [.iOS, .macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft],
        license: "Apache 2.0"
    )

    static let qwen3_4B = LocalModel(
        id: "qwen-3-4b",
        displayName: "Qwen 3 4B",
        family: .qwen,
        parameters: "4B",
        tagline: "Sweet spot for newer iPhones and Macs.",
        description: "Noticeably smarter than the smaller models, while still fast on iPhone 15 Pro / 16 and any Apple Silicon Mac.",
        strengths: ["Strong reasoning", "Good tool-use"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Qwen3-4B-4bit",
        ollamaTag: "qwen3:4b",
        downloadSizeMB: 2500,
        ramRequiredGB: 4.5,
        platforms: [.iOS, .macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft, .reason],
        license: "Apache 2.0"
    )

    static let qwen3_8B = LocalModel(
        id: "qwen-3-8b",
        displayName: "Qwen 3 8B",
        family: .qwen,
        parameters: "8B",
        tagline: "Mac-grade quality on Apple Silicon.",
        description: "A high-quality general-purpose model for Macs with 16 GB+ unified memory.",
        strengths: ["High-quality replies", "Reliable tool-use"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Qwen3-8B-4bit",
        ollamaTag: "qwen3:8b",
        downloadSizeMB: 5000,
        ramRequiredGB: 8.0,
        platforms: [.macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft, .reason, .code],
        license: "Apache 2.0"
    )

    static let qwen3_14B = LocalModel(
        id: "qwen-3-14b",
        displayName: "Qwen 3 14B",
        family: .qwen,
        parameters: "14B",
        tagline: "Heavy hitter for serious local work.",
        description: "Excellent reasoning and code quality. Recommended on Macs with 16 GB+ unified memory.",
        strengths: ["Strong reasoning", "Strong coding"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Qwen3-14B-4bit",
        ollamaTag: "qwen3:14b",
        downloadSizeMB: 9000,
        ramRequiredGB: 14.0,
        platforms: [.macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft, .reason, .code],
        license: "Apache 2.0"
    )

    static let qwen3_32B = LocalModel(
        id: "qwen-3-32b",
        displayName: "Qwen 3 32B",
        family: .qwen,
        parameters: "32B",
        tagline: "Top-tier local quality. 32 GB+ recommended.",
        description: "Comparable in quality to many cloud models. Needs an Apple Silicon Mac with at least 32 GB of unified memory.",
        strengths: ["Top-tier local quality"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Qwen3-32B-4bit",
        ollamaTag: "qwen3:32b",
        downloadSizeMB: 20000,
        ramRequiredGB: 28.0,
        platforms: [.macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft, .reason, .code],
        license: "Apache 2.0"
    )

    // MARK: - Gemma 3

    static let gemma3_1B = LocalModel(
        id: "gemma-3-1b",
        displayName: "Gemma 3 1B",
        family: .gemma,
        parameters: "1B",
        tagline: "Google's tiny multilingual model.",
        description: "Strong multilingual performance for its size. Fits on every modern iPhone and iPad.",
        strengths: ["Multilingual", "Compact"],
        runtime: .mlx,
        mlxRepo: "mlx-community/gemma-3-1b-it-4bit",
        ollamaTag: "gemma3:1b",
        downloadSizeMB: 700,
        ramRequiredGB: 1.5,
        platforms: [.iOS, .macOS],
        supportsToolUse: false,
        goodFor: [.chat, .summarize],
        license: "Gemma Terms"
    )

    static let gemma3_4B = LocalModel(
        id: "gemma-3-4b",
        displayName: "Gemma 3 4B",
        family: .gemma,
        parameters: "4B",
        tagline: "Polished writing. Works on iPhone 15 Pro+.",
        description: "Google's mid-size Gemma 3, tuned for instruction following and multilingual chat.",
        strengths: ["Polished tone", "Multilingual"],
        runtime: .mlx,
        mlxRepo: "mlx-community/gemma-3-4b-it-4bit",
        ollamaTag: "gemma3:4b",
        downloadSizeMB: 2500,
        ramRequiredGB: 4.5,
        platforms: [.iOS, .macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft],
        license: "Gemma Terms"
    )

    static let gemma3_12B = LocalModel(
        id: "gemma-3-12b",
        displayName: "Gemma 3 12B",
        family: .gemma,
        parameters: "12B",
        tagline: "Strong all-rounder for 16 GB Macs.",
        description: "A high-quality general-purpose model. Recommended for Macs with 16 GB+ of unified memory.",
        strengths: ["Quality writing", "Multilingual"],
        runtime: .mlx,
        mlxRepo: "mlx-community/gemma-3-12b-it-4bit",
        ollamaTag: "gemma3:12b",
        downloadSizeMB: 7000,
        ramRequiredGB: 12.0,
        platforms: [.macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft, .reason],
        license: "Gemma Terms"
    )

    static let gemma3_27B = LocalModel(
        id: "gemma-3-27b",
        displayName: "Gemma 3 27B",
        family: .gemma,
        parameters: "27B",
        tagline: "Heavy-duty quality on a high-RAM Mac.",
        description: "Top-end Gemma 3. Recommended on Macs with 32 GB+ of unified memory.",
        strengths: ["High-quality replies", "Strong reasoning"],
        runtime: .mlx,
        mlxRepo: "mlx-community/gemma-3-27b-it-4bit",
        ollamaTag: "gemma3:27b",
        downloadSizeMB: 17000,
        ramRequiredGB: 22.0,
        platforms: [.macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft, .reason, .code],
        license: "Gemma Terms"
    )

    // MARK: - Ministral

    static let ministral_3B = LocalModel(
        id: "ministral-3b",
        displayName: "Ministral 3B",
        family: .ministral,
        parameters: "3B",
        tagline: "Mistral's compact 3B. Friendly default.",
        description: "Mistral's small instruction-tuned model. Good balance of size and quality for everyday chat.",
        strengths: ["Friendly tone", "Reasonable size"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Ministral-3B-Instruct-2410-4bit",
        ollamaTag: "ministral:3b",
        downloadSizeMB: 1800,
        ramRequiredGB: 3.0,
        platforms: [.iOS, .macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft],
        license: "Mistral Research"
    )

    static let ministral_8B = LocalModel(
        id: "ministral-8b",
        displayName: "Ministral 8B",
        family: .ministral,
        parameters: "8B",
        tagline: "Mistral 8B for Macs that can take it.",
        description: "Mistral's mid-size instruction-tuned model. A strong general assistant on Apple Silicon.",
        strengths: ["Strong reasoning", "Strong drafting"],
        runtime: .mlx,
        mlxRepo: "mlx-community/Ministral-8B-Instruct-2410-4bit",
        ollamaTag: "ministral:8b",
        downloadSizeMB: 5000,
        ramRequiredGB: 8.0,
        platforms: [.macOS],
        supportsToolUse: true,
        goodFor: [.chat, .summarize, .draft, .reason],
        license: "Mistral Research"
    )

    // MARK: - All

    /// Canonical ordered list of every model the app surfaces. Order matters
    /// for the catalog UI: tinier / cheaper variants first inside each family.
    static let all: [LocalModel] = [
        appleIntelligence,
        // Llama
        llama3_2_1B,
        llama3_2_3B,
        // Qwen
        qwen3_0_6B,
        qwen3_1_7B,
        qwen3_4B,
        qwen3_8B,
        qwen3_14B,
        qwen3_32B,
        // Gemma
        gemma3_1B,
        gemma3_4B,
        gemma3_12B,
        gemma3_27B,
        // Ministral
        ministral_3B,
        ministral_8B,
    ]

    // MARK: - Lookup helpers

    /// Returns the curated list filtered to models that can run on `platform`.
    static func available(on platform: LocalModelPlatform) -> [LocalModel] {
        all.filter { $0.platforms.contains(platform) }
    }

    /// Lookup by canonical id. Returns nil for unknown ids (e.g. an ad-hoc
    /// Ollama-installed model that isn't in the curated list).
    static func model(forId id: String) -> LocalModel? {
        all.first { $0.id == id }
    }

    /// Match a server-side model string back to a curated entry. Used by the
    /// chat services when restoring `selectedModel` from UserDefaults — the
    /// same string can be either a curated id, an Ollama tag, or an HF repo.
    static func match(modelString raw: String) -> LocalModel? {
        let s = raw.lowercased()
        return all.first { m in
            m.id.lowercased() == s
                || (m.ollamaTag?.lowercased() == s)
                || (m.mlxRepo?.lowercased() == s)
        }
    }

    /// True if `modelString` resolves to a model that runs on-device (any local
    /// runtime). Used by the chat services to decide whether to bypass the
    /// backend entirely. Defaults to `false` when the string is unknown so we
    /// never accidentally skip the cloud path for a cloud model.
    static func isLocal(modelString raw: String) -> Bool {
        match(modelString: raw) != nil
    }
}
