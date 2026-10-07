import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(ProcessingCenter.self) private var center
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var isDropTargeted = false

    init(initialSelection: UUID? = nil) {
        _selection = State(initialValue: initialSelection)
    }

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter {
            $0.displayTitle.localizedStandardContains(searchText)
                || $0.searchText.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        @Bindable var center = center
        NavigationSplitView {
            NoteListView(notes: filteredNotes, selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            if let note = notes.first(where: { $0.id == selection }) {
                NoteDetailView(note: note)
                    .id(note.id)
            } else {
                WelcomeView(hasNotes: !notes.isEmpty)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Import Video", systemImage: "plus") {
                    center.isImporterPresented = true
                }
                .help("Import a video (⌘O)")
            }
        }
        .fileImporter(
            isPresented: $center.isImporterPresented,
            allowedContentTypes: [.audiovisualContent],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { center.importFiles(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            !center.importFiles(urls).isEmpty
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isDropTargeted = targeted }
        }
        .overlay {
            if isDropTargeted { DropOverlay().transition(.opacity) }
        }
        .alert("Some files were skipped", isPresented: Binding(
            get: { center.importError != nil },
            set: { if !$0 { center.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(center.importError ?? "")
        }
        .onChange(of: center.lastImportedID) { _, id in
            if let id {
                searchText = ""
                selection = id
            }
        }
        .onAppear {
            if selection == nil { selection = notes.first?.id }
        }
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background.opacity(0.75))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .padding(18)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to make a note")
                    .font(.title2.weight(.semibold))
            }
        }
        .allowsHitTesting(false)
    }
}
