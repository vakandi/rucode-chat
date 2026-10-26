//
//  InputFields_macOS.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/02/2024.
//

#if os(macOS) || os(visionOS)
import SwiftUI

struct InputFieldsView: View {
    @Binding var message: String
    var conversationState: ConversationState
    var onStopGenerateTap: @MainActor () -> Void
    var selectedModel: LanguageModelSD?
    var onSendMessageTap: @MainActor (_ prompt: String, _ model: LanguageModelSD, _ image: Image?, _ trimmingMessageId: String?) -> ()
    @Binding var editMessage: MessageSD?
    
    @State private var selectedImage: Image?
    @State private var attachedFiles: [URL] = []
    @State private var fileDropActive: Bool = false
    @State private var fileSelectingActive: Bool = false
    @State private var documentSelectingActive: Bool = false
    @State private var showModelAlert: Bool = false
    @FocusState private var isFocusedInput: Bool
    
    @MainActor private func sendMessage() {
        let hasText = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || !attachedFiles.isEmpty else { return }
        guard let selectedModel = selectedModel else {
            showModelAlert = true
            return
        }
        
        onSendMessageTap(
            promptWithAttachments(),
            selectedModel,
            selectedImage,
            editMessage?.id.uuidString
        )
        withAnimation {
            isFocusedInput = false
            editMessage = nil
            selectedImage = nil
            attachedFiles = []
            message = ""
        }
    }
    
    /// The server only receives text, so attachments travel as their absolute
    /// paths on their own lines, ahead of whatever the user typed.
    private func promptWithAttachments() -> String {
        guard !attachedFiles.isEmpty else { return message }
        let listing = attachedFiles.map { "- \($0.path)" }.joined(separator: "\n")
        return "Attached files:\n\(listing)\n\n\(message)"
    }
    
    private func fileIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "swift", "py", "ts", "tsx", "js", "jsx", "rs", "go", "java", "rb", "sh", "zsh", "json", "yml", "yaml", "toml", "md", "txt", "html", "css", "sql":
            return "chevron.left.forwardslash.chevron.right"
        case "zip", "tar", "gz", "rar", "7z", "dmg":
            return "doc.zipper"
        case "csv", "xlsx", "xls", "numbers":
            return "tablecells"
        default:
            return "doc.fill"
        }
    }
    
    private func attachmentChip(_ url: URL) -> some View {
        HStack(spacing: 4) {
            Image(systemName: fileIcon(for: url))
                .font(.system(size: 10, weight: .semibold))
            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Button {
                attachedFiles.removeAll { $0 == url }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Color.accentColor)
        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35)))
        .help(url.path)
    }
    
    private func updateSelectedImage(_ image: Image) {
        selectedImage = image
    }
    
#if os(macOS)
    var hotkeys: [HotkeyCombination] {
        [
            HotkeyCombination(keyBase: [.command], key: .kVK_ANSI_V) {
                if let nsImage = Clipboard.shared.getImage() {
                    let image = Image(nsImage: nsImage)
                    updateSelectedImage(image)
                }
            }
        ]
    }
#endif
    
    var body: some View {
        HStack(spacing: 20) {
            if let image = selectedImage {
                RemovableImage(
                    image: image,
                    onClick: {selectedImage = nil},
                    height: 70
                )
                .padding(5)
            }
            
            ZStack(alignment: .trailing) {
                VStack(alignment: .leading, spacing: 6) {
                    if !attachedFiles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(attachedFiles, id: \.self) { url in
                                    attachmentChip(url)
                                }
                            }
                            .padding(.top, 6)
                        }
                        .frame(maxHeight: 30)
                    }

                    TextField("Message", text: $message.animation(.easeOut(duration: 0.3)), axis: .vertical)
                        .focused($isFocusedInput)
                        .font(.system(size: 14))
                        .frame(maxWidth:.infinity, minHeight: 40)
                        .clipped()
                        .textFieldStyle(.plain)
#if os(macOS)
                        .onSubmit {
                            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                                message += "\n"
                            } else {
                                sendMessage()
                            }
                        }
#endif
                    /// TextField bypasses drop area
                        .allowsHitTesting(!fileDropActive)
#if os(macOS)
                        .addCustomHotkeys(hotkeys)
#endif
                        .padding(.leading, 28)
                        .padding(.trailing, 80)
                }
                
                HStack {
                    
                    SimpleFloatingButton(systemImage: "photo.fill", onClick: { fileSelectingActive.toggle() })
                        .showIf(selectedModel?.supportsImages ?? false)
                        .fileImporter(isPresented: $fileSelectingActive,
                                      allowedContentTypes: [.png, .jpeg, .tiff],
                                      onCompletion: { result in
                            switch result {
                            case .success(let url):
                                guard url.startAccessingSecurityScopedResource() else { return }
                                if let imageData = try? Data(contentsOf: url) {
                                    selectedImage = Image(data: imageData)
                                }
                                url.stopAccessingSecurityScopedResource()
                            case .failure(let error):
                                print(error)
                            }
                        })
                    
                    
                    SimpleFloatingButton(systemImage: "paperplane.fill", onClick: { Task { sendMessage() } })
                        .showIf(!message.isEmpty || !attachedFiles.isEmpty)
                    
                }
            }
            .overlay(alignment: .bottomLeading) {
                SimpleFloatingButton(systemImage: "paperclip") {
                    documentSelectingActive = true
                }
                .padding(.leading, 6)
                .padding(.bottom, 11)
                .help("Attach a file — its absolute path is sent with the message")
            }
            .fileImporter(
                isPresented: $documentSelectingActive,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                for url in urls where !attachedFiles.contains(url) {
                    attachedFiles.append(url)
                }
            }
            
        }
        .transition(.slide)
        .padding(.horizontal)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    Color.gray2Custom,
                    style: StrokeStyle(lineWidth: 1)
                )
        )
        .overlay {
            if fileDropActive {
                DragAndDrop(cornerRadius: 10)
            }
        }
        .animation(.default, value: fileDropActive)
        .onDrop(of: [.image], isTargeted: $fileDropActive.animation(), perform: { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(for: .image) { data, error in
                if error == nil, let data {
                    selectedImage = Image(data: data)
                }
            }
            
            return true
        })
        .contentShape(Rectangle())
        .onTapGesture {
            // allow focusing text area on greater tap area
            isFocusedInput = true
        }
        .alert("Select a model first", isPresented: $showModelAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pick a model from the toolbar before sending your message.")
        }
    }
}

#Preview {
    @State var message = ""
    return InputFieldsView(
        message: $message,
        conversationState: .completed,
        onStopGenerateTap: {},
        onSendMessageTap: {_, _, _, _  in},
        editMessage: .constant(nil)
    )
}
#endif
