import Foundation

/// One block of a Markdown note: what Obsidian renders in reading view.
nonisolated indirect enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MarkdownListItem])
    case quote([MarkdownBlock])
    case callout(MarkdownCallout)
    case code(language: String, text: String)
    case rule
    case table(MarkdownTable)
}

nonisolated struct MarkdownListItem: Equatable, Sendable {
    enum Marker: Equatable, Sendable {
        case bullet
        case ordered(Int)
        case task(done: Bool)
    }

    /// 0 for a top-level item, 1 for one nested under it, and so on.
    var level: Int
    var marker: Marker
    var text: String
    /// The item's line in the source, so a task can be ticked off.
    var line: Int
}

/// `> [!kind] Title`, Obsidian's boxed note.
nonisolated struct MarkdownCallout: Equatable, Sendable {
    /// Lowercased, such as "summary" or "warning".
    var kind: String
    /// Empty when the source gives none; the kind is shown instead.
    var title: String
    /// Nil when the callout can't fold, true when it starts folded (`[!kind]-`).
    var folded: Bool?
    var body: [MarkdownBlock]
}

nonisolated struct MarkdownTable: Equatable, Sendable {
    enum Alignment: Equatable, Sendable { case leading, center, trailing }

    var header: [String]
    var alignments: [Alignment]
    var rows: [[String]]
}

