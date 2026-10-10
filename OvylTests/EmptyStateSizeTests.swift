import AppKit
import SwiftUI
import Testing
@testable import Ovyl

/// Renders every empty state at the sizes the middle pane can take, from the
/// narrowest pane in the smallest window to a full screen, at moments spread
/// through each loop, for checking by eye that nothing is cut off. Frames land
/// in the test host's temporary folder under ovyl-sizes; the path is printed.
@MainActor
@Suite(.serialized)
struct EmptyStateSizeTests {
    static let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-sizes")

    /// The middle pane's sizes: its minimum width (360) and the smallest
    /// window's height (about 490) up to a large display, plus the extremes
    /// of narrow and tall, wide and short.
    nonisolated static let sizes: [CGSize] = [
        CGSize(width: 360, height: 490),
        CGSize(width: 360, height: 1100),
        CGSize(width: 440, height: 620),
        CGSize(width: 540, height: 490),
        CGSize(width: 640, height: 760),
        CGSize(width: 760, height: 520),
        CGSize(width: 900, height: 680),
        CGSize(width: 1100, height: 820),
        CGSize(width: 1320, height: 490),
        CGSize(width: 1500, height: 940),
        CGSize(width: 1900, height: 1150),
        CGSize(width: 2500, height: 1350),
    ]

    @Test func renderAtEverySize() throws {
        try? FileManager.default.removeItem(at: Self.folder)
        print("SIZES \(Self.folder.path)")
        let scenes: [(String, Double, () -> AnyView)] = [
            ("home", 18.9, { AnyView(HomeEmptyState(onNew: {})) }),
            ("search", 13.5, { AnyView(SearchEmptyState(query: "Ovyl")) }),
            ("search-long", 13.5, { AnyView(SearchEmptyState(query: "quarterly planning review")) }),
            ("folder", 6.4, { AnyView(FolderEmptyState(onNew: {})) }),
            ("frames", 14.5, { AnyView(FramesEmptyState()) }),
            ("pictures", 14.5, { AnyView(FramesEmptyState(isPictures: true)) }),
        ]
        for (name, loop, view) in scenes {
            for size in Self.sizes {
                let folder = Self.folder.appending(path: "\(name)/\(Int(size.width))x\(Int(size.height))")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Eight moments through the loop, past the opening fade.
                for index in 0..<8 {
                    let t = 1.2 + loop * Double(index) / 8
                    try write(view(), size: size, t: t, dark: index % 4 == 3, to: folder.appending(path: "t\(index).png"))
                }
            }
        }
    }

    /// Whatever the pane, every piece placed sits whole inside it, clear
    /// of the headline and of the other pieces.
    @Test(arguments: EmptyStateSizeTests.sizes)
    func piecesFitWhole(_ size: CGSize) {
        let headline = CGRect(x: size.width / 2 - 200, y: size.height / 2 - 110, width: 400, height: 220)
        let layout = GridLayout(size: size).with(headline: headline)
        let pieces = GridLayout.ring.map { GridPiece($0, size: CGSize(width: 190, height: 114), outset: EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0)) }
        let corners = layout.place(pieces)
        let rects = corners.compactMap { $0 }.map { CGRect(x: $0.x, y: $0.y - 8, width: 190, height: 122) }
        for rect in rects {
            #expect(CGRect(origin: .zero, size: size).contains(rect), "\(rect) runs off \(size)")
            #expect(!rect.intersects(headline.insetBy(dx: 4, dy: -8)), "\(rect) covers the headline at \(size)")
        }
        for (index, rect) in rects.enumerated() {
            for other in rects[(index + 1)...] {
                #expect(!rect.intersects(other), "\(rect) overlaps \(other) at \(size)")
            }
        }
        // A roomy pane shows every piece.
        if size.width >= 1100, size.height >= 680 {
            #expect(rects.count == pieces.count)
        }
    }

    private func write(_ view: AnyView, size: CGSize, t: Double, dark: Bool, to url: URL) throws {
        let frame = view
            .environment(\.motionTime, t)
            .frame(width: size.width, height: size.height)
            .background(Palette.background)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: frame)
        renderer.scale = 1
        var image: CGImage?
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        let rendered = try #require(image)
        let data = try #require(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
