# Reasonable Live Player (native Swift)

A native macOS rewrite of Reasonable Live Player using SwiftUI, AppKit, CoreMIDI and the
Accessibility API. It replaces the Avalonia/.NET app in the parent directory and behaves the
same way: it opens Reason song files in order and advances when a MIDI trigger note arrives.

**Status:** written without access to a Mac. The platform-independent core (models, JSON
files, MIDI byte parsing, and the playlist state machine in `PlayerController`) was compiled
with Swift 5.10 on Linux, and its 44 unit tests pass. The parts that need macOS frameworks
(CoreMIDI, Accessibility, AppKit, SwiftUI) have not been compiled or run. See the
[First build checklist](#first-build-checklist).

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (Swift 5.9). The command line tools alone are not enough for SwiftUI
  apps in most setups; install Xcode.

## Build

```bash
cd ReasonableLivePlayer-Swift

swift build                      # compile
swift test                       # unit tests (RLPCoreTests)
./scripts/build-app.sh           # creates dist/Reasonable Live Player.app
open "dist/Reasonable Live Player.app"
```

Options for `build-app.sh`:

| Variable | Effect |
|---|---|
| `UNIVERSAL=1` | Build for arm64 and x86_64 |
| `CODESIGN_IDENTITY="Developer ID Application: …"` | Sign with a real identity instead of ad-hoc |
| `VERSION=2.0.1` | Version written to Info.plist |

To work in Xcode, use **File > Open…** and choose `Package.swift`. Select the
`ReasonableLivePlayer` scheme and run. When run from Xcode, macOS asks for Accessibility
permission for the Xcode-built binary, not for a `.app` you built with the script.

## Layout

```
Package.swift
Sources/RLPCore/                 no SwiftUI; unit tested
  Models.swift                   Song, PlaylistData, SettingsData, Array.movingItems
  Persistence.swift              .rlp files and settings.json
  MidiParsing.swift              raw MIDI bytes -> messages, note-on matching
  MidiNoteListener.swift         CoreMIDI input
  ReasonBridge.swift             open songs, close via Accessibility, permission check
  PlayerController.swift         playlist + playback state machine
Sources/ReasonableLivePlayer/    SwiftUI app
  RLPApp.swift                   App, menu commands, app delegate (quit confirmation)
  AppModel.swift                 settings, MIDI, permission polling, file panels
  ContentView.swift              toolbar, playlist, drag and drop
  SettingsView.swift, HelpView.swift
  WindowAccessor.swift           access to the NSWindow (always on top, frame saving)
Tests/RLPCoreTests/
Resources/Info.plist, icon.png
scripts/build-app.sh
```

## Compatibility with the .NET version

- **Playlists (`.rlp`)** use the same JSON (`{"Version":1,"Songs":[…]}`). Files open in both.
- **Settings** are read from the old `~/.config/ReasonableLivePlayer/settings.json` the first
  time, and then saved to `~/Library/Application Support/ReasonableLivePlayer/settings.json`.
  The JSON keys are unchanged.
- **Bundle identifier** is still `com.reasonablelive.player`, and the `.rlp` file type is the
  same.
- **Window position and size** are saved with macOS frame autosave, not with the
  `WindowX/Y/Width/Height` settings. Those values are preserved in the file but unused.

## Behavior differences from the .NET version

1. **One transition at a time.** Advance, skip, jump and play each run as a single cancellable
   task. A MIDI trigger that arrives while a transition is running is ignored. Skip or select
   during a transition cancels it and starts the new one. A song is closed at most once. The
   old code could run two overlapping transitions and close the wrong window.
2. **Whole MIDI buffer is parsed.** The old code looked only at the first three bytes of each
   message buffer. Now every message in the buffer is checked, including running status.
3. **Paused, select a song, trigger arrives.** The open song is closed and the pointer stays
   on the song you selected. The old code also moved the pointer one further.
4. **Play after selecting a different song while paused** closes the song that is still open
   first, so Reason does not end up with two documents.
5. **Closing the Reason window** uses the Accessibility API directly (File > Close in
   Reason's menu bar). If that menu item is not found, it runs the same AppleScript as before.
   The scripted path needs a separate "control System Events" permission; the direct path does
   not.
6. **Accessibility status updates live.** The app checks every 2 seconds until permission is
   granted, so the status dot turns green without a restart.
7. **MIDI hot-plug.** The app reconnects when the IAC Driver or a controller comes online and
   notices when it goes away.
8. **Quit confirmation** covers both Cmd-Q and closing the window, and cancelling the save
   panel cancels the quit. The old code continued closing.
9. **Opening a bad playlist** shows an error instead of crashing.
10. **Always on top** from the toolbar is saved immediately.
11. **Finder integration.** Double-clicking an `.rlp` opens it in the running app.
12. Added: keyboard shortcuts (Cmd-O open playlist, Shift-Cmd-O add songs, Cmd-S save,
    Cmd-, settings).

## First build checklist

The macOS-specific code was reviewed by reading, not by compiling. Expect to fix a few compiler
errors or warnings (CoreMIDI's older packet API is deprecated and will warn). Then check these
on a Mac in roughly this order:

1. `swift build` and `swift test`. If a test fails, tell me which; the tests encode the
   behavior listed above.
2. Launch the app. Check the window appears dark, the toolbar is laid out sensibly, and the
   status dot is red or yellow.
3. **Accessibility:** the system prompt appears after about 2 seconds. Grant it. The dot
   should change without restarting.
4. **MIDI device name.** Open Settings and check the IAC Driver bus is listed. If you used the
   .NET version before, check your saved device is preselected. The .NET library may have
   saved a different name format than CoreMIDI's display name; the app matches by display name,
   plain name, and display-name prefix.
5. **MIDI trigger.** Set channel and note to match a Reason External MIDI Instrument. Confirm
   the dot is green and a note-on advances the playlist.
6. **Closing songs.** With Reason open, advance between two songs. The first should close
   through File > Close with no AppleScript prompt. If the menu item is not found by title, the
   AppleScript fallback runs and macOS may ask for System Events access. Tell me if that
   happens: Reason's menu title may differ from "File" or "Close".
7. **Drag and drop:** drag `.reason` files from Finder into the list (also try an empty
   list). Drag rows to reorder. These rely on SwiftUI `List` `onMove` and `onInsert`, which
   can behave differently across macOS versions.
8. **Always on top**, window position restore across launches, and Cmd-Q with an unsaved
   playlist.
9. **Races:** press Skip repeatedly while playing, and send the trigger note twice quickly.
   Each song should open once.

## Signing and the Accessibility permission

macOS ties the permission to the app's code signature. With ad-hoc signing (the script's
default) every rebuild looks like a new app, so you must remove and re-add it in System
Settings > Privacy & Security > Accessibility, as the old README describes. Signing with a
stable Developer ID certificate avoids that. Notarization needs a paid Apple Developer
account.

## License

MIT. See `../LICENSE`.
