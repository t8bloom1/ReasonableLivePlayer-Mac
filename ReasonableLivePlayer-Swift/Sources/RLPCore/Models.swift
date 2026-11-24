import Foundation

/// A song in the playlist. `id` identifies the row in the UI; it is not persisted.
public struct Song: Identifiable, Equatable, Hashable {
    public let id: UUID
    public var path: String

    public init(path: String, id: UUID = UUID()) {
        self.path = path
        self.id = id
    }

    /// File name without its extension. Accepts both `/` and `\` separators so
    /// playlists created by the Windows version still show readable names.
    public var displayName: String {
        let last = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
        return (last as NSString).deletingPathExtension
    }

    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// On-disk format of a `.rlp` playlist. Key names match the files written by the
/// .NET versions of the app (`{"Version":1,"Songs":[...]}`).
public struct PlaylistData: Codable, Equatable {
    public var version: Int
    public var songs: [String]

    public init(version: Int = 1, songs: [String]) {
        self.version = version
        self.songs = songs
    }

    enum CodingKeys: String, CodingKey {
        case version = "Version"
        case songs = "Songs"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        songs = try c.decodeIfPresent([String].self, forKey: .songs) ?? []
    }
}

/// How the app chooses light or dark appearance.
public enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Size of the toolbar icons. The toolbar grows with them. Medium is the default.
public enum ToolbarIconSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}

/// User settings. Stored in UserDefaults by `SettingsStore`. The `Codable` conformance exists
/// so the `settings.json` written by the .NET version can be imported once; its key names
/// are kept for that reason.
public struct SettingsData: Codable, Equatable {
    public var midiDeviceName: String?
    public var midiChannel: Int          // 1-16
    public var endNoteNumber: Int        // 0-127
    public var transitionDelaySec: Int   // seconds between closing one song and opening the next
    public var lastPlaylistPath: String?
    public var loadLastPlaylist: Bool
    public var alwaysOnTop: Bool
    public var songSpacing: Int          // 0-20 points between songs
    public var songFontSize: Double      // 10-24
    public var appearance: AppearanceMode
    public var showTooltips: Bool
    public var toolbarIconSize: ToolbarIconSize

    public static let defaultTransitionDelaySec = 5

    public init(
        midiDeviceName: String? = nil,
        midiChannel: Int = 1,
        endNoteNumber: Int = 0,
        transitionDelaySec: Int = SettingsData.defaultTransitionDelaySec,
        lastPlaylistPath: String? = nil,
        loadLastPlaylist: Bool = false,
        alwaysOnTop: Bool = false,
        songSpacing: Int = 0,
        songFontSize: Double = 13,
        appearance: AppearanceMode = .system,
        showTooltips: Bool = true,
        toolbarIconSize: ToolbarIconSize = .medium
    ) {
        self.midiDeviceName = midiDeviceName
        self.midiChannel = midiChannel
        self.endNoteNumber = endNoteNumber
        self.transitionDelaySec = transitionDelaySec
        self.lastPlaylistPath = lastPlaylistPath
        self.loadLastPlaylist = loadLastPlaylist
        self.alwaysOnTop = alwaysOnTop
        self.songSpacing = songSpacing
        self.songFontSize = songFontSize
        self.appearance = appearance
        self.showTooltips = showTooltips
        self.toolbarIconSize = toolbarIconSize
    }

    enum CodingKeys: String, CodingKey {
        case midiDeviceName = "MidiDeviceName"
        case midiChannel = "MidiChannel"
        case endNoteNumber = "EndNoteNumber"
        case transitionDelaySec = "TransitionDelaySec"
        case lastPlaylistPath = "LastPlaylistPath"
        case loadLastPlaylist = "LoadLastPlaylist"
        case alwaysOnTop = "AlwaysOnTop"
        case songSpacing = "SongSpacing"
        case songFontSize = "SongFontSize"
        case appearance = "Appearance"
        case showTooltips = "ShowTooltips"
        case toolbarIconSize = "ToolbarIconSize"
    }

    /// Tolerant decoding: any missing key takes its default, as the .NET record did.
    /// Window geometry keys in old files are ignored (macOS saves the window frame itself).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        midiDeviceName = try c.decodeIfPresent(String.self, forKey: .midiDeviceName)
        midiChannel = try c.decodeIfPresent(Int.self, forKey: .midiChannel) ?? 1
        endNoteNumber = try c.decodeIfPresent(Int.self, forKey: .endNoteNumber) ?? 0
        transitionDelaySec = try c.decodeIfPresent(Int.self, forKey: .transitionDelaySec)
            ?? SettingsData.defaultTransitionDelaySec
        lastPlaylistPath = try c.decodeIfPresent(String.self, forKey: .lastPlaylistPath)
        loadLastPlaylist = try c.decodeIfPresent(Bool.self, forKey: .loadLastPlaylist) ?? false
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        songSpacing = try c.decodeIfPresent(Int.self, forKey: .songSpacing) ?? 0
        songFontSize = try c.decodeIfPresent(Double.self, forKey: .songFontSize) ?? 13
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? .system
        showTooltips = try c.decodeIfPresent(Bool.self, forKey: .showTooltips) ?? true
        toolbarIconSize = (try? c.decodeIfPresent(ToolbarIconSize.self, forKey: .toolbarIconSize)) ?? .medium
    }
}

extension Array {
    /// Returns a copy with the elements at `offsets` moved so they end up before the
    /// element that was at `destination`. Same semantics as SwiftUI's `onMove`, without
    /// requiring SwiftUI.
    public func movingItems(fromOffsets offsets: IndexSet, toOffset destination: Int) -> [Element] {
        let sources = offsets.filter { $0 >= 0 && $0 < count }
        guard !sources.isEmpty else { return self }
        let target = Swift.max(0, Swift.min(destination, count))
        let moved = sources.sorted().map { self[$0] }
        var result = self
        for index in sources.sorted(by: >) { result.remove(at: index) }
        let removedBefore = sources.filter { $0 < target }.count
        result.insert(contentsOf: moved, at: target - removedBefore)
        return result
    }
}
