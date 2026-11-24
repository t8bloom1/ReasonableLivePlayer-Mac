import SwiftUI

@MainActor
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    ⌘→  Skip to next song
                    ⌘O  Open playlist
                    ⇧⌘O  Add songs
                    ⌘S  Save playlist
                    ⇧⌘S  Save playlist as
                    ⌘Z / ⇧⌘Z  Undo / Redo playlist edits
                    ⌘,  Settings
                    """)

                    section("Playing and pausing", """
                    While playing, double-click a song to close the current one and jump to it. While paused, double-click (or click the arrow) to choose which song plays next. Drag rows to reorder them.
                    """)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 620)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
