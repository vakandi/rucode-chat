//
//  ConversationHistoryList.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import SwiftUI

struct ConversationGroup: Hashable {
    let date: Date
    var conversations: [ConversationSD]

    // Implementing the Hashable protocol
    static func == (lhs: ConversationGroup, rhs: ConversationGroup) -> Bool {
        lhs.date == rhs.date
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
    }
}

struct ConversationHistoryList: View {
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var onTap: (_ conversation: ConversationSD) -> ()
    var onDelete: (_ conversation: ConversationSD) -> ()
    var onDeleteDailyConversations: (_ date: Date) -> ()

    @State private var sidebarStore = SessionSidebarStore.shared
    @State private var folderPrompt: FolderPrompt?
    @State private var folderNameDraft = ""
    @State private var conversationForNewFolder: ConversationSD?
    @State private var collapsedFolders: Set<UUID> = []

    private enum FolderPrompt: Identifiable {
        case create
        case rename(SessionFolder)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .rename(let folder):
                return "rename-\(folder.id.uuidString)"
            }
        }

        var title: String {
            switch self {
            case .create:
                return "New Session Folder"
            case .rename:
                return "Rename Folder"
            }
        }

        var message: String {
            switch self {
            case .create:
                return "Group related sessions in the sidebar."
            case .rename:
                return "Choose a new name for this folder."
            }
        }
    }

    func groupConversationsByDay(conversations: [ConversationSD]) -> [ConversationGroup] {
        let groupedDictionary = Dictionary(grouping: conversations) { (conversation) -> Date in
            return Calendar.current.startOfDay(for: conversation.updatedAt)
        }

        return groupedDictionary.map { (key, value) in
            ConversationGroup(date: key, conversations: value)
        }.sorted(by: { $0.date > $1.date })
    }

    private var pinnedConversations: [ConversationSD] {
        conversations
            .filter { sidebarStore.isPinned($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var ungroupedConversations: [ConversationSD] {
        conversations.filter { conversation in
            !sidebarStore.isPinned(conversation) && sidebarStore.folder(containing: conversation) == nil
        }
    }

    var conversationGroups: [ConversationGroup] {
        groupConversationsByDay(conversations: ungroupedConversations)
    }

    private func conversations(in folder: SessionFolder) -> [ConversationSD] {
        folder.conversationIDs.compactMap { id in
            conversations.first { $0.id == id }
        }.filter { !sidebarStore.isPinned($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            header

            if !pinnedConversations.isEmpty {
                pinnedSection
                Divider()
            }

            ForEach(sidebarStore.folders) { folder in
                folderSection(folder)
                Divider()
            }

            ForEach(conversationGroups, id: \.date) { conversationGroup in
                HStack {
                    Text(conversationGroup.date.daysAgoString())
                        .font(.system(size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(Color(nsColor: .systemGray))

                    Spacer()
                }
                .contextMenu(menuItems: {
                    Button(role: .destructive, action: { onDeleteDailyConversations(conversationGroup.date) }) {
                        Label("Delete daily conversations", systemImage: "trash")
                    }
                })

                ForEach(conversationGroup.conversations, id: \.self) { dailyConversation in
                    conversationRow(dailyConversation, pinned: false, indented: false)
                }

                Divider()
            }
        }
        .alert(folderPrompt?.title ?? "Session Folder", isPresented: folderPromptPresented) {
            TextField("Folder name", text: $folderNameDraft)
            Button("Save") { saveFolderPrompt() }
            Button("Cancel", role: .cancel) { resetFolderPrompt() }
        } message: {
            Text(folderPrompt?.message ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Chats")
                .font(.system(size: 14))
                .fontWeight(.semibold)
                .foregroundColor(Color(nsColor: .systemGray))

            Spacer()

            Button {
                folderNameDraft = ""
                conversationForNewFolder = nil
                folderPrompt = .create
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemGray))
            }
            .buttonStyle(.plain)
            .help("New session folder")
            .accessibilityLabel("New session folder")
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                Text("Pinned")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundColor(Color(nsColor: .systemGray))

            ForEach(pinnedConversations, id: \.self) { conversation in
                conversationRow(conversation, pinned: true, indented: false)
            }
        }
    }

    private func folderSection(_ folder: SessionFolder) -> some View {
        let members = conversations(in: folder)
        let isCollapsed = collapsedFolders.contains(folder.id)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isCollapsed {
                    collapsedFolders.remove(folder.id)
                } else {
                    collapsedFolders.insert(folder.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                    Text(folder.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(members.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .foregroundColor(Color(nsColor: .systemGray))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    folderNameDraft = folder.name
                    folderPrompt = .rename(folder)
                } label: {
                    Label("Rename Folder", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    sidebarStore.deleteFolder(id: folder.id)
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            }

            if !isCollapsed {
                ForEach(members, id: \.self) { conversation in
                    conversationRow(conversation, pinned: false, indented: true)
                }

                if members.isEmpty {
                    Text("No sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                }
            }
        }
    }

    private func conversationRow(_ conversation: ConversationSD, pinned: Bool, indented: Bool) -> some View {
        Button(action: { onTap(conversation) }) {
            HStack {
                Circle()
                    .frame(width: 6, height: 6)
                    .animation(.easeOut(duration: 0.15))
                    .transition(.opacity)
                    .showIf(selectedConversation == conversation)

                Text(conversation.name)
                    .lineLimit(1)
                    .font(.system(size: 16))
                    .foregroundColor(Color.labelCustom)
                    .animation(.easeOut(duration: 0.15))
                    .transition(.opacity)

                Spacer()

                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, indented ? 24 : 0)
            .animation(.easeOut(duration: 0.15))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                sidebarStore.togglePin(conversation)
            } label: {
                Label(
                    sidebarStore.isPinned(conversation) ? "Unpin" : "Pin",
                    systemImage: sidebarStore.isPinned(conversation) ? "pin.slash" : "pin"
                )
            }

            Menu("Move to Folder") {
                if sidebarStore.folders.isEmpty {
                    Button("No folders yet") {}
                        .disabled(true)
                } else {
                    ForEach(sidebarStore.folders) { folder in
                        Button {
                            sidebarStore.add(conversation, toFolder: folder.id)
                        } label: {
                            if sidebarStore.folder(containing: conversation)?.id == folder.id {
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Text(folder.name)
                            }
                        }
                    }
                }

                Divider()

                Button("New Folder…") {
                    folderNameDraft = ""
                    conversationForNewFolder = conversation
                    folderPrompt = .create
                }

                if sidebarStore.folder(containing: conversation) != nil {
                    Divider()
                    Button("Remove from Folder") {
                        sidebarStore.removeFromFolder(conversation)
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                sidebarStore.forget(conversation)
                onDelete(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var folderPromptPresented: Binding<Bool> {
        Binding(
            get: { folderPrompt != nil },
            set: { presented in
                if !presented {
                    resetFolderPrompt()
                }
            }
        )
    }

    private func saveFolderPrompt() {
        switch folderPrompt {
        case .create:
            if let folder = sidebarStore.createFolder(named: folderNameDraft),
               let conversation = conversationForNewFolder {
                sidebarStore.add(conversation, toFolder: folder.id)
            }
        case .rename(let folder):
            sidebarStore.renameFolder(id: folder.id, name: folderNameDraft)
        case .none:
            break
        }
        resetFolderPrompt()
    }

    private func resetFolderPrompt() {
        folderPrompt = nil
        folderNameDraft = ""
        conversationForNewFolder = nil
    }
}


#Preview {
    ConversationHistoryList(selectedConversation: ConversationSD.sample[0], conversations: ConversationSD.sample, onTap: {_ in}, onDelete: {_ in}, onDeleteDailyConversations: {_ in})
}
