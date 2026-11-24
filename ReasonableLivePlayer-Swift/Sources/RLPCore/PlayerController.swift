import Combine
import Foundation

/// Asks the view to scroll a song into view. `serial` makes repeated requests for the
/// same song distinct so the view's change observer fires each time.
public struct ScrollRequest: Equatable {
    public let songID: UUID
    public let serial: Int
}

/// The playlist and its playback state machine.
///
/// Behavior matches the .NET version, with one structural change: every transition that
/// involves closing and opening songs (advance, skip, jump, play, paused trigger) runs as a
/// single cancellable task. Only one can be in flight. That removes the races the old
/// `async void` code had:
///
/// * A MIDI trigger that arrives while a transition is running is ignored. Before, it ran a
///   second close/advance and could skip a song or close an unrelated Reason window.
/// * Skip or select while a transition is running cancels it and starts the new one.
/// * The controller records which song it opened and claims it before closing it, so the
///   same song is never closed twice.
///
/// "Active" means the song the pointer is on: the one that is open (playing), or, while
/// paused, the one that will open next.
@MainActor
public final class PlayerController: ObservableObject {
    // MARK: Published state

    @Published public private(set) var songs: [Song] = []
    /// Index of the active song, or nil when nothing is active.
    @Published public private(set) var activeIndex: Int? = nil
    /// True while the playlist is running (shown as the pause button).
    @Published public private(set) var isPlaying = false
    @Published public private(set) var statusText = "Ready"
    /// True when the playlist has changed since it was last saved or loaded.
    @Published public private(set) var isDirty = false
    @Published public private(set) var scrollRequest: ScrollRequest? = nil

    /// Seconds between closing one song and opening the next. Set from settings.
    public var transitionDelaySec = SettingsData.defaultTransitionDelaySec

    // MARK: Private state

    private let reason: ReasonControlling
    private let sleeper: (Int) async -> Void

    /// The song this controller opened and has not yet closed.
    private var openSong: Song?
    private var transitionTask: Task<Void, Never>?
    private var transitionToken = 0
    /// When a transition ends, switch to the playing state. Set by play, skip and jump.
    private var resumeAfterTransition = false
    private var scrollSerial = 0

    public init(reason: ReasonControlling, sleeper: @escaping (Int) async -> Void = PlayerController.defaultSleep) {
        self.reason = reason
        self.sleeper = sleeper
    }

