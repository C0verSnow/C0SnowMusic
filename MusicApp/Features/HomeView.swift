import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if library.songs.isEmpty { EmptyLibraryView().frame(minHeight: 360) }
                else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("只属于你的声音").font(.largeTitle.bold())
                        Text("\(library.songs.count) 首歌曲，随时随地聆听。").foregroundStyle(.secondary)
                    }.padding(.horizontal)
                    NavigationLink(value: LibraryRoute.songs(.favorites)) {
                        HStack {
                            Image(systemName: "star.fill").font(.largeTitle).frame(width: 64, height: 64).background(.pink.opacity(0.1), in: .rect(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("收藏歌曲").font(.title2.bold())
                                Text("\(library.songs.filter(\.isFavorite).count) 首喜爱的音乐").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding().background(.pink.opacity(0.05), in: .rect(cornerRadius: 22))
                    }.buttonStyle(.plain).padding(.horizontal)
                    if !library.albums.isEmpty {
                        Text("最近加入的专辑").font(.title2.bold()).padding(.horizontal)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(recentAlbums) { album in
                                    NavigationLink(value: LibraryRoute.album(album.id)) { AlbumCard(album: album).frame(width: 166) }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal)
                        }.scrollIndicators(.hidden)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink("继续聆听", value: LibraryRoute.songs(.history)).font(.title2.bold())
                        ForEach(library.songs.filter { $0.lastPlayedAt != nil }.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }.prefix(6)) { song in SongRow(song: song) }
                        if !library.songs.contains(where: { $0.lastPlayedAt != nil }) {
                            Text("播放过的歌曲会出现在这里。").foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal)
                }
            }.padding(.vertical)
        }.navigationTitle("首页")
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

struct DiscoverView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("重新发现你的音乐").font(.title.bold())
                    Text("按专辑、艺术家和流派探索本地收藏。").foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }.listRowSeparator(.hidden)
            Section("浏览收藏") {
                NavigationLink(value: LibraryRoute.albums) { Label("全部专辑", systemImage: "square.stack.fill") }
                NavigationLink(value: LibraryRoute.artists) { Label("所有艺术家", systemImage: "music.mic") }
                NavigationLink(value: LibraryRoute.songs(.recent)) { Label("最近添加", systemImage: "clock.badge.plus") }
            }
            Section("流派") {
                ForEach(Array(Set(library.songs.map(\.genre))).sorted(), id: \.self) { genre in
                    NavigationLink(genre, value: LibraryRoute.genre(genre))
                }
                if library.songs.isEmpty { Text("导入音乐后，流派会出现在这里。").foregroundStyle(.secondary) }
            }
        }.listStyle(.plain).navigationTitle("发现")
    }
}
