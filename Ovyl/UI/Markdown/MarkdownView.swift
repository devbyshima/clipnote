import SwiftUI

/// Obsidian's reading view in Ovyl's look: a note's Markdown blocks with
/// Obsidian's type scale and spacing, list guides, task boxes, callouts,
/// quotes, code and tables.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    /// Called with a task's source line when its box is clicked.
    var onToggleTask: ((Int) -> Void)?
    @Environment(\.readerStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                MarkdownBlockView(block: block, onToggleTask: onToggleTask)
                    .padding(.top, index == 0 ? 0 : style.spacing(before: block, after: blocks[index - 1]))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How notes are set: the body size and family the reader picks, and
/// Obsidian's type scale and spacing from there.
struct ReaderStyle: Equatable {
    var size: CGFloat = 16
    var serif = false

    /// The readable line length.
    var lineWidth: CGFloat { 660 }
    var titleSize: CGFloat { size * 1.6 }
    var lineSpacing: CGFloat { size * 0.36 }

    func headingSize(_ level: Int) -> CGFloat {
        let scale: [CGFloat] = [1.6, 1.4, 1.25, 1.12, 1.05, 1.0]
        return size * scale[min(max(level, 1), 6) - 1]
    }

    func headingWeight(_ level: Int) -> Font.Weight {
        level <= 2 ? .bold : .semibold
    }

    func spacing(before block: MarkdownBlock, after previous: MarkdownBlock) -> CGFloat {
        if case .heading(let level, _) = block { return size * (level <= 2 ? 2.0 : 1.6) }
        if case .heading = previous { return size * 0.7 }
        return size
    }

    func render(_ text: String, scale: CGFloat = 1, weight: Font.Weight = .regular) -> AttributedString {
        MarkdownInline.render(text, size: size * scale, weight: weight, serif: serif)
    }
}

extension EnvironmentValues {
    @Entry var readerStyle = ReaderStyle()
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var onToggleTask: ((Int) -> Void)?
    @Environment(\.readerStyle) private var style

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownInline.render(text, size: style.headingSize(level), weight: style.headingWeight(level), serif: style.serif))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(style.render(text))
                .lineSpacing(style.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let items):
            MarkdownListView(items: items, onToggleTask: onToggleTask)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.ovylAccent)
                    .frame(width: 2)
                MarkdownView(blocks: blocks, onToggleTask: onToggleTask)
                    .padding(.leading, 22)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .callout(let callout):
            CalloutView(callout: callout, onToggleTask: onToggleTask)
        case .code(let language, let text):
            CodeBlockView(language: language, code: text)
        case .rule:
            Rectangle().fill(Color.ovylBorder).frame(height: 1).padding(.vertical, 12)
        case .table(let table):
            TableBlockView(table: table)
        }
    }
}

// MARK: - Inline

/// Turns a line of inline Markdown into styled text: bold, italic, code,
/// strikethrough, ==highlights==, links, [[wikilinks]] and timestamp links.
enum MarkdownInline {
    static func render(_ source: String, size: CGFloat, weight: Font.Weight = .regular, serif: Bool = false) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var text = (try? AttributedString(markdown: wikilinks(source), options: options)) ?? AttributedString(source)

