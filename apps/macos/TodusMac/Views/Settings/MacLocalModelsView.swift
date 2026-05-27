import OSLog
import SwiftUI

private let hfBridgeLog = Logger(subsystem: "com.todus.macos", category: "HFBridge")

// MARK: - MacLocalModelsView
//
// Settings → AI → Local Models on macOS. Same shape as the iOS counterpart
// (LocalModelsView) but uses the MacTheme card styling that the rest of the
// macOS settings rely on, so it slots cleanly into the existing settings
// surface without bespoke chrome.

struct MacLocalModelsView: View {
    @Environment(MacAppServices.self) private var services
    @State private var detailModel: LocalModel?
    /// HF repo ids whose external→app-cache symlink bridge is currently
    /// running. Used to disable the row's "Use" button so a fast double-tap
    /// doesn't spawn duplicate bridge tasks (the bridge is idempotent — the
    /// second one would log an `EEXIST` and no-op — but disabling avoids the
    /// noisy error log and gives the user real feedback).
    @State private var bridgingHFIds: Set<String> = []

    private var profile: DeviceProfile { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                deviceSection
                recommendedSection
                installedSection
                ollamaSection
                huggingFaceSection
                allModelsSection
            }
            .padding(20)
        }
        .background(MacTheme.contentBackground)
        .frame(minWidth: 560, minHeight: 540)
        .navigationTitle("Local Models")
        .sheet(item: $detailModel) { model in
            MacLocalModelDetailSheet(model: model)
                .frame(minWidth: 460, minHeight: 380)
        }
        .task {
            // Re-probe whenever the screen opens so a daemon started after
            // launch shows up without a relaunch. HF cache scan is cheap and
            // catches models the user pulled outside the app in another tool.
            services.ollamaConnector.refresh()
            services.huggingFaceCacheConnector.refresh()
        }
    }

    // MARK: - Sections

    private var deviceSection: some View {
        sectionGroup(title: "Your device") {
            settingsCard {
                rowContainer {
                    Image(systemName: "cpu")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(profile.totalRamGB) GB unified memory · \(profile.freeDiskGB) GB free")
                            .font(.system(size: 12.5))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text("Local models run on this Mac. They never use plan credits.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer()
                    if profile.appleFMAvailable {
                        Label("Apple Intelligence", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var recommendedSection: some View {
        sectionGroup(title: "Recommended for you") {
            settingsCard {
                let recs = ModelRecommender.recommend(for: profile)
                ForEach(Array(recs.enumerated()), id: \.element.model.id) { idx, rec in
                    if idx > 0 { cardDivider }
                    // Wrap the row as a real Button so keyboard focus and
                    // VoiceOver treat it as activatable — an onTapGesture
                    // alone is invisible to assistive tech.
                    Button {
                        detailModel = rec.model
                    } label: {
                        MacLocalModelRow(model: rec.model, reason: rec.reason)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
        }
    }

    @ViewBuilder
    private var installedSection: some View {
        let installed = services.localModelStateStore.installedModels()
            .filter { $0.runtime != LocalModelRuntime.appleFM }
        if !installed.isEmpty {
            sectionGroup(title: "Installed") {
                settingsCard {
                    ForEach(Array(installed.enumerated()), id: \.element.id) { idx, model in
                        if idx > 0 { cardDivider }
                        // Match the Recommended section: a real Button gives
                        // assistive tech a target and proper keyboard focus.
                        Button {
                            detailModel = model
                        } label: {
                            MacLocalModelRow(model: model, reason: nil)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        let connector = services.ollamaConnector
        if connector.isReachable && !connector.installedModels.isEmpty {
            sectionGroup(title: "Connected (Ollama)") {
                settingsCard {
                    ForEach(Array(connector.installedModels.enumerated()), id: \.element.id) { idx, tag in
                        if idx > 0 { cardDivider }
                        ollamaTagRow(tag)
                    }
                }
            }
        } else if !connector.isReachable {
            sectionGroup(title: "Connect Ollama") {
                settingsCard {
                    rowContainer {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Have Ollama installed?")
                                .font(.system(size: 12.5))
                                .foregroundStyle(MacTheme.textPrimary)
                            Text(connector.lastError ?? "Start the Ollama app to use models you’ve already pulled.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                        Spacer()
                        Button("Re-check") { connector.refresh() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ollamaTagRow(_ tag: OllamaInstalledModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.hexagonpath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 22, height: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(tag.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(tag.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(MacTheme.textSecondary)
                if tag.sizeBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: tag.sizeBytes, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            let inUse = services.aiChatService.selectedModel == tag.id
            Button(inUse ? "In use" : "Use") {
                services.aiChatService.selectedModel = tag.id
                MacHaptic.levelChange.play()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(inUse)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var huggingFaceSection: some View {
        // Exclude HF entries whose repo already maps to a curated catalog
        // model that is shown in the Installed section above. Without this
        // filter a catalog model the app downloaded into
        // `Documents/huggingface/models/<repo>` shows up in BOTH "Installed"
        // (via `LocalModelStateStore.installedModels()`) and "Connected
        // (HuggingFace)" (via the connector's `collectAppCache()`), with
        // two different control affordances for the same model.
        let installedCatalogRepos: Set<String> = Set(
            services.localModelStateStore.installedModels()
                .compactMap { $0.mlxRepo }
        )
        let hfModels = services.huggingFaceCacheConnector.installedModels
            .filter { !installedCatalogRepos.contains($0.id) }
        if !hfModels.isEmpty {
            sectionGroup(title: "Connected (HuggingFace)") {
                settingsCard {
                    ForEach(Array(hfModels.enumerated()), id: \.element.id) { idx, entry in
                        if idx > 0 { cardDivider }
                        hfRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hfRow(_ entry: HuggingFaceInstalledModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 22, height: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(entry.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(MacTheme.textSecondary)
                HStack(spacing: 6) {
                    Text(entry.source.label)
                        .font(.caption)
                        .foregroundStyle(MacTheme.textSecondary)
                    if entry.sizeBytes > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(MacTheme.textSecondary)
                        Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
            }
            Spacer(minLength: 8)
            let inUse = services.aiChatService.selectedModel == entry.id
            let bridging = bridgingHFIds.contains(entry.id)
            Button(inUse ? "In use" : (bridging ? "Linking…" : "Use")) {
                // External-cache entries live under `~/.cache/huggingface/hub`
                // but `MLXInferenceService` only reads `Documents/huggingface/
                // models`. Symlink the external snapshot into the app cache
                // BEFORE assigning `selectedModel` — otherwise a fast user
                // could trigger inference between this main-thread assignment
                // and the detached bridge landing, and MLX would re-download
                // multi-GB weights the user already has on disk. Bridge first,
                // hop back to the main actor to assign + refresh + haptic.
                let chatService = services.aiChatService
                let connector = services.huggingFaceCacheConnector
                let id = entry.id
                bridgingHFIds.insert(id)
                Task { @MainActor in
                    defer { bridgingHFIds.remove(id) }
                    await Task.detached(priority: .userInitiated) {
                        // Pass the shared logger so silent re-download
                        // failures surface in Console.app for support
                        // diagnosis — without this, the bridge's diagnostic
                        // calls were dead code.
                        HuggingFaceCacheConnector.bridgeIntoAppCacheIfPossible(entry, log: hfBridgeLog)
                    }.value
                    chatService.selectedModel = id
                    connector.refresh()
                    MacHaptic.levelChange.play()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(inUse || bridging)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var allModelsSection: some View {
        let groups = groupedByFamily(LocalModelCatalog.available(on: .macOS))
        return ForEach(groups, id: \.0) { family, models in
            sectionGroup(title: family) {
                settingsCard {
                    ForEach(Array(models.enumerated()), id: \.element.id) { idx, model in
                        if idx > 0 { cardDivider }
                        // Real Button (not onTapGesture) so keyboard focus and
                        // VoiceOver treat the row as activatable, matching the
                        // Recommended/Installed sections.
                        Button {
                            detailModel = model
                        } label: {
                            MacLocalModelRow(model: model, reason: nil)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
        }
    }

    // MARK: - Style helpers (kept local — MacSettingsView's helpers are private)

    private func sectionGroup<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .padding(.leading, 2)
            content()
        }
    }

    private func settingsCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
    }

    private var cardDivider: some View {
        Divider().opacity(0.12).padding(.horizontal, 12)
    }

    private func rowContainer<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 7) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }

    private func groupedByFamily(_ models: [LocalModel]) -> [(String, [LocalModel])] {
        let order: [LocalModelFamily] = [.appleFM, .llama, .qwen, .gemma, .ministral, .phi]
        let grouped = Dictionary(grouping: models, by: { $0.family })
        return order.compactMap { fam in
            guard let list = grouped[fam], !list.isEmpty else { return nil }
            return (familyHeader(fam), list)
        }
    }

    private func familyHeader(_ family: LocalModelFamily) -> String {
        switch family {
        case .appleFM: return "Apple Intelligence"
        case .llama: return "Llama 3.2 (Meta)"
        case .qwen: return "Qwen 3 (Alibaba)"
        case .gemma: return "Gemma 3 (Google)"
        case .ministral: return "Ministral (Mistral)"
        case .phi: return "Phi (Microsoft)"
        }
    }
}

// MARK: - MacLocalModelRow

private struct MacLocalModelRow: View {
    let model: LocalModel
    let reason: String?
    @Environment(MacAppServices.self) private var services
    @State private var modelPendingDelete: LocalModel?

    /// Whether this model is the one the chat service will use.
    private var isSelected: Bool {
        services.aiChatService.selectedModel == model.id
    }

    /// Approx GB the weights occupy on disk — used to gate Download so the user
    /// can't kick off a multi-GB transfer the volume can't hold.
    private var requiredDiskGB: Int { Int((Double(model.downloadSizeMB) / 1000.0).rounded(.up)) }
    private var hasEnoughDisk: Bool {
        model.runtime == .appleFM || DeviceProfile.current.freeDiskGB >= requiredDiskGB + 2
    }
    private var isNotInstalled: Bool {
        if case .notInstalled = state { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 22, height: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    if model.runtime == .appleFM {
                        MacBadge(text: "Built-in", tint: .green)
                    }
                    // Apple FM is always "installed" in the store but shows
                    // "Built-in" — don't also render the redundant "Installed"
                    // capsule for it.
                    if model.runtime != .appleFM, state.isInstalled {
                        MacBadge(text: "Installed", tint: .blue)
                    }
                    if isSelected {
                        MacBadge(text: "Active", tint: .accentColor)
                    }
                }
                if let reason {
                    Text(reason)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Text(model.tagline)
                    .font(.system(size: 11.5))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(2)
                detailLine
                    .padding(.top, 1)
            }
            Spacer(minLength: 8)
            actionView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .confirmDestructive(
            item: $modelPendingDelete,
            title: "Delete weights?",
            message: { "This removes the downloaded weights for \($0.displayName) from this Mac. You can re-download anytime." },
            confirmLabel: "Delete",
            perform: { services.modelDownloadService.delete($0) }
        )
    }

    private var state: LocalModelInstallState {
        services.localModelStateStore.state(for: model)
    }

    private var iconName: String {
        switch model.family {
        case .appleFM: return "apple.logo"
        case .llama: return "sparkles"
        case .qwen: return "circle.hexagongrid"
        case .gemma: return "g.circle"
        case .ministral: return "wind"
        case .phi: return "p.circle"
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        switch state {
        case .downloading(let progress, let down, let total):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress).tint(.blue)
                Text(progressCaption(down: down, total: total))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(MacTheme.textSecondary)
            }
        case .paused(let progress, let down, let total):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress).tint(.orange)
                Text("Paused · " + progressCaption(down: down, total: total))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(MacTheme.textSecondary)
            }
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
        default:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sizeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MacTheme.textSecondary)
                    if model.ramRequiredGB > 0 {
                        Text("· needs ~\(formatGB(model.ramRequiredGB)) RAM")
                            .font(.caption)
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
                if isNotInstalled, !hasEnoughDisk {
                    Text("Not enough free space · needs ~\(requiredDiskGB) GB")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var sizeLabel: String {
        if model.runtime == .appleFM { return "Built into your Mac" }
        let mb = model.downloadSizeMB
        if mb >= 1000 { return String(format: "%.1f GB", Double(mb) / 1000) }
        return "\(mb) MB"
    }

    private func formatGB(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f GB", value) : "\(Int(value)) GB"
    }

    private func progressCaption(down: Int64, total: Int64) -> String {
        let down = ByteCountFormatter.string(fromByteCount: down, countStyle: .file)
        if total > 0 {
            let total = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "\(down) of \(total)"
        }
        return down
    }

    @ViewBuilder
    private var actionView: some View {
        switch state {
        case .notInstalled:
            if model.runtime == .appleFM {
                Button("Use") { useModel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button {
                    services.modelDownloadService.startDownload(model)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasEnoughDisk)
                .help(hasEnoughDisk
                      ? "Download \(model.displayName)"
                      : "Needs ~\(requiredDiskGB) GB free — free up space to download")
            }
        case .downloading:
            Button("Cancel") { services.modelDownloadService.cancelDownload(model.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .paused:
            Button("Resume") { services.modelDownloadService.startDownload(model) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .installed:
            if model.runtime == .appleFM {
                // Apple Foundation Models have no downloadable weights — the
                // store returns `.installed(diskBytes: 0)` unconditionally so
                // the chat service's readiness check is uniform. There's
                // nothing to delete here; offering a destructive menu would
                // either be a no-op or mutate the store into a fake
                // `.deleting` / `.notInstalled` for a model that's always
                // available on this Mac.
                Button(isSelected ? "In use" : "Use") { useModel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSelected)
            } else {
                Menu {
                    Button { useModel() } label: {
                        if isSelected {
                            Label("In use", systemImage: "checkmark")
                        } else {
                            Text("Use this model")
                        }
                    }
                    .disabled(isSelected)
                    Button("Delete weights", role: .destructive) {
                        modelPendingDelete = model
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.mutedText)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("Options for \(model.displayName)")
                .help("More options")
            }
        case .deleting:
            ProgressView().controlSize(.small)
        case .failed:
            Button("Retry") { services.modelDownloadService.startDownload(model) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func useModel() {
        services.aiChatService.selectedModel = model.id
        MacHaptic.levelChange.play()
    }
}

// MARK: - MacBadge

private struct MacBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - MacLocalModelDetailSheet

struct MacLocalModelDetailSheet: View {
    let model: LocalModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName).font(.system(size: 15, weight: .semibold))
                    Text(model.tagline).font(.system(size: 12)).foregroundStyle(MacTheme.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            Text(model.description)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textPrimary)

            if !model.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strengths").font(.system(size: 11, weight: .medium)).foregroundStyle(MacTheme.mutedText)
                    ForEach(model.strengths, id: \.self) { s in
                        Label(s, systemImage: "sparkles").font(.system(size: 12))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Specs").font(.system(size: 11, weight: .medium)).foregroundStyle(MacTheme.mutedText)
                detailRow("Parameters", value: model.parameters)
                if model.runtime == .appleFM {
                    detailRow("Download size", value: "Built into your Mac")
                } else {
                    detailRow("Download size", value: sizeLabel)
                    detailRow("RAM recommended", value: "\(format(model.ramRequiredGB)) GB")
                }
                detailRow("Runs on", value: runtimeLabel)
                detailRow("Tool use", value: model.supportsToolUse ? "Yes" : "Not reliably")
                detailRow("License", value: model.license)
            }

            Text("Local models run entirely on this Mac. They never use your plan credits and work offline.")
                .font(.system(size: 11.5))
                .foregroundStyle(MacTheme.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(MacTheme.contentBackground)
    }

    private var sizeLabel: String {
        let mb = model.downloadSizeMB
        if mb >= 1000 { return String(format: "%.1f GB", Double(mb) / 1000) }
        return "\(mb) MB"
    }

    private var runtimeLabel: String {
        switch model.runtime {
        case .mlx: return "MLX (Apple Silicon)"
        case .appleFM: return "Apple Intelligence"
        case .ollama: return "Ollama"
        }
    }

    private func format(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : "\(Int(v))"
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(MacTheme.textSecondary)
        }
    }
}
