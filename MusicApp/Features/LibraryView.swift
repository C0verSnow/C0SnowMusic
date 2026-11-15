import SwiftUI

enum SongFilter: String, Hashable { case all = "歌曲", recent = "最近添加", history = "最近播放", favorites = "收藏歌曲" }
enum LibraryRoute: Hashable {
    case songs(SongFilter), albums, artists, genres, playlists
    case album(UUID), artist(UUID), genre(String), playlist(UUID)
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        List {
            Section {
                NavigationLink(value: LibraryRoute.playlists) { Label("播放列表", systemImage: "music.note.list") }
                NavigationLink(value: LibraryRoute.artists) { Label("艺术家", systemImage: "music.mic") }
                NavigationLink(value: LibraryRoute.albums) { Label("专辑", systemImage: "square.stack") }
                NavigationLink(value: LibraryRoute.songs(.all)) { Label("歌曲", systemImage: "music.note") }
                NavigationLink(value: LibraryRoute.genres) { Label("流派", systemImage: "guitars") }
                NavigationLink(value: LibraryRoute.songs(.history)) { Label("最近播放", systemImage: "clock") }
                NavigationLink(value: LibraryRoute.songs(.favorites)) { Label("收藏歌曲", systemImage: "star") }
            }
            Section("最近添加") {
                if library.songs.isEmpty { EmptyLibraryView().listRowSeparator(.hidden) }
                else {
                    ForEach(library.songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(12)) { song in SongRow(song: song) }
                    NavigationLink("查看全部", value: LibraryRoute.songs(.recent))
                }
            }
        }
        .listStyle(.plain)
        .localizedNavigationTitle("资料库")
    }
}

struct LibraryRouteView: View {
    @Environment(LibraryStore.self) private var library
    let route: LibraryRoute
    var body: some View {
        switch route {
        case .songs(let filter): SongListView(title: filter.rawValue, songs: filtered(filter))
        case .albums:
            AlbumGridView(albums: library.albums).localizedNavigationTitle("专辑")
        case .artists:
            List(library.artists) { artist in NavigationLink(artist.name, value: LibraryRoute.artist(artist.id)) }.localizedNavigationTitle("艺术家")
        case .genres:
            List(Array(Set(library.songs.map(\.genre))).sorted(), id: \.self) { genre in
                NavigationLink(genre, value: LibraryRoute.genre(genre))
            }.localizedNavigationTitle("流派")
        case .playlists: PlaylistsView()
        case .album(let id):
            if let album = library.albums.first(where: { $0.id == id }) { AlbumDetailView(album: album) }
            else { ContentUnavailableView("专辑已移除", systemImage: "square.stack") }
        case .artist(let id):
            if let artist = library.artists.first(where: { $0.id == id }) {
                SongListView(title: artist.name, songs: library.songs.filter { $0.artistID == id })
            } else { ContentUnavailableView("艺术家已移除", systemImage: "music.mic") }
        case .genre(let genre): SongListView(title: genre, songs: library.songs.filter { $0.genre == genre })
        case .playlist(let id):
            if let playlist = library.playlists.first(where: { $0.id == id }) { PlaylistDetailView(playlist: playlist) }
            else { ContentUnavailableView("播放列表已移除", systemImage: "music.note.list") }
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
    case original = "默认顺序", title = "标题", artist = "艺术家", added = "添加时间"
    var id: String { rawValue }
}

struct SongListView: View {
    @Environment(PlaybackStore.self) private var playback
    let title: String
    let songs: [Song]
    @State private var sort = SongSort.original
    private var sortedSongs: [Song] {
        switch sort {
        case .original: songs
        case .title: songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: songs.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case .added: songs.sorted { $0.dateAdded > $1.dateAdded }
        }
    }
    var body: some View {
        List {
            if !songs.isEmpty {
                Section {
                    HStack {
                        Button("播放", systemImage: "play.fill") { playback.play(sortedSongs) }
                        Spacer()
                        Button("随机播放", systemImage: "shuffle") { playback.play(sortedSongs.shuffled(), shuffled: true) }
                    }.buttonStyle(.bordered).listRowSeparator(.hidden)
                }
            }
            ForEach(Array(sortedSongs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, play: { playback.play(sortedSongs, startingAt: index) })
            }
        }
        .listStyle(.plain)
        .overlay { if songs.isEmpty { ContentUnavailableView("这里还没有歌曲", systemImage: "music.note") } }
        .navigationTitle(title)
        .toolbar {
            Menu("排序", systemImage: "arrow.up.arrow.down") {
                Picker("排序", selection: $sort) { ForEach(SongSort.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
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
        .overlay { if albums.isEmpty { ContentUnavailableView("还没有专辑", systemImage: "square.stack") } }
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
                        Button("播放", systemImage: "play.fill") { playback.play(songs) }.frame(maxWidth: .infinity)
                        Button("随机播放", systemImage: "shuffle") { playback.play(songs.shuffled(), shuffled: true) }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).disabled(songs.isEmpty)
                }.frame(maxWidth: .infinity).padding(.vertical).listRowSeparator(.hidden)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, play: { playback.play(songs, startingAt: index) })
            }
            Text("\(songs.count) 首歌曲 · \(playbackTime(songs.reduce(0) { $0 + $1.duration }))")
                .font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden)
        }.listStyle(.plain).navigationBarTitleDisplayMode(.inline)
    }
}
