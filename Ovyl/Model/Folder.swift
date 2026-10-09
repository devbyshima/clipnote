import Foundation
import SwiftData

/// A folder in the sidebar. Notes point at their folder by ID, so deleting a
/// folder leaves its notes in place, out of any folder.
@Model
final class Folder {
    var id = UUID()
    var name = ""
    var createdAt = Date.now
    /// One of `Folder.colors`, for the folder's icon.
    var colorName = ""

    init(name: String, colorName: String = "") {
        self.name = name
        self.colorName = colorName
    }

    /// The colors a folder's icon can have, in the order new folders get them.
    static let colors = ["blue", "orange", "purple", "green", "pink", "yellow", "teal", "red", "gray"]
}
