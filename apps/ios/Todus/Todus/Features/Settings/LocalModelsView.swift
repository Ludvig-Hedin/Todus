import SwiftUI

// MARK: - LocalModelsView (iOS)
//
// Settings → AI → Local Models. Lets users:
//   • see which on-device models are recommended for their device,
//   • browse the full curated catalog grouped by family,
//   • download / pause / delete weights,
//   • read a per-model detail sheet (description, strengths, RAM, license).
//
// In Phase 1 the action buttons call into LocalModelStateStore stubs — the
// real download / inference plumbing lands in Phase 3.

struct LocalModelsView: View {
    @Environment(AppServices.self) private var services
    @State private var detailModel: LocalModel?

    private var profile: DeviceProfile { .current }

    var body: some View {
        List {
            deviceSection
            recommendedSection
            installedSection
            allModelsSection
            footerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $detailModel) { model in
            LocalModelDetailSheet(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sections

    private var deviceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your device")
                    .font(.subheadline.weight(.semibold))
                Text("\(profile.totalRamGB) GB RAM · \(profile.freeDiskGB) GB free")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if profile.appleFMAvailable {
                    Label("Apple Intelligence available", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                Text("Local models run entirely on this device. They never use plan credits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 6)
        }
    }

    private var recommendedSection: some View {
        Section("Recommended for you") {
            ForEach(ModelRecommender.recommend(for: profile), id: \.model.id) { rec in
                LocalModelRow(model: rec.model, reason: rec.reason)
                    .contentShape(Rectangle())
                    .onTapGesture { detailModel = rec.model }
            }
        }
    }

    private var installedSection: some View {
        let installed = services.localModelStateStore.installedModels()
            .filter { $0.runtime != .appleFM } // Apple FM is implicit, not a "downloaded" entry
        return Group {
            if !installed.isEmpty {
                Section("Installed") {
                    ForEach(installed) { model in
                        LocalModelRow(model: model, reason: nil)
                            .contentShape(Rectangle())
                            .onTapGesture { detailModel = model }
                    }
                }
            }
        }
    }

    private var allModelsSection: some View {
        let groups = groupedByFamily(LocalModelCatalog.available(on: .iOS))
        return ForEach(groups, id: \.0) { family, models in
            Section(family) {
                ForEach(models) { model in
                    LocalModelRow(model: model, reason: nil)
                        .contentShape(Rectangle())
                        .onTapGesture { detailModel = model }
                }
            }
        }
    }

    private var footerSection: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Models are downloaded from HuggingFace’s `mlx-community` repository.")
                Text("Downloads continue in the background. Storage shown is for the quantized 4-bit weights.")
            }
            .font(.footnote)
        }
    }

    // MARK: - Helpers

    private func groupedByFamily(_ models: [LocalModel]) -> [(String, [LocalModel])] {
        // Stable, scannable order: Apple FM first, then Llama, Qwen, Gemma, Ministral.
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

// MARK: - LocalModelRow

private struct LocalModelRow: View {
    let model: LocalModel
    let reason: String?
    @Environment(AppServices.self) private var services

    /// Gates "Delete weights" behind a confirm — deleting multi-GB on-device
    /// weights is irreversible short of a full re-download, and every other
    /// destructive action in the app confirms.
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.body.weight(.semibold))
                    if model.runtime == .appleFM {
                        BadgeView(text: "Built-in", tint: .green)
                    }
                    if isActiveModel {
                        // Which model actually answers was previously invisible —
                        // "Use this model" changed nothing on screen.
                        BadgeView(text: "Active", tint: .green)
                    } else if state.isInstalled {
                        BadgeView(text: "Installed", tint: .blue)
                    }
                }
                if let reason {
                    Text(reason)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(model.tagline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                detailLine
            }
            Spacer(minLength: 8)
            actionView
        }
        .padding(.vertical, 4)
    }

    private var state: LocalModelInstallState {
        services.localModelStateStore.state(for: model)
    }

    private var isActiveModel: Bool {
        services.aiChatService.selectedModel == model.id
    }

    @ViewBuilder
    private var detailLine: some View {
        switch state {
        case .downloading(let progress, let down, let total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(.blue)
                Text(progressCaption(down: down, total: total))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        case .paused(let progress, let down, let total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(.orange)
                Text("Paused · " + progressCaption(down: down, total: total))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
        default:
            HStack(spacing: 8) {
                Text(sizeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if model.ramRequiredGB > 0 {
                    Text("· needs ~\(formatGB(model.ramRequiredGB)) RAM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sizeLabel: String {
        if model.runtime == .appleFM { return "Built into your device" }
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
            }
        case .downloading:
            // MLX's downloader has no first-class pause; cancelling reverts
            // the row to .notInstalled. The cached partial transfer is
            // preserved so the next Download resumes where we left off.
            Button("Cancel") { services.modelDownloadService.cancelDownload(model.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .paused:
            Button("Resume") { services.modelDownloadService.startDownload(model) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .installed:
            Menu {
                Button("Use this model", systemImage: "checkmark.circle") { useModel() }
                Button("Delete weights", systemImage: "trash", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .confirmationDialog(
                "Delete \(model.displayName)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Weights", role: .destructive) {
                    services.modelDownloadService.delete(model)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The downloaded weights (\(sizeLabel)) will be removed from this device. Using this model again requires a full re-download.")
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
        // Sets the chat service's selected model to this local entry. The chat
        // service's send() path (Phase 5) branches on `LocalModelCatalog.match`
        // and routes to the local runtime instead of /api/ai/chat.
        services.aiChatService.selectedModel = model.id
        AppHaptic.selection.play()
    }
}

// MARK: - BadgeView

private struct BadgeView: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - LocalModelDetailSheet

struct LocalModelDetailSheet: View {
    let model: LocalModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.displayName).font(.title3.weight(.semibold))
                        Text(model.tagline).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("About") {
                    Text(model.description)
                        .font(.callout)
                }
                if !model.strengths.isEmpty {
                    Section("Strengths") {
                        ForEach(model.strengths, id: \.self) { s in
                            Label(s, systemImage: "sparkles")
                        }
                    }
                }
                Section("Specs") {
                    detailRow("Parameters", value: model.parameters)
                    if model.runtime == .appleFM {
                        detailRow("Download size", value: "Built into your device")
                    } else {
                        detailRow("Download size", value: sizeLabel)
                        if model.ramRequiredGB > 0 {
                            detailRow("RAM recommended", value: "\(format(model.ramRequiredGB)) GB")
                        }
                    }
                    detailRow("Runs on", value: runtimeLabel)
                    detailRow("Tool use", value: model.supportsToolUse ? "Yes" : "Not reliably")
                    detailRow("License", value: model.license)
                }
                Section {
                    Text("Local models run entirely on this device. They never use your plan credits and work offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(model.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
        case .ollama: return "Ollama (macOS)"
        }
    }

    private func format(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : "\(Int(v))"
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
