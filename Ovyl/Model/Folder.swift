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

    init(name: String, colorName: String = "") {
        self.name = name
        self.colorName = colorName
    }

    /// The colors new folders get, in turn.
    static let colors = ["pink", "purple", "orange", "blue", "green", "yellow", "teal", "red", "gray"]

    /// The folder's color as a hex value.
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
