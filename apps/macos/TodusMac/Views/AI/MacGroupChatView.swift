import SwiftUI
import AppKit

// MARK: - MacGroupChatView

/// macOS group chat view using HSplitView — member list on left, messages + composer on right.
/// TODO(realtime): Replace polling (5s refetch) with URLSessionWebSocketTask Durable Object
/// subscription when DO group rooms are available.
struct MacGroupChatView: View {
    let groupId: String

    @Environment(MacAppServices.self) private var services

    @State private var messageText: String = ""
    @State private var isSending = false
    @State private var inviteCopied = false

    private var groupService: GroupChatService { services.groupChatService }
    private var group: GroupDetails? { groupService.currentGroupDetails }

    var body: some View {
        HSplitView {
            memberListPanel
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            messagePanel
                .frame(minWidth: 320)
        }
        .task {
            try? await groupService.loadGroupDetails(groupId: groupId)
            groupService.startPolling(groupId: groupId)
        }
        .onDisappear {
            groupService.stopPolling()
        }
        // Pause polling when the window loses focus, resume when it returns.
        // Cuts background battery/network use on a chat that the user isn't watching.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            groupService.stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            groupService.startPolling(groupId: groupId)
        }
        .navigationTitle(group?.name ?? "Group")
        .toolbar { toolbarContent }
    }

    // MARK: - Member list (left panel)

    private var memberListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Members")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group?.members ?? [], id: \.userId) { member in
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(width: 26, height: 26)
                                Text(String((member.name ?? "?").prefix(1)).uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(member.name ?? "Unknown")
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                if member.role == "owner" {
                                    Text("Owner")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                }
                .padding(.top, 6)
                .background(MacScrollViewChromeAnchor())
            }

            Spacer(minLength: 0)
        }
        .background(.background.opacity(0.5))
    }

    // MARK: - Message panel (right side)

    private var messagePanel: some View {
        VStack(spacing: 0) {
            // Messages scroll area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(groupService.currentMessages) { msg in
                            MacGroupMessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(MacScrollViewChromeAnchor())
                }
                .onAppear { MacScrollStyle.reapplyToAllWindows() }
                .onChange(of: groupService.currentMessages.count) {
                    if let last = groupService.currentMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider().opacity(0.4)

            // Composer
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    group?.aiMode == "mention" ? "Message (@ai to ask AI)…" : "Message…",
                    text: $messageText,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit {
                    guard NSEvent.modifierFlags.contains(.shift) == false else { return }
                    Task { await sendMessage() }
                }

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: isSending ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(messageText.isEmpty || isSending ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let token = group?.inviteToken {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://todus.app/g/\(token)", forType: .string)
                    inviteCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { inviteCopied = false }
                }
            } label: {
                Image(systemName: inviteCopied ? "checkmark" : "person.badge.plus")
                    .foregroundStyle(inviteCopied ? .green : .primary)
            }
            .help("Copy invite link")
        }
    }

    // MARK: - Actions

    private func sendMessage() async {
        let content = messageText.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        messageText = ""
        isSending = true
        defer { isSending = false }
        do {
            try await groupService.sendMessage(groupId: groupId, content: content)
            try? await groupService.loadMessages(groupId: groupId)
        } catch {
            messageText = content
        }
    }
}

// MARK: - MacGroupMessageBubble

private struct MacGroupMessageBubble: View {
    let message: GroupMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            switch message.senderType {
            case "user":
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 3) {
                    if let name = message.senderName {
                        Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text(message.content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
                        .foregroundStyle(.primary)
                }

            case "ai":
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI").font(.system(size: 10)).foregroundStyle(.secondary)
                    MarkdownView(content: message.content, fontSize: 13)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 80)

            default:
                // System message — centered, muted
                Spacer()
                Text(message.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
    }
}

// MARK: - MacGroupListSection

/// Group list shown inside the AI assistant panel (not the sidebar).
/// Uses a callback instead of a binding so it stays self-contained within the panel.
struct MacGroupListSection: View {
    @Environment(MacAppServices.self) private var services
    /// Called when the user taps a group row — passes the group ID to the panel
    var onSelect: (String) -> Void
    /// Currently active group ID for row highlighting
    var activeGroupId: String? = nil

    @State private var showCreateSheet = false
    @State private var showJoinSheet = false

    private var groupService: GroupChatService { services.groupChatService }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section header
            HStack(spacing: 0) {
                Text("Groups")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.leading, 8)
                Spacer()
                Button { showJoinSheet = true } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .focusEffectDisabled()
                .help("Join a group")

                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .focusEffectDisabled()
                .help("New group")
            }
            .padding(.trailing, 4)
            .padding(.vertical, 4)

            if groupService.myGroups.isEmpty {
                Text("No groups yet — create one or join with an invite link.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(groupService.myGroups) { group in
                    Button {
                        onSelect(group.id)
                    } label: {
                        HStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.18))
                                    .frame(width: 18, height: 18)
                                Text(String(group.name.prefix(1)).uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            Text(group.name)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.primary.opacity(0.8))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            activeGroupId == group.id
                                ? Color.primary.opacity(0.08)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .macClickablePointer()
                    .focusEffectDisabled()
                }
            }
        }
        .task { try? await groupService.loadMyGroups() }
        // Create group sheet
        .sheet(isPresented: $showCreateSheet) {
            MacCreateGroupSheet()
                .environment(services)
                .frame(width: 340)
        }
        // Join by token sheet
        .sheet(isPresented: $showJoinSheet) {
            MacJoinGroupSheet()
                .environment(services)
                .frame(width: 340)
        }
    }
}

// MARK: - MacCreateGroupSheet

private struct MacCreateGroupSheet: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var aiMode = "mention"
    @State private var isCreating = false
    @State private var error: String? = nil

    private var groupService: GroupChatService { services.groupChatService }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Group")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Group name", text: $groupName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI mode").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Picker("AI mode", selection: $aiMode) {
                    Text("When @ai is mentioned").tag("mention")
                    Text("Always respond").tag("always")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            if let e = error {
                Text(e).font(.system(size: 12)).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") { Task { await create() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(20)
    }

    private func create() async {
        isCreating = true; error = nil
        defer { isCreating = false }
        do {
            _ = try await groupService.createGroup(name: groupName.trimmingCharacters(in: .whitespaces), aiMode: aiMode)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - MacJoinGroupSheet

private struct MacJoinGroupSheet: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var isJoining = false
    @State private var error: String? = nil

    private var groupService: GroupChatService { services.groupChatService }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Join Group")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Invite token")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Paste invite token", text: $token)
                    .textFieldStyle(.roundedBorder)
            }

            if let e = error {
                Text(e).font(.system(size: 12)).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Join") { Task { await join() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
            }
        }
        .padding(20)
    }

    private func join() async {
        isJoining = true; error = nil
        defer { isJoining = false }
        do {
            _ = try await groupService.joinGroup(token: token.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
