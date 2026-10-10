import AppKit
import Observation
import SwiftUI

/// Lets SwiftUI format the editor's text and place the formatting bar.
@MainActor @Observable
final class EditorController {
    /// The selection's bounds in the editor, while text is selected.
    var selectionRect: CGRect?
    @ObservationIgnored weak var textView: NSTextView?

    func wrap(_ marker: String) {
        guard let textView else { return }
        apply(MarkdownEditing.toggleWrap(textView.string, selection: textView.selectedRange(), marker: marker))
    }

    func lines(_ style: MarkdownEditing.LineStyle) {
        guard let textView else { return }
        apply(MarkdownEditing.toggleLines(textView.string, selection: textView.selectedRange(), style: style))
    }

    func link() {
        guard let textView else { return }
        apply(MarkdownEditing.link(textView.string, selection: textView.selectedRange()))
    }

    /// Replaces text the way typing does, so it can be undone.
    private func apply(_ edit: MarkdownEditing.Edit) {
        guard let textView, let storage = textView.textStorage,
              textView.shouldChangeText(in: edit.range, replacementString: edit.replacement)
        else { return }
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.window?.makeFirstResponder(textView)
    }
}

/// The note's Markdown, editable. Headings, emphasis and links show styled,
/// and their syntax is hidden except on the line being edited, as in
/// Obsidian's live preview. It grows with its text, so the page scrolls as one.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var controller: EditorController?
    var style = ReaderStyle()
    var focusOnAppear = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MarkdownTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: style.lineWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let view = MarkdownTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.insertionPointColor = Palette.NS.accentText
        view.delegate = context.coordinator
        view.controller = controller
        controller?.textView = view
        context.coordinator.textView = view
        context.coordinator.setText(text)
        return view
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        let coordinator = context.coordinator
        let styleChanged = coordinator.parent.style != style
        coordinator.parent = self
        view.controller = controller
        controller?.textView = view
        if view.string != text {
            coordinator.setText(text)
        } else if styleChanged {
            coordinator.restyle()
        }
        if focusOnAppear, !coordinator.didFocus {
            coordinator.didFocus = true
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: 0, length: 0))
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite,
              let layout = nsView.layoutManager, let container = nsView.textContainer
        else { return nil }
        if container.containerSize.width != width {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        return CGSize(width: width, height: max(ceil(used) + 8, 120))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        var didFocus = false
        private var pendingRange: NSRange?
        private var needsFullPass = false
        private var isSettingText = false
        /// The lines around the caret, whose syntax shows.
        private var revealed: NSRange?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        private var highlighter: MarkdownHighlighter { MarkdownHighlighter(style: parent.style) }

        func setText(_ text: String) {
            guard let textView, let storage = textView.textStorage else { return }
            isSettingText = true
            textView.string = text
            revealed = nil
            highlighter.highlight(storage, reveal: nil)
            textView.typingAttributes = highlighter.baseAttributes
            isSettingText = false
            textView.invalidateIntrinsicContentSize()
        }

        func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            highlighter.highlight(storage, reveal: revealed)
            textView.typingAttributes = highlighter.baseAttributes
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            let replaced = (textView.string as NSString).substring(with: range)
            let inserted = replacementString ?? ""
            // Fences change how every later line reads, so they restyle the whole text.
            if pendingRange != nil || [replaced, inserted].contains(where: { $0.contains("`") || $0.contains("~") }) {
                needsFullPass = true
            }
            pendingRange = NSRange(location: range.location, length: (inserted as NSString).length)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isSettingText, let textView, let storage = textView.textStorage else { return }
            let string = textView.string as NSString
            revealed = string.paragraphRange(for: textView.selectedRange())
            highlighter.highlight(storage, around: needsFullPass ? nil : pendingRange, reveal: revealed)
            pendingRange = nil
            needsFullPass = false
            parent.text = textView.string
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isSettingText, let textView, let storage = textView.textStorage else { return }
            let string = textView.string as NSString
            let selection = textView.selectedRange()
            let paragraph = string.paragraphRange(for: selection)
            if paragraph != revealed {
                let previous = revealed
                revealed = paragraph
                if let previous, NSMaxRange(previous) <= string.length {
                    highlighter.highlight(storage, around: previous, reveal: paragraph)
                }
                highlighter.highlight(storage, around: paragraph, reveal: paragraph)
            }
            let rect = selection.length > 0 ? bounds(of: selection, in: textView) : nil
            let controller = parent.controller
            DispatchQueue.main.async { controller?.selectionRect = rect }
        }

        func textDidEndEditing(_ notification: Notification) {
            let controller = parent.controller
            DispatchQueue.main.async { controller?.selectionRect = nil }
        }

        private func bounds(of range: NSRange, in textView: NSTextView) -> CGRect? {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            return rect
        }
    }
}

