import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ovylFolder = UTType(exportedAs: "com.fulltimestudio.ovyl.folder")
}

/// The hand-made order of Home and of each folder, as note and folder ids,
/// kept in the user's defaults.
enum OrderStore {
    private static func key(_ scope: String) -> String { "order.\(scope)" }

    static func load(_ scope: String) -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: key(scope)) ?? []).compactMap(UUID.init)
    }

    static func save(_ ids: [UUID], for scope: String) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key(scope))
    }

    /// `ids` with `dragged` put where `target` is: after it when moving
    /// forward, before it when moving back, so it takes the target's place.
    static func moving(_ dragged: UUID, to target: UUID, in ids: [UUID]) -> [UUID] {
        guard let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target), from != to else { return ids }
        var moved = ids
        moved.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        return moved
    }
}

/// When a drag last passed over the page. A drag that's cancelled tells no
/// one, so the page lets go of it once it falls quiet.
final class DragSignal {
    var last = Date.distantPast
}

/// What's being dragged around the grid or list.
struct DraggedItem: Equatable {
    let id: UUID
    let isFolder: Bool

    /// What it carries: a note can also be dropped on a folder in the
    /// sidebar, which reads it as a `NoteReference`.
    var provider: NSItemProvider {
        let provider = NSItemProvider()
        let type = isFolder ? UTType.ovylFolder : UTType.ovylNote
        let data = try? JSONEncoder().encode(NoteReference(id: id))
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return provider
    }
}

/// A card or row as a drop target while something is dragged. Passing over
/// a card moves the dragged one into its place, so the rest slide aside as
/// it goes; a note over a folder files into it on release instead.
struct ReorderDrop: DropDelegate {
    let target: UUID
    let targetIsFolder: Bool
    @Binding var dragging: DraggedItem?
    @Binding var fileTarget: UUID?
    let signal: DragSignal
    var move: (UUID, UUID) -> Void
    var file: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil
    }

    func dropEntered(info: DropInfo) {
        signal.last = .now
        guard let dragging, dragging.id != target else { return }
        if targetIsFolder, !dragging.isFolder {
            fileTarget = target
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            move(dragging.id, target)
        }
    }

    func dropExited(info: DropInfo) {
        if fileTarget == target { fileTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        signal.last = .now
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let dragging, targetIsFolder, !dragging.isFolder, dragging.id != target {
            file(dragging.id, target)
        }
        dragging = nil
        fileTarget = nil
        return true
    }
}

/// The grid or list as a whole: a drop between cards just ends the drag.
struct ReorderEnd: DropDelegate {
    @Binding var dragging: DraggedItem?
    @Binding var fileTarget: UUID?
    let signal: DragSignal

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        signal.last = .now
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        fileTarget = nil
        return true
    }
}
