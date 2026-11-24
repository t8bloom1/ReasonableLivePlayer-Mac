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

/// User settings. Key names match the `settings.json` written by the .NET versions.
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
    // Retained so a settings file round-trips unchanged. The Swift app stores window
    // geometry with NSWindow frame autosave instead.
    public var windowX: Double?
    public var windowY: Double?
    public var windowWidth: Double?
    public var windowHeight: Double?

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
        windowX: Double? = nil,
        windowY: Double? = nil,
        windowWidth: Double? = nil,
        windowHeight: Double? = nil
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
        self.windowX = windowX
        self.windowY = windowY
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
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
        case windowX = "WindowX"
        case windowY = "WindowY"
        case windowWidth = "WindowWidth"
        case windowHeight = "WindowHeight"
    }

    /// Tolerant decoding: any missing key takes its default, as the .NET record did.
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
        windowX = try c.decodeIfPresent(Double.self, forKey: .windowX)
        windowY = try c.decodeIfPresent(Double.self, forKey: .windowY)
        windowWidth = try c.decodeIfPresent(Double.self, forKey: .windowWidth)
        windowHeight = try c.decodeIfPresent(Double.self, forKey: .windowHeight)
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
