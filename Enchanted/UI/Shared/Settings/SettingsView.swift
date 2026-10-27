//
//  SettingsView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var vibrations: Bool
    @Binding var colorScheme: AppColorScheme
    @Binding var defaultModel: String
    @Binding var appUserInitials: String
    @Binding var pingInterval: String
    @Binding var voiceIdentifier: String
    var save: () -> ()
    var deleteAll: () -> ()
    var models: [LanguageModelSD]
    var voices: [AVSpeechSynthesisVoice]
    
    @State private var deleteConversationsDialog = false
    @AppStorage("rucodeControlURL") private var rucodeControlURL = "http://127.0.0.1:5656"
    @AppStorage("rucodeEngineURL") private var rucodeEngineURL = "http://127.0.0.1:4096"
    @State private var rucodeAuthToken = ""
    @AppStorage("rucodeWorkingDirectory") private var rucodeWorkingDirectory = NSHomeDirectory() + "/Documents"
    @AppStorage("rucodeRepositoryPath") private var rucodeRepositoryPath = ""
    @AppStorage("rucodeSelectedAgent") private var rucodeSelectedAgent = ""
    @State private var rucodeHealth = "Not checked"
    @State private var isCheckingRuCode = false
    @State private var engineAgents: [RuCodeEngineAgent] = []
    @State private var configuredAgents: [RuCodeConfiguredAgents.Agent] = []
    @State private var agentPhotos: [String: Data] = [:]
    @State private var selectedPhotoAgent: String?
    @State private var showAgentPhotoImporter = false
    @State private var schedulingAgent: RuCodeConfiguredAgents.Agent?
    @State private var agentEnableConfirmation: RuCodeConfiguredAgents.Agent?
    @State private var promptTemplateStore = PromptTemplateStore.shared
    @State private var promptTemplateEditor: PromptTemplateEditorContext?

    @MainActor
    private func refreshConfiguredAgents() async {
        do {
            configuredAgents = try await RuCodeAPI.shared.configuredAgents()
            for agent in configuredAgents {
                if let data = try? await RuCodeAPI.shared.agentPhoto(agent.name) { agentPhotos[agent.name] = data }
            }
        } catch { /* Health and auth status already appears above. */ }
    }

    private func imageContentType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        default: return nil
        }
    }

    @ViewBuilder
    private func agentPhoto(_ name: String) -> some View {
        if let data = agentPhotos[name] {
#if os(macOS)
            if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(Circle()) }
            else { Image(systemName: "person.crop.circle.fill").font(.system(size: 38)) }
#else
            if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(Circle()) }
            else { Image(systemName: "person.crop.circle.fill").font(.system(size: 38)) }
