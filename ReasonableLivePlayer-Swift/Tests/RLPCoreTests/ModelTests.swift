import XCTest
@testable import RLPCore

final class SongTests: XCTestCase {
    func testDisplayNameIsFileNameWithoutExtension() {
        XCTAssertEqual(Song(path: "/Users/me/Music/My Song.reason").displayName, "My Song")
        XCTAssertEqual(Song(path: "/a/b/track.rns").displayName, "track")
        XCTAssertEqual(Song(path: "plain.reason").displayName, "plain")
    }

    func testDisplayNameHandlesWindowsPaths() {
        XCTAssertEqual(Song(path: #"C:\Music\Set 1\Opener.reason"#).displayName, "Opener")
    }

    func testFileExists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rlp-\(UUID()).reason")
        XCTAssertFalse(Song(path: url.path).fileExists)
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(Song(path: url.path).fileExists)
    }
}

final class ArrayMoveTests: XCTestCase {
    func testMatchesOnMoveSemantics() {
        let a = ["A", "B", "C", "D"]
        XCTAssertEqual(a.movingItems(fromOffsets: [0], toOffset: 3), ["B", "C", "A", "D"])
        XCTAssertEqual(a.movingItems(fromOffsets: [3], toOffset: 0), ["D", "A", "B", "C"])
        XCTAssertEqual(a.movingItems(fromOffsets: [0], toOffset: 4), ["B", "C", "D", "A"])
        XCTAssertEqual(a.movingItems(fromOffsets: [1], toOffset: 1), a)
        XCTAssertEqual(a.movingItems(fromOffsets: [1], toOffset: 2), a)
        XCTAssertEqual(a.movingItems(fromOffsets: [0, 1], toOffset: 4), ["C", "D", "A", "B"])
    }

    func testPreservesContents() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let count = Int.random(in: 2...30, using: &rng)
            let source = Int.random(in: 0..<count, using: &rng)
            let destination = Int.random(in: 0...count, using: &rng)
            let items = Array(0..<count)
            let moved = items.movingItems(fromOffsets: [source], toOffset: destination)
            XCTAssertEqual(moved.sorted(), items)
            // The moved element lands directly before the old element at `destination`.
            let expectedIndex = destination > source ? destination - 1 : destination
            XCTAssertEqual(moved[expectedIndex], source)
        }
    }
}

final class PlaylistFileTests: XCTestCase {
    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rlp-test-\(UUID()).\(ext)")
    }

    func testRoundTripPreservesPathsAndOrder() throws {
        let paths = ["/Music/b.reason", "/Music/a.rns", #"C:\Windows\Path\c.reason"#, "/with space/ünïcode ♪.reason"]
        let url = tempURL("rlp")
        defer { try? FileManager.default.removeItem(at: url) }
        try PlaylistFileService.save(paths: paths, to: url)
        XCTAssertEqual(try PlaylistFileService.load(from: url), paths)
    }

    func testEmptyPlaylistRoundTrips() throws {
        let url = tempURL("rlp")
        defer { try? FileManager.default.removeItem(at: url) }
        try PlaylistFileService.save(paths: [], to: url)
        XCTAssertEqual(try PlaylistFileService.load(from: url), [])
    }

    func testReadsFileWrittenByDotNetVersion() throws {
        let json = """
        {
          "Version": 1,
          "Songs": [
            "/Users/me/Songs/one.reason",
            "C:\\\\Music\\\\two.rns"
          ]
        }
        """
        let url = tempURL("rlp")
        defer { try? FileManager.default.removeItem(at: url) }
        try json.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try PlaylistFileService.load(from: url), ["/Users/me/Songs/one.reason", #"C:\Music\two.rns"#])
    }

    func testWritesDotNetCompatibleKeys() throws {
        let url = tempURL("rlp")
        defer { try? FileManager.default.removeItem(at: url) }
        try PlaylistFileService.save(paths: ["/a/b.reason"], to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"Version\""))
        XCTAssertTrue(text.contains("\"Songs\""))
        XCTAssertTrue(text.contains("/a/b.reason"))   // slashes are not escaped
    }

    func testCorruptFileThrows() throws {
        let url = tempURL("rlp")
        defer { try? FileManager.default.removeItem(at: url) }
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try PlaylistFileService.load(from: url))
    }
}

