import SwiftUI

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(OnlineMusicStore.self) private var online
    @Environment(CloudMusicStore.self) private var cloud
    @State private var text = ""
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var searching = false
    @State private var scope = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Search in", selection: $scope) {
                Text("c0vermusic").tag(0)
                Text("Library").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 8)
            if scope == 0 { OnlineSearchView(query: $text) }
            else { localSearch }
        }
        .navigationTitle("Search")
        .searchable(text: $text, prompt: scope == 0 ? "Artists, Songs, and More" : "Search Your Library")
    }

    private var localSearch: some View {
        List {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass", description: Text("Songs, artists, albums, and playlists"))
            } else if songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && onlineMatches.isEmpty && !searching {
                ContentUnavailableView.search(text: text)
            } else {
                if !songs.isEmpty {
                    Section("Songs\(songs.count > 100 ? " (first 100 shown)" : "")") {
                        ForEach(Array(songs.prefix(100).enumerated()), id: \.element.id) { index, song in
                            SongRow(song: song, play: { playback.play(songs, startingAt: index) })
                        }
                    }
                }
                ForEach(onlineMatches) { OnlineTrackRow(track: $0) }
                if !albums.isEmpty { Section("Albums") { ForEach(albums) { NavigationLink($0.title, value: LibraryRoute.album($0.id)) } } }
                if !artists.isEmpty { Section("Artists") { ForEach(artists) { NavigationLink($0.name, value: LibraryRoute.artist($0.id)) } } }
                if !playlists.isEmpty { Section("Playlists") { ForEach(playlists) { NavigationLink($0.name, value: LibraryRoute.playlist($0.id)) } } }
            }
        }
        .listStyle(.plain).localizedNavigationTitle("Search")
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
    private var onlineMatches: [OnlineTrack] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (online.songs(for: .all, cloud: cloud) + online.playlists + online.albums + online.artists).filter {
            $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) || ($0.albumTitle?.localizedStandardContains(query) ?? false)
        }
    }

}
