import SwiftUI

struct SettingsView: View {
    @Environment(ProcessingCenter.self) private var center
    @AppStorage(PipelineOptions.engineKey) private var engine = EnginePreference.automatic.rawValue
    @AppStorage(PipelineOptions.languageKey) private var language = ""
    @AppStorage(PipelineOptions.readsScreenTextKey) private var readsScreenText = true
    @AppStorage(PipelineOptions.frameIntervalKey) private var frameInterval = 1.0
    @AppStorage(PipelineOptions.smartFormattingKey) private var smartFormatting = true
    @AppStorage(PipelineOptions.skipsMusicKey) private var skipsMusic = true

    /// Languages both Whisper and most Macs handle well, by ISO code.
    private static let languages = [
        "en", "es", "fr", "de", "it", "pt", "nl", "sv", "da", "no", "fi", "pl", "cs", "ro", "hu", "el",
        "ru", "uk", "tr", "ar", "he", "fa", "hi", "bn", "ur", "ja", "ko", "zh", "vi", "th", "id", "ms",
    ]

    var body: some View {
        Form {
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
                    .help("Singing and music are recognized on this Mac and marked in the note instead of transcribed. Talking over background music is still transcribed.")
                LabeledContent("Whisper model") {
                    Text(whisperStatus).foregroundStyle(.secondary)
                }
                LabeledContent("Apple Speech") {
                    Text(AppleSpeechEngine.isAvailable ? "Available" : "Not available on this Mac")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Speech")
            } footer: {
                Text(engineFootnote).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Read text that appears on screen", isOn: $readsScreenText)
                Picker("Check the screen", selection: $frameInterval) {
                    Text("Every half second").tag(0.5)
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                }
                .disabled(!readsScreenText)
            } header: {
                Text("On-Screen Text")
            } footer: {
                Text("Subtitles that repeat the speech appear once: the transcript, or the subtitles where speech was unclear. Without speech, captions become the note's text.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Smart formatting with Apple Intelligence", isOn: $smartFormatting)
            } header: {
                Text("Formatting")
            } footer: {
                Text(formattingFootnote).foregroundStyle(.secondary)
            }

            Section {
                Label("Everything runs on this Mac. Videos, pictures, transcripts, and notes never leave your computer.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
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
