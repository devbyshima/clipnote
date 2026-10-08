import AppKit
import SwiftUI

struct NoteListView: View {
    @Environment(ProcessingCenter.self) private var center
    let notes: [Note]
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(notes) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .contextMenu { menu(for: note) }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label("No Notes", systemImage: "film.stack")
                } description: {
                    Text("Drop a video here or press ⌘O.")
                }
            }
        }
        .onDeleteCommand {
            guard let id = selection, let note = notes.first(where: { $0.id == id }) else { return }
            let index = notes.firstIndex(of: note)
            center.delete(note)
            let remaining = notes.filter { $0.id != id }
            if let index, !remaining.isEmpty { selection = remaining[min(index, remaining.count - 1)].id }
        }
        .safeAreaInset(edge: .bottom) { ModelStatusBar() }
    }

    @ViewBuilder
    private func menu(for note: Note) -> some View {
        switch note.status {
        case .queued, .processing:
            Button("Stop Processing", systemImage: "stop.circle") { center.stop(note) }
        case .ready, .failed:
            Button("Process Again", systemImage: "arrow.clockwise") { center.enqueue(note) }
        }
        Button("Show Video in Finder", systemImage: "folder") { revealSource(of: note) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            if selection == note.id { selection = nil }
            center.delete(note)
        }
    }

    private func revealSource(of note: Note) {
        guard let url = note.resolveSource() else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.headline)
                .lineLimit(2)
            switch note.status {
            case .ready:
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            case .processing:
                ProgressView(value: note.progress)
                    .controlSize(.small)
                    .padding(.top, 2)
                Text(note.stage.isEmpty ? "Working" : note.stage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .queued:
                Label("Waiting", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed:
                Label(note.errorMessage ?? "Couldn't make this note", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 5)
    }

    private var subtitle: String {
        var parts = [note.createdAt.formatted(.relative(presentation: .named))]
        if note.duration > 0 { parts.append(TimeFormat.duration(note.duration)) }
        return parts.joined(separator: " · ")
    }

    private var preview: String {
        String(note.searchText.prefix(160)).replacing("\n", with: " ")
    }
}

/// Shows the speech model's state while it loads or if it failed.
struct ModelStatusBar: View {
    @Environment(ProcessingCenter.self) private var center

    var body: some View {
        switch center.speechPhase {
        case .loading(let firstTime):
            bar {
                ProgressView().controlSize(.mini)
                Text(firstTime ? "Getting the speech model ready…" : "Loading the speech model…")
            }
            .help("The first launch takes about a minute. After that, the speech model loads in seconds.")
        case .optimizing:
            bar {
                ProgressView().controlSize(.mini)
                Text("Optimizing speech for this Mac…")
            }
            .help("Videos are transcribed already. When this one-time step finishes, transcription is about 2.5 times faster and uses less power.")
        case .failed(let message):
            bar {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Whisper unavailable; Apple Speech will be used")
            }
            .help(message)
        case .idle, .ready:
            EmptyView()
        }
    }

    private func bar(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) { content() }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)
    }
}