final class SettingsStoreTests: XCTestCase {
    private var dir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rlp-settings-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suiteName = "rlp-test-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
    }

    private func store(legacy: URL? = nil) -> SettingsStore {
        SettingsStore(defaults: defaults, legacyURL: legacy)
    }

    private func writeLegacy(_ json: String) throws -> URL {
        let url = dir.appendingPathComponent("legacy.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testDefaultsWhenNothingExists() {
        XCTAssertEqual(store().load(), SettingsData())
        XCTAssertEqual(SettingsData().midiChannel, 1)
        XCTAssertEqual(SettingsData().transitionDelaySec, 5)
        XCTAssertEqual(SettingsData().appearance, .system)
        XCTAssertTrue(SettingsData().showTooltips)
        XCTAssertEqual(SettingsData().toolbarIconSize, .small)
    }

    func testRoundTrip() {
        let s = SettingsData(
            midiDeviceName: "IAC Driver Bus 1", midiChannel: 7, endNoteNumber: 64, transitionDelaySec: 12,
            lastPlaylistPath: "/tmp/set.rlp", loadLastPlaylist: true, alwaysOnTop: true,
            songSpacing: 6, songFontSize: 17.5, appearance: .dark,
            showTooltips: false, toolbarIconSize: .large)
        let store = store()
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testClearingOptionalValuesRemovesThem() {
        let store = store()
        store.save(SettingsData(midiDeviceName: "X", lastPlaylistPath: "/a.rlp"))
        store.save(SettingsData(midiDeviceName: nil, lastPlaylistPath: nil))
        XCTAssertNil(store.load().midiDeviceName)
        XCTAssertNil(store.load().lastPlaylistPath)
    }

    func testImportsOlderDotNetFileWithMissingKeys() throws {
        let legacy = try writeLegacy(
            #"{"MidiDeviceName":"IAC Driver Bus 1","MidiChannel":2,"EndNoteNumber":5,"TransitionDelaySec":3}"#)
        let loaded = store(legacy: legacy).load()
        XCTAssertEqual(loaded.midiDeviceName, "IAC Driver Bus 1")
        XCTAssertEqual(loaded.midiChannel, 2)
        XCTAssertEqual(loaded.endNoteNumber, 5)
        XCTAssertEqual(loaded.transitionDelaySec, 3)
        XCTAssertEqual(loaded.songFontSize, 13)
        XCTAssertEqual(loaded.songSpacing, 0)
        XCTAssertFalse(loaded.alwaysOnTop)
        XCTAssertEqual(loaded.appearance, .system)
    }

    func testImportsFileWrittenByDotNetVersion() throws {
        let legacy = try writeLegacy("""
        {
          "MidiDeviceName": null,
          "MidiChannel": 1,
          "EndNoteNumber": 0,
          "TransitionDelaySec": 5,
          "LastPlaylistPath": "/Users/me/set.rlp",
          "LoadLastPlaylist": true,
          "AlwaysOnTop": false,
          "SongSpacing": 2,
          "SongFontSize": 13,
          "WindowX": 100,
          "WindowY": 80,
          "WindowWidth": 420,
          "WindowHeight": 520
        }
        """)
        let loaded = store(legacy: legacy).load()
        XCTAssertNil(loaded.midiDeviceName)
        XCTAssertEqual(loaded.lastPlaylistPath, "/Users/me/set.rlp")
        XCTAssertTrue(loaded.loadLastPlaylist)
        XCTAssertEqual(loaded.songSpacing, 2)
    }

    func testImportHappensOnlyOnce() throws {
        let legacy = try writeLegacy(#"{"MidiChannel":9}"#)
        let store = store(legacy: legacy)
        XCTAssertEqual(store.load().midiChannel, 9)          // imported
        var changed = store.load()
        changed.midiChannel = 3
        store.save(changed)
        XCTAssertEqual(store.load().midiChannel, 3)          // user's value wins
        try #"{"MidiChannel":12}"#.write(to: legacy, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.load().midiChannel, 3)          // legacy file is not read again
    }

    func testExistingSettingsAreNotOverwrittenByImport() throws {
        let first = store()
        first.save(SettingsData(midiChannel: 4))
        let legacy = try writeLegacy(#"{"MidiChannel":9}"#)
        XCTAssertEqual(store(legacy: legacy).load().midiChannel, 4)
    }

    func testNegativeDelayFallsBackToDefault() {
        let store = store()
        store.save(SettingsData(transitionDelaySec: -4))
        XCTAssertEqual(store.load().transitionDelaySec, 5)
    }

    func testCorruptLegacyFileIsIgnored() throws {
        let legacy = try writeLegacy("{ nope")
        XCTAssertEqual(store(legacy: legacy).load(), SettingsData())
    }

    func testTooltipsStayOnAndIconsSmallForOlderSettings() throws {
        // Settings saved before these options existed must not turn tooltips off.
        defaults.set(3, forKey: "midiChannel")
        let loaded = store().load()
        XCTAssertTrue(loaded.showTooltips)
        XCTAssertEqual(loaded.toolbarIconSize, .small)
        let legacy = try writeLegacy(#"{"MidiChannel":2}"#)
        XCTAssertTrue(SettingsStore(defaults: UserDefaults(suiteName: suiteName + "-b")!, legacyURL: legacy).load().showTooltips)
    }

    func testTooltipAndIconSizeRoundTrip() {
        let store = store()
        var s = SettingsData()
        s.showTooltips = false
        s.toolbarIconSize = .medium
        store.save(s)
        XCTAssertFalse(store.load().showTooltips)
        XCTAssertEqual(store.load().toolbarIconSize, .medium)
    }

    func testUnknownIconSizeFallsBackToSmall() throws {
        defaults.set("huge", forKey: "toolbarIconSize")
        XCTAssertEqual(store().load().toolbarIconSize, .small)
    }

    func testUnknownAppearanceInLegacyFileFallsBackToSystem() throws {
        let legacy = try writeLegacy(#"{"Appearance":"sepia"}"#)
        XCTAssertEqual(store(legacy: legacy).load().appearance, .system)
    }
}

final class ActivityKeeperTests: XCTestCase {
    func testTogglesAndIsIdempotent() {
        let keeper = ActivityKeeper()
        XCTAssertFalse(keeper.isActive)
        keeper.setActive(true)
        keeper.setActive(true)
        XCTAssertTrue(keeper.isActive)
        keeper.setActive(false)
        keeper.setActive(false)
        XCTAssertFalse(keeper.isActive)
    }
}
