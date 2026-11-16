import SwiftUI

enum SongFilter: String, Hashable { case all = "Songs", recent = "Recently Added", history = "Recently Played", favorites = "Favorite Songs" }
enum LibraryRoute: Hashable {
    case songs(SongFilter), albums, artists, genres, playlists
    case album(UUID), artist(UUID), genre(String), playlist(UUID)
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    var body: some View {
        List {
            Section {
                NavigationLink(value: LibraryRoute.playlists) { Label("Playlists", systemImage: "music.note.list") }
                NavigationLink(value: LibraryRoute.artists) { Label("Artists", systemImage: "music.mic") }
                NavigationLink(value: LibraryRoute.albums) { Label("Albums", systemImage: "square.stack") }
                NavigationLink(value: LibraryRoute.songs(.all)) { Label("Songs", systemImage: "music.note") }
                NavigationLink(value: LibraryRoute.genres) { Label("Genres", systemImage: "guitars") }
                NavigationLink(value: LibraryRoute.songs(.history)) { Label("Recently Played", systemImage: "clock") }
                NavigationLink(value: LibraryRoute.songs(.favorites)) { Label("Favorite Songs", systemImage: "star") }
            }.font(.title3).foregroundStyle(.primary)
            Section("Recently Added") {
                ForEach(library.songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(8)) { SongRow(song: $0) }
                ForEach(online.songs(for: .recent, cloud: cloud).prefix(8)) { OnlineTrackRow(track: $0) }
                if library.songs.isEmpty && online.songs(for: .recent, cloud: cloud).isEmpty {
                    EmptyLibraryView().listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Library")
        .refreshable {
            if account.isSignedIn { await online.loadLibrary(cookies: account.downloadCookies(), cloud: cloud) }
            else { await cloud.refresh() }
        }
    }
}

struct LibraryRouteView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(OnlineMusicStore.self) private var online
    @Environment(CloudMusicStore.self) private var cloud
    let route: LibraryRoute
    var body: some View {
        switch route {
        case .songs(let filter): SongListView(title: filter.rawValue, songs: filtered(filter), onlineSongs: online.songs(for: filter, cloud: cloud))
        case .albums:
            List {
                if !library.albums.isEmpty {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 20)], spacing: 24) {
                            ForEach(library.albums) { album in
                                NavigationLink(value: LibraryRoute.album(album.id)) { AlbumCard(album: album) }.buttonStyle(.plain)
                            }
                        }.padding(.vertical).listRowSeparator(.hidden)
                    }
                }
                ForEach(online.albums) { OnlineTrackRow(track: $0) }
            }.listStyle(.plain).navigationTitle("Albums")
                .overlay { if library.albums.isEmpty && online.albums.isEmpty { ContentUnavailableView("No Albums Yet", systemImage: "square.stack") } }
        case .artists:
            List {
                ForEach(library.artists) { artist in
                    NavigationLink(value: LibraryRoute.artist(artist.id)) {
                        Label(artist.name, systemImage: "music.mic").padding(.vertical, 8)
                    }
                }
                ForEach(online.artists) { OnlineTrackRow(track: $0) }
            }.listStyle(.plain).navigationTitle("Artists")
                .overlay { if library.artists.isEmpty && online.artists.isEmpty { ContentUnavailableView("No Artists Yet", systemImage: "music.mic") } }
        case .genres:
            List(library.genres, id: \.self) { genre in
                NavigationLink(genre, value: LibraryRoute.genre(genre))
            }.localizedNavigationTitle("Genres")
        case .playlists: PlaylistsView()
        case .album(let id):
            if let album = library.albums.first(where: { $0.id == id }) { AlbumDetailView(album: album) }
            else { ContentUnavailableView("Album removed", systemImage: "square.stack") }
        case .artist(let id):
            if let artist = library.artists.first(where: { $0.id == id }) {
                SongListView(title: artist.name, songs: library.songs.filter { $0.artistID == id })
            } else { ContentUnavailableView("Artist removed", systemImage: "music.mic") }
        case .genre(let genre): SongListView(title: genre, songs: library.songs.filter { $0.genre == genre })
        case .playlist(let id):
            if let playlist = library.playlists.first(where: { $0.id == id }) { PlaylistDetailView(playlist: playlist) }
            else { ContentUnavailableView("Playlist removed", systemImage: "music.note.list") }
        }
    }

    private func filtered(_ filter: SongFilter) -> [Song] {
        switch filter {
        case .all: library.songs
        case .recent: library.songs.sorted { $0.dateAdded > $1.dateAdded }
        case .history: library.songs.filter { $0.lastPlayedAt != nil }.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .favorites: library.songs.filter(\.isFavorite)
        }
    }
}

