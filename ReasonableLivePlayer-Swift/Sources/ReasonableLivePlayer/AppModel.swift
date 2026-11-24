import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import RLPCore

/// Application-level state: settings, MIDI, Accessibility permission, file panels, window
/// chrome. Playlist and transport state live in `PlayerController`.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let windowFrameName = "RLPMainWindow"
    static let appName = "Reasonable Live Player"
    static let repositoryURL = URL(string: "https://github.com/t8bloom1/ReasonableLivePlayer-Mac")!

    let player: PlayerController

    @Published private(set) var settings: SettingsData
    @Published private(set) var midiConnected = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var availableDevices: [String] = []
    @Published private(set) var recentPlaylists: [URL] = []
    /// The `.rlp` file behind the current playlist, if it has been saved or opened from disk.
    @Published private(set) var currentPlaylistURL: URL? = nil {
        didSet { updateWindowChrome() }
    }

    private let store: SettingsStore
    private let midi = MidiNoteListener()
    private let keepAwake = ActivityKeeper()
    private weak var window: NSWindow?
    private var accessibilityTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

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

        // Hold a keep-awake assertion for as long as a set is running.
        player.$needsToStayAwake
            .removeDuplicates()
            .sink { [weak self] needed in self?.keepAwake.setActive(needed) }
            .store(in: &cancellables)
        // Show the unsaved-changes dot in the window's close button.
        player.$isDirty
            .removeDuplicates()
            .sink { [weak self] dirty in self?.window?.isDocumentEdited = dirty }
            .store(in: &cancellables)

        availableDevices = MidiNoteListener.availableDevices()
        connectMidi()
        loadLastPlaylistIfWanted()
        refreshRecents()
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

    /// Applies a change to the settings, saves it, and updates whatever depends on it.
    func update(_ change: (inout SettingsData) -> Void) {
        var new = settings
        change(&new)
        guard new != settings else { return }
        let old = settings
        settings = new
        store.save(new)

        player.transitionDelaySec = new.transitionDelaySec
        if new.alwaysOnTop != old.alwaysOnTop { applyWindowLevel() }
        if new.appearance != old.appearance { applyAppearance() }
        if new.midiDeviceName != old.midiDeviceName
            || new.midiChannel != old.midiChannel
            || new.endNoteNumber != old.endNoteNumber {
            connectMidi()
        }
    }

    /// The saved device name resolved to the display name shown in the picker. Handles names
    /// saved by the .NET version, which may not match CoreMIDI's display name exactly.
    var selectedDeviceName: String {
        guard let saved = settings.midiDeviceName, !saved.isEmpty else { return "" }
        return MidiNoteListener.findSource(named: saved)?.displayName ?? saved
    }

    private func applyAppearance() {
        let appearance: NSAppearance?
        switch settings.appearance {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        NSApplication.shared.appearance = appearance
    }

    // MARK: - Playing a chosen song

    /// Double-click or Return on a song. Closing songs needs Accessibility permission, so this
    /// does nothing without it, the same as the disabled Play button.
    func playSong(id: Song.ID) {
        guard accessibilityGranted else {
            player.setStatus("⚠ Accessibility permission required to play songs")
            return
        }
        player.playSong(id: id)
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
        availableDevices = MidiNoteListener.availableDevices()
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

    var windowTitle: String {
        currentPlaylistURL?.deletingPathExtension().lastPathComponent ?? Self.appName
    }

    /// Called with the hosting window. Safe to call repeatedly: SwiftUI calls it on every view
    /// update, which also lets it re-hide the title if SwiftUI restores it.
    func attach(window newWindow: NSWindow) {
        if window !== newWindow {
            window = newWindow
            newWindow.setFrameUsingName(Self.windowFrameName)
            newWindow.setFrameAutosaveName(Self.windowFrameName)
            keepOnScreen(newWindow)
            applyAppearance()
            updateWindowChrome()
        }
        // The title (the playlist name) sits in the title bar. Keep it visible in case SwiftUI
        // or an earlier version of the app left it hidden.
        if newWindow.titleVisibility != .visible { newWindow.titleVisibility = .visible }
        applyWindowLevel()
    }

    private func applyWindowLevel() {
        window?.level = settings.alwaysOnTop ? .floating : .normal
    }

    /// Proxy icon (when the title is shown) and the unsaved-changes dot in the close button.
    private func updateWindowChrome() {
        window?.representedURL = currentPlaylistURL
        window?.isDocumentEdited = player.isDirty
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
            currentPlaylistURL = url
            didUse(playlistAt: url)
        } catch {
            RLPLog.error("Could not open \(url.path): \(error.localizedDescription)")
            showError("Could not open playlist", detail: error.localizedDescription)
        }
    }

    /// Saves to the current file, or asks for one if the playlist has not been saved yet.
    /// Returns true if saved (or there was nothing to save).
    @discardableResult
    func savePlaylist() -> Bool {
        guard !player.songs.isEmpty else { return true }
        if let url = currentPlaylistURL { return write(to: url) }
        return savePlaylistAs()
    }

    @discardableResult
    func savePlaylistAs() -> Bool {
        guard !player.songs.isEmpty else { return true }
        let panel = NSSavePanel()
        panel.title = "Save Playlist"
        panel.nameFieldStringValue = (currentPlaylistURL?.lastPathComponent) ?? "Playlist.rlp"
        panel.allowedContentTypes = ["rlp"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(to: url)
    }

    private func write(to url: URL) -> Bool {
        do {
            try PlaylistFileService.save(paths: player.paths, to: url)
            player.markClean()
            currentPlaylistURL = url
            didUse(playlistAt: url)
            return true
        } catch {
            RLPLog.error("Could not save \(url.path): \(error.localizedDescription)")
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

    private func didUse(playlistAt url: URL) {
        update { $0.lastPlaylistPath = url.path }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecents()
    }

    private func refreshRecents() {
        recentPlaylists = NSDocumentController.shared.recentDocumentURLs
    }

    func clearRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecents()
    }

    private func loadLastPlaylistIfWanted() {
        guard settings.loadLastPlaylist,
              let path = settings.lastPlaylistPath,
              FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        guard let paths = try? PlaylistFileService.load(from: url) else { return }
        player.replaceSongs(paths: paths, undoable: false)
        currentPlaylistURL = url
    }

    // MARK: - About

    func showAboutPanel() {
        let build = Bundle.main.object(forInfoDictionaryKey: "RLPBuildDate") as? String ?? "unknown"
        let credits = NSMutableAttributedString(
            string: "Build date: \(build)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(
            string: Self.repositoryURL.absoluteString,
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: Self.repositoryURL]))
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate(ignoringOtherApps: true)
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
        case .alertFirstButtonReturn: return savePlaylist()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func shutdown() {
        accessibilityTask?.cancel()
        midi.disconnect()
        keepAwake.setActive(false)
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
