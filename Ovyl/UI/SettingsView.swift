import SwiftUI

/// Settings, laid out as Beam's: a sidebar of panes on the left, on the same
/// background as the main window's, and on the right the open pane's title
/// over cards of rows, split by hairlines, with green switches and capsule
/// choices.
struct SettingsView: View {
    static let size = CGSize(width: 760, height: 520)

    /// The pane last shown, so Settings opens where it was left.
    @AppStorage("settingsTab") private var pane = SettingsPane.speech

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
        }
        // As tall as the window, which adds the titlebar's height to it.
        .frame(width: Self.size.width)
        .frame(minHeight: Self.size.height, maxHeight: .infinity)
        .background(Palette.background)
        .ignoresSafeArea()
        .background(SettingsWindowStyler())
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                OvylMark()
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 16, height: 16)
                Text("Settings")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 14)
            // Clear of the traffic lights.
            .padding(.top, 40)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { sidebarRow($0) }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
            Text("Ovyl \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.textSecondary.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Palette.background)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.border).frame(width: 0.5)
        }
    }

    private func sidebarRow(_ item: SettingsPane) -> some View {
        let selected = pane == item
        return Button { pane = item } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12.5))
                    .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Palette.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // MARK: Panes

    @ViewBuilder private var content: some View {
        switch pane {
        case .speech: SpeechPane()
        case .screen: ScreenTextPane()
        case .formatting: FormattingPane()
        case .assistant: AssistantPane()
        case .storage: StoragePane()
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case speech, screen, formatting, assistant, storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speech: "Speech"
        case .screen: "Screen Text"
        case .formatting: "Formatting"
        case .assistant: "Assistant"
        case .storage: "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .speech: "waveform"
        case .screen: "text.viewfinder"
        case .formatting: "text.alignleft"
        case .assistant: "sparkles"
        case .storage: "internaldrive"
        }
    }
}

// MARK: - Speech

private struct SpeechPane: View {
    @Environment(ProcessingCenter.self) private var center
    @AppStorage(PipelineOptions.engineKey) private var engine = EnginePreference.automatic.rawValue
    @AppStorage(PipelineOptions.languageKey) private var language = ""
    @AppStorage(PipelineOptions.skipsMusicKey) private var skipsMusic = true

    /// Languages both Whisper and most Macs handle well, by ISO code.
    private static let languages = [
        "en", "es", "fr", "de", "it", "pt", "nl", "sv", "da", "no", "fi", "pl", "cs", "ro", "hu", "el",
        "ru", "uk", "tr", "ar", "he", "fa", "hi", "bn", "ur", "ja", "ko", "zh", "vi", "th", "id", "ms",
    ]

    var body: some View {
        PaneScaffold(title: "Speech", subtitle: "How Ovyl turns what's said into text.") {
            SettingsGroup(title: "Transcription") {
                StackedRow(title: "Engine", note: engineNote) {
                    CapsuleChoice(selection: $engine, options: EnginePreference.allCases.map { ($0.rawValue, $0.label) })
                }
                RowDivider()
                ValueRow(title: "Spoken language") {
                    ValueMenu(label: languageName) {
                        Button("Detect automatically") { language = "" }
                        Divider()
                        ForEach(sortedLanguages, id: \.code) { item in
                            Button(item.name) { language = item.code }
                        }
                    }
                }
                RowDivider()
                ToggleRow(
                    title: "Leave out songs and music",
                    subtitle: "Singing and music are recognized on this Mac and marked in the note instead of transcribed. Talking over background music is still transcribed.",
                    isOn: $skipsMusic
                )
            }
            SettingsGroup(title: "Engines") {
                ValueRow(title: "Whisper model") { ValuePill(text: whisperStatus) }
                RowDivider()
                ValueRow(title: "Apple Speech") { ValuePill(text: AppleSpeechEngine.isAvailable ? "Available" : "Not available on this Mac") }
            }
        }
    }

