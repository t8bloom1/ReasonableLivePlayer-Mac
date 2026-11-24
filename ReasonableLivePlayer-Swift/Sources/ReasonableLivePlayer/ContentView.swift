import SwiftUI
import UniformTypeIdentifiers
import RLPCore

private let windowBackground = Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255)
private let listBackground = Color(red: 0x25 / 255, green: 0x25 / 255, blue: 0x25 / 255)

@MainActor
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(spacing: 8) {
            ToolbarRow()
            PlaylistView()
            Text(player.statusText)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, 2)
        }
        .padding(8)
        .frame(minWidth: 340, minHeight: 240)
        .background(windowBackground)
        .preferredColorScheme(.dark)
        .background(WindowAccessor { window in model.attach(window: window) })
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model)
        }
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
    }
}

// MARK: - Toolbar

@MainActor
private struct ToolbarRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        HStack(spacing: 6) {
            IconButton(systemName: player.isPlaying ? "pause.fill" : "play.fill",
                       help: player.isPlaying ? "Pause" : "Play",
                       width: 44) {
                if player.isPlaying { player.pause() } else { player.play() }
            }
            .disabled(player.songs.isEmpty || !model.accessibilityGranted)

            IconButton(systemName: "forward.end.fill", help: "Skip to next song", width: 44) {
                player.skip()
            }
            .disabled(player.songs.isEmpty)

            IconButton(systemName: "plus", help: "Add songs", width: 44) {
                model.addSongsViaPanel()
            }

            IconButton(systemName: "square.and.arrow.down", help: "Save playlist") {
                model.savePlaylistViaPanel()
            }
            .disabled(player.songs.isEmpty)

            IconButton(systemName: "folder", help: "Open playlist") {
                model.loadPlaylistViaPanel()
            }

            IconButton(systemName: "gearshape", help: "Settings") {
                model.showSettings = true
            }

            IconButton(systemName: "questionmark", help: "Help") {
                model.showHelp = true
            }

            Circle()
                .fill(model.statusIndicatorColor)
                .frame(width: 14, height: 14)
                .padding(.leading, 4)
                .help(model.statusIndicatorTooltip)

            Toggle(isOn: Binding(
                get: { model.settings.alwaysOnTop },
                set: { model.setAlwaysOnTop($0) }
            )) {
                Image(systemName: "pin.fill")
            }
            .toggleStyle(.button)
            .help("Stay on top of other windows")
        }
    }
}

@MainActor
private struct IconButton: View {
    let systemName: String
    let help: String
    var width: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: width - 16, height: 20)
        }
        .help(help)
        .focusable(false)
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
            listBackground
            Text("Drop .reason or .rns files here,\nor click + to add songs.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
        }
        .cornerRadius(6)
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
                    .listRowSeparator(.hidden)
                }
                .onMove { offsets, destination in
                    player.moveSongs(fromOffsets: offsets, toOffset: destination)
                }
                .onInsert(of: [UTType.fileURL]) { index, providers in
                    insertDropped(providers, at: index)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(listBackground)
            .cornerRadius(6)
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
        return isPlaying ? Color(red: 0, green: 0.8, blue: 0.4) : Color(white: 0.6)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { player.selectSong(id: song.id) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(indicatorColor)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Select this song")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.4))
                .frame(width: 18)

            Text(song.displayName)
                .font(.system(size: fontSize))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { player.selectSong(id: song.id) }

            Button { player.removeSong(id: song.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from playlist")
        }
        .padding(.top, CGFloat(spacing))
    }
}