    nonisolated public static func defaultSleep(_ seconds: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds)) * 1_000_000_000)
    }

    // MARK: Derived

    public var paths: [String] { songs.map { $0.path } }

    public var activeSongID: UUID? {
        guard let index = activeIndex, songs.indices.contains(index) else { return nil }
        return songs[index].id
    }

    private var isTransitioning: Bool { transitionTask != nil }
    /// Playing, or about to resume playing after a transition.
    private var inPlayMode: Bool { isPlaying || resumeAfterTransition }

    /// Resolves when the current transition (if any) has finished. For tests.
    public func waitForTransition() async {
        await transitionTask?.value
    }

    public func setStatus(_ text: String) { statusText = text }

    // MARK: Playlist editing

    /// Inserts songs at `index` (default: end).
    public func insertSongs(paths: [String], at index: Int? = nil) {
        guard !paths.isEmpty else { return }
        let new = paths.map { Song(path: $0) }
        let at = max(0, min(index ?? songs.count, songs.count))
        songs.insert(contentsOf: new, at: at)
        if let active = activeIndex, at <= active { activeIndex = active + new.count }
        isDirty = true
    }

    public func removeSong(id: Song.ID) {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        songs.remove(at: index)
        if let active = activeIndex {
            if index < active {
                activeIndex = active - 1
            } else if index == active, active >= songs.count {
                activeIndex = nil
            }
        }
        if songs.isEmpty {
            cancelTransition()
            isPlaying = false
            activeIndex = nil
        }
        isDirty = true
    }

    /// Reorders songs. The active song stays active wherever it ends up.
    public func moveSongs(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let activeID = activeSongID
        songs = songs.movingItems(fromOffsets: offsets, toOffset: destination)
        if let activeID { activeIndex = songs.firstIndex { $0.id == activeID } }
        isDirty = true
    }

    /// Replaces the playlist, for opening a saved playlist. Resets playback state.
    public func replaceSongs(paths: [String]) {
        cancelTransition()
        songs = paths.map { Song(path: $0) }
        activeIndex = nil
        isPlaying = false
        statusText = "Loaded \(songs.count) songs"
        isDirty = false
    }

    public func markClean() { isDirty = false }

    // MARK: Transport

    public func play() {
        guard !songs.isEmpty else { return }
        if isTransitioning {
            // Something is already opening or closing. Resume when it finishes.
            resumeAfterTransition = true
            return
        }
        var index = activeIndex ?? 0
        if !songs.indices.contains(index) { index = 0 }
        setActive(index)
        let song = songs[index]
        statusText = "Opening: \(song.displayName)"
        resumeAfterTransition = true
        beginTransition { [self] in
            // If another song is still open (the user selected a different one while paused),
            // close it first so Reason does not end up with two documents.
            if let opened = openSong, opened.id != song.id { await closeOpenSong() }
            if Task.isCancelled { return }
            await open(song)
            if Task.isCancelled { return }
            statusText = "Playing: \(song.displayName)"
        }
    }

    public func pause() {
        isPlaying = false
        resumeAfterTransition = false
        statusText = "Paused"
    }

    public func skip() {
        guard !songs.isEmpty else { return }
        let wasPlaying = inPlayMode
        isPlaying = false
        resumeAfterTransition = wasPlaying
        beginTransition { [self] in
            if wasPlaying {
                await closeOpenSong()
                if Task.isCancelled { return }
            }
            let next = (activeIndex ?? -1) + 1
            guard next < songs.count else { completeSet(); return }
            setActive(next)
            let song = songs[next]
            if wasPlaying {
                statusText = "Opening: \(song.displayName)"
                await sleeper(transitionDelaySec)
                if Task.isCancelled { return }
                await open(song)
                if Task.isCancelled { return }
                statusText = "Ready: \(song.displayName)"
            } else {
                statusText = "Skipped to: \(song.displayName)"
            }
        }
    }

    /// Single or double click on a song. While playing: close the current song and jump to
    /// it. While paused: make it the next song to play.
    public func selectSong(id: Song.ID) {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        if inPlayMode {
            resumeAfterTransition = true
            beginTransition { [self] in
                await closeOpenSong()
                if Task.isCancelled { return }
                guard let target = songs.firstIndex(where: { $0.id == id }) else { return }
                setActive(target)
                let song = songs[target]
                statusText = "Opening: \(song.displayName)"
                await sleeper(transitionDelaySec)
                if Task.isCancelled { return }
                await open(song)
                if Task.isCancelled { return }
                statusText = "Playing: \(song.displayName)"
            }
        } else {
            cancelTransition()
            setActive(index)
            statusText = "Next: \(songs[index].displayName)"
        }
    }

    /// Called when the MIDI trigger note arrives.
    public func handleTrigger() {
        // The trigger comes from the song that is open. While a transition runs, the old
        // song is already closed, so a second trigger is stale. Ignore it.
        if isTransitioning { return }

        if isPlaying {
            beginTransition { [self] in await advanceToNext() }
        } else if let index = activeIndex, songs.indices.contains(index) {
            beginTransition { [self] in await handlePausedTrigger() }
        }
    }

    // MARK: Transitions

    private func advanceToNext() async {
        await closeOpenSong()
        if Task.isCancelled { return }
        let next = (activeIndex ?? -1) + 1
        guard next < songs.count else { completeSet(); return }
        setActive(next)
        let song = songs[next]
        statusText = "Opening: \(song.displayName)"
        await sleeper(transitionDelaySec)
        if Task.isCancelled { return }
        await open(song)
        if Task.isCancelled { return }
        statusText = "Ready: \(song.displayName)"
    }

    /// Trigger received while paused: close the song that just finished and move the
    /// pointer to the next one without opening it.
    private func handlePausedTrigger() async {
        let pointerID = activeSongID
        let openedID = openSong?.id

        if let opened = openSong {
            openSong = nil
            await reason.closeSong(path: opened.path)
        } else if let index = activeIndex, songs.indices.contains(index) {
            // We did not open anything (the user opened the song by hand). Same as the
            // original: close Reason's front document.
            await reason.closeSong(path: songs[index].path)
        }
        if Task.isCancelled { return }

        // The user picked a different "next" song while paused. Keep their choice.
        if let openedID, let pointerID, openedID != pointerID {
            if let index = activeIndex, songs.indices.contains(index) {
                statusText = "Next: \(songs[index].displayName)"
            }
            return
        }

        let next = (activeIndex ?? -1) + 1
        if next < songs.count {
            setActive(next)
            statusText = "Next: \(songs[next].displayName)"
        } else {
            completeSet()
        }
    }

    private func completeSet() {
        activeIndex = nil
        isPlaying = false
        resumeAfterTransition = false
        statusText = "Set complete"
    }

    // MARK: Helpers

    private func open(_ song: Song) async {
        openSong = song           // claim before awaiting so a later close sees it
        await reason.openSong(path: song.path)
    }

    private func closeOpenSong() async {
        guard let song = openSong else { return }
        openSong = nil            // claim before awaiting so it is closed only once
        await reason.closeSong(path: song.path)
    }

    private func setActive(_ index: Int) {
        guard songs.indices.contains(index) else { return }
        activeIndex = index
        // Scroll to the next song so the upcoming song is visible, or the song itself if last.
        let target = index < songs.count - 1 ? index + 1 : index
        scrollSerial += 1
        scrollRequest = ScrollRequest(songID: songs[target].id, serial: scrollSerial)
    }

    private func beginTransition(_ work: @escaping @MainActor () async -> Void) {
        transitionTask?.cancel()
        transitionToken += 1
        let token = transitionToken
        transitionTask = Task { @MainActor [weak self] in
            if !Task.isCancelled { await work() }
            self?.endTransition(token)
        }
    }

    private func endTransition(_ token: Int) {
        guard token == transitionToken else { return }   // superseded by a newer transition
        transitionTask = nil
        if resumeAfterTransition {
            resumeAfterTransition = false
            if openSong != nil { isPlaying = true }
        }
    }

    private func cancelTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        transitionToken += 1
        resumeAfterTransition = false
    }
}