/// The editor's text view: ⌘B, ⌘I and ⌘K format the selection.
final class MarkdownTextView: NSTextView {
    weak var controller: EditorController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let controller,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }
        switch key {
        case "b": controller.wrap("**")
        case "i": controller.wrap("*")
        case "k": controller.link()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

/// The bar over selected text: emphasis, headings, lists and quotes.
struct FormatBar: View {
    let editor: EditorController

    var body: some View {
        if let rect = editor.selectionRect {
            GeometryReader { geo in
                let half: CGFloat = 230
                let x = min(max(rect.midX, half), max(half, geo.size.width - half))
                let above = rect.minY > 44
                bar
                    .fixedSize()
                    .position(x: x, y: above ? rect.minY - 24 : rect.maxY + 24)
            }
            .transition(.opacity)
        }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            button("bold", "Bold (⌘B)") { editor.wrap("**") }
            button("italic", "Italic (⌘I)") { editor.wrap("*") }
            button("strikethrough", "Strikethrough") { editor.wrap("~~") }
            button("chevron.left.forwardslash.chevron.right", "Code") { editor.wrap("`") }
            button("highlighter", "Highlight") { editor.wrap("==") }
            button("link", "Link (⌘K)") { editor.link() }
            separator
            text("H1", "Heading 1") { editor.lines(.heading1) }
            text("H2", "Heading 2") { editor.lines(.heading2) }
            text("H3", "Heading 3") { editor.lines(.heading3) }
            separator
            button("list.bullet", "Bulleted list") { editor.lines(.bullet) }
            button("list.number", "Numbered list") { editor.lines(.numbered) }
            button("checklist", "Checklist") { editor.lines(.task) }
            button("text.quote", "Quote") { editor.lines(.quote) }
        }
        .padding(.horizontal, 5)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        .shadow(color: Palette.shadow, radius: 10, y: 3)
    }

    private var separator: some View {
        Rectangle().fill(Palette.border).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        FormatButton(help: help, action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }
    }

    private func text(_ label: String, _ help: String, action: @escaping () -> Void) -> some View {
        FormatButton(help: help, action: action) {
            Text(label).font(.system(size: 13, weight: .semibold))
        }
    }
}

