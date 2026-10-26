//
//  MessageListVIew.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MessageListView: View {
    var messages: [MessageSD]
    var conversationState: ConversationState
    var userInitials: String
    @Binding var editMessage: MessageSD?
    @State private var messageSelected: MessageSD?
    @StateObject private var speechSynthesizer = SpeechSynthesizer.shared
    
    func onEditMessageTap() -> (MessageSD) -> Void {
        return { message in
            editMessage = message
        }
    }
    
    func onReadAloud(_ message: String) {
        Task {
            await speechSynthesizer.speak(text: message)
        }
    }
    
    func stopReadingAloud() {
        Task {
            await speechSynthesizer.stopSpeaking()
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message)
                        }
                    }
                }
                .onAppear {
                    scrollViewProxy.scrollTo(messages.last, anchor: .bottom)
                }
                .onChange(of: messages) { _, _ in
                    scrollViewProxy.scrollTo(messages.last, anchor: .bottom)
                }
                .onChange(of: messages.last?.content) { _ in
                    scrollViewProxy.scrollTo(messages.last, anchor: .bottom)
                }
#if os(iOS) || os(visionOS)
                .sheet(item: $messageSelected) { message in
                    SelectTextSheet(message: message)
                }
#endif
            }

            ReadingAloudView(onStopTap: stopReadingAloud)
                .frame(maxWidth: 400)
                .showIf(speechSynthesizer.isSpeaking)
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.7, anchor: .top)),
                    removal: AnyTransition.opacity.combined(with: .scale(scale: 0.7, anchor: .top)))
                )
        }
    }

    /// Extracted from `body`: the single-expression row builder blew past the
    /// type-checker's budget once the message model gained observation.
    private func messageRow(_ message: MessageSD) -> some View {
        ChatMessageView(
            message: message,
            showLoader: conversationState == .loading && messages.last == message,
            userInitials: userInitials,
            editMessage: $editMessage
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .contextMenu { messageMenu(for: message) }
        .runningBorder(animated: message.id == editMessage?.id)
    }

    @ViewBuilder
    private func messageMenu(for message: MessageSD) -> some View {
        Button {
            Clipboard.shared.setString(message.content)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

#if os(iOS) || os(visionOS)
        Button {
            messageSelected = message
        } label: {
            Label("Select Text", systemImage: "selection.pin.in.out")
        }

        Button {
            onReadAloud(message.content)
        } label: {
            Label("Read Aloud", systemImage: "speaker.wave.3.fill")
        }
#endif

        if message.role == "user" {
            Button {
                withAnimation { editMessage = message }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }

        if editMessage?.id == message.id {
            Button {
                withAnimation { editMessage = nil }
            } label: {
                Label("Unselect", systemImage: "pencil")
            }
        }
    }
}

#Preview {
    MessageListView(
        messages: MessageSD.sample,
        conversationState: .loading,
        userInitials: "AM",
        editMessage: .constant(MessageSD.sample[0])
    )
}
