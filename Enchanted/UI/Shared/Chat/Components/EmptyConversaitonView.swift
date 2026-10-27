//
//  EmptyConversaitonView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/02/2024.
//

import SwiftUI

struct EmptyConversaitonView: View, KeyboardReadable {
    @State private var showPromptsAnimation = false
    @State private var templateStore = PromptTemplateStore.shared
    @State private var editorContext: PromptTemplateEditorContext?
    let sendPrompt: (String) -> Void
#if os(iOS)
    @State private var isKeyboardVisible = false
#endif
    
#if os(macOS)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 15), count: 4)
#else
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
#endif
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 25) {
                VStack(alignment: .center) {
                    Text("RuChat")
                        .font(Font.system(size: 46, weight: .thin))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "4285f4"), Color(hex: "9b72cb"), Color(hex: "d96570"), Color(hex: "#d96570")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                templateCards
                    .frame(maxWidth: 700)
                    .padding()
                    .opacity(showPromptsAnimation ? 1 : 0)
                    .transition(AnyTransition(.opacity).combined(with: .slide))
#if os(iOS)
                .showIf(!isKeyboardVisible)
#endif
            }
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation {
                    showPromptsAnimation = true
                }
            }
        }
#if os(iOS)
        .onReceive(keyboardPublisher) { newIsKeyboardVisible in
            DispatchQueue.main.async {
                withAnimation {
                    isKeyboardVisible = newIsKeyboardVisible
                }
            }
        }
#endif
        .sheet(item: $editorContext) { context in
            PromptTemplateEditorView(
                isNew: context.template == nil,
                initialText: context.template?.text ?? ""
            ) { text in
                if let template = context.template {
                    templateStore.update(id: template.id, text: text)
                } else {
                    templateStore.add(text: text)
                }
            }
        }

    }

    @ViewBuilder
    private var templateCards: some View {
        if templateStore.templates.count > 8 {
            ScrollView(.vertical, showsIndicators: false) {
                templateGrid
            }
            .frame(maxHeight: 280)
        } else {
            templateGrid
        }
    }

    private var templateGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 15) {
            ForEach(templateStore.templates) { template in
                promptButton(for: template)
            }
        }
    }

    private func promptButton(for template: PromptTemplate) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: {
                withAnimation {
                    sendPrompt(template.text)
                }
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(template.text)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.labelCustom)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    HStack {
                        Spacer()
                        Image(systemName: "text.bubble")
                            .imageScale(.medium)
                            .foregroundStyle(Color.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .padding(15)
                .background(Color.gray5Custom, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.gray4Custom.opacity(0.35), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(template.text))

            Button {
                editorContext = PromptTemplateEditorContext(template: template)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .padding(6)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(Color.gray4Custom.opacity(0.4), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Edit prompt template")
            .accessibilityLabel("Edit prompt template")
        }
        .opacity(showPromptsAnimation ? 1 : 0)
    }
}

#Preview(traits: .fixedLayout(width: 1000, height: 1000)) {
    EmptyConversaitonView(sendPrompt: {_ in})
}
