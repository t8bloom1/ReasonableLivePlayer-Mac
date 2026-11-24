import SwiftUI
import UniformTypeIdentifiers
import RLPCore

@MainActor
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(spacing: 0) {
            ToolbarBar()
            Divider()
            VStack(spacing: 6) {
                PlaylistView()
                Text(player.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
            .padding([.horizontal, .top], 8)
        }
        // The window's minimum width follows the icon size so the buttons always fit.
        .frame(minWidth: model.settings.toolbarIconSize.minimumWindowWidth, minHeight: 260)
        .navigationTitle(model.windowTitle)
        .background(WindowAccessor { window in model.attach(window: window) })
    }
}

// MARK: - Toolbar

extension View {
    /// A tooltip that can be switched off in Settings.
    fileprivate func tip(_ text: String, _ enabled: Bool) -> some View {
        help(enabled ? text : "")
    }
}

extension ToolbarIconSize {
    /// Size of the toolbar symbols in points.
    fileprivate var symbolSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 17
        case .large: return 22
        case .extraLarge: return 28
        }
    }

    fileprivate var buttonWidth: CGFloat { symbolSize * 1.8 }
    fileprivate var buttonHeight: CGFloat { symbolSize * 1.5 }
    fileprivate var barVerticalPadding: CGFloat { max(6, symbolSize * 0.35) }
    fileprivate var statusDotDiameter: CGFloat { (symbolSize * 0.85).rounded() }

    /// Room for the nine controls at this size, plus the playlist area.
    fileprivate var minimumWindowWidth: CGFloat {
        switch self {
        case .small: return 400
        case .medium: return 480
        case .large: return 580
        case .extraLarge: return 700
        }
    }
}

/// The toolbar. It is part of the window content, not a system toolbar, because the system
/// toolbar has a fixed height and clips larger icons. The bar grows with the icon size.
@MainActor
private struct ToolbarBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let size = model.settings.toolbarIconSize
        HStack(spacing: 6) {
            PlayPauseButton()
            SkipButton()
            Spacer(minLength: 8)
            AddSongsButton()
            OpenPlaylistButton()
            SavePlaylistButton()
            SettingsButton()
            HelpButton()
            StayOnTopToggle()
            StatusDot()
                .padding(.leading, 4)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 10)
        .padding(.vertical, size.barVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// An icon-only label sized by the toolbar icon size setting.
@MainActor
private struct ToolbarGlyph: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let systemImage: String

    var body: some View {
        let size = model.settings.toolbarIconSize
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: size.symbolSize))
            .frame(width: size.buttonWidth, height: size.buttonHeight)
    }
}

@MainActor
private struct PlayPauseButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Button {
            if player.isPlaying { player.pause() } else { player.play() }
        } label: {
            ToolbarGlyph(title: player.isPlaying ? "Pause" : "Play",
                         systemImage: player.isPlaying ? "pause.fill" : "play.fill")
        }
        .tip(player.isPlaying ? "Pause (⌘↩)" : "Play (⌘↩)", model.settings.showTooltips)
        .disabled(player.songs.isEmpty || !model.accessibilityGranted)
    }
}

@MainActor
private struct SkipButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Button { player.skip() } label: {
            ToolbarGlyph(title: "Skip to Next Song", systemImage: "forward.end.fill")
        }
        .tip("Skip to next song (⌘→)", model.settings.showTooltips)
        .disabled(player.songs.isEmpty)
    }
}

@MainActor
private struct AddSongsButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.addSongsViaPanel() } label: {
            ToolbarGlyph(title: "Add Songs", systemImage: "plus")
        }
        .tip("Add songs (⇧⌘O)", model.settings.showTooltips)
    }
}

@MainActor
private struct OpenPlaylistButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.loadPlaylistViaPanel() } label: {
            ToolbarGlyph(title: "Open Playlist", systemImage: "folder")
        }
        .tip("Open playlist (⌘O)", model.settings.showTooltips)
    }
}

@MainActor
private struct SavePlaylistButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Button { model.savePlaylist() } label: {
            ToolbarGlyph(title: "Save Playlist", systemImage: "square.and.arrow.down")
        }
        .tip("Save playlist (⌘S)", model.settings.showTooltips)
        .disabled(player.songs.isEmpty)
    }
}

/// Opens the Settings window. macOS 14 added `SettingsLink`; on macOS 13 the window is opened
/// by sending the standard action.
@MainActor
private struct SettingsButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if #available(macOS 14, *) {
            SettingsLink {
                ToolbarGlyph(title: "Settings", systemImage: "gearshape")
            }
            .tip("Settings (⌘,)", model.settings.showTooltips)
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                ToolbarGlyph(title: "Settings", systemImage: "gearshape")
            }
            .tip("Settings (⌘,)", model.settings.showTooltips)
        }
    }
}

