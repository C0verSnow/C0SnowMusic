import SwiftUI

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @State private var text = ""
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var searching = false
    @State private var scope = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("搜索范围", selection: $scope) {
                Text("资料库").tag(0)
                Text("YouTube").tag(1)
                Text("音乐仓库").tag(2)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
            if scope == 1 { OnlineSearchView() }
            else if scope == 2 { CloudSearchView() }
            else { localSearch }
        }.localizedNavigationTitle("搜索")
    }

    private var localSearch: some View {
        List {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("搜索你的资料库", systemImage: "magnifyingglass", description: Text("歌曲、艺术家、专辑和播放列表"))
            } else if songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && !searching {
                ContentUnavailableView.search(text: text)
            } else {
                if !songs.isEmpty {
                    Section("歌曲\(songs.count > 100 ? "（显示前 100 首）" : "")") {
                        ForEach(Array(songs.prefix(100).enumerated()), id: \.element.id) { index, song in
                            SongRow(song: song, play: { playback.play(songs, startingAt: index) })
                        }
                    }
                }
                if !albums.isEmpty { Section("专辑") { ForEach(albums) { NavigationLink($0.title, value: LibraryRoute.album($0.id)) } } }
                if !artists.isEmpty { Section("艺术家") { ForEach(artists) { NavigationLink($0.name, value: LibraryRoute.artist($0.id)) } } }
                if !playlists.isEmpty { Section("播放列表") { ForEach(playlists) { NavigationLink($0.name, value: LibraryRoute.playlist($0.id)) } } }
            }
        }
        .listStyle(.plain).localizedNavigationTitle("搜索")
        .searchable(text: $text, prompt: "歌曲、艺术家、专辑、播放列表")
        .task(id: text + "\(library.revision)") {
            searching = true
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            songs = library.songs.filter { $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) || $0.albumTitle.localizedStandardContains(query) }
            albums = library.albums.filter { $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }
            artists = library.artists.filter { $0.name.localizedStandardContains(query) }
            playlists = library.playlists.filter { $0.name.localizedStandardContains(query) }
            searching = false
        }
    }
}
