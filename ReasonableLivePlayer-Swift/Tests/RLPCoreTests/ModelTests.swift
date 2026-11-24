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

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rlp-settings-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store(legacy: URL? = nil) -> SettingsStore {
        SettingsStore(url: dir.appendingPathComponent("new/settings.json"), legacyURL: legacy)
    }

    func testDefaultsWhenNothingExists() {
        XCTAssertEqual(store().load(), SettingsData(midiDeviceName: nil, midiChannel: 1, endNoteNumber: 0, transitionDelaySec: 5))
    }

    func testRoundTrip() throws {
        let s = SettingsData(
            midiDeviceName: "IAC Driver Bus 1", midiChannel: 7, endNoteNumber: 64, transitionDelaySec: 12,
            lastPlaylistPath: "/tmp/set.rlp", loadLastPlaylist: true, alwaysOnTop: true,
            songSpacing: 6, songFontSize: 17.5,
            windowX: -120, windowY: 40, windowWidth: 420, windowHeight: 520)
        let store = store()
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testReadsOlderFileWithMissingKeys() throws {
        let legacy = dir.appendingPathComponent("legacy.json")
        let json = """
        {"MidiDeviceName":"IAC Driver Bus 1","MidiChannel":2,"EndNoteNumber":5,"TransitionDelaySec":3}
        """
        try json.write(to: legacy, atomically: true, encoding: .utf8)
        let loaded = store(legacy: legacy).load()
        XCTAssertEqual(loaded.midiDeviceName, "IAC Driver Bus 1")
        XCTAssertEqual(loaded.midiChannel, 2)
        XCTAssertEqual(loaded.endNoteNumber, 5)
        XCTAssertEqual(loaded.transitionDelaySec, 3)
        XCTAssertEqual(loaded.songFontSize, 13)
        XCTAssertEqual(loaded.songSpacing, 0)
        XCTAssertFalse(loaded.alwaysOnTop)
        XCTAssertNil(loaded.windowX)
    }

    func testReadsFileWrittenByDotNetVersion() throws {
        let legacy = dir.appendingPathComponent("legacy.json")
        let json = """
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
        """
        try json.write(to: legacy, atomically: true, encoding: .utf8)
        let loaded = store(legacy: legacy).load()
        XCTAssertNil(loaded.midiDeviceName)
        XCTAssertEqual(loaded.lastPlaylistPath, "/Users/me/set.rlp")
        XCTAssertTrue(loaded.loadLastPlaylist)
        XCTAssertEqual(loaded.windowWidth, 420)
    }

    func testNewLocationWinsOverLegacy() throws {
        let legacy = dir.appendingPathComponent("legacy.json")
        try #"{"MidiChannel":9}"#.write(to: legacy, atomically: true, encoding: .utf8)
        let store = store(legacy: legacy)
        XCTAssertEqual(store.load().midiChannel, 9)          // migrated from legacy
        try store.save(SettingsData(midiChannel: 3))
        XCTAssertEqual(store.load().midiChannel, 3)          // new file now takes over
    }

    func testNegativeDelayFallsBackToDefault() throws {
        let store = store()
        try store.save(SettingsData(transitionDelaySec: -4))
        XCTAssertEqual(store.load().transitionDelaySec, 5)
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ nope".write(to: store.url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.load(), SettingsData())
    }
}
