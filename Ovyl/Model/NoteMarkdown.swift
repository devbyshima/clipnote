import Foundation

/// A note's text as Markdown, the way the note view shows and edits it. It
/// follows Obsidian: on-screen text and music are callouts, and
/// timestamps are links (`[1:05](#t=65)`) that play the video from there.
nonisolated enum NoteMarkdown {
    static func body(of content: NoteContent) -> String {
        var blocks: [String] = []
        if let notice = content.notice {
            blocks.append(callout("warning", title: "Heads up", lines: [notice]))
        }
        if !content.screenTitles.isEmpty {
            blocks.append(callout("info", title: "On screen throughout", lines: content.screenTitles))
        }
        if !content.keyPoints.isEmpty {
            blocks.append("## Key points")
            blocks.append(content.keyPoints.map { "- \(oneLine($0))" }.joined(separator: "\n"))
        }

        let sections = Timeline.sections(of: content)
        if sections.isEmpty {
            blocks.append(content.isPictures
                ? "*No text was found in the pictures.*"
                : "*No speech or on-screen text was found in this video.*")
        }
        for section in sections {
            if let heading = section.heading {
                blocks.append("## \(oneLine(heading))")
            }
            if let picture = section.picture,
               let index = content.pictures.firstIndex(where: { $0.id == picture.id }) {
                blocks.append(pictureLink(picture.name, index: index))
                if section.entries.isEmpty { blocks.append("*No text was found in this picture.*") }
            }
            for entry in section.entries {
                switch entry {
                case .paragraph(let paragraph):
                    blocks.append(paragraph.source == .picture
                        ? paragraph.text
                        : "\(timestamp(paragraph.start)) \(paragraph.text)")
                case .screen(let moment):
                    let title = "On screen · \(timestamp(moment.start))"
                    if moment.kind == .commentary {
                        blocks.append(callout("quote", title: title, lines: moment.lines))
                    } else {
                        let lines = moment.lines.map { $0 == moment.title ? "**\($0)**" : $0 }
                        blocks.append(callout("screen", title: title, lines: lines))
                    }
                case .music(let span):
                    let title = "Music · \(timestamp(span.start))–\(TimeFormat.clock(span.end))"
                    blocks.append(callout("music", title: title, lines: ["Not transcribed."]))
                }
            }
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: Links

    /// `[1:05](#t=65)`, a link that plays the video from that moment.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let value = seconds.rounded(.down) == seconds
            ? String(Int(seconds))
            : String(format: "%.1f", seconds)
        return "[\(TimeFormat.clock(seconds))](#t=\(value))"
    }

    /// `[name](#p=2)`, a link that shows that picture.
    static func pictureLink(_ name: String, index: Int) -> String {
        let label = name.replacing("[", with: "(").replacing("]", with: ")")
        return "[\(label)](#p=\(index))"
    }

    /// The moment a timestamp link points at.
    static func seconds(in url: URL) -> TimeInterval? {
        guard url.scheme == nil, let fragment = url.fragment, fragment.hasPrefix("t=") else { return nil }
        return TimeInterval(fragment.dropFirst(2))
    }

    /// The picture a picture link points at.
    static func pictureIndex(in url: URL) -> Int? {
        guard url.scheme == nil, let fragment = url.fragment, fragment.hasPrefix("p=") else { return nil }
        return Int(fragment.dropFirst(2))
    }

    // MARK: Export

    /// The Markdown with its in-app links made plain, for other apps:
    /// timestamps become bold, picture links become italic names.
    static func portable(_ markdown: String) -> String {
        markdown
            .replacing(/\[([^\]\n]*)\]\(#t=[0-9.]+\)/) { "**\($0.output.1)**" }
            .replacing(/\[([^\]\n]*)\]\(#p=[0-9]+\)/) { "*\($0.output.1)*" }
    }

    /// The text without Markdown syntax, for search and plain-text export.
    static func plainText(_ markdown: String) -> String {
        MarkdownDocument.plainText(MarkdownDocument.parse(markdown))
    }

    // MARK: Helpers

    /// An Obsidian callout: `> [!kind] Title` and the lines, quoted.
    private static func callout(_ kind: String, title: String, lines: [String]) -> String {
        let body = lines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.isEmpty ? ">" : "> \($0)" }
        return (["> [!\(kind)] \(title)"] + body).joined(separator: "\n")
    }

    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }
}
