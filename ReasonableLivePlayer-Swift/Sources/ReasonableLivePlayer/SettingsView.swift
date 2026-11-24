import SwiftUI
import RLPCore

/// Contents of the standard Settings window (⌘,). Changes apply immediately, as is usual for
/// Mac preferences, so there are no Save or Cancel buttons. The window opens at the height of
/// the form, so nothing needs scrolling.
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

            Section("Toolbar") {
                Picker("Icon size", selection: binding(\.toolbarIconSize)) {
                    ForEach(ToolbarIconSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show tooltips", isOn: binding(\.showTooltips))
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
        // Size the window to the form: the height is whatever the settings need (no scrolling),
        // and the width can be dragged wider.
        .scrollDisabled(true)
        .frame(minWidth: 440, idealWidth: 480, maxWidth: 760)
        .fixedSize(horizontal: false, vertical: true)
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
