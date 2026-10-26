//
//  SwiftDataService.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//
//  RuCode Chat build: this machine runs on Command Line Tools only, where the
//  SwiftData macro plugin is unavailable. The persistence contract used by the
//  stores is unchanged, but the backing store is an atomic JSON snapshot in
//  Application Support instead of a SwiftData container.
//

import Foundation

actor SwiftDataService {
    let modelContainer: Void = ()

    private var models: [LanguageModelSD] = []
    private var conversations: [ConversationSD] = []
    private var instructions: [CompletionInstructionSD] = []
    private let storeURL: URL

    static let shared = SwiftDataService()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("RuCodeChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("store.json")
        Self.loadSnapshot(at: storeURL, models: &models, conversations: &conversations, instructions: &instructions)
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = Snapshot(
            models: models.map(ModelDTO.init),
            conversations: conversations.map { conversation in
                ConversationDTO(
                    id: conversation.id,
                    name: conversation.name,
                    createdAt: conversation.createdAt,
                    updatedAt: conversation.updatedAt,
                    workDirectory: conversation.workDirectory,
                    modelName: conversation.model?.name,
                    messages: conversation.messages.map(MessageDTO.init)
                )
            },
            instructions: instructions.map { InstructionDTO(source: $0) }
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("RuCodeChat persistence failure: \(error.localizedDescription)")
        }
    }

    private static func loadSnapshot(
        at url: URL,
        models: inout [LanguageModelSD],
        conversations: inout [ConversationSD],
        instructions: inout [CompletionInstructionSD]
    ) {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return }

        models = snapshot.models.map { dto in
            let model = LanguageModelSD(name: dto.name, imageSupport: dto.imageSupport, modelProvider: dto.provider ?? .opencodeRust)
            model.isAvailable = dto.isAvailable
            return model
        }
        let modelsByName = Dictionary(uniqueKeysWithValues: models.map { ($0.name, $0) })

        conversations = snapshot.conversations.map { dto in
            let conversation = ConversationSD(name: dto.name, updatedAt: dto.updatedAt, workDirectory: dto.workDirectory)
            conversation.id = dto.id
            conversation.createdAt = dto.createdAt
            if let modelName = dto.modelName {
                conversation.model = modelsByName[modelName]
            }
            conversation.messages = dto.messages.map { messageDTO in
                let message = MessageSD(
                    content: messageDTO.content,
                    role: messageDTO.role,
                    done: messageDTO.done,
                    error: messageDTO.error,
                    image: messageDTO.image
                )
                message.id = messageDTO.id
                message.createdAt = messageDTO.createdAt
                message.conversation = conversation
                return message
            }
            return conversation
        }

        instructions = snapshot.instructions.map { dto in
            let instruction = CompletionInstructionSD(
                name: dto.name,
                keyboardCharacterStr: dto.keyboardCharacterStr,
                instruction: dto.instruction,
                order: dto.order,
                modelTemperature: dto.modelTemperature ?? 0.8
            )
            instruction.id = dto.id
            return instruction
        }
    }
}

// MARK: - Snapshot DTOs

extension SwiftDataService {
    fileprivate struct Snapshot: Codable {
        var models: [ModelDTO]
        var conversations: [ConversationDTO]
        var instructions: [InstructionDTO]
    }

    fileprivate struct ModelDTO: Codable {
        var name: String
        var isAvailable: Bool
        var imageSupport: Bool
        var provider: ModelProvider?

        init(_ model: LanguageModelSD) {
            name = model.name
            isAvailable = model.isAvailable
            imageSupport = model.imageSupport
            provider = model.modelProvider
        }
    }

