// OpenCodeRust and Bun control-plane transport used by RuCode Chat.
// Credentials stay in native UserDefaults for this first native-only adapter;
// browser builds must use a trusted backend instead of exposing this token.
import Foundation
import Security

enum RuCodeCredentialStore {
    private static let service = "com.vakandi.rucode-chat"
    private static let account = "elia-auth-token"

    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(token.utf8)
        if token.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { var insert = query; attributes.forEach { insert[$0.key] = $0.value }; SecItemAdd(insert as CFDictionary, nil) }
    }
}

struct RuCodeModel: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let provider: String?
    let reasoning: Bool?
    let variants: [String]?
}

struct RuCodeModelList: Decodable, Sendable {
    let models: [RuCodeModel]
}

struct RuCodeEngineAgent: Decodable, Identifiable, Sendable {
    let id: String
    var description: String?

    private enum CodingKeys: String, CodingKey { case id, name, description }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

struct RuCodeConfiguredAgents: Decodable, Sendable {
    struct Agent: Decodable, Identifiable, Sendable {
        let name: String
        let enabled: Bool
        let running: Bool
        var schedule: [String: JSONValue]?
        var model: String?
        var id: String { name }
    }
    let subworkers: [Agent]
}

indirect enum JSONValue: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }
}

struct RuCodeSession: Decodable, Identifiable, Sendable {
    let id: String
    var title: String?
    var directory: String?
    var time: TimeInfo?

    struct TimeInfo: Decodable, Sendable {
        var updated: Int64?
    }
}

struct RuCodeStoredMessage: Decodable, Sendable {
    struct Info: Decodable, Sendable {
        let id: String
        let role: String
    }
    struct Part: Decodable, Sendable {
        let type: String?
        let text: String?
    }
    let info: Info
    let parts: [Part]?
}

struct RuCodeEvent: Sendable {
    let sessionID: String?
    let type: String
    let text: String?
    let partID: String?
}

struct RuCodeServerHealth: Decodable, Sendable {
    var health_status: String?
    var child: Child?
    var status: String?
    var repo: String?
    var error: String?

    struct Child: Decodable, Sendable {
        var base_url: String?
        var status: String?
        var version: String?
        var error: String?
    }
}

enum RuCodeAPIError: LocalizedError {
    case invalidURL(String)
    case http(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Invalid RuCode server URL: \(value)"
        case .http(let status, let body): return "RuCode server returned HTTP \(status): \(body)"
        case .malformedResponse: return "RuCode server returned an invalid response."
        }
    }
}

final class RuCodeAPI: @unchecked Sendable {
    static let shared = RuCodeAPI()

    private var controlURL: URL {
        URL(string: UserDefaults.standard.string(forKey: "rucodeControlURL") ?? "http://127.0.0.1:5656")!
    }
    private var engineURL: URL {
        URL(string: UserDefaults.standard.string(forKey: "rucodeEngineURL") ?? "http://127.0.0.1:4096")!
    }
    private var token: String { RuCodeCredentialStore.load() ?? UserDefaults.standard.string(forKey: "rucodeAuthToken") ?? "" }

    private func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/;?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func get<T: Decodable>(_ type: T.Type, base: URL, path: String) async throws -> T {
        try await request(type, base: base, path: path, method: "GET")
    }

