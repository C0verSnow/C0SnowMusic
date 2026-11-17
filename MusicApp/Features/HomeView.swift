import SwiftUI

struct HomeView: View {
    let onSearch: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HomeFeatureCard(track: online.home.first?.items.first, onSearch: onSearch).padding(.horizontal, 20)
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
                if !library.songs.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        NavigationLink(value: LibraryRoute.songs(.favorites)) {
                            Label("Favorite Songs", systemImage: "star.fill").font(.title2.bold())
                        }.buttonStyle(.plain)
                        ForEach(library.songs.filter(\.isFavorite).prefix(4)) { SongRow(song: $0) }
                    }.padding(.horizontal, 20)
                }
            }.padding(.top, 4).padding(.bottom, 20)
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

private struct HomeFeatureCard: View {
    let track: OnlineTrack?
    let onSearch: () -> Void
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    @Environment(PlaybackStore.self) private var playback
    var body: some View {
        Group {
            if let track, let id = track.browseID, !track.isPlayable {
                NavigationLink { MusicCollectionView(browseID: id, title: track.title) } label: { poster }
            } else {
                Button {
                    if let track, track.isPlayable {
                        online.prepare(track, play: true, playback: playback, cookies: account.downloadCookies(), cloud: cloud)
                    } else { onSearch() }
                } label: { poster }
            }
        }.buttonStyle(.plain)
    }
    private var poster: some View {
        VStack(spacing: 16) {
            Text("Music just for you.").font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center).padding(.top, 28)
            Spacer()
            if let track {
                OnlineArtworkView(track: track).frame(width: 180, height: 180).shadow(radius: 20)
            } else {
                VStack(spacing: 12) {
                    AppLogoView().frame(width: 96, height: 96).clipShape(.rect(cornerRadius: 20))
                    Text("c0versnow music").font(.system(size: 26, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                }.padding(.horizontal)
            }
            Spacer()
            VStack(spacing: 4) {
                Text(track?.title ?? "Explore Music").font(.headline).lineLimit(2)
                Text(track?.artist ?? "Find your next favorite.").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }.multilineTextAlignment(.center).padding(.horizontal).padding(.bottom, 24)
        }.frame(maxWidth: .infinity).frame(height: 440)
            .background(LinearGradient(colors: [Color(uiColor: .secondarySystemGroupedBackground), Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.quaternary) }
    }
}

struct RadioView: View {
    @Environment(YouTubeAccountStore.self) private var account
    @State private var stations: [OnlineTrack] = []
    @State private var loading = false
    @State private var unavailable = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !stations.isEmpty { OnlineHomeShelf(title: "Radio Playlists", items: stations) }
                else if unavailable {
                    VStack(spacing: 8) {
                        Text("Cannot Connect").font(.title3.bold())
                        Text("The page couldn't be loaded. Try again.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Retry") { Task { await load() } }.padding(.top, 12)
                    }.frame(maxWidth: .infinity).containerRelativeFrame(.vertical)
                } else if loading { MusicPlaceholderRows().padding(.horizontal, 20) }
            }.padding(.vertical, 20)
        }
        .navigationTitle("Radio").navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await load() } }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; unavailable = false
        defer { loading = false }
        do {
            let page = try await YouTubeMusicClient().search("music radio", filter: .playlists, cookies: account.downloadCookies())
            stations = page.sections.flatMap(\.items).filter { $0.kind == .playlist }
        } catch { unavailable = true }
    }
}
