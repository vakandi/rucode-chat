//
//  Settings.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 28/12/2023.
//

import SwiftUI
import Combine

struct Settings: View {
    var languageModelStore = LanguageModelStore.shared
    var conversationStore = ConversationStore.shared
    var swiftDataService = SwiftDataService.shared
    
    @AppStorage("vibrations") private var vibrations: Bool = true
    @AppStorage("colorScheme") private var colorScheme = AppColorScheme.system
    @AppStorage("rucodeDefaultModel") private var defaultModel: String = ""
    @AppStorage("appUserInitials") private var appUserInitials: String = ""
    @AppStorage("pingInterval") private var pingInterval: String = "5"
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = ""
    
    @StateObject private var speechSynthesiser = SpeechSynthesizer.shared
    
    @Environment(\.presentationMode) var presentationMode
    
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var cancellable: AnyCancellable?
    
    private func save() {
        Task {
            Haptics.shared.mediumTap()
            try? await languageModelStore.loadModels()
        }
        presentationMode.wrappedValue.dismiss()
    }
    
    private func deleteAll() {
        Task {
            try? await conversationStore.deleteAllConversations()
            try? await languageModelStore.deleteAllModels()
        }
    }
    
    var body: some View {
        SettingsView(
            vibrations: $vibrations,
            colorScheme: $colorScheme,
            defaultModel: $defaultModel,
            appUserInitials: $appUserInitials,
            pingInterval: $pingInterval,
            voiceIdentifier: $voiceIdentifier,
            save: save,
            deleteAll: deleteAll,
            models: languageModelStore.models,
            voices: speechSynthesiser.voices
        )
        .frame(maxWidth: 700)
        #if os(visionOS)
        .frame(minWidth: 600, minHeight: 800)
        #endif
        .onChange(of: defaultModel) { _, modelName in
            languageModelStore.setModel(modelName: modelName)
        }
        .onAppear {
            if defaultModel.isEmpty, let legacy = UserDefaults.standard.string(forKey: "defaultOllamaModel") {
                defaultModel = legacy
            }
            /// refresh voices in the background
            cancellable = timer.sink { _ in
                speechSynthesiser.fetchVoices()
            }
        }
        .onDisappear {
            cancellable?.cancel()
        }
    }
}

#Preview {
    Settings()
}
