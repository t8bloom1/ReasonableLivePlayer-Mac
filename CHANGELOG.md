# Changelog

## 2.0.0 - 2026-11-24

Reasonable Live Player is now a native macOS app written in Swift (SwiftUI, AppKit, CoreMIDI and the Accessibility API). It replaces the Avalonia/.NET app. It needs macOS 14 or later.

### Compatibility

- Playlists (`.rlp`) are unchanged. Files open in both 1.x and 2.0.
- Settings are stored in the standard macOS preferences. The 1.x `settings.json` is imported once on first launch. After that the two versions no longer share settings.
- The bundle identifier (`com.reasonablelive.player`) is unchanged. Because release builds are ad-hoc signed, macOS treats a new build as a new app, so re-add the Accessibility permission after upgrading.

### Added

- Settings window (⌘,) that applies changes immediately, and a separate resizable Help window.
- Click a song to highlight it, move with the up and down arrow keys, and press Return to play it. Double-click plays a song, including while paused.
- Undo and Redo for adding, removing, reordering and opening playlists.
- File > Open Recent, Save and Save As, a window title showing the playlist name, and an unsaved-changes indicator.
- Playback menu with Play/Pause (⌘↩) and Skip (⌘→).
- Toolbar icon sizes (Small, Medium, Large, Extra Large) with a toolbar that grows to fit, and a setting to turn tooltips on or off.
- Light, Dark or Match System appearance.
- The Mac stays awake, and macOS App Nap is blocked, while a set is running.
- Reconnects automatically when a MIDI device or the IAC Driver comes back, and shows Accessibility status live.
- New app icon, standard About panel, VoiceOver labels, and logging to the macOS unified log (subsystem `com.reasonablelive.player`).

### Changed

- MIDI input uses the current CoreMIDI event API (Universal MIDI Packets) and checks every message in a packet. Version 1.x looked only at the first message.
- Closing a song brings Reason to the front first, then chooses File > Close through the Accessibility API. Version 1.x ran an AppleScript through System Events.
- Advance, skip, jump and play now run as one transition at a time. A trigger note that arrives during a transition is ignored, and a song is never closed twice. Version 1.x could run two overlapping transitions.
- While paused, selecting a song and then receiving a trigger note keeps your selection instead of moving one song further.
- Playing a song while a different one is still open closes the open one first, waits the transition delay, then opens the new one.
- Quitting or closing the window with an unsaved playlist asks to save, and cancelling the save cancels the quit.
- A playlist file that cannot be read shows an error instead of crashing.
- Window position and size are saved by macOS.

## 1.2.0

Last release of the Avalonia/.NET version. Configurable song spacing and font size, auto-scroll, tri-color status indicator, play/pause improvements, and remembered window position and size. Its source remains in `ReasonableLivePlayer/`.