private struct FormatButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Palette.textPrimary.opacity(0.8))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovered ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Styles Markdown source the way Obsidian's live preview does.
@MainActor
struct MarkdownHighlighter {
    let style: ReaderStyle

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.ovyl(style.size, serif: style.serif), .foregroundColor: Palette.NS.textPrimary, .paragraphStyle: paragraph]
    }

    private var paragraph: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = style.size * 0.3
        return paragraph
    }

    /// A quote or callout line, set in from the margin.
    private var indented: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = style.size * 0.3
        paragraph.firstLineHeadIndent = style.size * 1.1
        paragraph.headIndent = style.size * 1.1
        return paragraph
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed, so a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern)
    }

    private static let heading = regex(#"^[ ]{0,3}(#{1,6})(?=[ \t]|$)[ \t]*"#)
    private static let quotePrefix = regex(#"^(?:[ ]{0,3}>[ ]?)+"#)
    private static let calloutMarker = regex(#"^\[![A-Za-z0-9_-]+\][+-]?"#)
    private static let listMarker = regex(#"^[ \t]*(?:[-*+]|[0-9]{1,9}[.)])[ \t]+(?:(\[[ xX]\])[ \t]+)?"#)
    private static let rule = regex(#"^[ ]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let fence = regex(#"^[ ]{0,3}(`{3,}|~{3,})"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStar = regex(#"(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?![*\w])"#)
    private static let italicUnderscore = regex(#"(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])"#)
    private static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let mark = regex(#"==(?=\S)(.+?)(?<=\S)=="#)
    private static let link = regex(#"!?\[([^\]\n]*)\]\(([^)\n]*)\)"#)
    private static let wikilink = regex(#"\[\[([^\]\n]+)\]\]"#)
    private static let code = regex(#"`[^`\n]+`"#)

    /// Syntax on lines away from the caret: there, but too small to see.
    private static let hidden: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
    ]

    /// Restyles the lines around `range`, or all of them when it's nil.
    /// Lines that overlap `reveal` show their syntax.
    func highlight(_ storage: NSTextStorage, around range: NSRange? = nil, reveal: NSRange?) {
        let string = storage.string as NSString
        var target = NSRange(location: 0, length: string.length)
        if let range, NSMaxRange(range) <= string.length {
            target = string.lineRange(for: range)
        }
        var openFence = Self.fenceState(before: target.location, in: string)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: target)
        string.enumerateSubstrings(in: target, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosingRange, _ in
            let line = string.substring(with: lineRange)
            let local = NSRange(location: 0, length: lineRange.length)
            if let match = Self.fence.firstMatch(in: line, range: local) {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                if let open = openFence {
                    if marker.first == open.first, marker.count >= open.count { openFence = nil }
                } else {
                    openFence = marker
                }
                storage.addAttributes(codeAttributes(color: Palette.NS.faint), range: lineRange)
                return
            }
            if openFence != nil {
                storage.addAttributes(codeAttributes(color: .labelColor), range: lineRange)
                return
            }
            let shows = reveal.map { NSIntersectionRange($0, enclosingRange).length > 0 || $0.location == enclosingRange.location } ?? false
            styleLine(line, at: lineRange.location, revealed: shows, in: storage)
        }
        storage.endEditing()
    }

    /// The fence still open where `location` starts, if any.
    private static func fenceState(before location: Int, in string: NSString) -> String? {
        guard location > 0 else { return nil }
        var open: String?
        string.enumerateSubstrings(in: NSRange(location: 0, length: location), options: .byLines) { line, _, _, _ in
            guard let line, let match = fence.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return }
            let marker = (line as NSString).substring(with: match.range(at: 1))
            if let current = open {
                if marker.first == current.first, marker.count >= current.count { open = nil }
            } else {
                open = marker
            }
        }
        return open
    }

    private func codeAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: style.size * 0.9, weight: .medium),
            .foregroundColor: color,
            .backgroundColor: Palette.NS.surfaceSunken,
        ]
    }

    private func styleLine(_ line: String, at offset: Int, revealed: Bool, in storage: NSTextStorage) {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        func absolute(_ range: NSRange) -> NSRange { NSRange(location: range.location + offset, length: range.length) }
        func syntax(_ range: NSRange) {
            guard range.length > 0 else { return }
            if revealed {
                storage.addAttribute(.foregroundColor, value: Palette.NS.faint, range: absolute(range))
            } else {
                storage.addAttributes(Self.hidden, range: absolute(range))
            }
        }

        if Self.rule.firstMatch(in: line, range: all) != nil {
            storage.addAttribute(.foregroundColor, value: Palette.NS.faint, range: absolute(all))
            return
        }
        if let match = Self.heading.firstMatch(in: line, range: all) {
            let level = match.range(at: 1).length
            let size = style.headingSize(level)
            let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
            storage.addAttribute(.font, value: NSFont.ovyl(size, weight: weight, serif: style.serif), range: absolute(all))
            syntax(match.range)
            styleInline(line, from: match.range.length, size: size, weight: weight, offset: offset, revealed: revealed, in: storage)
            return
        }

        var start = 0
        if let match = Self.quotePrefix.firstMatch(in: line, range: all) {
            start = match.range.length
            if revealed {
                storage.addAttribute(.foregroundColor, value: Palette.NS.textSecondary, range: absolute(match.range))
            } else {
                // Away from the caret a quote reads as an indented block.
                syntax(match.range)
                storage.addAttribute(.paragraphStyle, value: indented, range: absolute(all))
            }
            let rest = NSRange(location: start, length: ns.length - start)
            if let callout = Self.calloutMarker.firstMatch(in: line, range: rest) {
                if revealed {
                    storage.addAttributes([
                        .foregroundColor: Palette.NS.textSecondary,
                        .font: NSFont.ovyl(style.size * 0.85, weight: .semibold),
                    ], range: absolute(callout.range))
                } else {
                    syntax(callout.range)
                    let title = NSRange(location: NSMaxRange(callout.range), length: ns.length - NSMaxRange(callout.range))
                    storage.addAttributes([
                        .foregroundColor: Palette.NS.textPrimary,
                        .font: NSFont.ovyl(style.size, weight: .semibold, serif: style.serif),
                    ], range: absolute(title))
                }
                start = NSMaxRange(callout.range)
            }
        }
        let rest = NSRange(location: start, length: ns.length - start)
        if let match = Self.listMarker.firstMatch(in: line, range: rest) {
            storage.addAttribute(.foregroundColor, value: Palette.NS.textSecondary, range: absolute(match.range))
            let box = match.range(at: 1)
            if box.location != NSNotFound, ns.substring(with: box).lowercased() == "[x]" {
                let after = NSRange(location: NSMaxRange(match.range), length: ns.length - NSMaxRange(match.range))
                storage.addAttributes([
                    .foregroundColor: Palette.NS.textSecondary,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: absolute(after))
            }
            start = NSMaxRange(match.range)
        }
        styleInline(line, from: start, size: style.size, weight: .regular, offset: offset, revealed: revealed, in: storage)
    }

    private func styleInline(
        _ line: String, from start: Int, size: CGFloat, weight: NSFont.Weight,
        offset: Int, revealed: Bool, in storage: NSTextStorage
    ) {
        let ns = line as NSString
        guard start < ns.length else { return }
        let range = NSRange(location: start, length: ns.length - start)
        func absolute(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }
        func syntax(_ r: NSRange) {
            guard r.length > 0 else { return }
            if revealed {
                storage.addAttribute(.foregroundColor, value: Palette.NS.faint, range: absolute(r))
            } else {
                storage.addAttributes(Self.hidden, range: absolute(r))
            }
        }
        func markers(of match: NSTextCheckingResult, inner: Int) {
            let content = match.range(at: inner)
            syntax(NSRange(location: match.range.location, length: content.location - match.range.location))
            syntax(NSRange(location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)))
        }

        for match in Self.bold.matches(in: line, range: range) {
            storage.addAttribute(.font, value: NSFont.ovyl(size, weight: .bold, serif: style.serif), range: absolute(match.range(at: 2)))
            markers(of: match, inner: 2)
        }
        let italic = NSFontManager.shared.convert(NSFont.ovyl(size, weight: weight, serif: style.serif), toHaveTrait: .italicFontMask)
        for pattern in [Self.italicStar, Self.italicUnderscore] {
            for match in pattern.matches(in: line, range: range) {
                storage.addAttribute(.font, value: italic, range: absolute(match.range(at: 1)))
                markers(of: match, inner: 1)
            }
        }
        for match in Self.strike.matches(in: line, range: range) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: absolute(match.range(at: 1)))
            markers(of: match, inner: 1)
        }
        for match in Self.mark.matches(in: line, range: range) {
            storage.addAttribute(.backgroundColor, value: Palette.NS.highlight, range: absolute(match.range(at: 1)))
            markers(of: match, inner: 1)
        }
        for match in Self.link.matches(in: line, range: range) {
            let label = match.range(at: 1)
            let target = ns.substring(with: match.range(at: 2))
            markers(of: match, inner: 1)
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: Palette.NS.accentText]
            if target.hasPrefix("#t=") {
                attributes[.font] = NSFont.monospacedDigitSystemFont(ofSize: size * 0.9, weight: .medium)
            }
            storage.addAttributes(attributes, range: absolute(label))
        }
        for match in Self.wikilink.matches(in: line, range: range) {
            markers(of: match, inner: 1)
            storage.addAttribute(.foregroundColor, value: Palette.NS.accentText, range: absolute(match.range(at: 1)))
        }
        for match in Self.code.matches(in: line, range: range) {
            let inner = NSRange(location: match.range.location + 1, length: match.range.length - 2)
            storage.addAttributes(codeAttributes(color: .labelColor), range: absolute(inner))
            syntax(NSRange(location: match.range.location, length: 1))
            syntax(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }
    }
}
