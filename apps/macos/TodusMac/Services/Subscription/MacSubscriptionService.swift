import Foundation
import Observation

/// Cached subscription / AI-usage state for the macOS app. Mirrors the iOS
/// SubscriptionService — both talk to the same `subscription.*` tRPC routes
/// on the shared backend. Source of truth lives in Autumn (server side).
@MainActor
@Observable
final class MacSubscriptionService {
    enum Plan: String {
        case free
        case pro
        case team
        case enterprise

        init(rawValue: String) {
            switch rawValue.lowercased() {
            case "pro", "pro_monthly", "pro_annual": self = .pro
            case "team": self = .team
            case "enterprise": self = .enterprise
            default: self = .free
            }
        }

        var displayName: String {
            switch self {
            case .free: return "Free"
            case .pro: return "Pro"
            case .team: return "Team"
            case .enterprise: return "Enterprise"
            }
        }

        var isPaid: Bool { self != .free }
    }

    private let apiClient: TodosAPIClient

    private(set) var plan: Plan = .free
    private(set) var status: String = "active"
    /// Active Autumn product id (e.g. `pro_monthly`, `pro_annual`, `free`). Resolved
    /// server-side from Autumn so cancellation targets the correct product instead of a
    /// hardcoded guess. Only `subscription.getStatus` returns it; `subscription.refresh`
    /// does not, so it persists across a refresh that omits the field.
    private(set) var activeProductId: String?
    /// Billing interval (`monthly` / `annual`) when known. Same provenance as `activeProductId`.
    private(set) var billingInterval: String?
    private(set) var aiUsageUsed: Double = 0
    private(set) var aiUsageLimit: Double = 0
    private(set) var aiUsageRemaining: Double = 0
    private(set) var aiUsageUnlimited: Bool = false
    private(set) var aiUsageResetAt: Date?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    var hasAiCredits: Bool {
        aiUsageUnlimited || (aiUsageLimit > 0 && aiUsageRemaining > 0)
    }

    var aiUsagePercent: Double {
        guard !aiUsageUnlimited else { return 0 }
        guard aiUsageLimit > 0 else { return 0 }
        return min(1, aiUsageUsed / aiUsageLimit)
    }

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: SubscriptionStatusResponse = try await apiClient.trpcQuery("subscription.getStatus")
            apply(response)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func forceRefreshFromAutumn() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: SubscriptionStatusResponse = try await apiClient.trpcMutation("subscription.refresh")
            apply(response)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func getBillingPortalUrl(returnUrl: String? = nil) async throws -> URL? {
        let input = BillingPortalInput(returnUrl: returnUrl)
        let response: BillingPortalResponse = try await apiClient.trpcMutation(
            "subscription.getBillingPortalUrl",
            input: input
        )
        return response.url.flatMap(URL.init(string:))
    }

    func cancel(productId: String) async throws {
        let input = CancelInput(productId: productId)
        let _: CancelResponse = try await apiClient.trpcMutation("subscription.cancel", input: input)
        await forceRefreshFromAutumn()
    }

    private func apply(_ response: SubscriptionStatusResponse) {
        self.plan = Plan(rawValue: response.plan)
        self.status = response.status
        // `refresh` omits productId/interval — only overwrite when present so a
        // post-cancel refresh doesn't blank the id resolved by the prior getStatus.
        if let productId = response.productId {
            self.activeProductId = productId
        }
        if let interval = response.interval {
            self.billingInterval = interval
        }
        self.aiUsageUsed = response.aiUsage.used
        self.aiUsageLimit = response.aiUsage.limit
        self.aiUsageRemaining = response.aiUsage.remaining
        self.aiUsageUnlimited = response.aiUsage.unlimited
        self.aiUsageResetAt = response.aiUsage.resetAt.flatMap { Self.parseISO8601($0) }
    }

    /// Backend `resetAt` timestamps may or may not carry fractional seconds
    /// (e.g. `…:00Z` vs `…:00.123Z`). A bare `ISO8601DateFormatter` only matches
    /// one shape and silently drops the other, so try both.
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain = ISO8601DateFormatter()

    private static func parseISO8601(_ value: String) -> Date? {
        iso8601WithFractional.date(from: value) ?? iso8601Plain.date(from: value)
    }
}

// MARK: - Wire formats

private struct SubscriptionStatusResponse: Decodable {
    let plan: String
    let status: String
    /// Active product id from Autumn (`pro_monthly` / `pro_annual` / `free`). Optional
    /// because `subscription.refresh` returns the same shape minus this field.
    let productId: String?
    /// Billing interval (`monthly` / `annual`). Optional for the same reason.
    let interval: String?
    let aiUsage: AiUsageInfo
}

private struct AiUsageInfo: Decodable {
    let used: Double
    let limit: Double
    let remaining: Double
    let unlimited: Bool
    let resetAt: String?
}

private struct BillingPortalInput: Encodable {
    let returnUrl: String?
}

private struct BillingPortalResponse: Decodable {
    let url: String?
}

private struct CancelInput: Encodable {
    let productId: String
}

private struct CancelResponse: Decodable {
    let plan: String
    let status: String
}
