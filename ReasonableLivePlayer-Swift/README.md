# Reasonable Live Player (native Swift)

A native macOS rewrite of Reasonable Live Player using SwiftUI, AppKit, CoreMIDI and the
Accessibility API. It replaces the Avalonia/.NET app in the parent directory and behaves the
same way: it opens Reason song files in order and advances when a MIDI trigger note arrives.

**Status:** written without access to a Mac. The platform-independent core (models, JSON
files, MIDI byte parsing, and the playlist state machine in `PlayerController`) was compiled
with Swift 5.10 on Linux, and its 73 unit tests pass. The parts that need macOS frameworks
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
  Persistence.swift              .rlp files; settings in UserDefaults
  Diagnostics.swift              os.Logger wrapper, keep-awake (ActivityKeeper)
  MidiParsing.swift              UMP words -> MIDI messages, note-on matching
  MidiNoteListener.swift         CoreMIDI input (UMP event API)
  ReasonBridge.swift             open songs, close via Accessibility, permission check
  PlayerController.swift         playlist, playback state machine, undo
Sources/ReasonableLivePlayer/    SwiftUI app
  RLPApp.swift                   App, menu commands, app delegate (quit confirmation)
  AppModel.swift                 settings, MIDI, permission polling, file panels, window title
  ContentView.swift              toolbar, playlist, drag and drop
  SettingsView.swift             contents of the Settings window (⌘,)
  HelpView.swift
  WindowAccessor.swift           access to the NSWindow (always on top, frame saving)
