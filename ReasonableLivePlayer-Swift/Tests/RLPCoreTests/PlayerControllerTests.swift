import XCTest
@testable import RLPCore

/// Records open and close calls instead of talking to Reason.
final class FakeReason: ReasonControlling {
    private(set) var events: [String] = []
    func openSong(path: String) async { events.append("open:" + name(path)) }
    func closeSong(path: String) async { events.append("close:" + name(path)) }
    private func name(_ path: String) -> String { (path as NSString).lastPathComponent }
}

/// A sleeper that blocks until released, to hold a transition open mid-delay.
/// Releases every waiter, including cancelled ones (a real sleep returns early when cancelled).
@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waiterCount: Int { waiters.count }
    func wait() async { await withCheckedContinuation { waiters.append($0) } }
    func releaseAll() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class PlayerControllerTests: XCTestCase {
    private let names = ["a.reason", "b.reason", "c.reason"]

    private func make(sleeper: @escaping (Int) async -> Void = { _ in }) -> (PlayerController, FakeReason) {
        let reason = FakeReason()
        let controller = PlayerController(reason: reason, sleeper: sleeper)
        controller.insertSongs(paths: names.map { "/m/" + $0 })
        return (controller, reason)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("condition not reached", file: file, line: line)
    }

    // MARK: Transport

    func testPlayOpensFirstSong() async {
        let (c, r) = make()
        c.play()
        await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason"])
        XCTAssertTrue(c.isPlaying)
        XCTAssertEqual(c.activeIndex, 0)
        XCTAssertEqual(c.statusText, "Playing: a")
    }

    func testTriggerWhilePlayingClosesAndOpensNext() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.handleTrigger(); await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason", "open:b.reason"])
        XCTAssertEqual(c.activeIndex, 1)
        XCTAssertTrue(c.isPlaying)
        XCTAssertEqual(c.statusText, "Ready: b")
    }

    func testTriggerOnLastSongCompletesSet() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.handleTrigger(); await c.waitForTransition()
        c.handleTrigger(); await c.waitForTransition()
        c.handleTrigger(); await c.waitForTransition()
        XCTAssertEqual(r.events.last, "close:c.reason")
        XCTAssertNil(c.activeIndex)
        XCTAssertFalse(c.isPlaying)
        XCTAssertEqual(c.statusText, "Set complete")
    }

    func testTriggerWhilePausedClosesAndMovesPointerWithoutOpening() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.pause()
        c.handleTrigger(); await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason"])
        XCTAssertEqual(c.activeIndex, 1)
        XCTAssertFalse(c.isPlaying)
        XCTAssertEqual(c.statusText, "Next: b")
    }

    func testPlayAfterPausedTriggerOpensTheNextSong() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.pause()
        c.handleTrigger(); await c.waitForTransition()
        c.play(); await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason", "open:b.reason"])
        XCTAssertTrue(c.isPlaying)
    }

    func testSelectWhilePausedKeepsChoiceAfterTrigger() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.pause()
        c.selectSong(id: c.songs[2].id)
        XCTAssertEqual(c.activeIndex, 2)
        XCTAssertEqual(c.statusText, "Next: c")
        c.handleTrigger(); await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason"])
        XCTAssertEqual(c.activeIndex, 2)    // not advanced past the user's choice
    }

    func testPlayAfterSelectClosesTheStillOpenSong() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.pause()
        c.selectSong(id: c.songs[2].id)
        c.play(); await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason", "open:c.reason"])
    }

    func testSelectWhilePlayingJumps() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.selectSong(id: c.songs[2].id); await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason", "open:c.reason"])
        XCTAssertEqual(c.activeIndex, 2)
        XCTAssertTrue(c.isPlaying)
    }

    func testSkipWhilePausedOnlyMovesPointer() async {
        let (c, r) = make()
        c.skip(); await c.waitForTransition()
        XCTAssertEqual(c.activeIndex, 0)
        XCTAssertEqual(c.statusText, "Skipped to: a")
        XCTAssertEqual(r.events, [])
    }

    func testSkipWhilePlayingClosesAndOpensNext() async {
        let (c, r) = make()
        c.play(); await c.waitForTransition()
        c.skip(); await c.waitForTransition()
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason", "open:b.reason"])
        XCTAssertTrue(c.isPlaying)
        XCTAssertEqual(c.statusText, "Ready: b")
    }

    // MARK: Races the .NET version had

    func testTriggerDuringTransitionIsIgnored() async {
        let gate = Gate()
        let (c, r) = make(sleeper: { _ in await gate.wait() })
        c.play(); await c.waitForTransition()

        c.handleTrigger()
        await waitUntil { gate.waiterCount == 1 }   // mid-delay: a.reason is closed, b not yet open
        c.handleTrigger()                           // stale second trigger
        gate.releaseAll()
        await c.waitForTransition()

        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason", "open:b.reason"])
        XCTAssertEqual(c.activeIndex, 1)
    }

    func testSkipDuringTransitionSupersedesItAndNeverClosesTwice() async {
        let gate = Gate()
        let (c, r) = make(sleeper: { _ in await gate.wait() })
        c.play(); await c.waitForTransition()

        c.skip()
        await waitUntil { gate.waiterCount == 1 }
        c.skip()
        await waitUntil { gate.waiterCount == 2 }
        gate.releaseAll()
        await c.waitForTransition()

        // b.reason was never opened. a.reason was closed exactly once.
        XCTAssertEqual(r.events, ["open:a.reason", "close:a.reason", "open:c.reason"])
        XCTAssertEqual(c.activeIndex, 2)
        XCTAssertTrue(c.isPlaying)
    }

    // MARK: Playlist editing

    func testInsertAtPositionKeepsActiveSong() {
        let (c, _) = make()
        c.selectSong(id: c.songs[1].id)
        let activeID = c.activeSongID
        c.insertSongs(paths: ["/m/x.reason", "/m/y.reason"], at: 0)
        XCTAssertEqual(c.songs.map { $0.displayName }, ["x", "y", "a", "b", "c"])
        XCTAssertEqual(c.activeSongID, activeID)
        XCTAssertTrue(c.isDirty)
    }

    func testRemoveBeforeActiveShiftsPointer() {
        let (c, _) = make()
        c.selectSong(id: c.songs[2].id)
        c.removeSong(id: c.songs[0].id)
        XCTAssertEqual(c.songs.count, 2)
        XCTAssertEqual(c.activeIndex, 1)
        XCTAssertEqual(c.songs[1].displayName, "c")
    }

    func testRemoveDecreasesCountAndSongIsGone() {
        let (c, _) = make()
        let removed = c.songs[1]
        c.removeSong(id: removed.id)
        XCTAssertEqual(c.songs.count, 2)
        XCTAssertFalse(c.songs.contains(removed))
    }

    func testMoveKeepsActiveSong() {
        let (c, _) = make()
        c.selectSong(id: c.songs[0].id)
        let activeID = c.activeSongID
        c.moveSongs(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(c.songs.map { $0.displayName }, ["b", "c", "a"])
        XCTAssertEqual(c.activeSongID, activeID)
        XCTAssertEqual(c.activeIndex, 2)
    }

    func testReplaceSongsResetsStateAndClearsDirty() async {
        let (c, _) = make()
        c.play(); await c.waitForTransition()
        c.replaceSongs(paths: ["/m/z.reason"])
        XCTAssertEqual(c.songs.count, 1)
        XCTAssertNil(c.activeIndex)
        XCTAssertFalse(c.isPlaying)
        XCTAssertFalse(c.isDirty)
        XCTAssertEqual(c.statusText, "Loaded 1 songs")
    }
}
