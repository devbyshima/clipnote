import Foundation
import FoundationModels
import Observation

/// The models the assistant can use. Apple's on-device model is the
/// default and keeps everything on this Mac; Apple's Private Cloud Compute
/// model and Claude are there when wanted.
nonisolated enum AssistantModel: String, CaseIterable, Identifiable, Sendable {
    case onDevice, privateCloud, claudeFable, claudeOpus, claudeSonnet, claudeHaiku

    var id: String { rawValue }

    static let defaultsKey = "assistantModel"

    var label: String {
        switch self {
        case .onDevice: "On this Mac"
        case .privateCloud: "Apple Private Cloud"
        case .claudeFable: "Claude Fable 5.1"
        case .claudeOpus: "Claude Opus 5.5"
        case .claudeSonnet: "Claude Sonnet 5.5"
        case .claudeHaiku: "Claude Haiku 5.5"
        }
    }

    var claudeID: String? {
        switch self {
        case .claudeFable: "claude-fable-5-1"
        case .claudeOpus: "claude-opus-5-5"
        case .claudeSonnet: "claude-sonnet-5-5"
        case .claudeHaiku: "claude-haiku-5-5"
        default: nil
        }
    }

    var isClaude: Bool { claudeID != nil }

    /// How much note text one read returns: Apple's on-device model holds a
    /// few pages at a time; the others hold far more.
    var readBudget: Int {
        switch self {
        case .onDevice: 2_400
        case .privateCloud: 12_000
        default: 40_000
        }
    }

    /// Where the notes the assistant reads go.
    var privacy: String {
        switch self {
        case .onDevice: "Runs on this Mac. Nothing leaves your computer."
        case .privateCloud: "Runs on Apple's Private Cloud Compute. What it reads isn't stored or seen by Apple."
        default: "Runs on Anthropic's servers. The notes it reads are sent to Anthropic."
        }
    }

    /// Why the model can't be used right now, if it can't.
    @MainActor var unavailableReason: String? {
        switch self {
        case .onDevice:
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use the assistant on this Mac."
            case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence. Pick Claude in the menu below instead."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading its model. Try again soon."
            case .unavailable: return "Apple Intelligence isn't available right now."
            }
        case .privateCloud:
            switch PrivateCloudComputeLanguageModel().availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return "This Mac can't use Private Cloud Compute."
            case .unavailable: return "Private Cloud Compute isn't ready. Check that Apple Intelligence is on."
            }
        default:
            return AnthropicKey.isSet ? nil : "Add your Anthropic API key in Settings › Assistant."
        }
    }

    static var saved: AssistantModel {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AssistantModel.init) ?? .onDevice
    }
}

/// One conversation with the assistant at a time: sends what the user asks
/// with the notes they're looking at, streams the answer in, records what
/// the assistant did, and keeps the chat on disk.
@MainActor @Observable
final class AssistantSession {
    static let shared = AssistantSession()

    private(set) var chat = Chat()
    private(set) var isResponding = false
    var model: AssistantModel = .saved {
        didSet {
            UserDefaults.standard.set(model.rawValue, forKey: AssistantModel.defaultsKey)
            appleSession = nil
        }
    }

    /// Opens a note in the window; set by the window.
    @ObservationIgnored var openNote: (UUID) -> Void = { _ in }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var appleSession: LanguageModelSession?
    @ObservationIgnored private var appleSessionChat: UUID?
    @ObservationIgnored private var tools: LibraryTools?

    private init() {}

    // MARK: Chats

    func newChat() {
        stop()
        if !chat.messages.isEmpty { ChatStore.save(chat) }
        chat = Chat()
        appleSession = nil
    }

    func open(_ id: UUID) {
        guard let loaded = ChatStore.load(id) else { return }
        show(loaded)
    }

    /// Shows a chat, as when picked from the history.
    func show(_ loaded: Chat) {
        stop()
        if !chat.messages.isEmpty, chat.id != loaded.id { ChatStore.save(chat) }
        chat = loaded
        appleSession = nil
    }

    func delete(_ id: UUID) {
        if chat.id == id {
            stop()
            chat = Chat()
            appleSession = nil
        }
        ChatStore.delete(id)
    }

    // MARK: Asking

