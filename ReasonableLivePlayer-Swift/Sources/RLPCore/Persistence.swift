import Foundation

private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}

/// Reads and writes `.rlp` playlist files.
public enum PlaylistFileService {
    public static func save(paths: [String], to url: URL) throws {
        let data = try makeEncoder().encode(PlaylistData(version: 1, songs: paths))
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PlaylistData.self, from: data).songs
    }
}

/// Persists `SettingsData` in UserDefaults (`~/Library/Preferences/<bundle id>.plist`).
///
/// The first time it runs with no saved settings, it imports the .NET version's
/// `~/.config/ReasonableLivePlayer/settings.json` (.NET maps ApplicationData to the XDG config
/// dir on macOS). That happens once; after that UserDefaults is the only source.
public struct SettingsStore {
    public let defaults: UserDefaults
    public let legacyURL: URL?

    private static let importDoneKey = "legacySettingsImportDone"

    private enum Key {
        static let midiDeviceName = "midiDeviceName"
        static let midiChannel = "midiChannel"
        static let endNoteNumber = "endNoteNumber"
        static let transitionDelaySec = "transitionDelaySec"
        static let lastPlaylistPath = "lastPlaylistPath"
        static let loadLastPlaylist = "loadLastPlaylist"
        static let alwaysOnTop = "alwaysOnTop"
        static let songSpacing = "songSpacing"
        static let songFontSize = "songFontSize"
        static let appearance = "appearance"
        static let showTooltips = "showTooltips"
        static let toolbarIconSize = "toolbarIconSize"
    }

    public init(defaults: UserDefaults = .standard, legacyURL: URL? = SettingsStore.defaultLegacyURL) {
        self.defaults = defaults
        self.legacyURL = legacyURL
    }

    public static var defaultLegacyURL: URL {
        let configHome: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configHome = URL(fileURLWithPath: xdg)
        } else {
            configHome = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        }
        return configHome.appendingPathComponent("ReasonableLivePlayer/settings.json")
    }

    public func load() -> SettingsData {
        importLegacyIfNeeded()

        var s = SettingsData()
        s.midiDeviceName = defaults.string(forKey: Key.midiDeviceName)
        if has(Key.midiChannel) { s.midiChannel = defaults.integer(forKey: Key.midiChannel) }
        if has(Key.endNoteNumber) { s.endNoteNumber = defaults.integer(forKey: Key.endNoteNumber) }
        if has(Key.transitionDelaySec) { s.transitionDelaySec = defaults.integer(forKey: Key.transitionDelaySec) }
        s.lastPlaylistPath = defaults.string(forKey: Key.lastPlaylistPath)
        s.loadLastPlaylist = defaults.bool(forKey: Key.loadLastPlaylist)
        s.alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
        if has(Key.songSpacing) { s.songSpacing = defaults.integer(forKey: Key.songSpacing) }
        if has(Key.songFontSize) { s.songFontSize = defaults.double(forKey: Key.songFontSize) }
        if let raw = defaults.string(forKey: Key.appearance), let mode = AppearanceMode(rawValue: raw) {
            s.appearance = mode
        }
        if has(Key.showTooltips) { s.showTooltips = defaults.bool(forKey: Key.showTooltips) }
        if let raw = defaults.string(forKey: Key.toolbarIconSize), let size = ToolbarIconSize(rawValue: raw) {
            s.toolbarIconSize = size
        }
        if s.transitionDelaySec < 0 { s.transitionDelaySec = SettingsData.defaultTransitionDelaySec }
        return s
    }

    public func save(_ s: SettingsData) {
        setOrRemove(s.midiDeviceName, Key.midiDeviceName)
        defaults.set(s.midiChannel, forKey: Key.midiChannel)
        defaults.set(s.endNoteNumber, forKey: Key.endNoteNumber)
        defaults.set(s.transitionDelaySec, forKey: Key.transitionDelaySec)
        setOrRemove(s.lastPlaylistPath, Key.lastPlaylistPath)
        defaults.set(s.loadLastPlaylist, forKey: Key.loadLastPlaylist)
        defaults.set(s.alwaysOnTop, forKey: Key.alwaysOnTop)
        defaults.set(s.songSpacing, forKey: Key.songSpacing)
        defaults.set(s.songFontSize, forKey: Key.songFontSize)
        defaults.set(s.appearance.rawValue, forKey: Key.appearance)
        defaults.set(s.showTooltips, forKey: Key.showTooltips)
        defaults.set(s.toolbarIconSize.rawValue, forKey: Key.toolbarIconSize)
    }

    private func has(_ key: String) -> Bool { defaults.object(forKey: key) != nil }

    private func setOrRemove(_ value: String?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private func importLegacyIfNeeded() {
        guard !defaults.bool(forKey: Self.importDoneKey) else { return }
        defaults.set(true, forKey: Self.importDoneKey)
        guard !has(Key.midiChannel),                       // nothing saved yet
              let url = legacyURL,
              let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode(SettingsData.self, from: data) else { return }
        save(legacy)
    }
}
