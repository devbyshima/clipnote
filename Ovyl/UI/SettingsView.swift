import SwiftUI

struct SettingsView: View {
    @Environment(ProcessingCenter.self) private var center
    @AppStorage(PipelineOptions.engineKey) private var engine = EnginePreference.automatic.rawValue
    @AppStorage(PipelineOptions.languageKey) private var language = ""
    @AppStorage(PipelineOptions.readsScreenTextKey) private var readsScreenText = true
    @AppStorage(PipelineOptions.frameIntervalKey) private var frameInterval = 1.0
    @AppStorage(PipelineOptions.smartFormattingKey) private var smartFormatting = true
    @AppStorage(PipelineOptions.skipsMusicKey) private var skipsMusic = true
    @State private var apiKey = AnthropicKey.value ?? ""
    @State private var keySaved = AnthropicKey.isSet
    @State private var confirmsSpeechClear = false
    private var assistant: AssistantSession { .shared }
    private var storage: StorageManager { .shared }

    /// Languages both Whisper and most Macs handle well, by ISO code.
    private static let languages = [
        "en", "es", "fr", "de", "it", "pt", "nl", "sv", "da", "no", "fi", "pl", "cs", "ro", "hu", "el",
        "ru", "uk", "tr", "ar", "he", "fa", "hi", "bn", "ur", "ja", "ko", "zh", "vi", "th", "id", "ms",
    ]

    /// The tab last shown, so Settings opens where it was left.
    @AppStorage("settingsTab") private var tab = SettingsTab.speech