    func send(_ text: String, context: [ContextItem]) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        if chat.messages.isEmpty {
            chat.title = LibraryTools.oneLine(text, limit: 48)
        }
        chat.messages.append(ChatMessage(role: .user, text: text, context: context))
        let reply = ChatMessage(role: .assistant, text: "", model: model.label)
        chat.messages.append(reply)
        isResponding = true
        let model = model
        let chatID = chat.id
        task = Task {
            await respond(to: text, context: context, replyID: reply.id, model: model)
            // Another chat may have been opened meanwhile; this one was saved then.
            guard chat.id == chatID else { return }
            isResponding = false
            chat.updatedAt = .now
            ChatStore.save(chat)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isResponding = false
    }

    /// Puts back a change the assistant made.
    func undo(step stepID: UUID, in messageID: UUID) {
        guard let m = chat.messages.firstIndex(where: { $0.id == messageID }),
              let s = chat.messages[m].steps.firstIndex(where: { $0.id == stepID }),
              let record = chat.messages[m].steps[s].undo, !chat.messages[m].steps[s].undone
        else { return }
        libraryTools(for: model).undo(record)
        chat.messages[m].steps[s].undone = true
        ChatStore.save(chat)
    }

    // MARK: Answering

    private func respond(to text: String, context: [ContextItem], replyID: UUID, model: AssistantModel) async {
        if let reason = model.unavailableReason {
            update(replyID) { $0.failure = reason }
            return
        }
        let tools = libraryTools(for: model)
        tools.onStep = { [weak self] step in self?.update(replyID) { $0.steps.append(step) } }
        tools.openNote = { [weak self] id in self?.openNote(id) }
        let prompt = Self.prompt(text, context: context)
        do {
            if model.isClaude {
                try await respondWithClaude(prompt: prompt, replyID: replyID, model: model, tools: tools)
            } else {
                try await respondWithApple(prompt: prompt, replyID: replyID, model: model, tools: tools)
            }
        } catch is CancellationError {
            update(replyID) { if $0.text.isEmpty { $0.failure = "Stopped." } }
        } catch {
            update(replyID) { $0.failure = Self.describe(error) }
        }
    }

