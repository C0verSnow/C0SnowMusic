import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if !online.history.isEmpty { OnlineHomeShelf(title: "Listen Again", items: online.history) }
                if !library.albums.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        NavigationLink(value: LibraryRoute.albums) {
                            HStack {
                                Text("Recently Added").font(.title2.bold())
                                Image(systemName: "chevron.right").font(.headline).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain).padding(.horizontal, 20)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(recentAlbums) { album in
                                    NavigationLink(value: LibraryRoute.album(album.id)) {
                                        AlbumCard(album: album).frame(width: 170)
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, 20)
                        }.scrollIndicators(.hidden)
                    }
                }
                ForEach(online.home) { section in
                    OnlineHomeShelf(title: section.title, items: section.items)
                }
                if !cloud.trending.isEmpty { OnlineHomeShelf(title: "Trending", items: cloud.trending) }
                if online.home.isEmpty && online.history.isEmpty && library.songs.isEmpty && cloud.trending.isEmpty {
                    EmptyLibraryView().frame(minHeight: 340)
                }
                if !library.songs.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        NavigationLink(value: LibraryRoute.songs(.favorites)) {
                            Label("Favorite Songs", systemImage: "star.fill").font(.title2.bold())
                        }.buttonStyle(.plain)
                        ForEach(library.songs.filter(\.isFavorite).prefix(4)) { SongRow(song: $0) }
                    }.padding(.horizontal, 20)
                }
            }.padding(.vertical, 20)
        }
        .navigationTitle("Home")
        .refreshable { await refresh() }
        .task {
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing"), online.home.isEmpty { await refresh() }
        }
    }

    private func refresh() async {
        await online.loadHome(cookies: account.downloadCookies())
        await cloud.refresh()
    }

    private var recentAlbums: [Album] {
        let ids = library.songs.sorted { $0.dateAdded > $1.dateAdded }.compactMap(\.albumID)
        var seen: Set<UUID> = []
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return library.albums.first { $0.id == id }
        }.prefix(12).map { $0 }
    }
}

private struct OnlineHomeShelf: View {
    let title: String
    let items: [OnlineTrack]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold()).padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { track in OnlineMusicCard(track: track).frame(width: 170) }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
        }
    }
}

struct OnlineMusicCard: View {
    let track: OnlineTrack
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    @Environment(PlaybackStore.self) private var playback
    var body: some View {
        Group {
            if track.isPlayable {
                Button {
                    online.prepare(track, play: true, playback: playback, cookies: account.downloadCookies(), cloud: cloud)
                } label: { card }.disabled(online.downloadingID != nil)
            } else if let id = track.browseID {
                NavigationLink { MusicCollectionView(browseID: id, title: track.title) } label: { card }
            }
        }.buttonStyle(.plain)
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 7) {
            OnlineArtworkView(track: track).aspectRatio(1, contentMode: .fit)
            Text(track.title).font(.subheadline.weight(.medium)).lineLimit(2)
            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.accessibilityElement(children: .combine)
    }
}

struct DiscoverView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        List {
            Section {
                NavigationLink(value: LibraryRoute.albums) { Label("All Albums", systemImage: "square.stack.fill") }
                NavigationLink(value: LibraryRoute.artists) { Label("All Artists", systemImage: "music.mic") }
                NavigationLink(value: LibraryRoute.songs(.all)) { Label("All Songs", systemImage: "music.note") }
            }.font(.title3)
            if !library.genres.isEmpty {
                Section("Genres") {
                    ForEach(library.genres, id: \.self) { genre in
                        NavigationLink(value: LibraryRoute.genre(genre)) { Label(genre, systemImage: "guitars") }
                    }
                }
            }
        }.listStyle(.plain).navigationTitle("Discover")
    }
}