    private func request<T: Decodable>(_ type: T.Type, base: URL, path: String, method: String, body: Data? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: base) else { throw RuCodeAPIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RuCodeAPIError.malformedResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw RuCodeAPIError.http(response.statusCode, String(decoding: data.prefix(2048), as: UTF8.self))
        }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw RuCodeAPIError.malformedResponse }
    }

    func isControlReachable() async -> Bool {
        do {
            struct ControlIdentity: Decodable { let repo: String? }
            let _: ControlIdentity = try await get(ControlIdentity.self, base: controlURL, path: "/health")
            return true
        } catch { return false }
    }

    func serverHealth() async throws -> RuCodeServerHealth {
        try await get(RuCodeServerHealth.self, base: controlURL, path: "/server/health")
    }

    func restartChild() async throws {
        guard let url = URL(string: "/server/restart", relativeTo: controlURL) else { throw RuCodeAPIError.invalidURL("/server/restart") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RuCodeAPIError.malformedResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw RuCodeAPIError.http(response.statusCode, String(decoding: data.prefix(2048), as: UTF8.self))
        }
    }

    func models() async throws -> [RuCodeModel] {
        try await get(RuCodeModelList.self, base: controlURL, path: "/models").models
    }

    func engineAgents() async throws -> [RuCodeEngineAgent] {
        try await get([RuCodeEngineAgent].self, base: engineURL, path: "/agent")
    }

    func configuredAgents() async throws -> [RuCodeConfiguredAgents.Agent] {
        try await get(RuCodeConfiguredAgents.self, base: controlURL, path: "/status").subworkers
    }

    func setAgentEnabled(_ name: String, enabled: Bool) async throws {
        let escaped = pathSegment(name)
        let path = "/\(enabled ? "enable" : "disable")/\(escaped)"
        try await controlRequest(path: path, method: "POST")
    }

    func setAgentSchedule(_ name: String, schedule: [String: JSONValue]) async throws {
        let escaped = pathSegment(name)
        let body = try JSONSerialization.data(withJSONObject: ["schedule": schedule.mapValues(Self.jsonObject)])
        try await controlRequest(path: "/status/\(escaped)", method: "PUT", body: body)
    }

    static func jsonObject(_ value: JSONValue) -> Any {
        switch value {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .object(let value): value.mapValues(jsonObject)
        case .array(let value): value.map(jsonObject)
        case .null: NSNull()
        }
    }

    private func controlRequest(path: String, method: String, body: Data? = nil) async throws {
        guard let url = URL(string: path, relativeTo: controlURL) else { throw RuCodeAPIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RuCodeAPIError.malformedResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw RuCodeAPIError.http(response.statusCode, String(decoding: data.prefix(2048), as: UTF8.self))
        }
    }

    func agentPhoto(_ name: String) async throws -> Data? {
        let escaped = pathSegment(name)
        guard let url = URL(string: "/agents/\(escaped)/photo", relativeTo: controlURL) else { throw RuCodeAPIError.invalidURL(name) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RuCodeAPIError.malformedResponse }
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw RuCodeAPIError.http(response.statusCode, "Agent photo request failed") }
        return data
    }

    func uploadAgentPhoto(_ name: String, data: Data, contentType: String) async throws {
        guard data.count <= 5 * 1024 * 1024, ["image/jpeg", "image/png", "image/webp"].contains(contentType) else {
            throw RuCodeAPIError.http(413, "Choose a JPEG, PNG, or WebP image under 5 MiB")
        }
        let escaped = pathSegment(name)
        guard let url = URL(string: "/agents/\(escaped)/photo", relativeTo: controlURL) else { throw RuCodeAPIError.invalidURL(name) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 20
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let response = response as? HTTPURLResponse else { throw RuCodeAPIError.malformedResponse }
        guard (200..<300).contains(response.statusCode) else { throw RuCodeAPIError.http(response.statusCode, "Agent photo upload failed") }
    }

    func deleteAgentPhoto(_ name: String) async throws {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "/agents/\(escaped)/photo", relativeTo: controlURL) else { throw RuCodeAPIError.invalidURL(name) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RuCodeAPIError.malformedResponse }
        guard (200..<300).contains(response.statusCode) || response.statusCode == 404 else { throw RuCodeAPIError.http(response.statusCode, "Agent photo removal failed") }
    }

    func createSession(directory: String, agent: String? = nil, title: String? = nil) async throws -> RuCodeSession {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "directory", value: directory)]
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let body = try JSONSerialization.data(withJSONObject: ["directory": directory, "agent": agent as Any? ?? NSNull(), "title": title as Any? ?? NSNull()])
        return try await request(RuCodeSession.self, base: controlURL, path: "/chat/sessions", method: "POST", body: body)
    }

    func prompt(sessionID: String, message: String, model: String? = nil, agent: String? = nil, system: String? = nil) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["message": message, "model": model as Any? ?? NSNull(), "agent": agent as Any? ?? NSNull(), "system": system as Any? ?? NSNull()])
        let path = "/chat/sessions/\(pathSegment(sessionID))/prompt"
        guard let url = URL(string: path, relativeTo: controlURL) else { throw RuCodeAPIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RuCodeAPIError.malformedResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw RuCodeAPIError.http(response.statusCode, String(decoding: data.prefix(2048), as: UTF8.self))
        }
    }

    func listSessions(directory: String) async throws -> [RuCodeSession] {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "directory", value: directory)]
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await get([RuCodeSession].self, base: controlURL, path: "/chat/sessions\(query)")
    }

    func messages(sessionID: String) async throws -> [RuCodeStoredMessage] {
        let safeID = pathSegment(sessionID)
        return try await get([RuCodeStoredMessage].self, base: controlURL, path: "/chat/sessions/\(safeID)/messages")
    }

    /// Establishes the global SSE feed before returning. The caller filters events by session ID.
    func connectEvents() async throws -> AsyncThrowingStream<RuCodeEvent, Error> {
        guard let url = URL(string: "/chat/events", relativeTo: controlURL) else { throw RuCodeAPIError.invalidURL("/chat/events") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60 * 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw RuCodeAPIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "SSE connection failed")
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        // The Rust server wraps diff events in `properties`, but emits the
                        // end-of-turn marker at the top level. Accept both shapes.
                        let properties = event["properties"] as? [String: Any] ?? event
                        let eventSession = (properties["sessionID"] as? String) ?? (event["sessionID"] as? String)
                        let type = (event["type"] as? String) ?? (event["event"] as? String) ?? ""
                        switch type {
                        case "message.part.delta":
                            guard let delta = properties["delta"] as? String else { break }
                            continuation.yield(RuCodeEvent(
                                sessionID: eventSession,
                                type: "part.delta",
                                text: delta,
                                partID: properties["partID"] as? String
                            ))
                        case "message.part.updated":
                            // First snapshot of a part: full accumulated text. Kept as a
                            // snapshot so a later delta can prepend it without duplicating.
                            guard let part = properties["part"] as? [String: Any],
                                  (part["type"] as? String) == "text",
                                  let partID = part["id"] as? String,
                                  let text = part["text"] as? String else { break }
                            continuation.yield(RuCodeEvent(
                                sessionID: eventSession,
                                type: "part.updated",
                                text: text,
                                partID: partID
                            ))
                        case "session.updated":
                            guard (properties["source"] as? String) == "prompt.final" else { break }
                            continuation.yield(RuCodeEvent(
                                sessionID: eventSession,
                                type: "prompt.final",
                                text: nil,
                                partID: nil
                            ))
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
