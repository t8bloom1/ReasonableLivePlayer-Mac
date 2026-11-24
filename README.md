# Reasonable Live Player for macOS

Reasonable Live Player (RLP) automates live set playback in [Reason](https://www.reasonstudios.com/). It opens Reason song files in sequence and advances to the next song when a MIDI trigger note is received, so transitions between songs are hands-free.

**Version 2.0 is a native macOS app** written in Swift with SwiftUI and CoreMIDI. It replaces the Avalonia/.NET app (1.x) that this repository previously contained. See the [changelog](CHANGELOG.md) for what changed.

> Looking for the Windows version? See [ReasonableLivePlayer](https://github.com/t8bloom1/ReasonableLivePlayer).

## Features

- Build and save playlists of `.reason` / `.rns` song files (`.rlp` playlist files)
- Drag files from Finder into the playlist, and drag rows to reorder them
- Advance to the next song automatically when a MIDI trigger note arrives
- Play, pause and skip at any time, and pick any song to play with a click, the arrow keys and Return, or a double-click
- Queue the next song while paused
- Configurable MIDI device, channel, trigger note and transition delay
- Undo and redo for playlist edits, Open Recent, and a window title that shows the playlist name
- Always-on-top mode for live use, and the Mac stays awake while a set is running
- Toolbar icon sizes from Small to Extra Large, optional tooltips, and Light, Dark or system appearance
- Built-in Help window, Settings window (⌘,), and standard menus and keyboard shortcuts

## System Requirements

| Requirement | Details |
|---|---|
| **Operating System** | macOS 14 (Sonoma) or later |
| **Reason** | Reason 13 or later installed |
| **Virtual MIDI Driver** | macOS IAC Driver (built in), see below |
| **Accessibility Permission** | Required. RLP uses the Accessibility API to close Reason song windows |

### Why Accessibility permission?

RLP closes the current Reason song before opening the next one. It does this by bringing Reason to the front and choosing **File → Close** from Reason's menu bar, which needs Accessibility permission. macOS prompts for it shortly after launch.

### Virtual MIDI setup (IAC Driver)

macOS includes a built-in virtual MIDI driver, so no third-party software is needed:

1. Open **Audio MIDI Setup** (in `/Applications/Utilities/`).
2. From the menu bar, choose **Window → Show MIDI Studio**.
3. Double-click **IAC Driver**.
4. Check **Device is online**.
5. Click **Apply**, then close.

The IAC Driver now appears as a MIDI device in both Reason and RLP.

## Installation

1. Download the app from the [Releases](https://github.com/t8bloom1/ReasonableLivePlayer-Mac/releases) page and move it to `/Applications` or wherever you prefer.
2. The app is not notarized, so macOS blocks it on first launch. Open **System Settings → Privacy & Security**, scroll to the message about Reasonable Live Player, and click **Open Anyway**. (On macOS 14 you can also right-click the app and choose **Open**.)
3. Grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility).

### Upgrading from a previous version

Builds that are not signed with a Developer ID certificate (including the ad-hoc signing the build script uses by default) look like a different app to macOS each time. After replacing RLP, **remove and re-add** the Accessibility permission, even though the app name is the same:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Select the old **Reasonable Live Player** entry and click the **−** button to remove it.
3. Click **+**, choose the new `.app`, and add it.
4. Make sure the toggle is on.

Without this step, the status dot stays yellow or red and RLP cannot close Reason song windows.

Version 2.0 reads your 1.x playlists unchanged and imports your 1.x settings once on first launch.

## Quick Start

1. Open RLP and click **＋** (or drag `.reason` files from Finder) to build your playlist.
2. Open **Settings** (⚙ or ⌘,) and choose your virtual MIDI device (for example "IAC Driver"), channel and trigger note.
3. The status dot turns **green** when MIDI is connected and Accessibility permission is granted.
4. Press **▶** to start. RLP opens the first song in Reason.
5. When Reason plays the trigger note, RLP closes the current song and opens the next one.

## Setting Up Reason Songs

Each song in your set needs a trigger note so it can tell RLP when to advance. Reason's **External MIDI Instrument** device sends it.

1. **Create an External MIDI Instrument device.** In Reason's rack, right-click and choose *Create > Players > External MIDI Instrument*.
2. **Configure its MIDI output.** Set the MIDI Output to your virtual MIDI device (for example "IAC Driver") and the channel to match RLP Settings (default: channel 1).
3. **Add a trigger note in the sequencer.** At the point where you want RLP to advance (typically the very end), draw a single note matching the trigger note number in RLP Settings (default: C0 / note 0).
4. **Test it.** Start RLP with at least two songs and press ▶. When the song reaches the trigger note, RLP should close it and open the next.

## Controls

| Control | Action |
|---|---|
| ▶ / ⏸ (⌘↩) | Play or pause the playlist |
| ⏭ (⌘→) | Skip to the next song |
| ＋ (⇧⌘O) | Add `.reason` / `.rns` files |
| Open (⌘O) | Open a saved playlist. File > Open Recent lists recent ones |
| Save (⌘S) | Save the playlist (⇧⌘S for Save As) |
| ⚙ (⌘,) | Settings |
| ? | Help |
| 📌 | Keep RLP above other windows |
| Click a song | Highlight it. Use ↑ ↓ to move and Return to play it |
| Double-click a song | Play it |
| Arrow beside a song | Make it the next song without starting it |
| ⌘Z / ⇧⌘Z | Undo / redo playlist edits |

## Building from Source

You need macOS 14 or later and Xcode 15 or later.

```bash
git clone https://github.com/t8bloom1/ReasonableLivePlayer-Mac.git
cd ReasonableLivePlayer-Mac/ReasonableLivePlayer-Swift

swift test                       # unit tests
./scripts/build-app.sh           # creates dist/Reasonable Live Player.app
```

See [ReasonableLivePlayer-Swift/README.md](ReasonableLivePlayer-Swift/README.md) for the project layout, signing, logging and the manual test checklist.

### The 1.x .NET app

The previous Avalonia/.NET version (1.3.0) is still in this repository, in `ReasonableLivePlayer/` and `ReasonableLivePlayer.Tests/`, with `build-mac.sh` to build it. It is no longer maintained. Building it requires the [.NET 8 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0).

## Differences from the Windows Version

| | Windows | macOS |
|---|---|---|
| UI Framework | WPF | SwiftUI |
| MIDI | winmm.dll (P/Invoke) | CoreMIDI |
| Virtual MIDI | LoopBe1 (third-party) | IAC Driver (built in) |
| Window Management | Win32 API | Accessibility API |
| Song Close | `SendMessage` / `PostMessage` | File → Close through the Accessibility API |
| Accessibility permission | Not required | Required |

## License

This project is licensed under the [MIT License](LICENSE).
