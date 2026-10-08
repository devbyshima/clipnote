import AppKit
import SwiftData
import SwiftUI

@main
struct OvylApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var center = ProcessingCenter.shared

    var body: some Scene {
        Window("Ovyl", id: "main") {
            ContentView()
                .environment(center)
                .frame(minWidth: 860, minHeight: 540)
        }
        .modelContainer(center.container)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Video or Pictures…") { center.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(center)
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
