import SwiftUI

struct BillingSettingsView: View {
    @Environment(AppServices.self) private var services

    @State private var isCanceling = false
    @State private var showCancelConfirm = false
    @State private var errorMessage: String?

    private var subscription: SubscriptionService { services.subscriptionService }

    private static let planIncludes: [SubscriptionService.Plan: [String]] = [
        .free: [
            "1 email connection",
            "75 credits / month of AI chat",
            "Basic AI email assistance",
        ],
        .pro: [
            "Unlimited email connections",
            "150 credits / month of AI chat & voice",
            "Auto-labeling, thread summaries, priority models",
            "Cancel anytime from this screen",
        ],
        .team: [
            "Everything in Pro",
            "Shared inbox + collaboration",
            "Org-level billing",
        ],
        .enterprise: [
            "Custom limits and SLAs",
            "SSO + advanced security controls",
            "Dedicated account support",
        ],
    ]

    private var resetLabel: String? {
        guard let date = subscription.aiUsageResetAt else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Credits are shown to users at 10× their internal (dollar-denominated)
    /// value so plan tiers read as round, motivating numbers (Free 75, Pro 150)
    /// while actual billing/limits stay unchanged. The static `planIncludes`
    /// copy below uses the same scale; keep it in sync with the web billing page.
    private static let creditsDisplayScale: Double = 10

    /// Tighter than NumberFormatter for our specific case: hide decimals on
    /// integer-ish values so "10 credits" doesn't render as "10.00". Applies the
    /// display scale so the usage meter matches the scaled plan copy. Guards
    /// against NaN / ±infinity: `Int(NaN.rounded())` traps and would crash the
    /// Billing tab on any upstream divide-by-zero or bad decode.
    private func formatCredits(_ value: Double) -> String {
        let scaled = value * Self.creditsDisplayScale
        guard scaled.isFinite else { return "—" }
        if scaled == 0 { return "0" }
        if scaled < 1 { return String(format: "%.2f", scaled) }
        if scaled < 10 { return String(format: "%.1f", scaled) }
        // `Int(Double.rounded())` traps on overflow (>~9.2e18). Subscription
        // credits won't realistically hit that range, but a corrupted
        // upstream value would crash the Billing tab. Render `"—"` as a
        // safe fallback for any too-large value.
        guard scaled < Double(Int.max) else { return "—" }
        return String(Int(scaled.rounded()))
    }

    private func formatUsageTotal(_ value: Double, unlimited: Bool) -> String {
        unlimited ? "Unlimited" : formatCredits(value)
    }

    private var percentRemaining: Int {
        guard !subscription.aiUsageUnlimited else { return 100 }
        guard subscription.aiUsageLimit > 0 else { return 0 }
        // `Int(ceil(NaN * 100))` traps. Guard against a non-finite
        // `aiUsagePercent` (upstream 0/0, bad decode) so the Billing tab
        // doesn't crash on bad data — render "100% remaining" as a safe
        // fallback when the percent is unknowable.
        let pct = subscription.aiUsagePercent
        guard pct.isFinite else { return 100 }
        // Use `ceil` for the consumed slice so any non-zero usage drops the
        // headline below 100% — `.rounded()` would report "100% remaining"
        // for small (e.g. 0.4%) consumption while the "Used X of Y" subtitle
        // simultaneously shows real consumption.
        return max(0, 100 - Int(ceil(pct * 100)))
    }

    var body: some View {
        List {
            planSection
            includesSection
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
        // The inline error Section above can be scrolled out of view (it renders
        // after usageSection) — surface a blocking alert too so a failed cancel
        // is never silently missed after the spinner disappears.
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
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
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    HStack {
                        Label("Cancel subscription", systemImage: "xmark.circle")
                        Spacer()
                        if isCanceling {
                            ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.toolbarInlineSpinner)
                        }
                    }
                }
                .disabled(isCanceling)
            } else {
                Label("Paid plan changes are not available in this iOS build.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Plan")
        } footer: {
            if !subscription.plan.isPaid {
                Text("The iOS app includes the free plan. Paid plan changes are not offered in this build.")
            } else {
                Text("Payment-method changes are handled outside this iOS build. You can cancel your active plan here.")
            }
        }
    }

    private var includesSection: some View {
        let items = Self.planIncludes[subscription.plan] ?? Self.planIncludes[.free] ?? []
        return Section {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(subscription.plan.isPaid ? Color.accentColor : .secondary)
                    Text(item)
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Includes")
        }
    }

    private var usageSection: some View {
        Section {
            VStack(alignment: .center, spacing: 14) {
                // Big number — credits remaining
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(subscription.aiUsageUnlimited ? "Unlimited" : "\(percentRemaining)%")
                            .font(.system(size: 44, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text(subscription.aiUsageUnlimited ? "AI credits" : "remaining")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(subscription.aiUsageUnlimited
                         ? "Unlimited AI usage on this plan"
                         : subscription.aiUsageLimit > 0
                         ? "Used \(formatCredits(subscription.aiUsageUsed)) of \(formatCredits(subscription.aiUsageLimit)) credits"
                         : "No credits on this plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                // Big progress bar. Clamp to [0, 1] and guard non-finite so
                // SwiftUI doesn't render undefined output when upstream
                // surfaces NaN / ±infinity (consistent with the percentRemaining
                // + warning-banner guards above).
                ProgressView(value: (subscription.aiUsageLimit > 0 && subscription.aiUsagePercent.isFinite)
                             ? min(max(subscription.aiUsagePercent, 0), 1)
                             : 0)
                    .tint(progressTint)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("AI credits used")
                    .accessibilityValue(subscription.aiUsageUnlimited
                                        ? "Unlimited"
                                        : "\(percentRemaining)% remaining")

                HStack {
                    Text("Used: \(formatCredits(subscription.aiUsageUsed))")
                        .monospacedDigit()
                    Spacer()
                    Text("Total: \(formatUsageTotal(subscription.aiUsageLimit, unlimited: subscription.aiUsageUnlimited))")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // `+infinity >= 0.8` is true and `Int(infinity.rounded())`
                // traps. Gate the warning banner on `.isFinite` so a bad
                // upstream percent value can't crash the Billing tab.
                if !subscription.aiUsageUnlimited && subscription.aiUsagePercent.isFinite
                    && subscription.aiUsagePercent >= 1 && subscription.aiUsageLimit > 0 {
                    Text("Out of AI credits this period.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !subscription.aiUsageUnlimited && subscription.aiUsagePercent.isFinite
                    && subscription.aiUsagePercent >= 0.8 && subscription.aiUsageLimit > 0 {
                    Text("You've used \(Int((subscription.aiUsagePercent * 100).rounded()))% of your AI credits.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        } header: {
            HStack {
                Text("AI usage")
                Spacer()
                if let resetLabel {
                    Text("Resets \(resetLabel)")
                        .textCase(.none)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Every AI chat message and voice session debits credits based on the model and length.")
        }
    }

    private var progressTint: Color {
        let pct = subscription.aiUsagePercent
        // Match the .isFinite guarding used by every other consumer of
        // aiUsagePercent in this view — a NaN/±infinity value shouldn't pick a
        // misleading tint.
        guard pct.isFinite else { return .accentColor }
        if pct >= 1 { return .red }
        if pct >= 0.8 { return .orange }
        return .accentColor
    }

    // MARK: - Actions

    private func performCancel() async {
        errorMessage = nil
        isCanceling = true
        defer { isCanceling = false }
        do {
            // Pro on iOS is always pro_monthly via the web checkout flow today;
            // when we add an annual upgrade on iOS we'll persist the actual
            // product id and use it here.
            try await subscription.cancel(productId: "pro_monthly")
            // `cancel()` applies the post-cancel plan/status from its own response,
            // but not usage/credit limits — force a fresh Autumn read so the AI
            // usage meter reflects the new (free) plan's limits immediately
            // instead of showing stale Pro numbers until the next webhook sync.
            await subscription.forceRefreshFromAutumn()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
