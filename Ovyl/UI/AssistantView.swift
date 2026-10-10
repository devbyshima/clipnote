import SwiftUI

/// The assistant in the right pane: a header with close, history and new
/// chat; the conversation; and a box to ask in, with the open note
/// attached and the model to use.
struct AssistantView: View {
    let currentNote: Note?
    let folders: [Folder]
    var close: () -> Void

    @State private var draft = ""
    @State private var attachesNote = true
    @State private var showsHistory = false
    @FocusState private var focused: Bool

    private var session: AssistantSession { .shared }

    var body: some View {
        VStack(spacing: 0) {
            header
            if session.chat.messages.isEmpty {
                welcome
            } else {
                conversation
            }
            composer
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .onChange(of: currentNote?.id) { attachesNote = true }
        .onAppear { focused = true }
    }

    // MARK: Header

    private var header: some View {
        // As in every view of the right pane: the way out first, then the title.
        HStack(spacing: 10) {
            RoundButton(symbol: "xmark", help: "Close the assistant (⌘J)", action: close)
            Text("Assistant")
                .font(.system(size: 14.5, weight: .medium))
            Spacer()
            RoundButton(symbol: "clock.arrow.circlepath", help: "Earlier chats") { showsHistory.toggle() }
                .popover(isPresented: $showsHistory, arrowEdge: .bottom) {
                    ChatHistory { showsHistory = false }
                }
            RoundButton(symbol: "plus", help: "New chat") {
                session.newChat()
                draft = ""
                focused = true
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MainWindowStyler.barHeight)
        .background(WindowDragHandle())
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(session.chat.messages) { message in
                        switch message.role {
                        case .user:
                            UserMessageView(message: message)
                        case .assistant:
                            AssistantMessageView(
                                message: message,
                                isWriting: session.isResponding && message.id == session.chat.messages.last?.id
                            )
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
            .onChange(of: session.chat.messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.chat.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            // The app mark in a green ring.
            OvylMark(accent: Palette.accent)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 26, height: 26)
                .frame(width: 46, height: 46)
                .background(Palette.surface, in: Circle())
                .padding(3)
                .overlay(Circle().strokeBorder(Palette.accent.gradient, lineWidth: 3))
                .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask about your notes.")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary.opacity(0.62))
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Or have them ")
                        .font(.system(size: 19, weight: .semibold))
                    Handwriting(text: "rewritten", size: 27, progress: 1)
                    Text(".")
                        .font(.system(size: 19, weight: .semibold))
                }
                Text(session.model.privacy)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(suggestions, id: \.text) { suggestion in
                    SuggestionButton(symbol: suggestion.symbol, text: suggestion.text) {
                        if suggestion.text.hasSuffix("…") {
                            draft = String(suggestion.text.dropLast())
                            focused = true
                        } else {
                            send(suggestion.text)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var suggestions: [(symbol: String, text: String)] {
        var list: [(String, String)] = []
        if currentNote != nil {
            list.append(("text.alignleft", "Summarize this note"))
            list.append(("wand.and.stars", "Tidy this note up so it reads well"))
        }
        list.append(("square.on.square", "Combine two notes into one…"))
        list.append(("magnifyingglass", "Find where something was said…"))
        list.append(("calendar", "What did I make notes about this week?"))
        return list.map { (symbol: $0.0, text: $0.1) }
    }

    // MARK: Composer

    private var context: [ContextItem] {
        guard attachesNote, let note = currentNote else { return [] }
        return [ContextItem(noteID: note.id, title: note.displayTitle, detail: Self.detail(of: note, folders: folders))]
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item = context.first {
                HStack(spacing: 6) {
                    Image(systemName: currentNote?.mediaKind.symbol ?? "doc.text")
                        .font(.system(size: 11))
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Button { attachesNote = false } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Don't send this note")
                }
                .foregroundStyle(Palette.textPrimary.opacity(0.75))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(Palette.fill))
            }
            TextField("Ask anything…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit { send(draft) }
            HStack(spacing: 8) {
                ModelMenu()
                Spacer()
                sendButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? Palette.accent : Palette.border, lineWidth: focused ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.12), value: focused)
    }

    private var sendButton: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            if session.isResponding { session.stop() } else { send(draft) }
        } label: {
            Image(systemName: session.isResponding ? "stop.fill" : "arrow.up")
                .font(.system(size: session.isResponding ? 10 : 13, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.prominentCircle)
        .focusEffectDisabled()
        .disabled(empty && !session.isResponding)
        .help(session.isResponding ? "Stop" : "Send (Return)")
    }

    private func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !session.isResponding else { return }
        session.send(text, context: context)
        draft = ""
    }

    /// "Video · 52:10 · School"
    static func detail(of note: Note, folders: [Folder]) -> String {
        var parts = [note.mediaKind.noun.capitalized]
        if note.kind == .pictures {
            parts[0] = note.pictureBookmarks.count == 1 ? "1 picture" : "\(note.pictureBookmarks.count) pictures"
        } else if note.duration > 0 {
            parts.append(TimeFormat.clock(note.duration))
        }
        if let id = note.folderID, let folder = folders.first(where: { $0.id == id }) { parts.append(folder.name) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Messages

/// What the user asked, in a blue bubble, under the notes they attached.
struct UserMessageView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(message.context, id: \.self) { item in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.fill)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(item.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .lineLimit(1)
                }
                .padding(7)
                .padding(.trailing, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
                .frame(maxWidth: 280, alignment: .trailing)
            }
            Text(message.text)
                .font(.system(size: 14.5))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.accentSoft))
        }
        .padding(.leading, 36)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The assistant's answer: what it looked up or changed, then its reply.
struct AssistantMessageView: View {
    @Environment(Navigator.self) private var navigator
    let message: ChatMessage
    let isWriting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.steps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(message.steps) { step in
                        StepRow(step: step, messageID: message.id)
                    }
                }
            }
            if message.text.isEmpty, isWriting {
                LogoLoader(.thinking)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.vertical, 2)
            }
            if !message.text.isEmpty {
                MarkdownView(blocks: MarkdownDocument.parse(message.text))
                    .environment(\.readerStyle, ReaderStyle(size: 14.5))
                    .textSelection(.enabled)
            }
            if let failure = message.failure {
                Label(failure, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One thing the assistant did. Changes get Open and Undo.
struct StepRow: View {
    @Environment(Navigator.self) private var navigator
    let step: ChatStep
    let messageID: UUID

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: step.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(step.changesLibrary ? Palette.accentText : Palette.textSecondary)
                .frame(width: 15)
            Text(step.summary)
                .font(.system(size: 12.5))
                .foregroundStyle(step.changesLibrary ? Palette.textPrimary.opacity(0.85) : Palette.textSecondary)
                .strikethrough(step.undone)
                .lineLimit(1)
            if step.changesLibrary {
                Spacer(minLength: 6)
                if let id = step.noteID, !step.undone {
                    smallButton("Open") { navigator.go(.note(id)) }
                }
                if step.undone {
                    Text("Undone")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    smallButton("Undo") { AssistantSession.shared.undo(step: step.id, in: messageID) }
                }
            }
        }
        .padding(.horizontal, step.changesLibrary ? 9 : 0)
        .padding(.vertical, step.changesLibrary ? 6 : 0)
        .background {
            if step.changesLibrary {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.surface)
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5)
            }
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Palette.fill))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

// MARK: - Controls

/// A round toolbar button, as in the assistant's header.
struct RoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary.opacity(0.72))
                .frame(width: 30, height: 30)
                .background(Circle().fill(isHovered ? Palette.fill : Palette.surface))
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                .shadow(color: Palette.shadow, radius: 1.5, y: 0.5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// A suggested question on an empty chat.
struct SuggestionButton: View {
    let symbol: String
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 16)
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textPrimary.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isHovered ? Palette.fill : Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
    }
}