        var styles: [(Range<AttributedString.Index>, Font, link: URL?, strike: Bool, code: Bool)] = []
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            let strong = intent.contains(.stronglyEmphasized)
            var font: Font
            if intent.contains(.code) {
                font = .system(size: size * 0.875, weight: strong ? .bold : .regular, design: .monospaced)
            } else {
                font = .ovyl(size, strong ? .bold : weight, serif: serif)
                if intent.contains(.emphasized) { font = font.italic() }
            }
            if let link = run.link, NoteMarkdown.seconds(in: link) != nil {
                font = .system(size: size * 0.9, weight: .medium).monospacedDigit()
            }
            styles.append((run.range, font, run.link, intent.contains(.strikethrough), intent.contains(.code)))
        }
        for style in styles {
            text[style.0].font = style.1
            if style.strike { text[style.0].strikethroughStyle = .single }
            if style.code { text[style.0].backgroundColor = Color.ovylCodeBG }
            if let link = style.link {
                text[style.0].foregroundColor = Color.ovylAccent
                let isAppLink = NoteMarkdown.seconds(in: link) != nil || NoteMarkdown.pictureIndex(in: link) != nil
                if !isAppLink { text[style.0].underlineStyle = .single }
            }
        }
        highlight(&text)
        return text
    }

    /// `[[Note]]` and `[[Note|label]]` become links that open the note with that title.
    private static func wikilinks(_ source: String) -> String {
        guard source.contains("[[") else { return source }
        return source.replacing(/\[\[([^\]|\n]+)(?:\|([^\]\n]+))?\]\]/) { match in
            let target = String(match.output.1)
            let label = match.output.2.map(String.init) ?? target
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            return "[\(label)](ovyl-note:\(encoded))"
        }
    }

    /// Marks text between `==` pairs and removes the `==`.
    private static func highlight(_ text: inout AttributedString) {
        while true {
            let characters = Array(text.characters)
            guard let open = pairStart(in: characters, from: 0),
                  let close = pairStart(in: characters, from: open + 2),
                  close > open + 2
            else { return }
            let start = text.characters.index(text.startIndex, offsetBy: open)
            let innerStart = text.characters.index(start, offsetBy: 2)
            let innerEnd = text.characters.index(text.startIndex, offsetBy: close)
            text[innerStart..<innerEnd].backgroundColor = Color.ovylHighlight
            let closeEnd = text.characters.index(innerEnd, offsetBy: 2)
            text.removeSubrange(innerEnd..<closeEnd)
            let openStart = text.characters.index(text.startIndex, offsetBy: open)
            text.removeSubrange(openStart..<text.characters.index(openStart, offsetBy: 2))
        }
    }

    private static func pairStart(in characters: [Character], from index: Int) -> Int? {
        var i = index
        while i + 1 < characters.count {
            if characters[i] == "=", characters[i + 1] == "=" { return i }
            i += 1
        }
        return nil
    }
}

// MARK: - Lists

struct MarkdownListView: View {
    let items: [MarkdownListItem]
    var onToggleTask: ((Int) -> Void)?
    @Environment(\.readerStyle) private var style