    private var sortedLanguages: [(code: String, name: String)] {
        Self.languages
            .map { (code: $0, name: Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var languageName: String {
        language.isEmpty ? "Detect automatically" : Locale.current.localizedString(forLanguageCode: language) ?? language
    }

    private var engineNote: String {
        switch EnginePreference(rawValue: engine) ?? .automatic {
        case .automatic:
            "Whisper large-v3 turbo, built into Ovyl, transcribes first for the best accuracy in any language. If it can't, Apple's on-device speech model takes over."
        case .whisper:
            "Only Whisper large-v3 turbo is used. It's built into Ovyl and works in about 100 languages."
        case .apple:
            "Apple's on-device speech model goes first; it's the fastest. macOS downloads its language files once. Whisper takes over if it can't."
        }
    }

    private var whisperStatus: String {
        guard WhisperEngine.isBundled else { return "Missing from this build" }
        return switch center.speechPhase {
        case .idle: "Built in"
        case .loading: "Loading…"
        case .optimizing: "Ready, optimizing for this Mac"
        case .ready: "Ready"
        case .failed: "Couldn't load"
        }
    }
}

// MARK: - Screen Text

private struct ScreenTextPane: View {
    @AppStorage(PipelineOptions.readsScreenTextKey) private var readsScreenText = true
    @AppStorage(PipelineOptions.frameIntervalKey) private var frameInterval = 1.0

    var body: some View {
        PaneScaffold(title: "Screen Text", subtitle: "What Ovyl reads from the screen in a video.") {
            SettingsGroup(
                title: "On-screen text",
                footer: "Subtitles that repeat the speech appear once: the transcript, or the subtitles where speech was unclear. Without speech, captions become the note's text."
            ) {
                ToggleRow(title: "Read text that appears on screen", isOn: $readsScreenText)
                RowDivider()
                StackedRow(title: "Check the screen") {
                    CapsuleChoice(selection: $frameInterval, options: [(0.5, "Every half second"), (1.0, "Every second"), (2.0, "Every 2 seconds")])
                }
                .disabled(!readsScreenText)
                .opacity(readsScreenText ? 1 : 0.5)
            }
        }
    }
}

// MARK: - Formatting

private struct FormattingPane: View {
    @AppStorage(PipelineOptions.smartFormattingKey) private var smartFormatting = false

    var body: some View {
        PaneScaffold(title: "Formatting", subtitle: "Titles, summaries and headings for each note.") {
            SettingsGroup(title: "Smart formatting", footer: "The transcript itself is never reworded. When it's off, notes use slide titles and the file name for headings.") {
                ToggleRow(title: "Write titles and summaries with Apple Intelligence", subtitle: note, isOn: $smartFormatting)
            }
        }
    }

    private var note: String {
        switch SmartFormatter.availability {
        case .available: "Writes the title, summary, key points, and section headings on this Mac."
        case .unavailable(let reason): reason
        }
    }
}

// MARK: - Assistant

private struct AssistantPane: View {
    @State private var apiKey = AnthropicKey.value ?? ""
    @State private var keySaved = AnthropicKey.isSet
    private var assistant: AssistantSession { .shared }

    var body: some View {
        PaneScaffold(title: "Assistant", subtitle: "The model that answers when you ask about your notes.") {
            SettingsGroup(title: "Model", footer: assistant.model.privacy) {
                ValueRow(title: "Model") {
                    ValueMenu(label: assistant.model.label) {
                        ForEach(AssistantModel.allCases) { model in
                            Button(model.label) { assistant.model = model }
                        }
                    }
                }
            }
            SettingsGroup(title: "Anthropic API key", footer: "Only needed for Claude. It's kept in your keychain.") {
                HStack(spacing: 10) {
                    SecureField("Anthropic API key", text: $apiKey, prompt: Text("sk-ant-…"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule(style: .continuous).fill(Palette.fill))
                        .onSubmit(save)
                    Button(action: save) {
                        Text(keyIsCurrent ? "Saved" : "Save")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.prominent)
                    .disabled(keyIsCurrent)
                    .focusEffectDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private var keyIsCurrent: Bool {
        keySaved && apiKey == (AnthropicKey.value ?? "")
    }

    private func save() {
        AnthropicKey.set(apiKey)
        keySaved = AnthropicKey.isSet
    }
}

// MARK: - Storage

private struct StoragePane: View {
    @Environment(ProcessingCenter.self) private var center
    @State private var confirmsSpeechClear = false
    private var storage: StorageManager { .shared }

    var body: some View {
        PaneScaffold(title: "Storage", subtitle: "What Ovyl keeps on this Mac.") {
            SettingsGroup(
                title: "Space used",
                footer: "Ovyl never copies your videos, audio or pictures; notes point to them where they are. Frames of deleted notes and old temporary files are cleaned up on their own."
            ) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowDivider() }
                    ValueRow(title: row.title) { ValuePill(text: StorageRow.format(row.bytes)) }
                }
                RowDivider()
                ValueRow(title: "Total", isBold: true) { ValuePill(text: StorageRow.format(storage.usage.total)) }
            }
            SettingsGroup(title: "Clean up") {
                ActionRow(
                    title: "Caches",
                    subtitle: "Empties the search index and temporary files. The index is rebuilt right away.",
                    action: "Clear"
                ) {
                    Task { await storage.clearCaches(center) }
                }
                RowDivider()
                ActionRow(
                    title: "Speech model build",
                    subtitle: "The next video takes a few extra minutes while Whisper is prepared for this Mac again.",
                    action: "Clear…"
                ) {
                    confirmsSpeechClear = true
                }
                .disabled(storage.usage.speechCache == 0)
            }
            SettingsGroup(title: "Privacy") {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(Palette.accent)
                    Text("Videos, audio, pictures, transcripts and notes are made on this Mac. Only when the assistant uses Claude or Apple's Private Cloud is what it reads sent out.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .task { await storage.measure() }
        .confirmationDialog("Clear the speech model build?", isPresented: $confirmsSpeechClear) {
            Button("Clear", role: .destructive) { Task { await storage.clearSpeechCache() } }
        } message: {
            Text("The next video takes a few extra minutes while Whisper is prepared for this Mac again.")
        }
    }

    private var rows: [(title: String, bytes: Int64)] {
        [
            ("Notes", storage.usage.notes),
            ("Frames and pictures", storage.usage.frames),
            ("Assistant chats", storage.usage.chats),
            ("Search index", storage.usage.index),
            ("Speech model build", storage.usage.speechCache),
            ("Temporary files", storage.usage.temporary),
        ]
    }
}

/// Byte counts as Settings shows them.
enum StorageRow {
    static func format(_ bytes: Int64) -> String {
        bytes == 0 ? "None" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Pane pieces

/// A scrolling pane: a large title and a line under it, above its cards.
private struct PaneScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 34)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.never)
    }
}

/// A titled card of rows, with an optional note under it.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .padding(.vertical, 3)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.textPrimary.opacity(0.06), lineWidth: 0.5)
                )
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
                    .padding(.top, 1)
            }
        }
    }
}

/// A hairline between rows in a card.
private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }
}

