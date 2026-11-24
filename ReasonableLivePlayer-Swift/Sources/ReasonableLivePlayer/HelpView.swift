import SwiftUI

enum HelpWindow {
    static let id = "help"
}

/// Contents of the Help window. It opens as its own resizable window, like Settings.
@MainActor
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reasonable Live Player").font(.title2).bold()

                section("Overview",
                        "RLP automates live set playback in Reason. It opens songs in sequence and advances to the next when a MIDI trigger note is received.")

                section("RLP Setup", """
                1. Click + (or choose File > Add Songs) or drag .reason / .rns files into the playlist.
                2. Open Settings (⌘,) and select your MIDI input device, channel, and trigger note number.
                3. The status dot turns green when MIDI is connected and Accessibility is granted.
                4. Press Play. RLP opens the first song in Reason.
                5. When the trigger note is received, RLP closes the current song and opens the next.
                """)

                section("macOS: Creating an Internal MIDI Port", """
                RLP listens for a MIDI note to advance songs. If you don't have an external MIDI controller, you can create a virtual MIDI port using macOS Audio MIDI Setup:

                1. Open Audio MIDI Setup (Applications → Utilities, or search Spotlight).
                2. From the menu bar, choose Window → Show MIDI Studio.
                3. Double-click the IAC Driver icon.
                4. Check 'Device is online'.
                5. Optionally add a bus (e.g. 'RLP Trigger') using the + button.
                6. Click Apply, then close.
                7. In RLP Settings, select the IAC Driver bus as the MIDI device.
                8. Any app that sends MIDI to the IAC bus (e.g. Reason, a foot controller app) will trigger RLP.
                """)

                section("macOS: Accessibility Permission", """
                RLP needs Accessibility permission to close Reason song windows (it chooses File → Close in Reason). Without it, RLP cannot advance between songs.

                To grant permission:

                1. Open System Settings → Privacy & Security → Accessibility.
                2. Click + and add Reasonable Live Player, or switch it on if it is already listed.

                The status dot and the Settings window show the current state, and update once permission is granted.
                """)

                section("Keyboard shortcuts", """
                ⌘↩  Play / Pause
                ↑ ↓  Choose a song in the playlist
                Return  Play the chosen song
                ⌘→  Skip to next song
                ⌘O  Open playlist
                ⇧⌘O  Add songs
                ⌘S  Save playlist
                ⇧⌘S  Save playlist as
                ⌘Z / ⇧⌘Z  Undo / Redo playlist edits
                ⌘,  Settings
                """)

                section("Playing and pausing", """
                Click a song to highlight it, use the up and down arrow keys to move through the list, and press Return to play the highlighted song. You can also double-click a song to play it. While playing, the current song is closed and the one you chose opens. While paused, the chosen song opens and playback resumes. To choose the next song without starting it, click the arrow beside it while paused. Drag rows to reorder them.
                """)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 420, idealWidth: 520, maxWidth: .infinity,
               minHeight: 320, idealHeight: 680, maxHeight: .infinity)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
