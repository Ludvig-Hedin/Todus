import SwiftUI
import SwiftData
import UIKit

/// Review sheet for the header "Organize" action. Runs the hybrid rules+AI
/// pass on appear, shows proposals grouped by destination folder with per-task
/// toggles, and applies the accepted subset only when the user taps Apply.
struct OrganizeReviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var proposals: [OrganizeProposal] = []
    @State private var isLoading = true

    private var acceptedCount: Int {
        proposals.filter(\.isAccepted).count
    }

    /// Proposals grouped by destination, new-folder groups last, stable order.
    private var groups: [(destination: OrganizeProposal.Destination, indices: [Int])] {
        var order: [OrganizeProposal.Destination] = []
        var byDestination: [OrganizeProposal.Destination: [Int]] = [:]
        for (index, proposal) in proposals.enumerated() {
            if byDestination[proposal.destination] == nil {
                order.append(proposal.destination)
            }
            byDestination[proposal.destination, default: []].append(index)
        }
        return order
            .sorted { !$0.isNewFolder && $1.isNewFolder }
            .map { ($0, byDestination[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingState
                } else if proposals.isEmpty {
                    emptyState
                } else {
                    proposalList
                }
            }
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        apply()
                    } label: {
                        Text(acceptedCount > 0 ? "Apply (\(acceptedCount))" : "Apply")
                            .fontWeight(.semibold)
                    }
                    .disabled(isLoading || acceptedCount == 0)
                }
            }
        }
        .task {
            proposals = await services.captureService.proposeOrganization(in: modelContext)
            isLoading = false
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                Text("Sorting your inbox…")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(AppTheme.mutedText)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(red: 0.30, green: 0.65, blue: 0.45))
            Text("Nothing to organize")
                .font(.system(size: 18, weight: .semibold))
            Text("Every task is already where it belongs, or there's nothing that clearly fits a folder.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Proposal list

    private var proposalList: some View {
        List {
            ForEach(groups, id: \.destination) { group in
                Section {
                    ForEach(group.indices, id: \.self) { index in
                        proposalRow(index: index)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    }
                } header: {
                    groupHeader(group.destination, count: group.indices.count)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func groupHeader(_ destination: OrganizeProposal.Destination, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: destination.isNewFolder ? "folder.badge.plus" : "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(destination.isNewFolder ? AppTheme.secondaryAccent : AppTheme.subtleText)
            Text(destination.isNewFolder ? "New folder: \(destination.displayName)" : destination.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
        }
        .textCase(nil)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func proposalRow(index: Int) -> some View {
        let proposal = proposals[index]
        return Button {
            proposals[index].isAccepted.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: proposal.isAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(proposal.isAccepted ? AppTheme.secondaryAccent : AppTheme.subtleText)

                Text(proposal.taskTitle)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary.opacity(proposal.isAccepted ? 1.0 : 0.55))

                Spacer(minLength: 4)

                if proposal.source == .ai {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText.opacity(0.7))
                        .accessibilityLabel("AI suggestion")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.rowFill, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.rowStroke, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Apply

    private func apply() {
        let moved = services.captureService.applyProposals(proposals, in: modelContext)
        if moved > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        dismiss()
    }
}
