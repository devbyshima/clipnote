import SwiftUI

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