    private func respondWithApple(prompt: String, replyID: UUID, model: AssistantModel, tools: LibraryTools, retried: Bool = false) async throws {
        let session = appleSession(for: model, tools: tools)
        do {
            let stream = session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.4))
            for try await snapshot in stream {
                try Task.checkCancellation()
                update(replyID) { $0.text = snapshot.content }
            }
        } catch let error as LanguageModelError {
            // Out of room: start over with a short recap of the chat.
            guard case .contextSizeExceeded = error, !retried else { throw error }
            appleSession = nil
            update(replyID) { $0.text = "" }
            try await respondWithApple(prompt: prompt, replyID: replyID, model: model, tools: tools, retried: true)
        }
    }

    /// The session for this chat, made fresh for a new chat, another model,
    /// or after running out of room, with what was said so far as a recap.
    private func appleSession(for model: AssistantModel, tools: LibraryTools) -> LanguageModelSession {
        if let appleSession, appleSessionChat == chat.id { return appleSession }
        var instructions = Self.instructions(for: model)
        let earlier = chat.messages.dropLast(2).suffix(6)
        if !earlier.isEmpty {
            instructions += "\n\nEarlier in this conversation:\n" + earlier.map { message in
                "\(message.role == .user ? "User" : "You"): \(LibraryTools.oneLine(message.text, limit: 400))"
            }.joined(separator: "\n")
        }
        let session = model == .privateCloud
            ? LanguageModelSession(model: PrivateCloudComputeLanguageModel(), tools: tools.appleTools(), instructions: instructions)
            : LanguageModelSession(model: SystemLanguageModel.default, tools: tools.appleTools(), instructions: instructions)
        appleSession = session
        appleSessionChat = chat.id
        return session
    }

    private func respondWithClaude(prompt: String, replyID: UUID, model: AssistantModel, tools: LibraryTools) async throws {
        guard let key = AnthropicKey.value, let id = model.claudeID else { return }
        let client = ClaudeClient(apiKey: key, model: id)
        var messages = claudeHistory()
        messages.append(ClaudeMessage(role: "user", content: [.text(prompt)]))
        var written = ""
        for _ in 0..<16 {
            var blocks: [ClaudeBlock] = []
            var text = ""
            var calls: [(id: String, name: String, input: JSONValue)] = []
            var reason = "end_turn"
            for try await event in client.stream(system: Self.instructions(for: model), messages: messages, tools: LibraryTools.specs) {
                try Task.checkCancellation()
                switch event {
                case .text(let piece):
                    text += piece
                    let shown = written.isEmpty ? text : written + "\n\n" + text
                    update(replyID) { $0.text = shown }
                case .toolUse(let id, let name, let input):
                    calls.append((id, name, input))
                case .stop(let stop):
                    reason = stop
                }
            }
            if !text.isEmpty {
                blocks.append(.text(text))
                written = written.isEmpty ? text : written + "\n\n" + text
            }
            blocks += calls.map { .toolUse(id: $0.id, name: $0.name, input: $0.input) }
            messages.append(ClaudeMessage(role: "assistant", content: blocks))
            guard reason == "tool_use", !calls.isEmpty else { return }
            var results: [ClaudeBlock] = []
            for call in calls {
                results.append(.toolResult(id: call.id, content: await tools.run(call.name, call.input)))
            }
            messages.append(ClaudeMessage(role: "user", content: results))
        }
    }

    /// The chat so far, for Claude: what was asked and answered, without the
    /// reply being written now. Older turns are dropped past a generous size.
    private func claudeHistory() -> [ClaudeMessage] {
        var messages: [ClaudeMessage] = []
        var size = 0
        for message in chat.messages.dropLast(2).reversed() {
            let text = message.role == .user ? Self.prompt(message.text, context: message.context) : message.text
            guard !text.isEmpty else { continue }
            size += text.count
            if size > 120_000 { break }
            messages.insert(ClaudeMessage(role: message.role == .user ? "user" : "assistant", content: [.text(text)]), at: 0)
        }
        // The API wants turns to alternate, starting with the user.
        var tidy: [ClaudeMessage] = []
        for message in messages where tidy.last?.role != message.role {
            tidy.append(message)
        }
        if tidy.first?.role == "assistant" { tidy.removeFirst() }
        if tidy.last?.role == "user" { tidy.removeLast() }
        return tidy
    }

    private func libraryTools(for model: AssistantModel) -> LibraryTools {
        if let tools, tools.readBudget == model.readBudget { return tools }
        let made = LibraryTools(center: .shared, readBudget: model.readBudget)
        tools = made
        return made
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = chat.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&chat.messages[index])
    }

    // MARK: Words

    private static func prompt(_ text: String, context: [ContextItem]) -> String {
        guard !context.isEmpty else { return text }
        let notes = context.map { "[\(LibraryTools.ref($0.noteID))] “\($0.title)” (\($0.detail))" }.joined(separator: ", ")
        return "The user has open: \(notes).\n\n\(text)"
    }

    static func instructions(for model: AssistantModel) -> String {
        let today = Date.now.formatted(date: .complete, time: .omitted)
        return """
            You are the assistant in Ovyl, a Mac app that turns videos, audio recordings and pictures into notes. Today is \(today).

            You work only with the user's Ovyl library: their notes, the transcripts of what was said (with times), the text read off the screen in videos (frames, such as slides), the text in their pictures, and their folders. Use the tools to look things up and never guess what a note says. Each note has an id in brackets, like [1a2b3c4d]; pass it to the tools. Call notes by their titles when you talk to the user. When you rely on a moment in a video or recording, give its time, like (4:02).

            You can change the library directly when asked: make notes, rewrite or add to a note, rename and move notes. The user can undo each change, so don't ask for permission first.
            - To combine notes: read each one in full, then make one new note with create_note that brings them together under clear headings, without repeating anything. Say that the originals were kept.
            - To restructure or tidy a note: read it in full, then rewrite it with update_note so it reads clearly, keeping every fact, time and name.
            - To help the user write: draft in your reply, or put it in a note if they ask.

            Write notes in Markdown: ## headings, short paragraphs, lists where they help; don't repeat the title as a heading. Keep your replies short, in Markdown.

            If you're asked about something that isn't in the library and isn't about writing with it, say briefly that you can only help with what's in Ovyl.
            """
    }

    private static func describe(_ error: any Error) -> String {
        if let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return "The model declined to answer that."
            case .rateLimited: return "The model is busy. Try again in a moment."
            case .unsupportedLanguageOrLocale: return "The model doesn't support this language yet."
            case .contextSizeExceeded: return "That was too much for the model to hold at once. Try a smaller request or another model."
            case .timeout: return "The model took too long. Try again."
            default: return error.localizedDescription
            }
        }
        if let error = error as? URLError {
            return error.code == .notConnectedToInternet ? "You're offline. Claude needs the internet; On this Mac doesn't." : error.localizedDescription
        }
        return error.localizedDescription
    }
}
