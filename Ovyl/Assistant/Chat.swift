import Foundation

/// A conversation with the assistant, kept as a JSON file under Application
/// Support/Assistant, so chats don't touch the notes store.
nonisolated struct Chat: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var title = "New chat"
    var createdAt = Date.now
    var updatedAt = Date.now
    var messages: [ChatMessage] = []
}

nonisolated struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    enum Role: String, Codable, Sendable {
        case user, assistant
    }

    var id = UUID()
    var role: Role
    var text: String
    /// Notes the user attached, shown above their message.
    var context: [ContextItem] = []
    /// What the assistant did on the way to its answer.
    var steps: [ChatStep] = []
    /// The model that answered.
    var model: String?
    /// Why the answer stopped short, if it did.
    var failure: String?
}

/// A note given to the assistant as context.
nonisolated struct ContextItem: Codable, Hashable, Sendable {
    var noteID: UUID
    var title: String
    var detail: String
}

/// One thing the assistant did: looked something up, read a note, or
/// changed the library. Changes can be undone.
nonisolated struct ChatStep: Codable, Identifiable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case searched, read, created, edited, renamed, moved, opened, listed
    }

    var id = UUID()
    var kind: Kind
    var summary: String
    var noteID: UUID?
    var undo: UndoRecord?
    var undone = false

    var changesLibrary: Bool { undo != nil }

    var symbol: String {
        switch kind {
        case .searched: "magnifyingglass"
        case .read: "doc.text.magnifyingglass"
        case .created: "doc.badge.plus"
        case .edited: "pencil"
        case .renamed: "character.cursor.ibeam"
        case .moved: "folder"
        case .opened: "arrow.up.forward.square"
        case .listed: "list.bullet"
        }
    }
}

/// How to put a change back.
nonisolated enum UndoRecord: Codable, Sendable, Equatable {
    /// Delete a note the assistant made.
    case removeNote(UUID)
    /// Put a note's text back; nil restores the text Ovyl wrote.
    case restoreText(UUID, previous: String?)
    case restoreTitle(UUID, previous: String, wasEdited: Bool)
    case restoreFolder(UUID, previous: UUID?)
}

/// Reads and writes chats, newest first.
nonisolated enum ChatStore {
    static var folder: URL { StorageManager.chatsRoot }

    static func save(_ chat: Chat) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(chat) else { return }
        try? data.write(to: url(for: chat.id), options: .atomic)
    }

    static func load(_ id: UUID) -> Chat? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Chat.self, from: data)
    }

    static func all() -> [Chat] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent).flatMap(load) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    private static func url(for id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString).json")
    }
}