    enum SettingsTab: String {
        case speech, screen, formatting, assistant, storage
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Speech", systemImage: "waveform", value: SettingsTab.speech) { page { speech } }
            Tab("Screen Text", systemImage: "text.viewfinder", value: SettingsTab.screen) { page { screenText } }
            Tab("Formatting", systemImage: "text.alignleft", value: SettingsTab.formatting) { page { formatting } }
            Tab("Assistant", systemImage: "sparkles", value: SettingsTab.assistant) { page { assistantSettings } }
            Tab("Storage", systemImage: "internaldrive", value: SettingsTab.storage) { page { storageSettings } }
        }
        .frame(width: 560)
        .task { await storage.measure() }
        .confirmationDialog("Clear the speech model build?", isPresented: $confirmsSpeechClear) {
            Button("Clear", role: .destructive) { Task { await storage.clearSpeechCache() } }
        } message: {
            Text("The next video takes a few extra minutes while Whisper is prepared for this Mac again.")
        }
    }

    /// A tab's settings as a grouped form on the app's background, as tall
    /// as its contents.
    private func page(@ViewBuilder _ content: () -> some View) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var speech: some View {
        Section {
            Picker("Engine", selection: $engine) {
                ForEach(EnginePreference.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Spoken language", selection: $language) {
                Text("Detect automatically").tag("")
                Divider()
                ForEach(sortedLanguages, id: \.code) { item in
                    Text(item.name).tag(item.code)
                }
            }
            Toggle("Leave out songs and music", isOn: $skipsMusic)
                .tint(Palette.accent)
                .help("Singing and music are recognized on this Mac and marked in the note instead of transcribed. Talking over background music is still transcribed.")
        } footer: {
            Text(engineFootnote).foregroundStyle(Palette.textSecondary)
        }
        Section {
            LabeledContent("Whisper model") {
                Text(whisperStatus).foregroundStyle(Palette.textSecondary)
            }
            LabeledContent("Apple Speech") {
                Text(AppleSpeechEngine.isAvailable ? "Available" : "Not available on this Mac")
                    .foregroundStyle(Palette.textSecondary)
            }
        } header: {
            Text("Engines")
        }
    }

    @ViewBuilder private var screenText: some View {
        Section {
            Toggle("Read text that appears on screen", isOn: $readsScreenText)
                .tint(Palette.accent)
            Picker("Check the screen", selection: $frameInterval) {
                Text("Every half second").tag(0.5)
                Text("Every second").tag(1.0)
                Text("Every 2 seconds").tag(2.0)
            }
            .disabled(!readsScreenText)
        } footer: {
            Text("Subtitles that repeat the speech appear once: the transcript, or the subtitles where speech was unclear. Without speech, captions become the note's text.")
                .foregroundStyle(Palette.textSecondary)
        }
    }

    @ViewBuilder private var formatting: some View {
        Section {
            Toggle("Smart formatting with Apple Intelligence", isOn: $smartFormatting)
                .tint(Palette.accent)
        } footer: {
            Text(formattingFootnote).foregroundStyle(Palette.textSecondary)
        }
    }

    @ViewBuilder private var assistantSettings: some View {
        Section {
            Picker("Model", selection: Binding(get: { assistant.model }, set: { assistant.model = $0 })) {
                ForEach(AssistantModel.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent("Anthropic API key") {
                HStack(spacing: 8) {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit(saveKey)
                    Button(keySaved && apiKey == (AnthropicKey.value ?? "") ? "Saved" : "Save", action: saveKey)
                        .disabled(keySaved && apiKey == (AnthropicKey.value ?? ""))
                }
            }
        } footer: {
            Text("\(assistant.model.privacy) The key is only needed for Claude and is kept in your keychain.")
                .foregroundStyle(Palette.textSecondary)
        }
    }

    @ViewBuilder private var storageSettings: some View {
        Section {
            StorageRow(title: "Notes", bytes: storage.usage.notes)
            StorageRow(title: "Frames and pictures", bytes: storage.usage.frames)
            StorageRow(title: "Assistant chats", bytes: storage.usage.chats)
            StorageRow(title: "Search index", bytes: storage.usage.index)
            StorageRow(title: "Speech model, built for this Mac", bytes: storage.usage.speechCache)
            StorageRow(title: "Temporary files", bytes: storage.usage.temporary)
            HStack {
                Button("Clear Caches") {
                    Task { await storage.clearCaches(center) }
                }
                .help("Empties the search index and temporary files. The index is rebuilt right away.")
                Button("Clear Speech Model Build…") { confirmsSpeechClear = true }
                    .disabled(storage.usage.speechCache == 0)
                Spacer()
                Text("Total \(StorageRow.format(storage.usage.total))")
                    .foregroundStyle(Palette.textSecondary)
            }
        } footer: {
            Text("Ovyl never copies your videos, audio or pictures; notes point to them where they are. Frames of deleted notes and old temporary files are cleaned up on their own.")
                .foregroundStyle(Palette.textSecondary)
        }
        Section {
            Label("Videos, audio, pictures, transcripts and notes are made on this Mac. Only when the assistant uses Claude or Apple's Private Cloud is what it reads sent out.", systemImage: "lock.fill")
                .foregroundStyle(Palette.textSecondary)
        } header: {
            Text("Privacy")
        }
    }

    private func saveKey() {
        AnthropicKey.set(apiKey)
        keySaved = AnthropicKey.isSet
    }

    private var sortedLanguages: [(code: String, name: String)] {
        Self.languages
            .map { (code: $0, name: Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var engineFootnote: String {
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

    private var formattingFootnote: String {
        switch SmartFormatter.availability {
        case .available:
            "Writes the title, summary, key points, and section headings on this Mac. The transcript itself is never reworded."
        case .unavailable(let reason):
            "\(reason) Until then, notes use slide titles and the file name for headings."
        }
    }
}

/// A kind of stored data and the space it takes.
struct StorageRow: View {
    let title: String
    let bytes: Int64

    var body: some View {
        LabeledContent(title) {
            Text(Self.format(bytes)).foregroundStyle(Palette.textSecondary).monospacedDigit()
        }
    }

    static func format(_ bytes: Int64) -> String {
        bytes == 0 ? "None" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
