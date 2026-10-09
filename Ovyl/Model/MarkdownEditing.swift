import Foundation

/// The formatting the editor's bar and shortcuts apply: each returns the
/// range to replace, what to put there, and where the selection goes after.
nonisolated enum MarkdownEditing {
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    enum LineStyle: Equatable, CaseIterable {
        case heading1, heading2, heading3, bullet, numbered, task, quote

        var prefix: String {
            switch self {
            case .heading1: "# "
            case .heading2: "## "
            case .heading3: "### "
            case .bullet: "- "
            case .numbered: "1. "
            case .task: "- [ ] "
            case .quote: "> "
            }
        }
    }

    /// Wraps the selection in `marker` ("**" for bold), or unwraps it when
    /// it's already wrapped.
    static func toggleWrap(_ text: String, selection: NSRange, marker: String) -> Edit {
        let ns = text as NSString
        let length = (marker as NSString).length
        let before = NSRange(location: selection.location - length, length: length)
        let after = NSRange(location: NSMaxRange(selection), length: length)
        if before.location >= 0, NSMaxRange(after) <= ns.length,
           ns.substring(with: before) == marker, ns.substring(with: after) == marker {
            return Edit(
                range: NSRange(location: before.location, length: selection.length + 2 * length),
                replacement: ns.substring(with: selection),
                selection: NSRange(location: before.location, length: selection.length)
            )
        }
        let selected = ns.substring(with: selection)
        if selection.length >= 2 * length, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: length, length: selection.length - 2 * length))
            return Edit(range: selection, replacement: inner, selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }
        return Edit(
            range: selection,
            replacement: marker + selected + marker,
            selection: NSRange(location: selection.location + length, length: selection.length)
        )
    }

    /// Makes the selection a link and selects the address to type over.
    static func link(_ text: String, selection: NSRange) -> Edit {
        let label = (text as NSString).substring(with: selection)
        let replacement = "[\(label)](url)"
        let urlStart = selection.location + (label as NSString).length + 3
        return Edit(range: selection, replacement: replacement, selection: NSRange(location: urlStart, length: 3))
    }

    /// Gives each line in the selection `style`, replacing any heading, list
    /// or quote it had, or takes `style` off when every line already has it.
    static func toggleLines(_ text: String, selection: NSRange, style: LineStyle) -> Edit {
        let ns = text as NSString
        let range = ns.lineRange(for: selection)
        var block = ns.substring(with: range)
        let endsWithNewline = block.hasSuffix("\n")
        if endsWithNewline { block.removeLast() }
        let lines = block.components(separatedBy: "\n")
        let removing = lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty || Self.style(of: $0) == style }

        var number = 1
        let changed = lines.map { line -> String in
            let body = stripped(line)
            if removing { return body }
            if lines.count > 1, line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if style == .numbered {
                defer { number += 1 }
                return "\(number). \(body)"
            }
            return style.prefix + body
        }
        let joined = changed.joined(separator: "\n")
        let replacement = joined + (endsWithNewline ? "\n" : "")
        let newSelection = selection.length == 0 && lines.count == 1
            ? NSRange(location: range.location + (joined as NSString).length, length: 0)
            : NSRange(location: range.location, length: (joined as NSString).length)
        return Edit(range: range, replacement: replacement, selection: newSelection)
    }

    /// The heading, list or quote a line starts with.
    static func style(of line: String) -> LineStyle? {
        guard let match = line.firstMatch(of: prefixPattern) else { return nil }
        let prefix = String(match.output.1)
        if prefix.hasPrefix("#") {
            return [1: .heading1, 2: .heading2, 3: .heading3][prefix.filter { $0 == "#" }.count]
        }
        if prefix.hasPrefix(">") { return .quote }
        if prefix.contains("[") { return .task }
        if prefix.first?.isNumber == true { return .numbered }
        return .bullet
    }

    private static func stripped(_ line: String) -> String {
        guard let match = line.firstMatch(of: prefixPattern) else { return line }
        return String(line[match.range.upperBound...])
    }

    private nonisolated(unsafe) static let prefixPattern = /^[ \t]*(#{1,6} |[-*+] \[[ xX]\] |[-*+] |[0-9]{1,9}[.)] |> )/
}
