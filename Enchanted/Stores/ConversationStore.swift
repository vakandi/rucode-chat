//
//  ChatsStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import Combine
import SwiftUI

@Observable
final class ConversationStore: Sendable {
    static let shared = ConversationStore(swiftDataService: SwiftDataService.shared)
    
    private var swiftDataService: SwiftDataService
    private var generation: Task<Void, Never>?
    
    /// For some reason (SwiftUI bug / too frequent UI updates) updating UI for each stream message sometimes freezes the UI.
    /// Throttling UI updates seem to fix the issue.
    private var currentMessageBuffer: String = ""
#if os(macOS)
    private let throttler = Throttler(delay: 0.1)
#else
    private let throttler = Throttler(delay: 0.1)
#endif
    
    @MainActor var conversationState: ConversationState = .completed
    @MainActor var conversations: [ConversationSD] = []
    @MainActor var selectedConversation: ConversationSD?
    @MainActor var messages: [MessageSD] = []
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    func loadConversations() async throws {
        print("loading conversations")
        var fetchedConversations = try await swiftDataService.fetchConversations()
        let directory = UserDefaults.standard.string(forKey: "rucodeWorkingDirectory") ?? ""
        if !directory.isEmpty, let remoteSessions = try? await RuCodeAPI.shared.listSessions(directory: directory) {
            var remoteIDs = UserDefaults.standard.dictionary(forKey: "rucodeSessionIDs") as? [String: String] ?? [:]
            for session in remoteSessions {
                if fetchedConversations.contains(where: { remoteIDs[$0.id.uuidString] == session.id }) { continue }
                let conversation = ConversationSD(name: session.title?.isEmpty == false ? session.title! : "OpenCodeRust session")
                remoteIDs[conversation.id.uuidString] = session.id
                try? await swiftDataService.createConversation(conversation)
                fetchedConversations.append(conversation)
            }
            UserDefaults.standard.set(remoteIDs, forKey: "rucodeSessionIDs")
        }
        DispatchQueue.main.async {
            self.conversations = fetchedConversations.sorted { $0.updatedAt > $1.updatedAt }
        }
        print("loaded conversations")
    }
    
    func deleteAllConversations() {
        Task {
            DispatchQueue.main.async { [weak self] in
                self?.messages = []
                self?.selectedConversation = nil
            }
            try? await swiftDataService.deleteConversations()
            try? await swiftDataService.deleteMessages()
            try? await loadConversations()
        }
    }
    
    func deleteDailyConversations(_ date: Date) {
        Task {
            DispatchQueue.main.async { [self] in
                selectedConversation = nil
                messages = []
            }
            try? await swiftDataService.deleteConversations(date)
            try? await loadConversations()
        }
    }
    
    
    func create(_ conversation: ConversationSD) async throws {
        try await swiftDataService.createConversation(conversation)
    }
    
    func reloadConversation(_ conversation: ConversationSD) async throws {
        let remoteIDs = UserDefaults.standard.dictionary(forKey: "rucodeSessionIDs") as? [String: String] ?? [:]
        if let remoteID = remoteIDs[conversation.id.uuidString],
           let remoteMessages = try? await RuCodeAPI.shared.messages(sessionID: remoteID) {
            let messages = remoteMessages.map { item -> MessageSD in
                let content = (item.parts ?? []).compactMap { $0.type == "text" ? $0.text : nil }.joined()
                return MessageSD(content: content, role: item.info.role, done: true)
            }
            DispatchQueue.main.async {
                self.messages = messages
                self.selectedConversation = conversation
            }
            return
        }
        let (messages, selectedConversation) = try await (
            swiftDataService.fetchMessages(conversation.id),
            swiftDataService.getConversation(conversation.id)
        )
        
        DispatchQueue.main.async {
                self.messages = messages
                self.selectedConversation = selectedConversation
        }
    }
    
    func selectConversation(_ conversation: ConversationSD) async throws {
        try await reloadConversation(conversation)
    }
    
    func delete(_ conversation: ConversationSD) async throws {
        try await swiftDataService.deleteConversation(conversation)
        let fetchedConversations = try await swiftDataService.fetchConversations()
        DispatchQueue.main.async {
            self.selectedConversation = nil
            self.conversations = fetchedConversations
        }
    }
    
    @MainActor func stopGenerate() {
        generation?.cancel()
        handleError("Stopped receiving live updates. The OpenCodeRust turn may still be running.")
    }
    
    @MainActor
    func sendPrompt(userPrompt: String, model: LanguageModelSD, image: Image? = nil, trimmingMessageId: String? = nil) {
        guard userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }
        guard image == nil else {
            conversationState = .error(message: "Image prompts are not supported by the OpenCodeRust integration yet.")
            return
        }

        let conversation = selectedConversation ?? ConversationSD(name: userPrompt)
        conversation.updatedAt = Date.now
        conversation.model = model

        /// trim conversation if on edit mode
        if let trimmingMessageId = trimmingMessageId {
            conversation.messages = Array(
                conversation.messages
                    .sorted { $0.createdAt < $1.createdAt }
                    .prefix(while: { $0.id.uuidString != trimmingMessageId })
            )
        }

        /// construct new message
        let userMessage = MessageSD(content: userPrompt, role: "user", image: image?.render()?.compressImageData())
        userMessage.conversation = conversation

        let assistantMessage = MessageSD(content: "", role: "assistant")
        assistantMessage.conversation = conversation

        /// Show the new turn immediately. For an existing session, reloading the
        /// remote transcript here would wipe the just-sent bubble (the server
        /// does not have it yet) and the assistant placeholder, killing the loader.
        if selectedConversation == nil {
            messages = []
        }
        selectedConversation = conversation
        messages.append(contentsOf: [userMessage, assistantMessage])

