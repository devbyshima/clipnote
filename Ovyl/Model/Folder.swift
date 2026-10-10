import Foundation
import SwiftData

/// A folder in the sidebar. Notes point at their folder by ID, so deleting a
/// folder leaves its notes in place, out of any folder.
@Model
final class Folder {
    var id = UUID()
    var name = ""
    var createdAt = Date.now
    /// The folder's color: a hex value such as "#FF2D55", picked with the
    /// color flower, or one of `Folder.colors` for older folders.
    var colorName = ""
    /// Whether the folder is pinned to the sidebar. Every folder is on Home;
    /// only pinned ones are also in the sidebar.
    var isPinned = false

    init(name: String, colorName: String = "") {
        self.name = name
        self.colorName = colorName
    }

    /// The colors new folders get, in turn: earth tones and the app's green,
    /// from the color flower.
    static let colors = ["#E2725B", "#2A9D8F", "#D4A017", "#3D5A80", "#B0C246", "#8E4162", "#E8833A", "#1F6F78", "#7A4E2D"]

    /// The folder's color as a hex value. Folders made before colors were hex
    /// values keep their named color.
    var hex: String {
        if colorName.hasPrefix("#") { return colorName }
        return switch colorName {
        case "pink": "#FF2D55"
        case "purple": "#AF52DE"
        case "orange": "#FF9500"
        case "green": "#30C75E"
        case "yellow": "#FFC300"
        case "teal": "#30B0C7"
        case "red": "#FF3B30"
        case "gray": "#8E8E93"
        default: "#0A84FF"
        }
    }
}
