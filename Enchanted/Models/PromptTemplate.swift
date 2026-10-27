//
//  PromptTemplate.swift
//  RuCode Chat
//

import Foundation
import Observation

struct PromptTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct PromptTemplateEditorContext: Identifiable {
    let id = UUID()
    var template: PromptTemplate?
}

@Observable
final class PromptTemplateStore {
    static let shared = PromptTemplateStore()

    private static let storageKey = "rucodePromptTemplates"

    private let defaults: UserDefaults
    private(set) var templates: [PromptTemplate]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        guard
            let data = defaults.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode([PromptTemplate].self, from: data)
        else {
            templates = Self.defaultTemplates
            return
        }

        templates = stored.compactMap { template in
            let text = Self.normalized(template.text)
            guard !text.isEmpty else { return nil }
            return PromptTemplate(id: template.id, text: text)
        }
    }

    @discardableResult
    func add(text: String) -> PromptTemplate? {
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty else { return nil }

        let template = PromptTemplate(text: normalized)
        templates.append(template)
        persist()
        return template
    }

    func update(id: UUID, text: String) {
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty, let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].text = normalized
        persist()
    }

    func delete(id: UUID) {
        templates.removeAll { $0.id == id }
        persist()
    }

    func move(id: UUID, by offset: Int) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard templates.indices.contains(target) else { return }
        templates.swapAt(index, target)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let defaultTemplates: [PromptTemplate] = [
        PromptTemplate(text: "Give me phrases to learn in a new language"),
        PromptTemplate(text: "Explain supercomputers like I'm five years old"),
        PromptTemplate(text: "How to center div in HTML?"),
        PromptTemplate(text: "What is bubble sort? Write example in python")
    ]
}
