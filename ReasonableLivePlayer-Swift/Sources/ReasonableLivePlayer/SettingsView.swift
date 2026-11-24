import SwiftUI
import RLPCore

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [String] = []
    @State private var device = ""            // "" = none
    @State private var channel = 1
    @State private var note = 0
    @State private var delayText = ""
    @State private var spacingText = ""
    @State private var fontSizeText = ""
    @State private var loadLastPlaylist = false
    @State private var alwaysOnTop = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Picker("MIDI Device:", selection: $device) {
                    Text("None").tag("")
                    ForEach(deviceChoices, id: \.self) { name in
                        Text(devices.contains(name) ? name : "\(name) (not available)").tag(name)
                    }
                }
                Picker("Channel (1-16):", selection: $channel) {
                    ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Note (0-127):", selection: $note) {
                    ForEach(0...127, id: \.self) { Text("\($0)").tag($0) }
                }
                TextField("Transition delay (s):", text: $delayText)
                    .frame(maxWidth: 220)
                TextField("Song spacing (0-20):", text: $spacingText)
                    .frame(maxWidth: 220)
                TextField("Font size (10-24):", text: $fontSizeText)
                    .frame(maxWidth: 220)
                Toggle("Load last playlist on startup", isOn: $loadLastPlaylist)
                Toggle("Always on top", isOn: $alwaysOnTop)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Accessibility:")
                    if model.accessibilityGranted {
                        Text("✓ Granted").foregroundColor(.green)
                    } else {
                        Text("✕ Not granted").foregroundColor(.orange)
                        Button("Open System Settings") { AccessibilityPermission.openSystemSettings() }
                    }
                }
                HStack {
                    Text("MIDI:")
                    Text(model.midiConnected ? "✓ Connected" : "✕ Not connected")
                        .foregroundColor(model.midiConnected ? .green : .orange)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear(perform: load)
        .alert("Validation Error", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    /// Available devices plus the saved one, so an offline device is not silently dropped.
    private var deviceChoices: [String] {
        var names = devices
        if !device.isEmpty, !names.contains(device) { names.append(device) }
        return names
    }

    private func load() {
        let s = model.settings
        devices = MidiNoteListener.availableDevices()
        if let saved = s.midiDeviceName, !saved.isEmpty {
            // Resolve the saved name to the display name used in the list (handles names
            // saved by the .NET version).
            device = MidiNoteListener.findSource(named: saved)?.displayName ?? saved
        }
        channel = min(16, max(1, s.midiChannel))
        note = min(127, max(0, s.endNoteNumber))
        delayText = String(s.transitionDelaySec)
        spacingText = String(s.songSpacing)
        fontSizeText = formatted(s.songFontSize)
        loadLastPlaylist = s.loadLastPlaylist
        alwaysOnTop = s.alwaysOnTop
    }

    private func save() {
        guard let delay = Int(delayText.trimmingCharacters(in: .whitespaces)), (0...99).contains(delay) else {
            validationMessage = "Transition delay must be a number between 0 and 99."
            return
        }
        guard let spacing = Int(spacingText.trimmingCharacters(in: .whitespaces)), (0...20).contains(spacing) else {
            validationMessage = "Song spacing must be a number between 0 and 20."
            return
        }
        guard let fontSize = Double(fontSizeText.trimmingCharacters(in: .whitespaces)),
              (10.0...24.0).contains(fontSize) else {
            validationMessage = "Font size must be a number between 10 and 24."
            return
        }

        var s = model.settings
        s.midiDeviceName = device.isEmpty ? nil : device
        s.midiChannel = channel
        s.endNoteNumber = note
        s.transitionDelaySec = delay
        s.songSpacing = spacing
        s.songFontSize = fontSize
        s.loadLastPlaylist = loadLastPlaylist
        s.alwaysOnTop = alwaysOnTop
        model.applySettings(s)
        dismiss()
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
