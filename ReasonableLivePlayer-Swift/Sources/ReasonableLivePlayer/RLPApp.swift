import AppKit
import SwiftUI

@main
@MainActor
struct ReasonableLivePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        // A single-instance window: opening a .rlp from Finder reuses it.
        Window("Reasonable Live Player", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.player)
                .onOpenURL { url in model.open(url: url) }
        }
        .defaultSize(width: 420, height: 520)
        .commands { AppCommands(model: model) }
    }
}

/// Menu bar items and keyboard shortcuts.
@MainActor
struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Songs…") { model.addSongsViaPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Open Playlist…") { model.loadPlaylistViaPanel() }
                .keyboardShortcut("o")
            Button("Save Playlist…") { model.savePlaylistViaPanel() }
                .keyboardShortcut("s")
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.showSettings = true }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .help) {
            Button("Reasonable Live Player Help") { model.showHelp = true }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched outside a bundle (swift run); harmless inside one.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Covers both Cmd-Q and closing the window (which quits the app).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.confirmQuit() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}
