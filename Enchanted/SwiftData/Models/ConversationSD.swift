//
//  ConversationSD.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import Observation

@Observable
final class ConversationSD: Identifiable {
    var id: UUID = UUID()

    var name: String
    var createdAt: Date
    var updatedAt: Date
    var workDirectory: String?
    var model: LanguageModelSD?
    var messages: [MessageSD] = []

    init(name: String, updatedAt: Date = Date.now, workDirectory: String? = nil) {
        self.name = name
        self.updatedAt = updatedAt
        self.createdAt = updatedAt
        self.workDirectory = workDirectory
    }
}

// MARK: - Sample data
extension ConversationSD {
    static let sample = [
        ConversationSD(name: "New Chat", updatedAt: Date.now),
        ConversationSD(name: "Presidential", updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date.now)!),
        ConversationSD(name: "What is QFT?", updatedAt: Calendar.current.date(byAdding: .day, value: -2, to: Date.now)!)
    ]
}

// MARK: - @unchecked Sendable
extension ConversationSD: @unchecked Sendable {
    /// The legacy persistence layer crossed actor boundaries; mutations still happen on the main actor.
}

// MARK: - Identity
extension ConversationSD: Hashable {
    static func == (lhs: ConversationSD, rhs: ConversationSD) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