Tests/RLPCoreTests/
Resources/Info.plist, icon.png
scripts/build-app.sh
scripts/make-icon.py             regenerates Resources/icon.png (needs Pillow)
```

## Compatibility with the .NET version

- **Playlists (`.rlp`)** use the same JSON (`{"Version":1,"Songs":[…]}`). Files open in both.
- **Settings** now live in UserDefaults (`~/Library/Preferences/com.reasonablelive.player.plist`).
  On first run with no saved settings, the .NET version's
  `~/.config/ReasonableLivePlayer/settings.json` is imported once. After that, the two apps no
  longer share settings.
- **Bundle identifier** is still `com.reasonablelive.player`, and the `.rlp` file type is the
  same.
- **Window position and size** are saved by macOS frame autosave. The old
  `WindowX/Y/Width/Height` values are not imported.

## Behavior differences from the .NET version

1. **One transition at a time.** Advance, skip, jump and play each run as a single cancellable
   task. A MIDI trigger that arrives while a transition is running is ignored. Skip or select
   during a transition cancels it and starts the new one. A song is closed at most once. The
   old code could run two overlapping transitions and close the wrong window.
2. **Current CoreMIDI API.** Input uses `MIDIInputPortCreateWithProtocol` and Universal MIDI
   Packets, requested in MIDI 1.0 form (CoreMIDI translates MIDI 2.0 devices), instead of the
   deprecated packet-list API. Every message in an event is checked. The old code looked only
   at the first three bytes of each buffer.
3. **Paused, select a song, trigger arrives.** The open song is closed and the pointer stays
   on the song you selected. The old code also moved the pointer one further.
4. **Double-click a song while paused** selects it and starts playing it. Clicking the arrow
   beside a song while paused still only queues it as the next song. Playing a song while a
   different one is still open closes the open one first, waits the transition delay, then
   opens the new one, so Reason does not end up with two documents.
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
12. **Keeps the Mac awake during a set.** While playing, or while a transition is running, the
    app holds a power assertion that blocks idle sleep and App Nap and keeps the display on. Without it,
    macOS can delay the app's timers while Reason is in front.
13. **Standard Settings window** (⌘,) replaces the settings dialog. Changes apply immediately.
    The values are set with steppers and pickers, so there is no validation dialog. The window
    opens at the height of its contents, so nothing needs scrolling, and its width can be
    dragged wider.
14. **Undo and Redo** for adding, removing, reordering and opening playlists (up to 50 steps).
15. **Open Recent**, **Save** and **Save As**. The unsaved-changes dot shows in the close button.
    The window title (the playlist name) is hidden so it does not take up toolbar width, but it
    still appears in the Window menu and Mission Control.
16. **Playback menu** with Play/Pause (⌘↩) and Skip (⌘→). Modifier shortcuts are used on purpose
    so a stray key press cannot start or skip a song during a show.
17. **System look.** System colors replace the fixed dark theme. The toolbar is part of the window
    content, not a system toolbar, so it can grow with the icon size (the system toolbar has a fixed
    height and clips large icons). Appearance
    can be set to Match System, Light or Dark in Settings.
18. **New app icon** (rounded macOS-style shape), standard About panel, VoiceOver labels on the
    icon-only buttons, and logging to the unified log (see below).

19. **Toolbar settings.** Settings has a Toolbar section with an icon size (Small, Medium, Large, Extra Large;
    Medium is the default) and a switch for tooltips (on by default). The tooltip switch
    also covers the buttons in the playlist rows.
20. **Help opens in its own resizable window**, like Settings, instead of a fixed sheet over the
    playlist.
21. **Selecting songs.** Clicking a song highlights it. The up and down arrow keys move the highlight
    and scroll the list, and Return (or keypad Enter) plays the highlighted song. Double-click still
    plays a song, and clicking the arrow beside a song also highlights it. Like the Play button,
    these do nothing until Accessibility permission is granted.

Other shortcuts: ⌘O open playlist, ⇧⌘O add songs, ⌘S save, ⇧⌘S save as, ⌘Z / ⇧⌘Z undo and redo.

## Logging

The app logs to the unified log under the subsystem `com.reasonablelive.player`: triggers
received or ignored, songs opened and closed, MIDI connection, how Reason's window was closed.

```bash
log stream --predicate 'subsystem == "com.reasonablelive.player"' --level info
```

## First build checklist

The macOS-specific code was reviewed by reading, not by compiling. Expect to fix a few compiler
errors or warnings (`NSRunningApplication.activate(options:)` is deprecated on macOS 14 and
will warn). Then check these on a Mac in roughly this order:

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
   the dot is green and a note-on advances the playlist. This is the first run of the UMP
   event-list code (`MidiNoteListener.packetWords`); if the trigger never fires, start there.
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
10. **Settings window:** the gear button and ⌘, should both open it, at a size that shows every
    section without scrolling. On macOS 13 the button
    sends `showSettingsWindow:`; on 14 and later it is a `SettingsLink`. Check which one you
    have works.
11. **Toolbar:** at each icon size (Small to Extra Large) check the bar grows to fit the icons and the
    window does not clip any button. Check dragging the window narrower at each size.
12. **Keep-awake:** while playing, `pmset -g assertions` should list "Reasonable Live Player"
    with a PreventUserIdleDisplaySleep or similar entry. After pausing it should be gone.
13. **Undo:** remove a song, press ⌘Z. Check the Edit menu names the action.
14. **Document features:** save a playlist, edit it, and check the dot in the close button.
    Check File > Open Recent lists it, and that ⌘S saves without asking again.
15. **Help window:** the ? button and Help > Reasonable Live Player Help open a separate window
    that can be resized and moved. It should not open by itself at launch.
16. **Toolbar tooltips and sizes:** hover over each toolbar button and check the tooltip. Switch
    tooltips off, then Medium and Large icons, in Settings.
17. **Appearance:** try Match System, Light and Dark in Settings.
18. **Selecting songs:** click a song (it should highlight), press the up and down arrow keys
    (the highlight moves and the list scrolls), then press Return (it should play). Note whether
    the first click on an inactive window selects the row or only activates the window.

## Signing and the Accessibility permission

macOS ties the permission to the app's code signature. With ad-hoc signing (the script's
default) every rebuild looks like a new app, so you must remove and re-add it in System
Settings > Privacy & Security > Accessibility, as the old README describes. Signing with a
stable Developer ID certificate avoids that. Notarization needs a paid Apple Developer
account.

## License

MIT. See `../LICENSE`.