/// Picks the model, with where it runs.
struct ModelMenu: View {
    private var session: AssistantSession { .shared }

    var body: some View {
        Menu {
            ForEach(AssistantModel.allCases) { model in
                Button {
                    session.model = model
                } label: {
                    if model == session.model {
                        Label(model.label, systemImage: "checkmark")
                    } else {
                        Text(model.isClaude && !AnthropicKey.isSet ? "\(model.label) (needs a key)" : model.label)
                    }
                }
                if model == .privateCloud { Divider() }
            }
            Divider()
            Text(session.model.privacy)
        } label: {
            HStack(spacing: 4) {
                Text(session.model.label)
                    .font(.system(size: 13))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Palette.textSecondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("The model the assistant uses")
    }
}

/// Earlier chats, newest first: open one, or delete it.
struct ChatHistory: View {
    var dismiss: () -> Void
    @State private var chats: [Chat] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chats")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            if chats.isEmpty {
                Text("No earlier chats.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(chats) { chat in
                            ChatHistoryRow(chat: chat, isCurrent: chat.id == AssistantSession.shared.chat.id) {
                                AssistantSession.shared.open(chat.id)
                                dismiss()
                            } delete: {
                                AssistantSession.shared.delete(chat.id)
                                chats.removeAll { $0.id == chat.id }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 300)
        .task { chats = await Task.detached { ChatStore.all() }.value }
    }
}

struct ChatHistoryRow: View {
    let chat: Chat
    let isCurrent: Bool
    let open: () -> Void
    let delete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Text(chat.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 4)
            if isHovered {
                Button(action: delete) {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .help("Delete this chat")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovered ? Palette.hover : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: open)
    }
}
