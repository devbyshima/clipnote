import AppKit
import SwiftData
import SwiftUI

@main
struct OvylApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var center = ProcessingCenter.shared

    init() {
        OvylFonts.register()
    }

    var body: some Scene {
        Window("Ovyl", id: "main") {
            ContentView()
                .environment(center)
                .tint(Palette.accentText)
                .frame(minWidth: 900, minHeight: 540)
        }
        .modelContainer(center.container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands { OvylCommands(center: center) }

        Settings {
            SettingsView()
                .environment(center)
        }
    }
}

struct OvylCommands: Commands {
    let center: ProcessingCenter
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showMedia") private var showMedia = true
    @AppStorage("showAssistant") private var showAssistant = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note from Video, Audio or Pictures…") { center.isImporterPresented = true }
                .keyboardShortcut("n")
            Button("Open Video, Audio or Pictures…") { center.isImporterPresented = true }
                .keyboardShortcut("o")
            Divider()
            Button("New Folder") {
                showSidebar = true
                center.createFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .sidebar) {
            Button(showSidebar ? "Hide Sidebar" : "Show Sidebar") { showSidebar.toggle() }
                .keyboardShortcut(".", modifiers: .command)
            Button(showMedia ? "Hide Media" : "Show Media") {
                if showAssistant {
                    showAssistant = false
                    showMedia = true
                } else {
                    showMedia.toggle()
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            Button(showAssistant ? "Close Assistant" : "Show Assistant") { showAssistant.toggle() }
                .keyboardShortcut("j", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessingCenter.shared.start()
    }

    /// Videos and pictures opened from Finder ("Open With" or dropped on the Dock icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        ProcessingCenter.shared.importFiles(urls)
    }
}