#endif
        } else {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 38)).foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func promptTemplateRow(_ template: PromptTemplate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(template.text)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Button {
                promptTemplateStore.move(id: template.id, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(promptTemplateStore.templates.first?.id == template.id)
            .help("Move up")
            .accessibilityLabel("Move prompt template up")

            Button {
                promptTemplateStore.move(id: template.id, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(promptTemplateStore.templates.last?.id == template.id)
            .help("Move down")
            .accessibilityLabel("Move prompt template down")

            Button {
                promptTemplateEditor = PromptTemplateEditorContext(template: template)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Edit prompt template")
            .accessibilityLabel("Edit prompt template")

            Button {
                promptTemplateStore.delete(id: template.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Delete prompt template")
            .accessibilityLabel("Delete prompt template")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray5Custom, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.gray4Custom.opacity(0.35), lineWidth: 1)
        }
    }

    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.primary)
                    }
                    
                    
                    Spacer()
                    
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.primary)
                    }
                }
                
                HStack {
                    Spacer()
                    Text("Settings")
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
            }
            .padding()
            
            Form {
                Section(header: Text("OpenCodeRust Server").font(.headline)) {
                    TextField("Bun control URL", text: $rucodeControlURL)
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Rust engine URL", text: $rucodeEngineURL)
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    SecureField("ELIA_AUTH_TOKEN", text: $rucodeAuthToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Server-visible working directory", text: $rucodeWorkingDirectory)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("OpenCodeRust repository path (lifecycle controls)", text: $rucodeRepositoryPath)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Picker("Prompt agent", selection: $rucodeSelectedAgent) {
                        Text("Server default").tag("")
                        ForEach(engineAgents) { agent in
                            Text(agent.id).tag(agent.id)
                        }
                    }
                    HStack {
                        Text("Engine health")
                        Spacer()
                        Text(rucodeHealth).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Check health") {
                            isCheckingRuCode = true
                            Task {
                                defer { isCheckingRuCode = false }
                                do {
                                    let result = try await RuCodeAPI.shared.serverHealth()
                                    rucodeHealth = "\(result.health_status ?? "unknown") · \(result.child?.status ?? "no child status")"
                                    engineAgents = try await RuCodeAPI.shared.engineAgents()
                                    await refreshConfiguredAgents()
                                } catch {
                                    rucodeHealth = error.localizedDescription
                                }
                            }
                        }
                        .disabled(isCheckingRuCode)
                        Button("Restart Rust child") {
                            isCheckingRuCode = true
                            Task {
                                defer { isCheckingRuCode = false }
                                do {
                                    try await RuCodeAPI.shared.restartChild()
                                    let result = try await RuCodeAPI.shared.serverHealth()
                                    rucodeHealth = "\(result.health_status ?? "unknown") · \(result.child?.status ?? "no child status")"
                                    engineAgents = try await RuCodeAPI.shared.engineAgents()
                                    await refreshConfiguredAgents()
                                } catch {
                                    rucodeHealth = error.localizedDescription
                                }
                            }
                        }
                        .disabled(isCheckingRuCode)
                    }
                    Text("General chat uses the Rust engine. Model choices come from Bun control. These URLs must be reachable from this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !configuredAgents.isEmpty {
                        Divider()
                        Text("Configured Bun subworkers and shared profiles").font(.subheadline.weight(.medium))
                        ForEach(configuredAgents) { agent in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    agentPhoto(agent.name)
                                    VStack(alignment: .leading) {
                                        Text(agent.name).font(.subheadline.weight(.medium))
                                        Text(agent.running ? "Running" : agent.enabled ? "Enabled" : "Disabled")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(agent.enabled ? "Disable" : "Enable and run") {
                                        if agent.enabled {
                                            Task {
                                                do {
                                                    try await RuCodeAPI.shared.setAgentEnabled(agent.name, enabled: false)
                                                    await refreshConfiguredAgents()
                                                } catch { rucodeHealth = error.localizedDescription }
                                            }
                                        } else {
                                            agentEnableConfirmation = agent
                                        }
                                    }
                                    Button("Change photo") { selectedPhotoAgent = agent.name; showAgentPhotoImporter = true }
                                    if agentPhotos[agent.name] != nil {
                                        Button("Remove") {
                                            Task {
                                                do {
                                                    try await RuCodeAPI.shared.deleteAgentPhoto(agent.name)
                                                    agentPhotos[agent.name] = nil
                                                } catch { rucodeHealth = error.localizedDescription }
                                            }
                                        }
                                    }
                                }
                                Button {
                                    schedulingAgent = agent
                                } label: {
                                    HStack {
                                        Image(systemName: "clock")
                                        Text("Schedule: \(ScheduleEditorView.summary(agent.schedule))")
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(header: Text("Prompt Templates").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        if promptTemplateStore.templates.isEmpty {
                            Text("No prompt templates yet. Add one to show it on the empty chat screen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 8) {
                                    ForEach(promptTemplateStore.templates) { template in
                                        promptTemplateRow(template)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(maxHeight: 230)
                        }

                        HStack {
                            Button {
                                promptTemplateEditor = PromptTemplateEditorContext(template: nil)
                            } label: {
                                Label("Add prompt template", systemImage: "plus")
                            }
                            Spacer()
                        }

                        Text("These cards appear when no conversation is open. Long prompts are truncated on the card; use the pencil to edit one without opening Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Chat").font(.headline)) {
                    Picker(selection: $defaultModel) {
                        ForEach(models, id:\.self) { model in
                            Text(model.name).tag(model.name)
                        }
                    } label: {
                        Label {
                            Text("Default Model")
                        } icon: {
                            Image(systemName: "cpu")
                        }
                    }
                    
                    
                    TextField("Ping Interval (seconds)", text: $pingInterval)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Section(header: Text("APP").font(.headline).padding(.top, 20)) {
                        
#if os(iOS)
                        Toggle(isOn: $vibrations, label: {
                            Label("Vibrations", systemImage: "water.waves")
                                .foregroundStyle(Color.primary)
                        })
#endif
                    }
                    
                    
                    Picker(selection: $colorScheme) {
                        ForEach(AppColorScheme.allCases, id:\.self) { scheme in
                            Text(scheme.toString).tag(scheme.id)
                        }
                    } label: {
                        Label("Appearance", systemImage: "sun.max")
                            .foregroundStyle(Color.primary)
                    }
                    
                    Picker(selection: $voiceIdentifier) {
                        ForEach(voices, id:\.self.identifier) { voice in
                            Text(voice.prettyName).tag(voice.identifier)
                        }
                    } label: {
                        Label("Voice", systemImage: "waveform")
                            .foregroundStyle(Color.primary)
                        
#if os(macOS)
                        Text("Download voices by going to Settings > Accessibility > Spoken Content > System Voice > Manage Voices.")
#else
                        Text("Download voices by going to Settings > Accessibility > Spoken Content > Voices.")
#endif
                        
                        Button(action: {
#if os(macOS)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems") {
                                NSWorkspace.shared.open(url)
                            }
#else
                            let url = URL(string: "App-Prefs:root=General&path=ACCESSIBILITY")
                            if let url = url, UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
#endif
                            
                        }) {
                            
                            Text("Open Settings")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    
                    TextField("Initials", text: $appUserInitials)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
#endif
                    
                    Button(action: {deleteConversationsDialog.toggle()}) {
                        HStack {
                            Spacer()
                            
                            Text("Clear All Data")
                                .foregroundStyle(Color.red)
                                .padding(.vertical, 6)
                            
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
        .confirmationDialog("Delete All Conversations?", isPresented: $deleteConversationsDialog) {
            Button("Delete", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Delete All Conversations?")
        }
        .confirmationDialog("Enable \(agentEnableConfirmation?.name ?? "subworker")?", isPresented: Binding(
            get: { agentEnableConfirmation != nil },
            set: { if !$0 { agentEnableConfirmation = nil } }
        )) {
            Button("Enable and run now") {
                guard let agent = agentEnableConfirmation else { return }
                agentEnableConfirmation = nil
                Task {
                    do {
                        try await RuCodeAPI.shared.setAgentEnabled(agent.name, enabled: true)
                        await refreshConfiguredAgents()
                    } catch { rucodeHealth = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { agentEnableConfirmation = nil }
        } message: {
            Text("Enabling this subworker immediately triggers its configured task.")
        }
        .sheet(item: $schedulingAgent) { agent in
            ScheduleEditorView(
                agentName: agent.name,
                photo: agentPhotos[agent.name],
                schedule: agent.schedule
            ) { schedule in
                try await RuCodeAPI.shared.setAgentSchedule(agent.name, schedule: schedule)
                await refreshConfiguredAgents()
            }
        }
        .sheet(item: $promptTemplateEditor) { context in
            PromptTemplateEditorView(
                isNew: context.template == nil,
                initialText: context.template?.text ?? ""
            ) { text in
                if let template = context.template {
                    promptTemplateStore.update(id: template.id, text: text)
                } else {
                    promptTemplateStore.add(text: text)
                }
            }
        }
        .fileImporter(isPresented: $showAgentPhotoImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard let agent = selectedPhotoAgent else { return }
            Task {
                do {
                    guard let url = try result.get().first, let contentType = imageContentType(for: url) else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    try await RuCodeAPI.shared.uploadAgentPhoto(agent, data: data, contentType: contentType)
                    agentPhotos[agent] = data
                } catch { rucodeHealth = error.localizedDescription }
            }
        }
        .onAppear {
            if let token = RuCodeCredentialStore.load() {
                rucodeAuthToken = token
            } else if let legacyToken = UserDefaults.standard.string(forKey: "rucodeAuthToken") {
                rucodeAuthToken = legacyToken
                RuCodeCredentialStore.save(legacyToken)
                UserDefaults.standard.removeObject(forKey: "rucodeAuthToken")
            }
        }
        .onChange(of: rucodeAuthToken) { _, token in
            RuCodeCredentialStore.save(token)
            UserDefaults.standard.removeObject(forKey: "rucodeAuthToken")
        }
    }
}

#Preview {
    SettingsView(
        vibrations: .constant(true),
        colorScheme: .constant(.light),
        defaultModel: .constant("opencode/example-model"),
        appUserInitials: .constant("AM"),
        pingInterval: .constant("5"),
        voiceIdentifier: .constant("sample"),
        save: {},
        deleteAll: {},
        models: LanguageModelSD.sample,
        voices: []
    )
}

