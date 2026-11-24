import SwiftUI
import UniformTypeIdentifiers
import RLPCore

@MainActor
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
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
        .frame(minWidth: 380, minHeight: 240)
        .navigationTitle(model.windowTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) { TransportButtons() }
            ToolbarItem(placement: .primaryAction) { FileButtons() }
            ToolbarItem(placement: .primaryAction) { StatusButtons() }
        }
        .background(WindowAccessor { window in model.attach(window: window) })
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
    }
}

// MARK: - Toolbar

@MainActor
private struct TransportButtons: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if player.isPlaying { player.pause() } else { player.play() }
            } label: {
                Label(player.isPlaying ? "Pause" : "Play",
                      systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
            }
            .help(player.isPlaying ? "Pause (⌘↩)" : "Play (⌘↩)")
            .disabled(player.songs.isEmpty || !model.accessibilityGranted)

            Button { player.skip() } label: {
                Label("Skip to Next Song", systemImage: "forward.end.fill").labelStyle(.iconOnly)
            }
            .help("Skip to next song (⌘→)")
            .disabled(player.songs.isEmpty)
        }
    }
}

@MainActor
private struct FileButtons: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        HStack(spacing: 4) {
            Button { model.addSongsViaPanel() } label: {
                Label("Add Songs", systemImage: "plus").labelStyle(.iconOnly)
            }
            .help("Add songs (⇧⌘O)")

            Button { model.loadPlaylistViaPanel() } label: {
                Label("Open Playlist", systemImage: "folder").labelStyle(.iconOnly)
            }
            .help("Open playlist (⌘O)")

            Button { model.savePlaylist() } label: {
                Label("Save Playlist", systemImage: "square.and.arrow.down").labelStyle(.iconOnly)
            }
            .help("Save playlist (⌘S)")
            .disabled(player.songs.isEmpty)
        }
    }
}

@MainActor
private struct StatusButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            SettingsButton()

            Button { model.showHelp = true } label: {
                Label("Help", systemImage: "questionmark.circle").labelStyle(.iconOnly)
            }
            .help("Help")

            Toggle(isOn: Binding(
                get: { model.settings.alwaysOnTop },
                set: { value in model.update { $0.alwaysOnTop = value } }
            )) {
                Label("Stay on Top", systemImage: "pin.fill").labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .help("Stay on top of other windows")

            Circle()
                .fill(model.statusIndicatorColor)
                .frame(width: 12, height: 12)
                .help(model.statusIndicatorTooltip)
                .accessibilityElement()
                .accessibilityLabel("Status")
                .accessibilityValue(model.statusIndicatorTooltip)
        }
    }
}

/// Opens the Settings window. macOS 14 added `SettingsLink`; on macOS 13 the window is opened
/// by sending the standard action.
@MainActor
private struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14, *) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
            }
            .help("Settings (⌘,)")
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
            }
            .help("Settings (⌘,)")
        }
    }
}

// MARK: - Playlist

@MainActor
private struct PlaylistView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

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
            List {
                ForEach(player.songs) { song in
                    SongRow(
                        song: song,
                        isActive: song.id == activeID,
                        isPlaying: player.isPlaying,
                        fontSize: model.settings.songFontSize,
                        spacing: model.settings.songSpacing
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
    @EnvironmentObject private var player: PlayerController

    let song: Song
    let isActive: Bool
    let isPlaying: Bool
    let fontSize: Double
    let spacing: Int

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
            .help("Make this the next song")
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
                .onTapGesture(count: 2) { player.playSong(id: song.id) }
                .accessibilityAddTraits(isActive ? .isSelected : [])

            Button { player.removeSong(id: song.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from playlist")
            .accessibilityLabel("Remove \(song.displayName)")
        }
        .padding(.top, CGFloat(spacing))
    }
}