        conversationState = .loading
        resetStreamBuffer()

        generation?.cancel()
        generation = Task { [weak self] in
            guard let self else { return }
            try? await swiftDataService.updateConversation(conversation)
            try? await swiftDataService.createMessage(userMessage)
            try? await swiftDataService.createMessage(assistantMessage)
            try? await loadConversations()

            do {
                let directory = conversation.workDirectory ?? UserDefaults.standard.string(forKey: "rucodeWorkingDirectory") ?? ""
                guard !directory.isEmpty else {
                    await MainActor.run { self.handleError("Set a server-visible working directory in Settings before starting a chat.") }
                    return
                }
                var remoteSessions = UserDefaults.standard.dictionary(forKey: "rucodeSessionIDs") as? [String: String] ?? [:]
                let key = conversation.id.uuidString
                let remoteID: String
                if let existingID = remoteSessions[key] {
                    remoteID = existingID
                } else {
                    let session = try await RuCodeAPI.shared.createSession(directory: directory, title: conversation.name)
                    remoteID = session.id
                    remoteSessions[key] = remoteID
                    UserDefaults.standard.set(remoteSessions, forKey: "rucodeSessionIDs")
                }

                let agent = UserDefaults.standard.string(forKey: "rucodeSelectedAgent")
                var finished = false
                var attempt = 0

                while !finished && !Task.isCancelled {
                    if attempt > 0 {
                        // The turn keeps running server-side: reconnect and keep
                        // consuming instead of re-sending the prompt.
                        try? await Task.sleep(nanoseconds: 750_000_000 * UInt64(attempt))
                    }
                    do {
                        // Subscribe before the prompt so nothing can race past us.
                        let events = try await RuCodeAPI.shared.connectEvents()
                        if attempt == 0 {
                            try await RuCodeAPI.shared.prompt(
                                sessionID: remoteID,
                                message: userPrompt,
                                model: model.name,
                                agent: agent,
                                system: nil
                            )
                        }
                        for try await event in events {
                            guard event.sessionID == remoteID else { continue }
                            if event.type == "prompt.final" {
                                finished = true
                                break
                            }
                            await MainActor.run { self.apply(streamEvent: event) }
                        }
                    } catch {
                        print("SSE attempt \(attempt) failed: \(error.localizedDescription)")
                    }
                    attempt += 1
                    if attempt >= 3 && !finished { break }
                }

                await self.finalizeTurn(remoteID: remoteID, reportedFinal: finished)
            } catch {
                await MainActor.run { self.handleError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Live stream reconciliation

    /// Parts streamed for the current turn, keyed by part id. `snapshots` holds the
    /// first full `message.part.updated` payload so the following delta can prepend
    /// it exactly once instead of duplicating text.
    @MainActor private var streamPartSnapshots: [String: String] = [:]
    @MainActor private var streamPartTexts: [String: String] = [:]
    @MainActor private var streamPartOrder: [String] = []

    @MainActor
    private func resetStreamBuffer() {
        streamPartSnapshots = [:]
        streamPartTexts = [:]
        streamPartOrder = []
    }

    @MainActor
    private func apply(streamEvent event: RuCodeEvent) {
        guard let partID = event.partID, let text = event.text else { return }
        switch event.type {
        case "part.updated":
            streamPartSnapshots[partID] = text
            // A part we already track was rewritten: replace, never append.
            if streamPartTexts[partID] != nil {
                streamPartTexts[partID] = text
                renderStreamBuffer()
            }
        case "part.delta":
            if streamPartTexts[partID] == nil {
                streamPartTexts[partID] = (streamPartSnapshots[partID] ?? "") + text
                streamPartOrder.append(partID)
            } else {
                streamPartTexts[partID]? += text
            }
            renderStreamBuffer()
        default:
            break
        }
    }

    @MainActor
    private func renderStreamBuffer() {
        guard !messages.isEmpty else { return }
        let joined = streamPartOrder.compactMap { streamPartTexts[$0] }.joined()
        messages[messages.count - 1].content = joined
    }

    /// Reconciles the turn with the server transcript: the live buffer can miss
    /// text across a reconnect, and provider failures arrive as assistant content
    /// even when `prompt.final` is emitted.
    private func finalizeTurn(remoteID: String, reportedFinal: Bool) async {
        var finalText: String?
        if let stored = try? await RuCodeAPI.shared.messages(sessionID: remoteID),
           let assistant = stored.last(where: { $0.info.role == "assistant" }) {
            finalText = (assistant.parts ?? [])
                .compactMap { $0.type == "text" ? $0.text : nil }
                .joined()
        }

        await MainActor.run {
            if let finalText, !finalText.isEmpty {
                self.messages.last?.content = finalText
            }
            if let finalText, finalText.hasPrefix("Provider error:") {
                self.handleError(finalText)
            } else if reportedFinal || self.messages.last?.content.isEmpty == false {
                self.handleComplete()
            } else {
                self.handleError("Live connection ended before the Rust server reported prompt.final. The turn may still be running.")
            }
        }
    }
    
    @MainActor
    private func handleError(_ errorMessage: String) {
        guard let lastMesasge = messages.last else { return }
        lastMesasge.error = true
        lastMesasge.done = false
        
        Task(priority: .background) {
            try? await swiftDataService.updateMessage(lastMesasge)
        }
        
        withAnimation {
            conversationState = .error(message: errorMessage)
        }
    }
    
    @MainActor
    private func handleComplete() {
        guard let lastMesasge = messages.last else { return }
        lastMesasge.error = false
        lastMesasge.done = true
        
        Task(priority: .background) {
            try await self.swiftDataService.updateMessage(lastMesasge)
        }
        
        withAnimation {
            conversationState = .completed
        }
    }
}
