import SwiftUI

enum HelpWindow {
    static let id = "help"
}

/// Contents of the Help window. It opens as its own resizable window, like Settings.
@MainActor
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reasonable Live Player").font(.title2).bold()

                section("Overview", """
                RLP automates live set playback in Reason. It opens your songs in order and, when Reason plays a MIDI trigger note at the end of a song, closes that song and opens the next one.
                """)

                section("Getting started", """
                1. Add songs: click +, choose File > Add Songs, or drag .reason and .rns files from Finder into the playlist.
                2. Open Settings (⌘,) and choose your MIDI device, channel and trigger note.
                3. Check the status dot in the toolbar. Green means MIDI is connected and Accessibility permission is granted. Yellow means one of the two is missing. Red means both are.
                4. Press Play. RLP opens the first song in Reason.
                5. When Reason sends the trigger note, RLP closes the current song, waits the transition delay, and opens the next one. After the last song the status line says "Set complete".
                """)

                section("Playing and pausing", """
                Play opens the queued song, the one marked with the arrow (or the first song if none is marked), and starts the set. Pause does not stop Reason. It only tells RLP not to open the next song automatically.

                While paused, a trigger note still closes the song that finished and moves the "next" marker (the arrow beside a song) to the following song, without opening it. Press Play to open it.

                Skip while playing closes the current song and opens the next one. Skip while paused moves the marker to the next song without opening anything.
                """)

                section("Choosing songs", """
                Click a song to highlight it. Use the up and down arrow keys to move through the list, and press Return to play the highlighted song. You can also double-click a song to play it.

                Playing a song while another is playing closes the current one, waits the transition delay, and opens the one you chose. Playing a song while paused opens it and resumes playback.

                To pick the next song without starting it, click the arrow beside a song while paused. Drag rows to reorder them, and click the ✕ beside a song to remove it.
                """)

                section("Playlists", """
                A playlist is saved as an .rlp file. Use File > Open Playlist (⌘O), Open Recent, Save Playlist (⌘S) and Save Playlist As (⇧⌘S). The window title shows the playlist name, and a dot in the close button means there are unsaved changes.

                Undo (⌘Z) and Redo (⇧⌘Z) cover adding, removing, reordering and opening playlists.
                """)

                section("Keyboard shortcuts", """
                ⌘↩  Play / Pause
                ⌘→  Skip to next song
                ↑ ↓  Move the highlight through the playlist
                Return  Play the highlighted song
                ⌘O  Open playlist
                ⇧⌘O  Add songs
                ⌘S  Save playlist
                ⇧⌘S  Save playlist as
                ⌘Z / ⇧⌘Z  Undo / Redo playlist edits
                ⌘,  Settings
                """)

                section("Settings", """
                MIDI: the input device, channel (1-16) and trigger note (0-127).
                Playback: the transition delay, from 0 to 99 seconds, between closing one song and opening the next.
                Playlist: spacing between songs and font size.
                Toolbar: icon size (Small, Medium, Large, Extra Large) and whether tooltips are shown.
                General: load the last playlist at startup, keep the window on top of other windows, and Light, Dark or Match System appearance.

                Changes apply immediately. The pin button in the toolbar also turns Always on Top on and off.
                """)

                section("Setting up Reason songs", """
                Each song needs a trigger note so it can tell RLP when to advance. Reason's External MIDI Instrument device sends it.

                1. In Reason's rack, choose Create > Players > External MIDI Instrument.
                2. Set its MIDI output to the same device you chose in RLP (for example IAC Driver) and its channel to match RLP's channel.
                3. In the sequencer, draw a single note at the point where RLP should advance, usually the very end. Its note number must match RLP's trigger note (the default is note 0, C0).
                4. Test with at least two songs. When the first reaches the note, RLP should close it and open the next.
                """)

                section("macOS: creating an internal MIDI port", """
                If you don't have an external MIDI controller, create a virtual port with the macOS IAC Driver:

                1. Open Audio MIDI Setup (Applications → Utilities).
                2. Choose Window → Show MIDI Studio.
                3. Double-click the IAC Driver icon.
                4. Check "Device is online".
                5. Optionally add a bus (for example "RLP Trigger") with the + button.
                6. Click Apply, then close.
                7. Choose the IAC Driver bus as the MIDI device in RLP Settings.

                Anything that sends MIDI to that bus, such as Reason, will trigger RLP.
                """)

                section("macOS: Accessibility permission", """
                RLP needs Accessibility permission to close Reason's song windows. It brings Reason to the front and chooses File → Close. Without the permission, the Play button is disabled and RLP cannot advance between songs.

                1. Open System Settings → Privacy & Security → Accessibility.
                2. Click + and add Reasonable Live Player, or switch it on if it is already listed.

                The status dot and the Settings window update when permission is granted. If you replace the app with a new version and the status stays red or yellow, remove the old Reasonable Live Player entry with the − button, then add the new app again.
                """)

                section("Troubleshooting", """
                The song does not close: check that Accessibility permission is granted (see above), and that the song is open in Reason.
                MIDI says "not connected": make sure the IAC Driver is online in Audio MIDI Setup and that the device is selected in Settings. RLP reconnects by itself when the device comes back.
                The trigger does nothing: check that the channel and note in Reason match the ones in Settings.
                The Play button is disabled: the playlist is empty or Accessibility permission has not been granted.

                RLP writes a log you can read in Console.app. Search for "com.reasonablelive.player".
                """)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 420, idealWidth: 540, maxWidth: .infinity,
               minHeight: 320, idealHeight: 700, maxHeight: .infinity)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