enum SongSort: String, CaseIterable, Identifiable {
    case original = "Default order", title = "Title", artist = "Artists", added = "Date added"
    var id: String { rawValue }
}

struct SongListView: View {
    @Environment(PlaybackStore.self) private var playback
    let title: String
    let songs: [Song]
    var onlineSongs: [OnlineTrack] = []
    @State private var sort = SongSort.original
    private var sortedSongs: [Song] {
        switch sort {
        case .original: songs
        case .title: songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: songs.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case .added: songs.sorted { $0.dateAdded > $1.dateAdded }
        }
    }
    private var sortedOnlineSongs: [OnlineTrack] {
        switch sort {
        case .title: onlineSongs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: onlineSongs.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case .original, .added: onlineSongs
        }
    }
    var body: some View {
        List {
            if !songs.isEmpty {
                Section {
                    HStack {
                        Button("Play", systemImage: "play.fill") { playback.play(sortedSongs) }
                        Spacer()
                        Button("Shuffle", systemImage: "shuffle") { playback.play(sortedSongs.shuffled(), shuffled: true) }
                    }.buttonStyle(.bordered).listRowSeparator(.hidden)
                }
            }
            ForEach(Array(sortedSongs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, play: { playback.play(sortedSongs, startingAt: index) })
            }
            ForEach(sortedOnlineSongs) { OnlineTrackRow(track: $0) }
        }
        .listStyle(.plain)
        .overlay { if songs.isEmpty && onlineSongs.isEmpty { ContentUnavailableView("No songs here yet", systemImage: "music.note") } }
        .navigationTitle(title)
        .toolbar {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort", selection: $sort) { ForEach(SongSort.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
            }
        }
    }
}

struct AlbumGridView: View {
    let albums: [Album]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 20)], spacing: 24) {
                ForEach(albums) { album in
                    NavigationLink(value: LibraryRoute.album(album.id)) { AlbumCard(album: album) }.buttonStyle(.plain)
                }
            }.padding()
        }
        .overlay { if albums.isEmpty { ContentUnavailableView("No albums yet", systemImage: "square.stack") } }
    }
}

struct AlbumDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    let album: Album
    private var songs: [Song] {
        library.songs.filter { $0.albumID == album.id }.sorted {
            if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
            if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
            return $0.title < $1.title
        }
    }
    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    ArtworkView(id: album.artworkID, thumbnail: false, cornerRadius: 14)
                        .aspectRatio(1, contentMode: .fit).frame(maxWidth: 300).shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                    Text(album.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(album.artist).font(.title3).foregroundStyle(.pink)
                    if let year = album.releaseYear { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button("Play", systemImage: "play.fill") { playback.play(songs) }.frame(maxWidth: .infinity)
                        Button("Shuffle", systemImage: "shuffle") { playback.play(songs.shuffled(), shuffled: true) }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).disabled(songs.isEmpty)
                }.frame(maxWidth: .infinity).padding(.vertical).listRowSeparator(.hidden)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, play: { playback.play(songs, startingAt: index) })
            }
            Text("\(songs.count) songs · \(playbackTime(songs.reduce(0) { $0 + $1.duration }))")
                .font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden)
        }.listStyle(.plain).navigationBarTitleDisplayMode(.inline)
    }
}
