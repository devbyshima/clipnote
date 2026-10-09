import SwiftUI
import UniformTypeIdentifiers

/// The middle pane for an open note: the note itself once it's made, or its
/// progress, or what went wrong.
struct NotePageView: View {
    let note: Note
    let folders: [Folder]
    var startsEditing = false
    var onLink: (URL) -> OpenURLAction.Result

    private var folderName: String? {
        note.folderID.flatMap { id in folders.first { $0.id == id }?.name }
    }

    var body: some View {
        switch note.status {
        case .ready:
            NoteDocumentView(note: note, folders: folders, folderName: folderName, startsEditing: startsEditing, onLink: onLink)
        case .queued, .processing, .failed:
            VStack(spacing: 0) {
                PaneToolbar {
                    NoteTitle(note: note, subtitle: folderName)
                } trailing: {
                    PillGroup {
                        PillMenu(help: "More") { NoteMenuItems(note: note, folders: folders) }
                    }
                    RightPaneToggle()
                }
                if note.status == .failed {
                    FailedView(note: note)
                } else {
                    ProcessingView(note: note)
                }
            }
            .background(Color.ovylBG)
        }
    }
}

/// The note's title and, under it, its folder or file, centered in a toolbar.
struct NoteTitle: View {
    let note: Note
    var subtitle: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(note.displayTitle)
                .font(.system(size: 13.5, weight: .medium))
                .truncationMode(.tail)
            Text(subtitle ?? note.sourceName)
                .font(.system(size: 11))
                .foregroundStyle(Color.ovylSecondary)
                .truncationMode(.middle)
        }
        .lineLimit(1)
    }
}

/// The assistant (⌘J) and the right pane (⌘P). The assistant takes the
/// right pane while it's open; the pane button brings the media back.
struct RightPaneToggle: View {
    @AppStorage("showMedia") private var showRightPane = true
    @AppStorage("showAssistant") private var showAssistant = false

    var body: some View {
        PillGroup {
            PillButton(symbol: "sparkles", help: showAssistant ? "Close the assistant (⌘J)" : "Ask the assistant (⌘J)", isActive: showAssistant) {
                showAssistant.toggle()
            }
            PillButton(symbol: "sidebar.right", help: showRightPane && !showAssistant ? "Hide the right pane (⌘P)" : "Show the right pane (⌘P)") {
                if showAssistant {
                    showAssistant = false
                    showRightPane = true
                } else {
                    showRightPane.toggle()
                }
            }
        }
    }
}

/// The assistant button on pages without a note's media.
struct AssistantToggle: View {
    @AppStorage("showAssistant") private var showAssistant = false

    var body: some View {
        PillGroup {
            PillButton(symbol: "sparkles", help: showAssistant ? "Close the assistant (⌘J)" : "Ask the assistant (⌘J)", isActive: showAssistant) {
                showAssistant.toggle()
            }
        }
    }
}

struct ProcessingView: View {
    @Environment(ProcessingCenter.self) private var center
    let note: Note

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.ovylAccent)
                .symbolEffect(.variableColor.iterative.reversing, isActive: note.status == .processing)
                .frame(height: 50)

            VStack(spacing: 6) {
                Text(note.displayTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(note.status == .queued ? "Waiting for the note ahead of it" : note.stage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ovylSecondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: note.stage)
            }

            if note.status == .processing {
                VStack(spacing: 6) {
                    ProgressView(value: note.progress)
                        .frame(width: 300)
                        .animation(.easeOut(duration: 0.3), value: note.progress)
                    Text(note.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            PlainCapsuleButton(title: "Stop") { center.stop(note) }
                .keyboardShortcut(.cancelAction)
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
        VStack(spacing: 16) {
            EmptyState(
                symbol: "exclamationmark.triangle",
                title: "Couldn't make this note",
                message: note.errorMessage ?? "Something went wrong while making this note."
            )
            .frame(maxHeight: 220)
            HStack(spacing: 10) {
                FilledButton(title: "Try Again", symbol: "arrow.clockwise") { center.enqueue(note) }
                if note.kind == .video {
                    PlainCapsuleButton(title: note.mediaKind == .audio ? "Locate Recording…" : "Locate Video…") { isLocating = true }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
