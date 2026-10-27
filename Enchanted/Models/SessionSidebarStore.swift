//
//  SessionSidebarStore.swift
//  RuCode Chat
//

import Foundation
import Observation

struct SessionFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var conversationIDs: [UUID]
}

@Observable
final class SessionSidebarStore {
    static let shared = SessionSidebarStore()

    private static let pinnedKey = "rucodePinnedConversations"
    private static let foldersKey = "rucodeSessionFolders"

    private let defaults: UserDefaults
    private(set) var pinnedConversationIDs: Set<UUID>
    private(set) var folders: [SessionFolder]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let pinned = defaults.stringArray(forKey: Self.pinnedKey) ?? []
        pinnedConversationIDs = Set(pinned.compactMap(UUID.init(uuidString:)))

        if let data = defaults.data(forKey: Self.foldersKey),
           let stored = try? JSONDecoder().decode([SessionFolder].self, from: data) {
            folders = stored
        } else {
            folders = []
        }
    }

    func isPinned(_ conversation: ConversationSD) -> Bool {
        pinnedConversationIDs.contains(conversation.id)
    }

    func togglePin(_ conversation: ConversationSD) {
        if pinnedConversationIDs.contains(conversation.id) {
            pinnedConversationIDs.remove(conversation.id)
        } else {
            pinnedConversationIDs.insert(conversation.id)
        }
        persistPinned()
    }

    func folder(containing conversation: ConversationSD) -> SessionFolder? {
        folders.first { $0.conversationIDs.contains(conversation.id) }
    }

    @discardableResult
    func createFolder(named name: String) -> SessionFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let folder = SessionFolder(id: UUID(), name: trimmed, conversationIDs: [])
        folders.append(folder)
        persistFolders()
        return folder
    }

    func add(_ conversation: ConversationSD, toFolder folderID: UUID) {
        for index in folders.indices {
            folders[index].conversationIDs.removeAll { $0 == conversation.id }
        }
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].conversationIDs.append(conversation.id)
        persistFolders()
    }

    func removeFromFolder(_ conversation: ConversationSD) {
        for index in folders.indices {
            folders[index].conversationIDs.removeAll { $0 == conversation.id }
        }
        persistFolders()
    }

    func renameFolder(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
        persistFolders()
    }

    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        persistFolders()
    }

    func forget(_ conversation: ConversationSD) {
        pinnedConversationIDs.remove(conversation.id)
        persistPinned()
        removeFromFolder(conversation)
    }

    private func persistPinned() {
        defaults.set(pinnedConversationIDs.map(\.uuidString), forKey: Self.pinnedKey)
    }

    private func persistFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: Self.foldersKey)
    }
}
