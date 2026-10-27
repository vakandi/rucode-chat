//
//  PromptTemplateEditorView.swift
//  RuCode Chat
//

import SwiftUI

struct PromptTemplateEditorView: View {
    let isNew: Bool
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(isNew: Bool, initialText: String, onSave: @escaping (String) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New prompt template" : "Edit prompt template")
                .font(.headline)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.gray5Custom, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gray4Custom.opacity(0.4), lineWidth: 1)
                }
                .frame(minHeight: 140)
                .focused($isFocused)

            HStack {
                Text("Long prompts are truncated on the card.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(trimmedText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            isFocused = true
        }
    }
}