    /// How far each nesting level steps in.
    private let step: CGFloat = 26
    /// The column the marker sits in.
    private let markerWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                row(item)
            }
        }
    }

    private func row(_ item: MarkdownListItem) -> some View {
        let done = item.marker == .task(done: true)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker(item)
                .frame(width: markerWidth, alignment: .center)
            Text(style.render(item.text))
                .lineSpacing(style.lineSpacing)
                .strikethrough(done)
                .foregroundStyle(done ? Color.ovylSecondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.level) * step)
        .padding(.vertical, 2.5)
        .background(alignment: .leading) {
            // Obsidian's indentation guides, one per level above this item.
            ZStack(alignment: .leading) {
                ForEach(0..<item.level, id: \.self) { level in
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                        .offset(x: CGFloat(level) * step + markerWidth / 2)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(_ item: MarkdownListItem) -> some View {
        switch item.marker {
        case .bullet:
            Text("•")
                .font(.system(size: style.size, weight: .bold))
                .foregroundStyle(Color.ovylFaint)
        case .ordered(let number):
            Text("\(number).")
                .font(.ovyl(style.size, serif: style.serif).monospacedDigit())
                .foregroundStyle(Color.ovylSecondary)
                .fixedSize()
        case .task(let done):
            Button {
                onToggleTask?(item.line)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(done ? Color.ovylAccent : Color.clear)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(done ? Color.ovylAccent : Color.ovylFaint, lineWidth: 1)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 15, height: 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(onToggleTask == nil)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2.5 }
        }
    }
}

// MARK: - Callouts

/// Obsidian's callout: a tinted box with an icon and title, which can fold.
struct CalloutView: View {
    let callout: MarkdownCallout
    var onToggleTask: ((Int) -> Void)?
    @State private var folded: Bool
    @Environment(\.readerStyle) private var style

    init(callout: MarkdownCallout, onToggleTask: ((Int) -> Void)?) {
        self.callout = callout
        self.onToggleTask = onToggleTask
        _folded = State(initialValue: callout.folded ?? false)
    }

    var body: some View {
        let tint = CalloutStyle(kind: callout.kind)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: tint.symbol)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tint.title)
                Text(title)
                    .foregroundStyle(tint.title)
                    .fixedSize(horizontal: false, vertical: true)
                if callout.folded != nil {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint.title)
                        .rotationEffect(.degrees(folded ? -90 : 0))
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard callout.folded != nil else { return }
                withAnimation(.snappy(duration: 0.22)) { folded.toggle() }
            }

            if !folded, !callout.body.isEmpty {
                MarkdownView(blocks: callout.body, onToggleTask: onToggleTask)
                    .padding(.top, 8)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 13, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var title: AttributedString {
        let text = callout.title.isEmpty ? callout.kind.capitalized : callout.title
        return style.render(text, weight: .semibold)
    }
}

/// Icons and tints per callout kind.
struct CalloutStyle {
    let symbol: String
    let title: Color
    let background: Color

    init(kind: String) {
        let green = (Color.ovylAccent, Color.ovylAccent.opacity(0.09))
        let neutral = (Color.primary.opacity(0.75), Color.primary.opacity(0.045))
        let orange = (Color.orange, Color.orange.opacity(0.12))
        let red = (Color.red, Color.red.opacity(0.11))
        let (symbol, tint): (String, (Color, Color)) = switch kind {
        case "summary", "abstract", "tldr": ("list.bullet.clipboard", green)
        case "tip", "hint", "important": ("flame", green)
        case "success", "check", "done": ("checkmark.circle", green)
        case "screen": ("text.viewfinder", neutral)
        case "music": ("music.note", neutral)
        case "quote", "cite": ("quote.opening", neutral)
        case "todo": ("checkmark.circle", neutral)
        case "example": ("list.bullet", neutral)
        case "info": ("info.circle", neutral)
        case "question", "help", "faq": ("questionmark.circle", orange)
        case "warning", "caution", "attention": ("exclamationmark.triangle", orange)
        case "failure", "fail", "missing": ("xmark.circle", red)
        case "danger", "error": ("bolt", red)
        case "bug": ("ladybug", red)
        default: ("pencil", neutral)
        }
        self.symbol = symbol
        title = tint.0
        background = tint.1
    }
}

// MARK: - Code and tables

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code.isEmpty ? " " : code)
                .font(.system(size: 13, design: .monospaced))
                .lineSpacing(3)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ovylCodeBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isHovered || copied {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                } label: {
                    Text(copied ? "Copied" : (language.isEmpty ? "Copy" : language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ovylSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.ovylCodeBG, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Copy the code")
            }
        }
        .onHover { isHovered = $0 }
    }
}

struct TableBlockView: View {
    let table: MarkdownTable
    @Environment(\.readerStyle) private var style

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.header.indices, id: \.self) { column in
                        cell(table.header[column], column: column, isHeader: true)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.rows[row].indices, id: \.self) { column in
                            cell(table.rows[row][column], column: column, isHeader: false)
                        }
                    }
                }
            }
            .overlay {
                Rectangle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ text: String, column: Int, isHeader: Bool) -> some View {
        let alignment: Alignment = switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        return Text(style.render(text, scale: 0.94, weight: isHeader ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 60, maxWidth: 360, maxHeight: .infinity, alignment: alignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay {
                Rectangle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
    }
}
