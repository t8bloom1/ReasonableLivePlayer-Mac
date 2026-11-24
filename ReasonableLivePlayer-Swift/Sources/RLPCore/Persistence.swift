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

/// Persists `SettingsData` as JSON.
///
/// New location: `~/Library/Application Support/ReasonableLivePlayer/settings.json`.
/// The .NET build stored settings in `~/.config/ReasonableLivePlayer/settings.json`
/// (.NET maps ApplicationData to the XDG config dir on macOS). If the new file does
/// not exist yet, the old one is read, and the next save writes to the new location.
public struct SettingsStore {
    public let url: URL
    public let legacyURL: URL?

    public init(url: URL = SettingsStore.defaultURL, legacyURL: URL? = SettingsStore.defaultLegacyURL) {
        self.url = url
        self.legacyURL = legacyURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ReasonableLivePlayer/settings.json")
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
        for candidate in [url, legacyURL].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: candidate),
                  var settings = try? JSONDecoder().decode(SettingsData.self, from: data) else { continue }
            if settings.transitionDelaySec < 0 {
                settings.transitionDelaySec = SettingsData.defaultTransitionDelaySec
            }
            return settings
        }
        return SettingsData()
    }

    public func save(_ settings: SettingsData) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeEncoder().encode(settings).write(to: url, options: .atomic)
    }
}
