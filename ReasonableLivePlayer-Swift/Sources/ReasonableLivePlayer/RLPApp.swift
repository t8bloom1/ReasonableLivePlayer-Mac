import AppKit
import SwiftUI
import RLPCore

@main
@MainActor
struct ReasonableLivePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        // A single-instance window: opening a .rlp from Finder reuses it.
        Window(AppModel.appName, id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.player)
                .onOpenURL { url in model.open(url: url) }
        }
        .defaultSize(width: 420, height: 520)
        .commands { AppCommands(model: model, player: model.player) }

        // Help opens in its own resizable window, like Settings.
        Window("\(AppModel.appName) Help", id: HelpWindow.id) {
            HelpView()
        }
        .defaultSize(width: 520, height: 680)

        // The standard Settings window (⌘,).
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// Menu bar items and keyboard shortcuts.
@MainActor
struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppModel.appName)") { model.showAboutPanel() }
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Playlist…") { model.loadPlaylistViaPanel() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentPlaylists, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { model.loadPlaylist(from: url) }
                }
                Divider()
                Button("Clear Menu") { model.clearRecents() }
                    .disabled(model.recentPlaylists.isEmpty)
            }
            Button("Add Songs…") { model.addSongsViaPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Playlist") { model.savePlaylist() }
                .keyboardShortcut("s")
                .disabled(player.songs.isEmpty)
            Button("Save Playlist As…") { model.savePlaylistAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(player.songs.isEmpty)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(player.undoActionName.map { "Undo \($0)" } ?? "Undo") { player.undo() }
                .keyboardShortcut("z")
                .disabled(!player.canUndo)
            Button(player.redoActionName.map { "Redo \($0)" } ?? "Redo") { player.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!player.canRedo)
        }

        // Command-Return and Command-Right rather than bare keys, so a stray key press during a
        // live set cannot start or skip a song.
        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") {
                if player.isPlaying { player.pause() } else { player.play() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(player.songs.isEmpty || !model.accessibilityGranted)

            Button("Skip to Next Song") { player.skip() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player.songs.isEmpty)
        }

        CommandGroup(replacing: .help) {
            Button("\(AppModel.appName) Help") { openWindow(id: HelpWindow.id) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched outside a bundle (swift run); harmless inside one.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
