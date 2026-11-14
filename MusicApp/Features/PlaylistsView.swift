import SwiftUI
import PhotosUI

struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        List {
            Button("新建播放列表", systemImage: "plus") { name = ""; creating = true }
            ForEach(library.playlists) { playlist in
                NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                    HStack(spacing: 12) {
                        ArtworkView(id: playlist.artworkID).frame(width: 60, height: 60)
                        VStack(alignment: .leading) {
                            Text(playlist.name)
                            Text("\(library.playlistSongs(playlist).count) 首歌曲").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.onDelete { offsets in for index in offsets { library.deletePlaylist(library.playlists[index]) } }
        }
        .navigationTitle("播放列表")
        .alert("新建播放列表", isPresented: $creating) {
            TextField("播放列表名称", text: $name)
            Button("创建") { library.createPlaylist(name) }
            Button("取消", role: .cancel) { }
        }
    }
}

struct AddToPlaylistView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        List {
            Button("新建播放列表", systemImage: "plus") { creating = true }
            ForEach(library.playlists) { playlist in
                Button(playlist.name) { library.add(song, to: playlist); dismiss() }
            }
        }
        .navigationTitle("添加到播放列表").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .alert("新建播放列表", isPresented: $creating) {
            TextField("播放列表名称", text: $name)
            Button("创建") { library.createPlaylist(name) }
            Button("取消", role: .cancel) { }
        }
    }
}

struct PlaylistDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var renaming = false
    @State private var name = ""
    @State private var adding = false
    @State private var deleting = false
    @State private var cover: PhotosPickerItem?
    var body: some View {
        let entries = library.playlistSongs(playlist)
        List {
            Section {
                VStack(spacing: 12) {
                    ArtworkView(id: playlist.artworkID, thumbnail: false).aspectRatio(1, contentMode: .fit).frame(maxWidth: 240)
                    Text(playlist.name).font(.title.bold()).multilineTextAlignment(.center)
                    PhotosPicker(selection: $cover, matching: .images) { Label("更换封面", systemImage: "photo") }
                    HStack {
                        Button("播放", systemImage: "play.fill") { playback.play(entries.map(\.song)) }
                        Spacer()
                        Button("随机播放", systemImage: "shuffle") { playback.play(entries.map(\.song).shuffled(), shuffled: true) }
                    }.buttonStyle(.bordered).disabled(entries.isEmpty)
                }.padding(.vertical).frame(maxWidth: .infinity).listRowSeparator(.hidden)
                Button("添加歌曲", systemImage: "plus") { adding = true }
            }
            ForEach(Array(entries.enumerated()), id: \.element.item.id) { index, entry in
                SongRow(song: entry.song, play: { playback.play(entries.map(\.song), startingAt: index) })
            }
            .onDelete { library.removeItems(playlist, at: $0) }
            .onMove { library.moveItems(playlist, from: $0, to: $1) }
        }
        .listStyle(.plain).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
            Menu("播放列表操作", systemImage: "ellipsis.circle") {
                Button("修改名称", systemImage: "pencil") { name = playlist.name; renaming = true }
                Button("删除播放列表", systemImage: "trash", role: .destructive) { deleting = true }
            }
        }
        .alert("修改名称", isPresented: $renaming) {
            TextField("名称", text: $name)
            Button("保存") { library.rename(playlist, name: name) }
            Button("取消", role: .cancel) { }
        }
        .confirmationDialog("删除播放列表？歌曲仍保留在资料库。", isPresented: $deleting) {
            Button("删除播放列表", role: .destructive) { library.deletePlaylist(playlist); dismiss() }
        }
        .sheet(isPresented: $adding) { NavigationStack { PlaylistSongPicker(playlist: playlist) } }
        .task(id: cover) {
            guard let cover else { return }
            do {
                if let data = try await cover.loadTransferable(type: Data.self) { await library.setCover(playlist, data: data) }
            } catch { library.error = error.localizedDescription }
        }
    }
}

struct PlaylistSongPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var query = ""
    var body: some View {
        List(library.songs.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }) { song in
            let included = library.items.contains { $0.playlistID == playlist.id && $0.songID == song.id }
            Button { library.add(song, to: playlist) } label: {
                HStack {
                    VStack(alignment: .leading) { Text(song.title); Text(song.artist).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Image(systemName: included ? "checkmark.circle.fill" : "plus.circle")
                }
            }.disabled(included)
        }
        .searchable(text: $query, prompt: "搜索歌曲")
        .navigationTitle("添加歌曲").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}