/// Splits Markdown into blocks. Covers what notes use: ATX headings,
/// paragraphs, nested bullet, numbered and task lists, quotes and Obsidian
/// callouts, fenced code, rules and pipe tables. Inline syntax (emphasis,
/// links, code) is left in the text for the view to render.
nonisolated enum MarkdownDocument {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacing("\r\n", with: "\n").components(separatedBy: "\n")
        return parse(lines, firstLine: 0)
    }

    private static func parse(_ lines: [String], firstLine: Int) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isBlank(line) {
                i += 1
                continue
            }
            if let fence = fenceOpening(line) {
                var body: [String] = []
                i += 1
                while i < lines.count, !isFenceClose(lines[i], fence.marker) {
                    body.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.code(language: fence.language, text: body.joined(separator: "\n")))
                continue
            }
            if let heading = heading(line) {
                blocks.append(heading)
                i += 1
                continue
            }
            if isRule(line) {
                blocks.append(.rule)
                i += 1
                continue
            }
            if quoteContent(line) != nil {
                let start = i
                var inner: [String] = []
                while i < lines.count, let content = quoteContent(lines[i]) {
                    inner.append(content)
                    i += 1
                }
                blocks.append(quote(inner, firstLine: firstLine + start))
                continue
            }
            if i + 1 < lines.count, line.contains("|"), let alignments = tableAlignments(lines[i + 1]) {
                let header = cells(line)
                if header.count == alignments.count {
                    var rows: [[String]] = []
                    i += 2
                    while i < lines.count, lines[i].contains("|"), !isBlank(lines[i]) {
                        var row = cells(lines[i])
                        if row.count < header.count { row += Array(repeating: "", count: header.count - row.count) }
                        rows.append(Array(row.prefix(header.count)))
                        i += 1
                    }
                    blocks.append(.table(MarkdownTable(header: header, alignments: alignments, rows: rows)))
                    continue
                }
            }
            if listItem(line) != nil {
                var items: [MarkdownListItem] = []
                var indents: [Int] = []
                while i < lines.count {
                    let current = lines[i]
                    if let item = listItem(current) {
                        while let last = indents.last, last > item.indent { indents.removeLast() }
                        if indents.last.map({ $0 < item.indent }) ?? true { indents.append(item.indent) }
                        items.append(MarkdownListItem(
                            level: indents.count - 1, marker: item.marker, text: item.text, line: firstLine + i
                        ))
                        i += 1
                    } else if isBlank(current) {
                        // A blank line between items keeps the list going.
                        var next = i + 1
                        while next < lines.count, isBlank(lines[next]) { next += 1 }
                        guard next < lines.count, listItem(lines[next]) != nil else { break }
                        i = next
                    } else if !startsBlock(current), !items.isEmpty {
                        items[items.count - 1].text += "\n" + current.trimmingCharacters(in: .whitespaces)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(items))
                continue
            }

            var paragraph: [String] = []
            while i < lines.count, !isBlank(lines[i]), paragraph.isEmpty || !startsBlock(lines[i]) {
                paragraph.append(lines[i].trimmingCharacters(in: .whitespaces))
                i += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        }
        return blocks
    }

    // MARK: Blocks

    private static func quote(_ inner: [String], firstLine: Int) -> MarkdownBlock {
        if let first = inner.first,
           let match = first.wholeMatch(of: /\[!([A-Za-z0-9_-]+)\]([+-]?)[ \t]*(.*)/) {
            let fold = match.output.2
            return .callout(MarkdownCallout(
                kind: match.output.1.lowercased(),
                title: String(match.output.3).trimmingCharacters(in: .whitespaces),
                folded: fold.isEmpty ? nil : fold == "-",
                body: parse(Array(inner.dropFirst()), firstLine: firstLine + 1)
            ))
        }
        return .quote(parse(inner, firstLine: firstLine))
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        guard let match = line.wholeMatch(of: /[ ]{0,3}(#{1,6})(?:[ \t]+(.*))?/) else { return nil }
        var text = String(match.output.2 ?? "").trimmingCharacters(in: .whitespaces)
        // A closing run of #s is decoration.
        if let closing = text.firstMatch(of: /(^|[ \t]+)#+$/) {
            text = String(text[..<closing.range.lowerBound])
        }
        return .heading(level: match.output.1.count, text: text)
    }

    private static func isRule(_ line: String) -> Bool {
        line.wholeMatch(of: /[ ]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*/) != nil
    }

    /// The text after `>`, or nil when the line isn't quoted.
    private static func quoteContent(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: /[ ]{0,3}>[ ]?(.*)/) else { return nil }
        return String(match.output.1)
    }

    private static func fenceOpening(_ line: String) -> (marker: String, language: String)? {
        guard let match = line.wholeMatch(of: /[ ]{0,3}(`{3,}|~{3,})[ \t]*([^`\s]*).*/) else { return nil }
        return (String(match.output.1), String(match.output.2))
    }

    private static func isFenceClose(_ line: String, _ marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = marker.first, trimmed.count >= marker.count else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> (indent: Int, marker: MarkdownListItem.Marker, text: String)? {
        guard let match = line.wholeMatch(of: /([ \t]*)([-*+]|[0-9]{1,9}[.)])(?:[ \t]+(.*))?/) else { return nil }
        let indent = match.output.1.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let symbol = match.output.2
        var text = String(match.output.3 ?? "")
        var marker: MarkdownListItem.Marker = .bullet
        if symbol.first?.isNumber == true, let number = Int(symbol.dropLast()) {
            marker = .ordered(number)
        }
        if marker == .bullet, let task = text.wholeMatch(of: /\[([ xX])\](?:[ \t]+(.*))?/) {
            marker = .task(done: task.output.1 != " ")
            text = String(task.output.2 ?? "")
        }
        return (indent, marker, text)
    }

    /// Whether a line starts a block that ends a paragraph or a list item.
    private static func startsBlock(_ line: String) -> Bool {
        heading(line) != nil || isRule(line) || quoteContent(line) != nil
            || fenceOpening(line) != nil || listItem(line) != nil
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    // MARK: Tables

    private static func tableAlignments(_ line: String) -> [MarkdownTable.Alignment]? {
        guard line.contains("-") else { return nil }
        let parts = cells(line)
        var alignments: [MarkdownTable.Alignment] = []
        for part in parts {
            guard part.wholeMatch(of: /:?-+:?/) != nil else { return nil }
            alignments.append(part.hasPrefix(":") && part.hasSuffix(":") ? .center : part.hasSuffix(":") ? .trailing : .leading)
        }
        return alignments.isEmpty ? nil : alignments
    }

    private static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in row {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
                current.append(character)
            } else if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces).replacing("\\|", with: "|") }
    }

    // MARK: Editing

    /// The text with the task on `line` ticked or unticked.
    static func togglingTask(in text: String, line: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line),
              let match = lines[line].firstMatch(of: /^((?:[ ]{0,3}>[ ]?)*[ \t]*[-*+][ \t]+\[)([ xX])\]/)
        else { return text }
        let mark = match.output.2 == " " ? "x" : " "
        lines[line].replaceSubrange(match.output.2.startIndex..<match.output.2.endIndex, with: mark)
        return lines.joined(separator: "\n")
    }

    // MARK: Plain text

    static func plainText(_ blocks: [MarkdownBlock]) -> String {
        blocks.map(plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func plainText(_ block: MarkdownBlock) -> String {
        switch block {
        case .heading(_, let text), .paragraph(let text):
            return inlinePlain(text)
        case .list(let items):
            return items.map { item in
                let indent = String(repeating: "  ", count: item.level)
                let marker = switch item.marker {
                case .bullet: "•"
                case .ordered(let number): "\(number)."
                case .task(let done): done ? "[x]" : "[ ]"
                }
                return "\(indent)\(marker) \(inlinePlain(item.text))"
            }.joined(separator: "\n")
        case .quote(let blocks):
            return plainText(blocks)
        case .callout(let callout):
            let title = callout.title.isEmpty ? callout.kind.capitalized : inlinePlain(callout.title)
            return [title, plainText(callout.body)].filter { !$0.isEmpty }.joined(separator: "\n")
        case .code(_, let text):
            return text
        case .rule:
            return ""
        case .table(let table):
            return ([table.header] + table.rows)
                .map { $0.map(inlinePlain).joined(separator: "\t") }
                .joined(separator: "\n")
        }
    }

    /// Inline Markdown with its syntax removed: `**Hi** [there](x)` → `Hi there`.
    static func inlinePlain(_ text: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: text, options: options) else { return text }
        return String(parsed.characters).replacing("==", with: "")
    }
}
