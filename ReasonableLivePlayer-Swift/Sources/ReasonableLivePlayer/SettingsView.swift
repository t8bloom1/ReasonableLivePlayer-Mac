import SwiftUI
import RLPCore

/// Contents of the standard Settings window (⌘,). Changes apply immediately, as is usual for
/// Mac preferences, so there are no Save or Cancel buttons.
@MainActor
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("MIDI") {
                Picker("Device", selection: deviceBinding) {
                    Text("None").tag("")
                    ForEach(deviceChoices, id: \.self) { name in
                        Text(model.availableDevices.contains(name) ? name : "\(name) (not available)")
                            .tag(name)
                    }
                }
                Picker("Channel", selection: binding(\.midiChannel)) {
                    ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Trigger note", selection: binding(\.endNoteNumber)) {
                    ForEach(0...127, id: \.self) { Text("\($0)").tag($0) }
                }
                LabeledContent("Status") {
                    Text(model.midiConnected ? "✓ Connected" : "✕ Not connected")
                        .foregroundStyle(model.midiConnected ? .green : .orange)
                }
            }

            Section("Playback") {
                Stepper(value: binding(\.transitionDelaySec), in: 0...99) {
                    Text("Transition delay: \(model.settings.transitionDelaySec) s")
                }
            }

            Section("Playlist") {
                Stepper(value: binding(\.songSpacing), in: 0...20) {
                    Text("Song spacing: \(model.settings.songSpacing)")
                }
                Stepper(value: binding(\.songFontSize), in: 10...24, step: 1) {
                    Text("Font size: \(Int(model.settings.songFontSize))")
                }
            }

            Section("General") {
                Toggle("Load last playlist on startup", isOn: binding(\.loadLastPlaylist))
                Toggle("Always on top", isOn: binding(\.alwaysOnTop))
                Picker("Appearance", selection: binding(\.appearance)) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if model.accessibilityGranted {
                        Text("✓ Granted").foregroundStyle(.green)
                    } else {
                        HStack {
                            Text("✕ Not granted").foregroundStyle(.orange)
                            Button("Open System Settings") { AccessibilityPermission.openSystemSettings() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
    }

    /// Detected devices, plus the saved one so an offline device stays visible.
    private var deviceChoices: [String] {
        var names = model.availableDevices
        let selected = model.selectedDeviceName
        if !selected.isEmpty, !names.contains(selected) { names.append(selected) }
        return names
    }

    private var deviceBinding: Binding<String> {
        Binding(
            get: { model.selectedDeviceName },
            set: { name in model.update { $0.midiDeviceName = name.isEmpty ? nil : name } }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        )
    }
}
