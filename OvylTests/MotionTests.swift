import AppKit
import SwiftUI
import Testing
@testable import Ovyl

/// Renders the empty states frame by frame with the motion clock held at each
/// moment, for checking the animation by eye. Frames land in the test host's
/// temporary folder under ovyl-motion; the path is printed.
@MainActor
@Suite(.serialized)
struct MotionTests {
    static let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-motion")

    @Test func renderEmptyStates() throws {
        try? FileManager.default.removeItem(at: Self.folder)
        print("MOTION \(Self.folder.path)")

        try render("home-dark", size: CGSize(width: 980, height: 680), dark: true, seconds: 18.9, fps: 10) {
            HomeEmptyState(onNew: {})
        }
        try render("home-light", size: CGSize(width: 980, height: 680), dark: false, seconds: 9, fps: 5) {
            HomeEmptyState(onNew: {})
        }
        try render("search", size: CGSize(width: 980, height: 680), dark: false, seconds: 13.5, fps: 10) {
            SearchEmptyState(query: "Ovyl")
        }
        try render("search-dark", size: CGSize(width: 980, height: 680), dark: true, seconds: 13.5, fps: 4) {
            SearchEmptyState(query: "Ovyl")
        }
        try render("folder", size: CGSize(width: 980, height: 680), dark: false, seconds: 6.4, fps: 12) {
            FolderEmptyState(onNew: {})
        }
        try render("folder-dark", size: CGSize(width: 980, height: 680), dark: true, seconds: 6.4, fps: 4) {
            FolderEmptyState(onNew: {})
        }
        try render("frames", size: CGSize(width: 980, height: 680), dark: false, seconds: 14.5, fps: 10) {
            FramesEmptyState()
        }
        try render("frames-dark", size: CGSize(width: 980, height: 680), dark: true, seconds: 14.5, fps: 4) {
            FramesEmptyState()
        }
    }

    private func render(_ name: String, size: CGSize, dark: Bool, seconds: Double, fps: Double, @ViewBuilder view: () -> some View) throws {
        let folder = Self.folder.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let content = view()
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        for index in 0..<Int((seconds * fps).rounded()) {
            let t = Double(index) / fps
            let frame = content
                .environment(\.motionTime, t)
                .frame(width: size.width, height: size.height)
                .background(Color.ovylBG)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: frame)
            renderer.scale = 2
            var image: CGImage?
            appearance.performAsCurrentDrawingAppearance {
                image = renderer.cgImage
            }
            let rep = NSBitmapImageRep(cgImage: try #require(image))
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: folder.appending(path: String(format: "frame_%04d.png", index)))
        }
    }
}
