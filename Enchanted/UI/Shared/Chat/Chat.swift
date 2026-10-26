//
//  MainView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 09/12/2023.
//

import SwiftUI

struct Chat: View, Sendable {
    @State private var languageModelStore: LanguageModelStore
    @State private var conversationStore: ConversationStore
    @State private var appStore: AppStore
    @AppStorage("appUserInitials") private var userInitials: String = ""
    @AppStorage("rucodeDefaultModel") private var defaultModel: String = ""
    @AppStorage("rucodeWorkingDirectory") private var defaultWorkingDirectory = NSHomeDirectory() + "/Documents"
    @State var showMenu = false
    @State private var showNewChatDirectoryPrompt = false
    @State private var newChatDirectory = ""
    
    init(languageModelStore: LanguageModelStore, conversationStore: ConversationStore, appStore: AppStore) {
        _languageModelStore = State(initialValue: languageModelStore)
        _conversationStore = State(initialValue: conversationStore)
        _appStore = State(initialValue: appStore)
    }
    
    func toggleMenu() {
        withAnimation(.spring) {
            showMenu.toggle()
        }
        Task {
            await Haptics.shared.mediumTap()
        }
    }
    
    @MainActor
    func updateSelectedModel() {
        if languageModelStore.selectedModel == nil {
            if !defaultModel.isEmpty {
                languageModelStore.setModel(modelName: defaultModel)
            } else {
                languageModelStore.setModel(model: languageModelStore.models.first)
            }
        }
    }
    
    @MainActor
    func sendMessage(prompt: String, model: LanguageModelSD, image: Image?, trimmingMessageId: String?) {
        conversationStore.sendPrompt(
            userPrompt: prompt,
            model: model,
            image: image,
            trimmingMessageId: trimmingMessageId
        )
    }
    
    func onConversationTap(_ conversation: ConversationSD) {
        Task {
            try await conversationStore.selectConversation(conversation)
            await languageModelStore.setModel(model: conversation.model)
            Haptics.shared.mediumTap()
        }
        withAnimation {
            showMenu.toggle()
        }
    }
    
    @MainActor func onStopGenerateTap() {
        conversationStore.stopGenerate()
        Haptics.shared.mediumTap()
    }
    
    func onConversationDelete(_ conversation: ConversationSD) {
        Task {
            await Haptics.shared.mediumTap()
            try? await conversationStore.delete(conversation)
        }
    }
    
    func newConversation() {
        newChatDirectory = defaultWorkingDirectory
        showNewChatDirectoryPrompt = true
    }

    @MainActor
    private func createConversation(in directory: String) async {
        let conversation = ConversationSD(name: "New Chat", workDirectory: directory)
        do {
            try await conversationStore.create(conversation)
            conversationStore.selectedConversation = conversation
            conversationStore.messages = []
            try? await conversationStore.loadConversations()
        } catch {
            conversationStore.conversationState = .error(message: error.localizedDescription)
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.3)) { self.showMenu = false }
        }
        Task {
            await Haptics.shared.mediumTap()
            try? await languageModelStore.loadModels()
        }
        
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
    
    func copyChat(_ json: Bool) {
        Task {
            let messages = await ConversationStore.shared.messages
            
            if messages.count == 0 {
                return
            }
            
            if json {
                let jsonArray = messages.map { message in
                    return [
                        "role": message.role,
                        "content": message.content
                    ]
                }
                let jsonEncoder = JSONEncoder()
                jsonEncoder.outputFormatting = [.withoutEscapingSlashes]

                if let jsonData = try? jsonEncoder.encode(jsonArray),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    Clipboard.shared.setString(jsonString)
                }
            } else {
                let body = messages.map { message -> String in
                    "\(message.role.capitalized): \(message.content)"
                }.joined(separator: "\n\n")
                Clipboard.shared.setString(body)
            }
        }
    }
    
    var body: some View {
        content
        .onChange(of: languageModelStore.models) { _, _ in
            if languageModelStore.selectedModel == nil {
                updateSelectedModel()
            }
        }
        .onAppear {
            if defaultModel.isEmpty, let legacy = UserDefaults.standard.string(forKey: "defaultOllamaModel") {
                defaultModel = legacy
            }
        }
        .onChange(of: conversationStore.selectedConversation, initial: true) { _, newConversation in
            handleSelectedConversationChange(newConversation)
        }
        .alert("Working directory for new chat", isPresented: $showNewChatDirectoryPrompt) {
            TextField("Server-visible absolute path", text: $newChatDirectory)
#if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Create chat") {
                createConversationFromPrompt()
            }
        } message: {
            Text("Choose the absolute folder path as seen by the RuCode server. This is saved for this conversation.")
        }
    }

    private func handleSelectedConversationChange(_ newConversation: ConversationSD?) {
        if let conversation = newConversation {
            languageModelStore.setModel(model: conversation.model)
        } else {
            updateSelectedModel()
        }
    }

    private func createConversationFromPrompt() {
        let directory = newChatDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else { return }
        Task { await createConversation(in: directory) }
    }

    // The concrete `ChatView` return type keeps the compiler from solving the
    // whole 18-argument generic expression as one constraint system.
    @ViewBuilder
    private var content: some View {
        Group {
#if os(macOS) || os(visionOS)
            chatViewMacOS
#else
            SideBarStack(sidebarWidth: 300, showSidebar: $showMenu, sidebar: {
                SidebarView(
                    selectedConversation: conversationStore.selectedConversation,
                    conversations: conversationStore.conversations,
                    onConversationTap: onConversationTap,
                    onConversationDelete: onConversationDelete,
                    onDeleteDailyConversations: conversationStore.deleteDailyConversations
                )
            }) {
                ChatView(
                    conversation: conversationStore.selectedConversation,
                    messages: conversationStore.messages,
                    modelsList: languageModelStore.models,
                    selectedModel: languageModelStore.selectedModel,
                    onSelectModel: languageModelStore.setModel,
                    onMenuTap: toggleMenu,
                    onNewConversationTap: newConversation,
                    onSendMessageTap: sendMessage,
                    conversationState: conversationStore.conversationState,
                    onStopGenerateTap: onStopGenerateTap,
                    reachable: appStore.isReachable,
                    modelSupportsImages: languageModelStore.supportsImages,
                    userInitials: userInitials
                )
            }
#endif
        }
    }

#if os(macOS) || os(visionOS)
    private var chatViewMacOS: ChatView {
        ChatView(
            selectedConversation: conversationStore.selectedConversation,
            conversations: conversationStore.conversations,
            messages: conversationStore.messages,
            modelsList: languageModelStore.models,
            onMenuTap: toggleMenu,
            onNewConversationTap: newConversation,
            onSendMessageTap: sendMessage,
            onConversationTap: onConversationTap,
            conversationState: conversationStore.conversationState,
            onStopGenerateTap: onStopGenerateTap,
            reachable: appStore.isReachable,
            modelSupportsImages: languageModelStore.supportsImages,
            selectedModel: languageModelStore.selectedModel,
            onSelectModel: languageModelStore.setModel,
            onConversationDelete: onConversationDelete,
            onDeleteDailyConversations: conversationStore.deleteDailyConversations,
            userInitials: userInitials,
            copyChat: copyChat
        )
    }
#endif
}
