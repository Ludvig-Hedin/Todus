import SwiftUI

struct BillingSettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL

    @State private var isOpeningPortal = false
    @State private var isCanceling = false
    @State private var showCancelConfirm = false
    @State private var errorMessage: String?

    private var subscription: SubscriptionService { services.subscriptionService }

    private static let creditsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    private var resetLabel: String? {
        guard let date = subscription.aiUsageResetAt else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func formatCredits(_ value: Double) -> String {
        Self.creditsFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    var body: some View {
        List {
            planSection
            usageSection
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("Billing")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await subscription.refresh()
        }
        .refreshable {
            await subscription.forceRefreshFromAutumn()
        }
        .confirmationDialog(
            "Cancel your Pro subscription?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel subscription", role: .destructive) {
                Task { await performCancel() }
            }
            Button("Keep Pro", role: .cancel) {}
        } message: {
            Text("You'll keep access until the end of the current billing period.")
        }
    }

    private var planSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.plan.displayName)
                        .font(.title3.weight(.semibold))
                    if subscription.status != "active" {
                        Text(subscription.status.capitalized)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if subscription.plan.isPaid {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if subscription.plan.isPaid {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tint)
                }
            }

            if subscription.plan.isPaid {
                Button {
                    Task { await openBillingPortal() }
                } label: {
                    HStack {
                        Label("Manage billing", systemImage: "creditcard")
                        Spacer()
                        if isOpeningPortal {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isOpeningPortal)

                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    HStack {
                        Label("Cancel subscription", systemImage: "xmark.circle")
                        Spacer()
                        if isCanceling {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isCanceling)
            } else {
                Button {
                    openUpgradeUrl()
                } label: {
                    HStack {
                        Label("Upgrade to Pro", systemImage: "sparkles")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Plan")
        } footer: {
            if !subscription.plan.isPaid {
                Text("Pro unlocks $15 of AI usage per month, unlimited connections, and more.")
            }
        }
    }

    private var usageSection: some View {
        Section {
            if subscription.aiUsageLimit == 0 {
                Text("No AI credits on the \(subscription.plan.displayName) plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(formatCredits(subscription.aiUsageUsed))")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Text(" / \(formatCredits(subscription.aiUsageLimit)) credits used")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatCredits(subscription.aiUsageRemaining)) left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ProgressView(value: subscription.aiUsagePercent)
                        .tint(progressTint)
                    if let resetLabel {
                        Text("Resets on \(resetLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if subscription.aiUsagePercent >= 1 {
                        Text("Out of AI credits this period.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if subscription.aiUsagePercent >= 0.8 {
                        Text("You've used \(Int(subscription.aiUsagePercent * 100))% of your AI credits.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("AI usage")
        } footer: {
            Text("Each AI message uses credits based on the model and message length. 1 credit ≈ $1 of model cost.")
        }
    }

    private var progressTint: Color {
        let pct = subscription.aiUsagePercent
        if pct >= 1 { return .red }
        if pct >= 0.8 { return .orange }
        return .accentColor
    }

    // MARK: - Actions

    private func openBillingPortal() async {
        errorMessage = nil
        isOpeningPortal = true
        defer { isOpeningPortal = false }
        do {
            if let url = try await subscription.getBillingPortalUrl() {
                openURL(url)
            } else {
                errorMessage = "Couldn't open the billing portal. Try again in a moment."
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func openUpgradeUrl() {
        errorMessage = nil
        let base = services.configuration.effectiveBackendURL.absoluteString
        // Marketing pricing page lives on the web app, not the API. Fall back to a
        // hardcoded prod URL if we only know the API origin.
        let pricingURL: URL? = {
            if let host = URL(string: base)?.host, host.hasPrefix("api.") {
                return URL(string: "https://\(host.replacingOccurrences(of: "api.", with: "app."))/pricing")
            }
            return URL(string: "https://app.todus.app/pricing")
        }()
        if let url = pricingURL {
            openURL(url)
        } else {
            errorMessage = "Couldn't open the upgrade page."
        }
    }

    private func performCancel() async {
        errorMessage = nil
        isCanceling = true
        defer { isCanceling = false }
        do {
            // Pro on iOS is always pro_monthly via the web checkout flow today;
            // when we add an annual upgrade on iOS we'll persist the actual
            // product id and use it here.
            try await subscription.cancel(productId: "pro_monthly")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
