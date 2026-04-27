import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - ModelRecommender
//
// Picks a "best" model for the current device + 2–3 alternates with a one-line
// reason. Pure data-in / data-out — no UI dependencies. Identical between the
// iOS and macOS apps (the platform branch is a runtime check on `currentPlatform`).
//
// Heuristic table (from the plan):
//   ≤6 GB iPhone               → Qwen 3 1.7B  (alts: Llama 3.2 1B, Apple FM)
//   8 GB+ iPhone / iPad        → Qwen 3 4B    (alts: Gemma 3 4B, Apple FM)
//   8 GB Mac                   → Qwen 3 4B    (alts: Llama 3.2 3B, Apple FM)
//   16 GB Mac                  → Gemma 3 12B  (alts: Qwen 3 8B, Llama 3.2 3B)
//   32 GB+ Mac                 → Qwen 3 32B   (alts: Gemma 3 27B, Qwen 3 14B)

struct ModelRecommendation: Hashable {
    let model: LocalModel
    let reason: String
}

struct DeviceProfile: Hashable {
    let platform: LocalModelPlatform
    /// Total physical RAM in GB (rounded down to the nearest GB).
    let totalRamGB: Int
    /// Free disk space in GB on the volume we'd download to.
    let freeDiskGB: Int
    /// True when the OS exposes Apple Foundation Models. For iOS this means
    /// 26.0+; for macOS 26.0+. The recommender does not check whether Apple
    /// Intelligence is *enabled* — that's the runtime adapter's job.
    let appleFMAvailable: Bool

    static var current: DeviceProfile {
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Int(ramBytes / 1_073_741_824) // bytes → GiB

        let freeGB: Int = {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let bytes = values.volumeAvailableCapacityForImportantUsage {
                return Int(bytes / 1_073_741_824)
            }
            return 0
        }()

        #if os(iOS)
        let platform: LocalModelPlatform = .iOS
        let appleFM: Bool = {
            if #available(iOS 26.0, *) { return true }
            return false
        }()
        #else
        let platform: LocalModelPlatform = .macOS
        let appleFM: Bool = {
            if #available(macOS 26.0, *) { return true }
            return false
        }()
        #endif

        return DeviceProfile(
            platform: platform,
            totalRamGB: ramGB,
            freeDiskGB: freeGB,
            appleFMAvailable: appleFM
        )
    }
}

enum ModelRecommender {
    /// Returns a "best for you" pick (first element) followed by up to two
    /// alternates with one-line reasons. Output respects platform availability,
    /// so iOS callers never see Mac-only models.
    static func recommend(for profile: DeviceProfile = .current) -> [ModelRecommendation] {
        let pool = LocalModelCatalog.available(on: profile.platform)
        let pickFromPool: (String) -> LocalModel? = { id in pool.first(where: { $0.id == id }) }

        var picks: [ModelRecommendation] = []

        switch (profile.platform, profile.totalRamGB) {
        // ── iPhone / iPad ───────────────────────────────────────────────
        case (.iOS, 0...6):
            picks.append(contentsOf: [
                pickFromPool("qwen-3-1.7b").map { ModelRecommendation(model: $0, reason: "Best balance for your device") },
                pickFromPool("llama-3.2-1b").map { ModelRecommendation(model: $0, reason: "Smaller and faster") },
            ].compactMap { $0 })

        case (.iOS, _):
            picks.append(contentsOf: [
                pickFromPool("qwen-3-4b").map { ModelRecommendation(model: $0, reason: "Best balance for your device") },
                pickFromPool("gemma-3-4b").map { ModelRecommendation(model: $0, reason: "Polished writing, similar size") },
                pickFromPool("qwen-3-1.7b").map { ModelRecommendation(model: $0, reason: "Smaller and faster") },
            ].compactMap { $0 })

        // ── Mac ─────────────────────────────────────────────────────────
        case (.macOS, 0...10):
            picks.append(contentsOf: [
                pickFromPool("qwen-3-4b").map { ModelRecommendation(model: $0, reason: "Best fit for 8 GB Macs") },
                pickFromPool("llama-3.2-3b").map { ModelRecommendation(model: $0, reason: "Faster, slightly smaller") },
            ].compactMap { $0 })

        case (.macOS, 11...20):
            picks.append(contentsOf: [
                pickFromPool("gemma-3-12b").map { ModelRecommendation(model: $0, reason: "Best balance for 16 GB Macs") },
                pickFromPool("qwen-3-8b").map { ModelRecommendation(model: $0, reason: "Strong reasoning, fits comfortably") },
                pickFromPool("llama-3.2-3b").map { ModelRecommendation(model: $0, reason: "Fastest tokens") },
            ].compactMap { $0 })

        case (.macOS, _):
            picks.append(contentsOf: [
                pickFromPool("qwen-3-32b").map { ModelRecommendation(model: $0, reason: "Top-tier local quality on a 32 GB+ Mac") },
                pickFromPool("gemma-3-27b").map { ModelRecommendation(model: $0, reason: "High-quality alternative") },
                pickFromPool("qwen-3-14b").map { ModelRecommendation(model: $0, reason: "Smaller and faster") },
            ].compactMap { $0 })
        }

        // Always offer Apple Intelligence as a zero-download option when
        // available — append once if it isn't already in the list.
        if profile.appleFMAvailable, !picks.contains(where: { $0.model.id == LocalModelCatalog.appleIntelligence.id }) {
            picks.append(
                ModelRecommendation(
                    model: LocalModelCatalog.appleIntelligence,
                    reason: "Built into your device, zero download"
                )
            )
        }

        // Filter out models the user simply doesn't have RAM for. The catalog
        // already gates by platform; this is a final safety net so we never
        // recommend a 14 GB model to someone with 8 GB of RAM.
        return picks.filter { rec in
            // Apple FM has ramRequiredGB == 0; never gate it out.
            rec.model.runtime == .appleFM || Double(profile.totalRamGB) >= rec.model.ramRequiredGB
        }
    }
}