/// A title, and a note under it when there is one.
private struct RowTitle: View {
    let title: String
    var subtitle: String?
    var isBold = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: isBold ? .semibold : .regular))
                .foregroundStyle(Palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A title with a green switch at the end.
private struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            RowTitle(title: title, subtitle: subtitle)
            Spacer(minLength: 10)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Palette.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A title with a value or a control at the end.
private struct ValueRow<Trailing: View>: View {
    let title: String
    var isBold = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            RowTitle(title: title, isBold: isBold)
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A title over a control that takes the row's width, and a note under it.
private struct StackedRow<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
            control
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// A title and note with a green text button at the end.
private struct ActionRow: View {
    let title: String
    var subtitle: String?
    let action: String
    let perform: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            RowTitle(title: title, subtitle: subtitle)
            Spacer(minLength: 10)
            Button(action: perform) {
                Text(action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isEnabled ? Palette.accentText : Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A value in a small washed capsule.
private struct ValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(Palette.textPrimary.opacity(0.07)))
    }
}

/// A menu that looks like a `ValuePill` with a chevron.
private struct ValueMenu<Items: View>: View {
    let label: String
    @ViewBuilder var items: Items

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(Palette.textPrimary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
    }
}

/// Choices as a row of capsules, the chosen one washed green.
private struct CapsuleChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, label in
                let selected = selection == value
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(selected ? Palette.accent.opacity(0.2) : Palette.textPrimary.opacity(0.06)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
    }
}
