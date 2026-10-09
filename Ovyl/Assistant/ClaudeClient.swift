import Foundation
import Security

/// The user's Anthropic API key, kept in the login keychain.
nonisolated enum AnthropicKey {
    private static let service = "com.fulltimestudio.ovyl.anthropic"
    private static let account = "api-key"

    static var value: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static var isSet: Bool { value != nil }

    /// Saves the key, or removes it when empty.
    static func set(_ key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Ovyl: Anthropic API key"
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// A turn in a conversation with Claude, in the Messages API's shape.
nonisolated struct ClaudeMessage: Codable, Sendable {
    var role: String
    var content: [ClaudeBlock]
}

nonisolated enum ClaudeBlock: Codable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(id: String, content: String)

    private enum Keys: String, CodingKey {
        case type, text, id, name, input, content
        case toolUseID = "tool_use_id"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "tool_use":
            self = .toolUse(id: try values.decode(String.self, forKey: .id), name: try values.decode(String.self, forKey: .name), input: try values.decode(JSONValue.self, forKey: .input))
        case "tool_result":
            self = .toolResult(id: try values.decode(String.self, forKey: .toolUseID), content: try values.decode(String.self, forKey: .content))
        default:
            self = .text(try values.decodeIfPresent(String.self, forKey: .text) ?? "")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let text):
            try values.encode("text", forKey: .type)
            try values.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try values.encode("tool_use", forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(name, forKey: .name)
            try values.encode(input, forKey: .input)
        case .toolResult(let id, let content):
            try values.encode("tool_result", forKey: .type)
            try values.encode(id, forKey: .toolUseID)
            try values.encode(content, forKey: .content)
        }
    }
}

/// Streams replies from Claude through the Messages API, with tools.
nonisolated struct ClaudeClient: Sendable {
    let apiKey: String
    let model: String

    enum Event: Sendable {
        case text(String)
        case toolUse(id: String, name: String, input: JSONValue)
        case stop(reason: String)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Request: Encodable {
        struct Tool: Encodable {
            let name: String
            let description: String
            let input_schema: JSONValue
        }

        let model: String
        let max_tokens: Int
        let system: String
        let messages: [ClaudeMessage]
        let tools: [Tool]
        let stream = true
    }

    func stream(system: String, messages: [ClaudeMessage], tools: [ToolSpec]) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, messages: messages, tools: tools, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(system: String, messages: [ClaudeMessage], tools: [ToolSpec], into continuation: AsyncThrowingStream<Event, any Error>.Continuation) async throws {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(Request(
            model: model,
            max_tokens: 8192,
            system: system,
            messages: messages,
            tools: tools.map { .init(name: $0.name, description: $0.description, input_schema: $0.inputSchema) }
        ))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure(message: "Claude didn't answer.") }
        guard http.statusCode == 200 else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Failure(message: Self.message(from: body, status: http.statusCode))
        }

        // Tool calls arrive as JSON in pieces; they're put together per block.
        var tools: [Int: (id: String, name: String, json: String)] = [:]
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
            guard let event = try? JSONDecoder().decode(JSONValue.self, from: payload), let type = event["type"]?.string else { continue }
            let index = Int(event["index"]?.number ?? 0)
            switch type {
            case "content_block_start":
                if event["content_block"]?["type"]?.string == "tool_use" {
                    tools[index] = (event["content_block"]?["id"]?.string ?? "", event["content_block"]?["name"]?.string ?? "", "")
                }
            case "content_block_delta":
                if let text = event["delta"]?["text"]?.string {
                    continuation.yield(.text(text))
                } else if let json = event["delta"]?["partial_json"]?.string {
                    tools[index]?.json += json
                }
            case "content_block_stop":
                if let tool = tools.removeValue(forKey: index) {
                    let input = (try? JSONDecoder().decode(JSONValue.self, from: Data((tool.json.isEmpty ? "{}" : tool.json).utf8))) ?? .object([:])
                    continuation.yield(.toolUse(id: tool.id, name: tool.name, input: input))
                }
            case "message_delta":
                if let reason = event["delta"]?["stop_reason"]?.string { continuation.yield(.stop(reason: reason)) }
            case "error":
                throw Failure(message: event["error"]?["message"]?.string ?? "Claude ran into a problem.")
            default:
                break
            }
        }
    }

    private static func message(from body: Data, status: Int) -> String {
        let detail = (try? JSONDecoder().decode(JSONValue.self, from: body))?["error"]?["message"]?.string
        switch status {
        case 401: return "Claude didn't accept the API key. Check it in Settings › Assistant."
        case 429: return "Claude is busy or the key's limit was reached. Try again in a moment."
        case 529: return "Claude is overloaded right now. Try again in a moment."
        default: return detail ?? "Claude answered with an error (\(status))."
        }
    }
}
