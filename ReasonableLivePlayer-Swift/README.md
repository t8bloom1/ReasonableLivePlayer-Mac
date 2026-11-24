# Reasonable Live Player (native Swift)

The source for Reasonable Live Player 2.0: a native macOS app written with SwiftUI, AppKit,
CoreMIDI and the Accessibility API. For what the app does and how to use it, see the
[main README](../README.md). This file is for people building or changing it.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later. The command line tools alone are not enough for SwiftUI apps in most
  setups. It is developed and tested with Xcode 27 on macOS 26.

## Build and test

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
| `VERSION=2.0.1` | Version written to Info.plist (default 2.0.0) |

To work in Xcode, use **File > Open…** and choose `Package.swift`. Select the
`ReasonableLivePlayer` scheme and run. When run from Xcode, macOS asks for Accessibility
permission for the Xcode-built binary, not for a `.app` built with the script.

## Layout

```
Package.swift
Sources/RLPCore/                 no SwiftUI; unit tested
  Models.swift                   Song, PlaylistData, SettingsData, Array.movingItems
  Persistence.swift              .rlp files; settings in UserDefaults
  Diagnostics.swift              os.Logger wrapper, keep-awake (ActivityKeeper)
  MidiParsing.swift              UMP words -> MIDI messages, note-on matching
  MidiNoteListener.swift         CoreMIDI input (UMP event API)
  ReasonBridge.swift             open songs, close via Accessibility, permission check
  PlayerController.swift         playlist, playback state machine, undo, selection
Sources/ReasonableLivePlayer/    SwiftUI app
  RLPApp.swift                   App, menu commands, app delegate (quit confirmation)
  AppModel.swift                 settings, MIDI, permission polling, file panels, window title
  ContentView.swift              toolbar, playlist, drag and drop
  SettingsView.swift             contents of the Settings window (⌘,)
  HelpView.swift                 contents of the Help window
  WindowAccessor.swift           access to the NSWindow (always on top, frame saving)
Tests/RLPCoreTests/
Resources/Info.plist, icon.png
scripts/build-app.sh
scripts/make-icon.py             regenerates Resources/icon.png (needs Pillow)
```

`RLPCore` has no SwiftUI dependency apart from Combine, and its tests do not touch Reason or
MIDI hardware: `PlayerController` talks to a `ReasonControlling` protocol, which the tests
replace with a fake. `MidiNoteListener` and `ReasonBridge` are the only files that need real
CoreMIDI and Accessibility.

## Design notes

- **One transition at a time.** Advance, skip, jump, play and the paused trigger each run as a
  single cancellable task in `PlayerController`. A trigger note that arrives during a
  transition is ignored. A song is claimed before it is closed, so it is never closed twice.
- **MIDI 1.0 over UMP.** The input port asks CoreMIDI for the MIDI 1.0 protocol, so channel
  voice messages arrive as single-word Universal MIDI Packets. `UMPParser` skips every other
  message type using its size from the UMP specification.
- **Closing a song** presses File > Close in Reason's menu bar through the Accessibility API.
  That only works while Reason is the frontmost app, and from macOS 14 a background app cannot
  activate another app with a plain request. `ReasonBridge` sets the Accessibility frontmost
  attribute first, then falls back to `activate()` and to opening the app through
  LaunchServices. If the menu item is not found, it runs the AppleScript used by 1.x.
- **The toolbar is part of the window content**, not a system toolbar, because the system
  toolbar has a fixed height and clips large icons.
- **Settings** are in UserDefaults. The 1.x `settings.json` is imported once.
  `SettingsData` keeps the 1.x JSON key names for that import.
- **Keep-awake.** `ActivityKeeper` holds a power assertion while a set runs, so macOS does not
  sleep or delay timers while Reason is in front.

## Logging

The app logs to the unified log under the subsystem `com.reasonablelive.player`: triggers
received or ignored, songs opened and closed, MIDI connection, and how Reason's window was
closed.

```bash
log stream --predicate 'subsystem == "com.reasonablelive.player"' --level info
```

## Manual test checklist

The unit tests cover the playlist logic, MIDI parsing, file formats and settings. These need
a Mac with Reason:

1. **Accessibility:** the system prompt appears about 2 seconds after launch. Grant it. The
   status dot changes without restarting.
2. **MIDI device:** Settings lists the IAC Driver bus. A device saved by 1.x is preselected.
3. **MIDI trigger:** with channel and note matching a Reason External MIDI Instrument, the dot
   is green and a note-on advances the playlist.
4. **Closing songs:** advance between two songs while Reason, RLP itself and a third app are
   in front. The song closes each time. The log says "Reason brought to the front" when
   Reason was not already in front.
5. **Races:** press Skip repeatedly while playing, and send the trigger note twice quickly.
   Each song opens once.
6. **Playlist editing:** drag files from Finder into the list (also into an empty list), drag
   rows to reorder, remove a song, and undo each.
7. **Selecting songs:** click a song (it highlights), use the arrow keys, press Return, and
   double-click. Check clicking the arrow beside a song while paused only queues it.
8. **Files:** Save, Save As, Open, Open Recent. The title shows the playlist name and the
   close button shows a dot when there are unsaved changes. Cmd-Q with an unsaved playlist
   asks to save.
9. **Windows:** Settings (gear button and ⌘,) opens at a size that shows every section.
   Help opens in its own window. Always on top and window position persist across launches.
10. **Toolbar:** at each icon size the bar grows to fit and nothing is clipped. Tooltips
    appear, and switch off in Settings. Light, Dark and Match System appearance work.
11. **Keep-awake:** while playing, `pmset -g assertions` lists "Reasonable Live Player".
    After pausing and finishing transitions it is gone.

## Signing and the Accessibility permission

macOS ties the permission to the app's code signature. With ad-hoc signing (the script's
default) every rebuild looks like a new app, so you must remove and re-add it in System
Settings > Privacy & Security > Accessibility. Signing with a stable Developer ID certificate
avoids that. Notarization needs a paid Apple Developer account. The Mac App Store is unlikely to
work: as far as we know, the App Sandbox does not allow controlling another app through the
Accessibility API.

## License

MIT. See `../LICENSE`.
