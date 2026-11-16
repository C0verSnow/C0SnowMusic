import SwiftUI

enum SongFilter: String, Hashable { case all = "Songs", recent = "Recently Added", history = "Recently Played", favorites = "Favorite Songs" }
enum LibraryRoute: Hashable {
    case songs(SongFilter), albums, artists, genres, playlists
    case album(UUID), artist(UUID), genre(String), playlist(UUID)
}

enum LibraryCategory: String, CaseIterable, Identifiable {
    case playlists, artists, albums, songs, genres, history, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .genres: "Genres"
        case .history: "Recently Played"
        case .favorites: "Favorite Songs"
        }
    }
    var icon: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .genres: "guitars"
        case .history: "clock"
        case .favorites: "star"
        }
    }
    var route: LibraryRoute {
        switch self {
        case .playlists: .playlists
        case .artists: .artists
        case .albums: .albums
        case .songs: .songs(.all)
        case .genres: .genres
        case .history: .songs(.history)
        case .favorites: .songs(.favorites)
        }
    }
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    @AppStorage("libraryCategoryOrder") private var categoryOrder = LibraryCategory.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage("libraryVisibleCategories") private var visibleCategories = LibraryCategory.allCases.map(\.rawValue).joined(separator: ",")
    @Binding var editing: Bool
    private var orderedCategories: [LibraryCategory] { categoryOrder.split(separator: ",").compactMap { LibraryCategory(rawValue: String($0)) } }
    private var visible: Set<String> { Set(visibleCategories.split(separator: ",").map(String.init)) }

    var body: some View {
        List {
            Section {
                ForEach(orderedCategories.filter { editing || visible.contains($0.rawValue) }) { category in
                    Group {
                        if editing {
                            Button {
                                var next = visible
                                if !next.insert(category.rawValue).inserted { next.remove(category.rawValue) }
                                visibleCategories = orderedCategories.map(\.rawValue).filter { next.contains($0) }.joined(separator: ",")
                            } label: {
                                HStack(spacing: 20) {
                                    Image(systemName: visible.contains(category.rawValue) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(visible.contains(category.rawValue) ? Color.pink : .secondary)
                                    Label(category.title, systemImage: category.icon).labelStyle(LibraryLabelStyle())
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("libraryCategory-\(category.rawValue)")
                                .accessibilityValue(visible.contains(category.rawValue) ? "Shown" : "Hidden")
                        } else {
                            NavigationLink(value: category.route) {
                                Label(category.title, systemImage: category.icon).labelStyle(LibraryLabelStyle())
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(.visible, edges: .bottom)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in editing ? 84 : 44 }
                    .moveDisabled(!editing)
                }
                .onMove { offsets, destination in
                    var order = orderedCategories
                    order.move(fromOffsets: offsets, toOffset: destination)
                    categoryOrder = order.map(\.rawValue).joined(separator: ",")
                }
            }
            if !editing && (!library.songs.isEmpty || !online.songs(for: .recent, cloud: cloud).isEmpty) {
                Section {
                    ForEach(library.songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(8)) { SongRow(song: $0) }
                    ForEach(online.songs(for: .recent, cloud: cloud).prefix(8)) { OnlineTrackRow(track: $0) }
                } header: {
                    Text("Recently Added").font(.title2.bold()).foregroundStyle(.primary).textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .navigationTitle("Library")
        .refreshable {
            if account.isSignedIn { await online.loadLibrary(cookies: account.downloadCookies(), cloud: cloud) }
            else { await cloud.refresh() }
        }
    }
}

struct LibraryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 18) {
            configuration.icon.font(.title3).foregroundStyle(.pink).frame(width: 24)
            configuration.title.foregroundStyle(.primary)
        }.font(.body).frame(minHeight: 52)
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