    fileprivate struct ConversationDTO: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var workDirectory: String?
        var modelName: String?
        var messages: [MessageDTO]
    }

    fileprivate struct MessageDTO: Codable {
        var id: UUID
        var content: String
        var role: String
        var done: Bool
        var error: Bool
        var createdAt: Date
        var image: Data?

        init(_ message: MessageSD) {
            id = message.id
            content = message.content
            role = message.role
            done = message.done
            error = message.error
            createdAt = message.createdAt
            image = message.image
        }
    }

    fileprivate struct InstructionDTO: Codable {
        var id: UUID
        var name: String
        var keyboardCharacterStr: String
        var instruction: String
        var order: Int
        var modelTemperature: Float?

        init(source: CompletionInstructionSD) {
            id = source.id
            name = source.name
            keyboardCharacterStr = source.keyboardCharacterStr
            instruction = source.instruction
            order = source.order
            modelTemperature = source.modelTemperature
        }
    }
}

// MARK: - Language Models
extension SwiftDataService {
    func fetchModels() throws -> [LanguageModelSD] {
        models.sorted { $0.name < $1.name }
    }

    func saveModels(models incoming: [LanguageModelSD]) throws {
        for candidate in incoming {
            if let existing = models.first(where: { $0.name == candidate.name }) {
                existing.isAvailable = candidate.isAvailable
                existing.imageSupport = candidate.imageSupport
                existing.modelProvider = candidate.modelProvider
            } else {
                models.append(candidate)
            }
        }
        persist()
    }

    func deleteModels() throws {
        models = []
        persist()
    }
}

// MARK: - Conversations
extension SwiftDataService {
    func createConversation(_ conversation: ConversationSD) throws {
        if !conversations.contains(where: { $0.id == conversation.id }) {
            conversations.append(conversation)
        }
        persist()
    }

    func renameConversation(_ conversation: ConversationSD) throws {
        persist()
    }

    func deleteConversation(_ conversation: ConversationSD) throws {
        conversations.removeAll { $0.id == conversation.id }
        persist()
    }

    func updateConversation(_ conversation: ConversationSD) throws {
        conversation.updatedAt = .now
        if !conversations.contains(where: { $0.id == conversation.id }) {
            conversations.append(conversation)
        }
        persist()
    }

    func fetchConversations() throws -> [ConversationSD] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    func getConversation(_ conversationId: UUID) throws -> ConversationSD? {
        conversations.first { $0.id == conversationId }
    }

    func deleteConversations() throws {
        conversations = []
        persist()
    }

    func deleteMessages() throws {
        for conversation in conversations {
            conversation.messages = []
        }
        persist()
    }

    func deleteConversations(_ date: Date) throws {
        let calendar = Calendar.current
        conversations.removeAll { calendar.isDate($0.createdAt, inSameDayAs: date) }
        persist()
    }
}

// MARK: - Messages
extension SwiftDataService {
    func fetchMessages(_ conversationId: UUID) throws -> [MessageSD] {
        guard let conversation = conversations.first(where: { $0.id == conversationId }) else { return [] }
        return conversation.messages.sorted { $0.createdAt < $1.createdAt }
    }

    func updateMessage(_ message: MessageSD) throws {
        attach(message)
        persist()
    }

    func createMessage(_ message: MessageSD) throws {
        attach(message)
        persist()
    }

    private func attach(_ message: MessageSD) {
        guard let conversation = message.conversation else { return }
        if !conversations.contains(where: { $0.id == conversation.id }) {
            conversations.append(conversation)
        }
        if !conversation.messages.contains(where: { $0.id == message.id }) {
            conversation.messages.append(message)
        }
    }
}

// MARK: - CompletionInstruction
extension SwiftDataService {
    func fetchCompletionInstructions() throws -> [CompletionInstructionSD] {
        instructions.sorted { $0.order < $1.order }
    }

    func updateCompletionInstructions(_ incoming: [CompletionInstructionSD]) throws {
        for index in incoming.indices {
            incoming[index].order = index
            let instruction = incoming[index]
            if let existingIndex = instructions.firstIndex(where: { $0.id == instruction.id }) {
                instructions[existingIndex] = instruction
            } else {
                instructions.append(instruction)
            }
        }
        persist()
    }

    func deleteCompletionInstruction(_ instruction: CompletionInstructionSD) throws {
        instructions.removeAll { $0.id == instruction.id }
        persist()
    }
}

// MARK: - General
extension SwiftDataService {
    func deleteEverything() throws {
        conversations = []
        models = []
        instructions = []
        persist()
    }
}
