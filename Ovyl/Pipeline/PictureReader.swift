import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads the text in a picture (a screenshot, a photo of a page or a
/// whiteboard) with Vision's document reader, keeping its paragraphs.
nonisolated enum PictureReader {
    struct Page: Sendable, Equatable {
        var title: String?
        var paragraphs: [String] = []
    }

    /// Loads a picture upright, at most `maxSize` pixels on its long side.
    static func image(at url: URL, maxSize: Int = 4096) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    @concurrent static func read(_ image: CGImage) async throws -> Page {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        if let document = try await request.perform(on: image).first?.document {
            var page = Page(title: document.title.map { tidy($0.transcript) })
            page.paragraphs = document.paragraphs.map { tidy($0.transcript) }
            // List items and table rows the paragraphs left out.
            let known = Similarity.normalize(page.paragraphs.joined(separator: " "))
            let extras = document.lists.flatMap { $0.items.map { "• " + tidy($0.itemString) } }
                + document.tables.flatMap { table in
                    table.rows.map { row in row.map { tidy($0.content.text.transcript) }.filter { !$0.isEmpty }.joined(separator: " · ") }
                }
            for extra in extras where !extra.isEmpty && !known.contains(Similarity.normalize(extra)) {
                page.paragraphs.append(extra)
            }
            page.paragraphs.removeAll { $0.filter { $0.isLetter || $0.isNumber }.isEmpty }
            if let title = page.title, page.paragraphs.first.map({ Similarity.isSame($0, title) }) == true {
                page.paragraphs.removeFirst()
            }
            if !page.paragraphs.isEmpty || page.title != nil { return page }
        }
        // The document reader found nothing: fall back to plain lines,
        // grouped into paragraphs where the gap between lines is larger.
        let lines = try await ScreenTextReader.recognize(image)
        return Page(paragraphs: ScreenTextSorter.blocks(lines).map { block in tidy(block.map(\.text).joined(separator: "\n")) })
    }

    /// One paragraph on one line: line breaks become spaces, and words
    /// hyphenated across a line break are joined.
    static func tidy(_ text: String) -> String {
        text.replacing(/(\p{L})-\n(\p{Ll})/, with: { "\($0.output.1)\($0.output.2)" })
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
