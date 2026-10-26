//
//  PromptPanelVM.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 29/02/2024.
//

import SwiftUI

@Observable
final class CompletionsPanelVM {
    var selectedText: String?
    var onReceiveText: (String) -> ()
    var messageResponse: String = ""
    var isReady = false
    let sentenceQueue = AsyncQueue<String>()
    private var generation: Task<Void, Never>?
    private var currentMessageBuffer: String = ""

    
    init(onReceiveText: @escaping (String) -> Void = {_ in}) {
        self.onReceiveText = onReceiveText
    }
    
    static func constructPrompt(completion: CompletionInstructionSD, selectedText: String) -> String {
        var prompt = completion.instruction
        
        if prompt.contains("{{text}}") {
            prompt.replace("{{text}}", with: selectedText)
        } else {
            prompt += " " + selectedText
        }
        
        return prompt
    }
    
    @MainActor
    func sendPrompt(completion: CompletionInstructionSD, model: LanguageModelSD)  {
        guard let selectedText = selectedText, !isReady else { return }
        let prompt = CompletionsPanelVM.constructPrompt(completion: completion, selectedText: selectedText)
        
        currentMessageBuffer = ""
        messageResponse = ""
        
        Task {
            do {
                let directory = UserDefaults.standard.string(forKey: "rucodeWorkingDirectory") ?? ""
                guard !directory.isEmpty else { self.handleError("Set the server-visible working directory in RuCode Chat Settings."); return }
                let session = try await RuCodeAPI.shared.createSession(directory: directory, title: "Text completion")
                let events = try await RuCodeAPI.shared.connectEvents()
                let agent = UserDefaults.standard.string(forKey: "rucodeSelectedAgent")
                try await RuCodeAPI.shared.prompt(sessionID: session.id, message: prompt, model: model.name, agent: agent)
                generation = Task { [weak self] in
                    do {
                        for try await event in events where event.sessionID == session.id {
                            if let delta = event.text {
                                await self?.handleReceive(delta)
                            }
                            if event.type == "prompt.final" {
                                await self?.handleComplete()
                                return
                            }
                        }
                        await self?.handleError("Live connection ended before prompt.final.")
                    } catch {
                        await self?.handleError(error.localizedDescription)
                    }
                }
            } catch {
                self.handleError(error.localizedDescription)
            }
        }
    }
    
    @MainActor
    private func handleReceive(_ responseContent: String)  {
        Task { await sentenceQueue.enqueue(responseContent) }
        messageResponse += responseContent
    }
    
    @MainActor
    private func handleError(_ errorMessage: String) {
        print("error \(errorMessage)")
    }
    
    @MainActor
    private func handleComplete() {
        print("model response ", self.messageResponse)
    }
    
    @MainActor
    func cancel() {
        generation?.cancel()
    }
}
