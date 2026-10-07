import SwiftUI
import UniformTypeIdentifiers

struct NoteDetailView: View {
    @Environment(ProcessingCenter.self) private var center
    let note: Note

    var body: some View {
        switch note.status {
        case .ready:
            NoteDocumentView(note: note)
        case .queued, .processing:
            ProcessingView(note: note)
        case .failed:
            FailedView(note: note)
        }
    }
}

struct ProcessingView: View {
    @Environment(ProcessingCenter.self) private var center
    let note: Note

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative.reversing, isActive: note.status == .processing)
                .frame(height: 64)

            VStack(spacing: 6) {
                Text(note.displayTitle)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(note.status == .queued ? "Waiting for the video ahead of it" : note.stage)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: note.stage)
            }

            if note.status == .processing {
                VStack(spacing: 8) {
                    ProgressView(value: note.progress)
                        .frame(width: 360)
                        .animation(.easeOut(duration: 0.3), value: note.progress)
                    Text(note.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            Button("Stop", role: .cancel) { center.stop(note) }
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FailedView: View {
    @Environment(ProcessingCenter.self) private var center
    let note: Note
    @State private var isLocating = false

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Make This Note", systemImage: "exclamationmark.triangle")
        } description: {
            Text(note.errorMessage ?? "Something went wrong while processing this video.")
        } actions: {
            HStack {
                Button("Try Again") { center.enqueue(note) }
                    .buttonStyle(.borderedProminent)
                Button("Locate Video…") { isLocating = true }
            }
            .controlSize(.large)
        }
        .fileImporter(isPresented: $isLocating, allowedContentTypes: [.audiovisualContent]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            note.sourceBookmark = try? Note.bookmark(for: url)
            note.sourceName = url.lastPathComponent
            center.enqueue(note)
        }
    }
}

struct WelcomeView: View {
    @Environment(ProcessingCenter.self) private var center
    let hasNotes: Bool

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient.opacity(0.14))
                    .frame(width: 108, height: 108)
                Image(systemName: "film.stack")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Color.accentColor.gradient)
            }

            VStack(spacing: 10) {
                Text(hasNotes ? "Select a note, or drop a new video" : "Drop a video to make a note")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Clipnote transcribes what's said, reads any text that appears on screen, and writes it up as a clean, organized note.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            Button {
                center.isImporterPresented = true
            } label: {
                Label("Choose Video…", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)

            HStack(spacing: 12) {
                Feature(symbol: "waveform", title: "Transcribes speech")
                Feature(symbol: "text.viewfinder", title: "Reads on-screen text")
                Feature(symbol: "lock.fill", title: "Stays on this Mac")
            }
            .padding(.top, 8)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct Feature: View {
        let symbol: String
        let title: String

        var body: some View {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.6), in: Capsule())
        }
    }
}