@MainActor
private struct HelpButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { openWindow(id: HelpWindow.id) } label: {
            ToolbarGlyph(title: "Help", systemImage: "questionmark.circle")
        }
        .tip("Help", model.settings.showTooltips)
    }
}

@MainActor
private struct StayOnTopToggle: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.settings.alwaysOnTop },
            set: { value in model.update { $0.alwaysOnTop = value } }
        )) {
            ToolbarGlyph(title: "Stay on Top", systemImage: "pin.fill")
        }
        .toggleStyle(.button)
        .tip("Stay on top of other windows", model.settings.showTooltips)
    }
}

@MainActor
private struct StatusDot: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let diameter = model.settings.toolbarIconSize.statusDotDiameter
        Circle()
            .fill(model.statusIndicatorColor)
            .frame(width: diameter, height: diameter)
            .tip(model.statusIndicatorTooltip, model.settings.showTooltips)
            .accessibilityElement()
            .accessibilityLabel("Status")
            .accessibilityValue(model.statusIndicatorTooltip)
    }
}

// MARK: - Playlist

@MainActor
private struct PlaylistView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController
    @FocusState private var listHasFocus: Bool

    var body: some View {
        if player.songs.isEmpty {
            emptyState
        } else {
            songList
        }
    }

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            Text("Drop .reason or .rns files here,\nor click + to add songs.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            insertDropped(providers, at: nil)
            return true
        }
    }

    private var songList: some View {
        let activeID = player.activeSongID
        return ScrollViewReader { proxy in
            // Selection gives the row highlight and Up/Down arrow navigation (which also
            // scrolls the list). Return plays the selected song.
            List(selection: $player.selectedSongID) {
                ForEach(player.songs) { song in
                    SongRow(
                        song: song,
                        isActive: song.id == activeID,
                        isPlaying: player.isPlaying,
                        fontSize: model.settings.songFontSize,
                        spacing: model.settings.songSpacing,
                        showTooltips: model.settings.showTooltips
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .onMove { offsets, destination in
                    player.moveSongs(fromOffsets: offsets, toOffset: destination)
                }
                .onInsert(of: [UTType.fileURL]) { index, providers in
                    insertDropped(providers, at: index)
                }
            }
            .listStyle(.inset)
            .focused($listHasFocus)
            .onAppear { listHasFocus = true }
            .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: .down) { _ in
                guard let id = player.selectedSongID else { return .ignored }
                model.playSong(id: id)
                return .handled
            }
            .onChange(of: player.scrollRequest) { request in
                guard let request else { return }
                withAnimation { proxy.scrollTo(request.songID) }
            }
        }
    }

    private func insertDropped(_ providers: [NSItemProvider], at index: Int?) {
        loadFileURLs(from: providers) { urls in
            let songs = urls
                .filter { ["reason", "rns"].contains($0.pathExtension.lowercased()) }
                .map { $0.path }
            player.insertSongs(paths: songs, at: index)
        }
    }
}

/// Collects dropped URLs from several callbacks, keeping drop order.
private final class DropResults: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL?]

    init(count: Int) { urls = Array(repeating: nil, count: count) }

    func set(_ url: URL?, at index: Int) {
        lock.lock()
        urls[index] = url
        lock.unlock()
    }

    var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls.compactMap { $0 }
    }
}

/// Loads dropped file URLs, preserving drop order, and calls `completion` on the main queue.
private func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let results = DropResults(count: providers.count)

    for (index, provider) in providers.enumerated() {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            results.set(url, at: index)
            group.leave()
        }
    }
    group.notify(queue: .main) {
        completion(results.all)
    }
}

@MainActor
private struct SongRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    let song: Song
    let isActive: Bool
    let isPlaying: Bool
    let fontSize: Double
    let spacing: Int
    let showTooltips: Bool

    private var indicatorColor: Color {
        guard isActive else { return .clear }
        return isPlaying ? Color(red: 0, green: 0.8, blue: 0.4) : .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { player.selectSong(id: song.id) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(indicatorColor)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip("Make this the next song", showTooltips)
            .accessibilityLabel("Select \(song.displayName)")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(song.displayName)
                .font(.system(size: fontSize))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.playSong(id: song.id) }
                .accessibilityAddTraits(isActive ? .isSelected : [])

            Button { player.removeSong(id: song.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip("Remove from playlist", showTooltips)
            .accessibilityLabel("Remove \(song.displayName)")
        }
        .padding(.top, CGFloat(spacing))
    }
}
