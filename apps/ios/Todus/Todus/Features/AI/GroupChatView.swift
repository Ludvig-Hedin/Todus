import SwiftUI

// MARK: - GroupListView

/// Section shown in the AI / chat list showing the user's group chats.
/// Tapping a group opens GroupChatView as a full-screen sheet.
struct GroupListView: View {
    @Environment(AppServices.self) private var services

    @State private var showCreateSheet = false
    @State private var selectedGroupId: String? = nil
    @State private var joinToken: String = ""
    @State private var showJoinAlert = false
    @State private var joinError: String? = nil

    private var groupService: GroupChatService { services.groupChatService }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Text("Group Chats")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Spacer()
                HStack(spacing: 12) {
                    // Join by token
                    Button {
                        showJoinAlert = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    // Create new group
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if groupService.myGroups.isEmpty {
                Text("No groups yet — create one or join with an invite link.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ForEach(groupService.myGroups) { group in
                    Button {
                        selectedGroupId = group.id
                    } label: {
                        HStack(spacing: 12) {
                            // Group avatar placeholder
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Text(String(group.name.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(group.aiMode == "always" ? "AI always on" : "AI on @mention")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            try? await groupService.loadMyGroups()
        }
        // Create group sheet
        .sheet(isPresented: $showCreateSheet) {
            CreateGroupSheet()
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium])
                .presentationBackground(AppTheme.backgroundTop)
        }
        // Group chat view
        .fullScreenCover(item: Binding(
            get: { selectedGroupId.map { GroupChatNav(id: $0) } },
            set: { selectedGroupId = $0?.id }
        )) { nav in
            GroupChatView(groupId: nav.id)
        }
        // Join by invite token alert
        .alert("Join by invite link", isPresented: $showJoinAlert) {
            TextField("Paste invite token", text: $joinToken)
                .autocorrectionDisabled()
            Button("Join") { Task { await joinGroup() } }
            Button("Cancel", role: .cancel) { joinToken = "" }
        } message: {
            Text("Paste the invite token from a group invite link.")
        }
        // Join error alert
        .alert("Could not join group", isPresented: Binding(
            get: { joinError != nil },
            set: { if !$0 { joinError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(joinError ?? "")
        }
    }

    private func joinGroup() async {
        let token = joinToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            _ = try await groupService.joinGroup(token: token)
            joinToken = ""  // Only clear on success
        } catch {
            joinError = error.localizedDescription
        }
    }
}

// Navigation identity wrapper (Identifiable for fullScreenCover)
private struct GroupChatNav: Identifiable {
    let id: String
}

// MARK: - CreateGroupSheet

struct CreateGroupSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var groupName: String = ""
    @State private var aiMode: String = "mention"
    @State private var isCreating = false
    @State private var errorMessage: String? = nil

    private var groupService: GroupChatService { services.groupChatService }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group name") {
                    TextField("Enter name", text: $groupName)
                }

                Section("AI mode") {
                    Picker("AI responds", selection: $aiMode) {
                        Text("When @ai is mentioned").tag("mention")
                        Text("To every message").tag("always")
                    }
                    .pickerStyle(.menu)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isCreating {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Create") { Task { await create() } }
                            .font(.system(size: 15, weight: .semibold))
                            .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            _ = try await groupService.createGroup(name: groupName.trimmingCharacters(in: .whitespaces), aiMode: aiMode)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - GroupChatView

/// Full-screen group chat screen with 5-second polling.
/// TODO(realtime): Replace polling with URLSessionWebSocketTask Durable Object subscription
/// when DO group rooms are available. Call stopPolling() before disconnecting.
struct GroupChatView: View {
    let groupId: String

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var messageText: String = ""
    @State private var isSending = false
    @State private var showInviteCopied = false
    @State private var showLeaveConfirm = false
    @State private var leaveError: String? = nil

    private var groupService: GroupChatService { services.groupChatService }
    private var groupName: String { groupService.currentGroupDetails?.name ?? "Group" }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.backgroundTop.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Member avatars row
                    memberAvatarsRow

                    Divider()

                    // Messages
                    messagesView

                    // Composer
                    composerView
                }
            }
            .navigationTitle(groupName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task {
            try? await groupService.loadGroupDetails(groupId: groupId)
            groupService.startPolling(groupId: groupId)
        }
        .onDisappear {
            groupService.stopPolling()
        }
        // Reduce polling frequency when the app goes to the background to save battery
        .onChange(of: scenePhase) { _, newPhase in
            groupService.setActive(newPhase == .active)
        }
        .confirmationDialog("Leave this group?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leaveGroup() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will no longer receive messages from this group.")
        }
        .alert("Could not leave group", isPresented: Binding(
            get: { leaveError != nil },
            set: { if !$0 { leaveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(leaveError ?? "")
        }
    }

    // MARK: - Member avatars

    private var memberAvatarsRow: some View {
        let members = groupService.currentGroupDetails?.members ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -8) {
                ForEach(members.prefix(10), id: \.userId) { member in
                    MemberAvatarView(member: member)
                }
                if members.count > 10 {
                    ZStack {
                        Circle()
                            .fill(AppTheme.surfacePrimary)
                            .frame(width: 32, height: 32)
                        Text("+\(members.count - 10)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .overlay(Circle().stroke(AppTheme.backgroundTop, lineWidth: 2))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Messages

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(groupService.currentMessages) { msg in
                        GroupMessageBubbleView(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: groupService.currentMessages.count) {
                if let last = groupService.currentMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Composer

    private var composerView: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                TextField(
                    groupService.currentGroupDetails?.aiMode == "mention"
                        ? "Message (use @ai for AI)…"
                        : "Message…",
                    text: $messageText,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .font(.system(size: 15))

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: isSending ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(messageText.isEmpty || isSending ? .secondary : .blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                // Copy invite link
                Button {
                    if let token = groupService.currentGroupDetails?.inviteToken {
                        // Percent-encode token so special characters don't break the URL
                        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
                        let inviteUrl = "https://todus.app/g/\(encoded)"
                        UIPasteboard.general.string = inviteUrl
                        showInviteCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showInviteCopied = false
                        }
                    }
                } label: {
                    Image(systemName: showInviteCopied ? "checkmark" : "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(showInviteCopied ? .green : .primary)
                }
                .buttonStyle(.plain)

                // Leave group menu
                Menu {
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
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
            // Reload immediately so user sees their own message before next poll
            try? await groupService.loadMessages(groupId: groupId)
        } catch {
            messageText = content  // restore on failure
        }
    }

    private func leaveGroup() async {
        do {
            try await groupService.leaveGroup(groupId: groupId)
            dismiss()
        } catch {
            // Show error for all failures; the backend returns a clear message for owner-cannot-leave
            leaveError = error.localizedDescription
        }
    }
}

// MARK: - Supporting views

private struct MemberAvatarView: View {
    let member: GroupMember

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 32, height: 32)
            Text(String((member.name ?? "?").prefix(1)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
        }
        .overlay(Circle().stroke(AppTheme.backgroundTop, lineWidth: 2))
    }
}

private struct GroupMessageBubbleView: View {
    let message: GroupMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.senderType == "user" {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    if let name = message.senderName {
                        Text(name)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(message.content)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
            } else if message.senderType == "ai" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(message.content)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 60)
            } else {
                // System message — centered, muted
                Spacer()
                Text(message.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
    }
}
