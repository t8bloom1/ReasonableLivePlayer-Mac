import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RLPCore

/// Application-level state: settings, MIDI, Accessibility permission, file panels.
/// Playlist and transport state live in `PlayerController`.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let windowFrameName = "RLPMainWindow"

    let player: PlayerController

    @Published private(set) var settings: SettingsData
    @Published private(set) var midiConnected = false
    @Published private(set) var accessibilityGranted = false
    @Published var showSettings = false
    @Published var showHelp = false

    private let store: SettingsStore
    private let midi = MidiNoteListener()
    private weak var window: NSWindow?
    private var accessibilityTask: Task<Void, Never>?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        let loaded = store.load()
        self.settings = loaded
        self.player = PlayerController(reason: ReasonBridge())
        player.transitionDelaySec = loaded.transitionDelaySec

        midi.onTrigger = { [weak self] in
            Task { @MainActor in self?.player.handleTrigger() }
        }
        midi.onConnectionChanged = { [weak self] connected in
            Task { @MainActor in self?.midiConnected = connected }
        }
        midi.onDevicesChanged = { [weak self] in
            Task { @MainActor in self?.devicesChanged() }
        }

        connectMidi()
        loadLastPlaylistIfWanted()
        startAccessibilityMonitor()
    }

    // MARK: - Status

    var statusIndicatorColor: Color {
        switch (midiConnected, accessibilityGranted) {
        case (true, true): return .green
        case (false, false): return .red
        default: return .yellow
        }
    }

    var statusIndicatorTooltip: String {
        let midiText = midiConnected ? "MIDI connected" : "MIDI not connected"
        let axText = accessibilityGranted ? "Accessibility granted" : "Accessibility NOT granted"
        return "\(midiText), \(axText)"
    }

    // MARK: - Settings

    func applySettings(_ new: SettingsData) {
        let midiChanged = new.midiDeviceName != settings.midiDeviceName
            || new.midiChannel != settings.midiChannel
            || new.endNoteNumber != settings.endNoteNumber
        settings = new
        persistSettings()
        player.transitionDelaySec = new.transitionDelaySec
        applyWindowLevel()
        if midiChanged || !midi.isConnected { connectMidi() }
    }

    func setAlwaysOnTop(_ on: Bool) {
        var s = settings
        s.alwaysOnTop = on
        applySettings(s)
    }

    private func persistSettings() {
        do { try store.save(settings) } catch {
            NSLog("Could not save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - MIDI

    private func connectMidi() {
        midi.disconnect()
        guard let name = settings.midiDeviceName, !name.isEmpty else { return }
        let channel = min(15, max(0, settings.midiChannel - 1))
        let note = min(127, max(0, settings.endNoteNumber))
        midi.connect(deviceName: name, channel: channel, noteNumber: note)
    }

    private func devicesChanged() {
        midi.verifyConnection()
        if !midi.isConnected { connectMidi() }
    }

    // MARK: - Accessibility permission

    private func startAccessibilityMonitor() {
        accessibilityGranted = AccessibilityPermission.isTrusted(prompt: false)
        guard !accessibilityGranted else { return }

        accessibilityTask = Task { [weak self] in
            // Let the window appear before showing the system prompt.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if !AccessibilityPermission.isTrusted(prompt: true) {
                self.player.setStatus("⚠ Accessibility permission required. Grant it in System Settings.")
            }
            // Poll so the indicator turns green as soon as permission is granted.
            while !Task.isCancelled {
                if AccessibilityPermission.isTrusted(prompt: false) {
                    self.accessibilityGranted = true
                    if self.player.statusText.hasPrefix("⚠") { self.player.setStatus("Ready") }
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: - Window

    /// Called with the hosting window. Safe to call repeatedly.
    func attach(window newWindow: NSWindow) {
        if window !== newWindow {
            window = newWindow
            newWindow.setFrameUsingName(Self.windowFrameName)
            newWindow.setFrameAutosaveName(Self.windowFrameName)
            keepOnScreen(newWindow)
        }
        applyWindowLevel()
    }

    private func applyWindowLevel() {
        window?.level = settings.alwaysOnTop ? .floating : .normal
    }

    /// If a saved frame is on a monitor that is no longer connected, bring the window back.
    private func keepOnScreen(_ window: NSWindow) {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if !visible { window.center() }
    }

    // MARK: - Files

    func addSongsViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Songs"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["reason", "rns"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            player.insertSongs(paths: panel.urls.map { $0.path })
        }
    }

    func loadPlaylistViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Playlist"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["rlp"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            loadPlaylist(from: url)
        }
    }

    func loadPlaylist(from url: URL) {
        do {
            let paths = try PlaylistFileService.load(from: url)
            player.replaceSongs(paths: paths)
            rememberPlaylist(url)
        } catch {
            showError("Could not open playlist", detail: error.localizedDescription)
        }
    }

    /// Returns true if the playlist was saved (or there was nothing to save).
    @discardableResult
    func savePlaylistViaPanel() -> Bool {
        guard !player.songs.isEmpty else { return true }
        let panel = NSSavePanel()
        panel.title = "Save Playlist"
        panel.nameFieldStringValue = "Playlist.rlp"
        panel.allowedContentTypes = ["rlp"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try PlaylistFileService.save(paths: player.paths, to: url)
            player.markClean()
            rememberPlaylist(url)
            return true
        } catch {
            showError("Could not save playlist", detail: error.localizedDescription)
            return false
        }
    }

    /// Opened from Finder or the Dock.
    func open(url: URL) {
        switch url.pathExtension.lowercased() {
        case "rlp": loadPlaylist(from: url)
        case "reason", "rns": player.insertSongs(paths: [url.path])
        default: break
        }
    }

    private func rememberPlaylist(_ url: URL) {
        var s = settings
        s.lastPlaylistPath = url.path
        settings = s
        persistSettings()
    }

    private func loadLastPlaylistIfWanted() {
        guard settings.loadLastPlaylist,
              let path = settings.lastPlaylistPath,
              FileManager.default.fileExists(atPath: path),
              let paths = try? PlaylistFileService.load(from: URL(fileURLWithPath: path)) else { return }
        player.replaceSongs(paths: paths)
    }

    // MARK: - Quit

    /// Asks whether to save a modified playlist. Returns false if the user cancels.
    func confirmQuit() -> Bool {
        guard player.isDirty, !player.songs.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save Playlist"
        alert.informativeText = "The playlist has been modified. Save before closing?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return savePlaylistViaPanel()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func shutdown() {
        accessibilityTask?.cancel()
        midi.disconnect()
    }

    // MARK: - Errors

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
