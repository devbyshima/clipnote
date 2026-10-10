import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Ovyl

/// Home as cards, and the folder color flower, rendered for checking by eye.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct HomeTests {
    static let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-home")

    private static func library() throws -> (ProcessingCenter, [Folder]) {
        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let center = ProcessingCenter(container: container)
        let context = center.context
        let folders = [("Shared", "#FF2D55", 12), ("Personal", "#AF52DE", 23), ("Work", "#FF9500", 1)].enumerated().map { index, spec in
            let folder = Folder(name: spec.0, colorName: spec.1)
            folder.createdAt = .now.addingTimeInterval(Double(-index) * 40_000 - 20_000)
            context.insert(folder)
            for number in 0..<spec.2 {
                let note = center.createTextNote(title: "\(spec.0) \(number)", markdown: "Text.", in: folder.id)
                note.createdAt = folder.createdAt.addingTimeInterval(-Double(number) * 3_600)
            }
            return folder
        }
        let review = center.createTextNote(title: "Build Review", markdown: """
            Title: Build
            Author: Tony Fadell

            Review:

            'Build' by Tony Fadell is an exceptional book that delves into the world of innovation, entrepreneurship, and the art of creating transformative products. As the creator of the iPod and one of the key figures behind the development of the iPhone, Tony Fadell brings a wealth of experience and insights to the table.
            """)
        review.createdAt = .now.addingTimeInterval(-10_000)
        let untitled = center.createTextNote(title: "Untitled", markdown: " ")
        untitled.editedMarkdown = ""
        untitled.createdAt = .now.addingTimeInterval(-60_000)
        let routine = center.createTextNote(title: "Back Routine", markdown: """
            1. Warm-up:
               - Start with 5-10 minutes of light cardio, such as brisk walking or cycling, to increase your heart rate and warm up your muscles.
               - Perform dynamic stretches for the upper body, focusing on the back, shoulders, and arms.

            2. Lat Pulldowns:
               - Sit at the lat pulldown machine and grip the bar slightly wider than shoulder-width apart.
               - Engage your back muscles and pull the bar down towards your chest while keeping your chest lifted.
            """)
        routine.createdAt = .now.addingTimeInterval(-100_000)
        center.save()
        return (center, folders)
    }

    @Test func renderHome() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let (center, folders) = try Self.library()
        let defaults = UserDefaults.standard
        let showed = defaults.bool(forKey: "showAssistant")
        defaults.set(false, forKey: "showAssistant")
        defer { defaults.set(showed, forKey: "showAssistant") }

        let scale = defaults.object(forKey: "homeCardScale")
        defer { defaults.set(scale, forKey: "homeCardScale") }
        let viewKeys = [HomeView.layoutKey, HomeView.sortKey, HomeView.ascendingKey, HomeView.foldersFirstKey, HomeView.showsTextKey]
        let savedView = viewKeys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(viewKeys, savedView) { defaults.set(value, forKey: key) } }
        viewKeys.forEach(defaults.removeObject(forKey:))
        defaults.set(1.0, forKey: "homeCardScale")
        try await render(ContentView(route: .home), center: center, name: "home-light", dark: false)
        try await render(ContentView(route: .home), center: center, name: "home-dark", dark: true)
        defaults.set(0.7, forKey: "homeCardScale")
        try await render(ContentView(route: .home), center: center, name: "home-small", dark: false)
        defaults.set(1.5, forKey: "homeCardScale")
        try await render(ContentView(route: .home), center: center, name: "home-large", dark: false)
        defaults.set(1.0, forKey: "homeCardScale")

        // The other views: an even grid sorted by title with folders first, and the list.
        defaults.set(HomeLayout.grid.rawValue, forKey: HomeView.layoutKey)
        defaults.set(HomeSort.title.rawValue, forKey: HomeView.sortKey)
        defaults.set(true, forKey: HomeView.ascendingKey)
        defaults.set(true, forKey: HomeView.foldersFirstKey)
        try await render(ContentView(route: .home), center: center, name: "home-grid", dark: false)
        defaults.set(HomeLayout.list.rawValue, forKey: HomeView.layoutKey)
        try await render(ContentView(route: .home), center: center, name: "home-list", dark: false)
        try await render(ContentView(route: .home), center: center, name: "home-list-dark", dark: true)

        let notes = try center.context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        let grid = CardGrid(folders: folders, notes: notes.filter { $0.folderID == nil }, allNotes: notes, allFolders: folders, showsActionsFor: folders[1].id, pickerOpen: true)
            .environment(Navigator(.home))
        try await render(grid, center: center, name: "picker-light", dark: false, size: CGSize(width: 980, height: 820))
        try await render(grid, center: center, name: "picker-dark", dark: true, size: CGSize(width: 980, height: 820))
        print("HOME SNAPSHOTS \(Self.folder.path)")
    }

    /// The logo where the app shows it: notes being made on Home and open,
    /// a note that failed, and the assistant's welcome.
    @Test func renderLogoPlaces() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let (center, _) = try Self.library()
        let defaults = UserDefaults.standard
        let showed = defaults.bool(forKey: "showAssistant")
        defer { defaults.set(showed, forKey: "showAssistant") }
        defaults.set(false, forKey: "showAssistant")

        let lecture = center.createTextNote(title: "Lecture 4", markdown: " ")
        lecture.status = .processing
        lecture.stage = "Transcribing speech"
        lecture.progress = 0.42
        lecture.createdAt = .now
        let walkthrough = center.createTextNote(title: "Product walkthrough", markdown: " ")
        walkthrough.status = .processing
        walkthrough.stage = "Reading on-screen text"
        walkthrough.progress = 0.71
        walkthrough.createdAt = .now.addingTimeInterval(-5)
        let broken = center.createTextNote(title: "Interview", markdown: " ")
        broken.status = .failed
        broken.errorMessage = "The video couldn't be opened."
        broken.createdAt = .now.addingTimeInterval(-50_000)
        center.save()

        try await render(ContentView(route: .home), center: center, name: "logo-home", dark: false, time: 2.2)
        try await render(ContentView(route: .note(lecture.id)), center: center, name: "logo-transcribing", dark: false, time: 2.2)
        try await render(ContentView(route: .note(walkthrough.id)), center: center, name: "logo-reading", dark: true, time: 2.4)
        try await render(ContentView(route: .note(broken.id)), center: center, name: "logo-failed", dark: false, time: 2.6)
        defaults.set(true, forKey: "showAssistant")
        try await render(ContentView(route: .home), center: center, name: "logo-assistant", dark: false, time: 2.2)
        print("LOGO SNAPSHOTS \(Self.folder.path)")
    }

    /// The right pane's ways out, a recording without frames, the settings
    /// tabs, and the shared background of the sidebar.
    @Test func renderPanesAndSettings() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let (center, _) = try Self.library()
        let defaults = UserDefaults.standard
        let showed = defaults.bool(forKey: "showAssistant")
        defer { defaults.set(showed, forKey: "showAssistant") }
        defaults.set(false, forKey: "showAssistant")
        defaults.set(true, forKey: "showMedia")

        let recording = Note(sourceName: "standup.m4a", sourceBookmark: nil)
        recording.status = .ready
        recording.title = "Standup"
        center.context.insert(recording)
        let video = Note(sourceName: "lecture.mp4", sourceBookmark: nil)
        video.status = .ready
        video.title = "Lecture 4"
        center.context.insert(video)
        center.save()

        try await render(ContentView(route: .note(recording.id)), center: center, name: "pane-recording", dark: false)
        try await render(ContentView(route: .note(video.id), showsNoteInfo: true), center: center, name: "pane-note-info-back", dark: false)
        try await render(ContentView(route: .media(video.id, item: nil), history: [.note(video.id)]), center: center, name: "pane-inspector-back", dark: true)
        try await render(ContentView(route: .media(video.id, item: nil)), center: center, name: "pane-inspector-close", dark: false)
        for tab in ["speech", "screen", "assistant", "storage"] {
            defaults.set(tab, forKey: "settingsTab")
            try await render(SettingsView(), center: center, name: "settings-\(tab)", dark: tab == "assistant", size: SettingsView.size)
        }
        defaults.removeObject(forKey: "settingsTab")
        print("PANES \(Self.folder.path)")
    }

    /// The flower opening out of the pill's color button and folding back
    /// into it, every 1/60 s along the springs the app uses, and with a
    /// petal and the center hovered.
    @Test func recordFlowerMotion() throws {
        let frames = Self.folder.appending(path: "flower")
        try? FileManager.default.removeItem(at: frames)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        var index = 0
        func capture(_ progress: Double, hovered: Int? = nil) throws {
            let renderer = ImageRenderer(content: FlowerStage(progress: progress, hovered: hovered).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: frames.appending(path: String(format: "frame_%03d.png", index)))
            index += 1
        }
        let spring = Spring(response: 0.42, dampingRatio: 0.66)
        for step in 0..<6 { try capture(0); _ = step }
        for step in 1...36 {
            try capture(spring.value(target: 1.0, time: Double(step) / 60))
        }
        for _ in 0..<20 { try capture(1, hovered: 4) }
        for _ in 0..<20 { try capture(1, hovered: 18) }
        for id in [7, 8, 9, 10, 11, 0, 1, 2, 15, 18] { try capture(1, hovered: id) }
        for step in 1...14 {
            let t = min(1, Double(step) / 12)
            try capture(1 - t * t * t)
        }
        for _ in 0..<6 { try capture(0) }
        print("FLOWER FRAMES \(index)")
    }

    /// Carrying cards with real mouse events: a note trades places with the
    /// cards it's carried over and settles into its new place, and a note
    /// carried onto a folder's middle files into it. Frames along the way are
    /// rendered for checking by eye.
    @Test func carryingCards() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let keys = [HomeView.layoutKey, HomeView.sortKey, HomeView.ascendingKey, HomeView.foldersFirstKey, HomeView.showsTextKey, "homeCardScale", "order.home"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        keys.forEach(defaults.removeObject(forKey:))
        defaults.set(1.0, forKey: "homeCardScale")

        // Newest first, with no text so every card is one row tall: three
        // columns of 300 points, two rows.
        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let center = ProcessingCenter(container: container)
        func note(_ title: String, age: TimeInterval) -> Note {
            let note = center.createTextNote(title: title, markdown: " ")
            note.editedMarkdown = ""
            note.createdAt = .now.addingTimeInterval(-age)
            return note
        }
        func folder(_ name: String, _ hex: String, age: TimeInterval) -> Folder {
            let folder = Folder(name: name, colorName: hex)
            folder.createdAt = .now.addingTimeInterval(-age)
            center.context.insert(folder)
            return folder
        }
        let first = note("First", age: 1_000)
        let shelf = folder("Shelf", "#2A9D8F", age: 2_000)
        let second = note("Second", age: 3_000)
        let box = folder("Box", "#E2725B", age: 4_000)
        center.save()

        let drag = CardDrag()
        let size = CGSize(width: 1000, height: 640)
        let hosting = NSHostingView(rootView:
            CardGrid(folders: [shelf, box], notes: [first, second], allNotes: [first, second], allFolders: [shelf, box])
                .overlay { CardDragLayer() }
                .environment(drag)
                .environment(center)
                .environment(Navigator(.home))
                .modelContainer(container)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(1))

        // Points from the top left; window points run up from the bottom.
        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: size.height - point.y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
            if let event { window.sendEvent(event) }
        }
        func carry(from start: CGPoint, to end: CGPoint, steps: Int = 24) async throws {
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                send(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                try await Task.sleep(for: .milliseconds(16))
            }
            try await Task.sleep(for: .milliseconds(450))
        }
        func capture(_ name: String) throws {
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: Self.folder.appending(path: "\(name).png"))
            print("SNAPSHOT \(name) \(data.base64EncodedString())")
        }

        // Columns start at 30, 349 and 668; the first row's middle is at 100.
        let firstSpot = CGPoint(x: 180, y: 100)
        send(.leftMouseDown, firstSpot)
        try await carry(from: firstSpot, to: CGPoint(x: 200, y: 112), steps: 6)
        #expect(drag.held?.id == first.id)
        try capture("carry-lifted")

        // Over the folder's edge it trades places, then with the other note.
        try await carry(from: CGPoint(x: 200, y: 112), to: CGPoint(x: 370, y: 100))
        try await carry(from: CGPoint(x: 370, y: 100), to: CGPoint(x: 818, y: 100))
        try capture("carry-over")
        send(.leftMouseUp, CGPoint(x: 818, y: 100))
        try await Task.sleep(for: .seconds(1))
        #expect(drag.held == nil)
        #expect(OrderStore.load("home") == [shelf.id, second.id, first.id, box.id])
        try capture("carry-settled")

        // The second note, now in the middle column, into the box below the first.
        let secondSpot = CGPoint(x: 499, y: 100)
        send(.leftMouseDown, secondSpot)
        try await carry(from: secondSpot, to: CGPoint(x: 180, y: 299))
        #expect(drag.fileTarget == box.id)
        try capture("carry-into-folder")
        send(.leftMouseUp, CGPoint(x: 180, y: 299))
        try await Task.sleep(for: .seconds(1.2))
        #expect(second.folderID == box.id)
        #expect(drag.held == nil)

        window.orderOut(nil)
        window.contentView = nil
    }

    /// The sidebar lists only pinned folders, and a folder card carried from
    /// Home onto the sidebar is pinned there.
    @Test func carryingAFolderPinsIt() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let keys = [HomeView.layoutKey, HomeView.sortKey, HomeView.ascendingKey, HomeView.foldersFirstKey, HomeView.showsTextKey, "homeCardScale", "order.home", "showAssistant", "showSidebar"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        keys.forEach(defaults.removeObject(forKey:))
        defaults.set(1.0, forKey: "homeCardScale")
        defaults.set(false, forKey: "showAssistant")

        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let center = ProcessingCenter(container: container)
        let box = Folder(name: "Box", colorName: "#E2725B")
        let desk = Folder(name: "Desk", colorName: "#2A9D8F")
        desk.isPinned = true
        desk.createdAt = .now.addingTimeInterval(-5_000)
        center.context.insert(box)
        center.context.insert(desk)
        center.save()

        let size = CGSize(width: 1320, height: 760)
        let hosting = NSHostingView(rootView:
            ContentView(route: .home)
                .environment(center)
                .modelContainer(container)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(1.2))

        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: size.height - point.y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
            if let event { window.sendEvent(event) }
        }
        func capture(_ name: String) throws {
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: Self.folder.appending(path: "\(name).png"))
            print("SNAPSHOT \(name) \(data.base64EncodedString())")
        }
        try capture("pin-before")

        // The newest folder, Box, is the first card, just right of the sidebar.
        let start = CGPoint(x: SidebarView.width + 130, y: 110)
        let end = CGPoint(x: 110, y: 330)
        send(.leftMouseDown, start)
        for step in 1...30 {
            let t = CGFloat(step) / 30
            send(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            try await Task.sleep(for: .milliseconds(16))
        }
        try await Task.sleep(for: .milliseconds(500))
        try capture("pin-over-sidebar")
        send(.leftMouseUp, end)
        try await Task.sleep(for: .seconds(1.2))
        #expect(box.isPinned)
        try capture("pin-after")

        window.orderOut(nil)
        window.contentView = nil
    }

    /// A folder made from Home's toolbar is named right on its card: the
    /// field takes focus with the name selected, and Return keeps what's typed.
    @Test func namingANewFolderOnItsCard() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let keys = [HomeView.layoutKey, HomeView.sortKey, "homeCardScale", "showAssistant"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        keys.forEach(defaults.removeObject(forKey:))
        defaults.set(1.0, forKey: "homeCardScale")
        defaults.set(false, forKey: "showAssistant")

        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let center = ProcessingCenter(container: container)
        let size = CGSize(width: 1100, height: 600)
        let hosting = NSHostingView(rootView:
            ContentView(route: .home)
                .environment(center)
                .modelContainer(container)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(1))

        let folder = center.createFolder(pinned: false)
        try await Task.sleep(for: .seconds(1))
        let field = try #require(window.firstResponder as? NSTextView, "the name field has focus")
        #expect(field.selectedRange().length == folder.name.count)
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        print("SNAPSHOT naming-folder \(data.base64EncodedString())")

        field.insertText("Trips", replacementRange: field.selectedRange())
        field.insertNewline(nil)
        try await Task.sleep(for: .milliseconds(500))
        #expect(folder.name == "Trips")
        #expect(!folder.isPinned)

        window.orderOut(nil)
        window.contentView = nil
    }

    /// A real click through a window picks the petal on top under it.
    @Test func flowerPicksThePetalClicked() async throws {
        final class Picked { var hex: String? }
        let picked = Picked()
        let size = FlowerPicker.size
        let hosting = NSHostingView(rootView:
            FlowerPicker(progress: 1, origin: 0) { picked.hex = $0 }
                .frame(width: 220, height: 220)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: 220, height: 220)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(0.5))

        // The flower's square sits centered; window points run up from the bottom.
        let inset = (220 - size) / 2
        func click(_ point: CGPoint) async throws {
            let location = CGPoint(x: inset + point.x, y: 220 - inset - point.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
                if let event { window.sendEvent(event) }
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        // The terracotta petal, second from the top on the right.
        try await click(CGPoint(x: size / 2 + 47 * sin(.pi / 6), y: size / 2 - 47 * cos(.pi / 6)))
        #expect(picked.hex == "#E2725B")
        // The off-white center.
        try await click(CGPoint(x: size / 2, y: size / 2))
        #expect(picked.hex == "#F1F2EC")
        // Where the dusty rose overlaps the walnut behind it, the rose is on top.
        try await click(CGPoint(x: size / 2 - 25 * sin(.pi / 3) - 6, y: size / 2 - 25 * cos(.pi / 3) - 6))
        #expect(picked.hex == "#D9A5B3")
        window.orderOut(nil)
        window.contentView = nil
    }

    /// The pointer gliding round the outer petals and into the middle, the
    /// swell following it, for checking by eye.
    @Test func renderPointerSweep() throws {
        let frames = Self.folder.appending(path: "sweep")
        try? FileManager.default.removeItem(at: frames)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let size = FlowerPicker.size
        var points: [CGPoint] = []
        for step in 0..<90 {
            let angle = (180 + Double(step) * 3) * .pi / 180
            points.append(CGPoint(x: size / 2 + 47 * sin(angle), y: size / 2 - 47 * cos(angle)))
        }
        let last = points.last!
        for step in 1...20 {
            let t = CGFloat(step) / 20
            points.append(CGPoint(x: last.x + (size / 2 - last.x) * t, y: last.y + (size / 2 - last.y) * t))
        }
        for (index, point) in points.enumerated() {
            let view = ZStack {
                Color(hex: "#131617")
                FlowerPicker(progress: 1, origin: 0, pointer: point) { _ in }
            }
            .frame(width: 240, height: 240)
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: frames.appending(path: String(format: "frame_%03d.png", index)))
        }
    }

    @Test func reorderingTakesTheTargetsPlace() {
        let ids = (0..<5).map { _ in UUID() }
        // Forward: the first card dropped on the third lands where the third was.
        #expect(OrderStore.moving(ids[0], to: ids[2], in: ids) == [ids[1], ids[2], ids[0], ids[3], ids[4]])
        // Back: the last dropped on the second lands before it.
        #expect(OrderStore.moving(ids[4], to: ids[1], in: ids) == [ids[0], ids[4], ids[1], ids[2], ids[3]])
        #expect(OrderStore.moving(ids[2], to: ids[2], in: ids) == ids)
        let scope = "test-\(UUID().uuidString)"
        OrderStore.save(ids, for: scope)
        #expect(OrderStore.load(scope) == ids)
        UserDefaults.standard.removeObject(forKey: "order.\(scope)")
    }

    @Test func folderColorsReadAsHex() {
        let folder = Folder(name: "A", colorName: "purple")
        #expect(folder.hex == "#AF52DE")
        folder.colorName = "#13FFAB"
        #expect(folder.hex == "#13FFAB")
        #expect(HexColor("#F1F2EC").isLight)
        #expect(!HexColor("#4A3426").isLight)
        #expect(NoteCard.day(.now) == "TODAY")
        #expect(NoteCard.preview(of: "## Heading\n\n[4:02](#t=242) So **this** is it.\n\n\n> [!screen] On screen\n> Slide") == "Heading\n\n4:02 So this is it.\n\nOn screen\nSlide")
    }

    private func render(_ view: some View, center: ProcessingCenter, name: String, dark: Bool, size: CGSize = CGSize(width: 1320, height: 900), time: Double = 6.2) async throws {
        let root = view
            .environment(center)
            .environment(\.motionTime, time)
            .modelContainer(center.container)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.minSize]
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1.5))
        hosting.layoutSubtreeIfNeeded()
        let frameView = window.contentView?.superview ?? hosting
        let rep = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: Self.folder.appending(path: "\(name).png"))
        // The container is private to the app, so the image also goes to the
        // log, as in SnapshotTests.
        print("SNAPSHOT \(name) \(data.base64EncodedString())")
        window.orderOut(nil)
        window.contentView = nil
    }
}

/// The pill with the flower over its color button, on the dark ground of
/// the reference video.
struct FlowerStage: View {
    let progress: Double
    var hovered: Int?

    var body: some View {
        ZStack {
            Color(hex: "#131617")
            FlowerPicker(progress: progress, origin: 100, hovered: hovered) { _ in }
                .position(x: 150, y: 128)
            FolderActionsBar(pickerOpen: progress > 0.5, rename: {}, color: {}, delete: {})
                .position(x: 150 - FolderActionsBar.colorOffset, y: 228)
        }
        .frame(width: 300, height: 300)
    }
}
