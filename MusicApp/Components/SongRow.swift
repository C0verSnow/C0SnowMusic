import SwiftUI

struct SongRow: View {
    @Environment(PlaybackStore.self) private var playback
    @Environment(LibraryStore.self) private var library
    let song: Song
    var play: (() -> Void)?
    @State private var editing = false
    @State private var removing = false
    @State private var addingToPlaylist = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let play { play() } else { playback.play([song]) }
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(id: song.artworkID).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title).font(.body).foregroundStyle(playback.currentSong?.id == song.id ? Color.pink : .primary).lineLimit(2)
                        Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if song.isFavorite { Image(systemName: "star.fill").foregroundStyle(.pink).font(.caption) }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放 \(song.title)，\(song.artist)")
            Menu { actions } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("\(song.title) 的更多操作")
        }
        .contextMenu { actions }
        .sheet(isPresented: $editing) { NavigationStack { MetadataEditor(song: song) } }
        .sheet(isPresented: $addingToPlaylist) { NavigationStack { AddToPlaylistView(song: song) } }
        .confirmationDialog("移除「\(song.title)」", isPresented: $removing, titleVisibility: .visible) {
            Button("仅移除记录，保留音频文件") { library.remove(song, deleteFile: false, playback: playback) }
            Button("同时删除应用内音频文件", role: .destructive) { library.remove(song, deleteFile: true, playback: playback) }
        } message: { Text("仅移除记录的文件可以在设置中重新导入。不会修改文件应用中的原始文件。") }
    }

    @ViewBuilder private var actions: some View {
        Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") { playback.enqueue(song, next: true) }
        Button("添加到队列", systemImage: "text.append") { playback.enqueue(song, next: false) }
        Button(song.isFavorite ? "取消收藏" : "收藏", systemImage: song.isFavorite ? "star.slash" : "star") { library.toggleFavorite(song) }
        Button("添加到播放列表", systemImage: "text.badge.plus") { addingToPlaylist = true }
        if let album = library.albums.first(where: { $0.id == song.albumID }) {
            NavigationLink("查看专辑", value: LibraryRoute.album(album.id))
        }
        if let artist = library.artists.first(where: { $0.id == song.artistID }) {
            NavigationLink("查看艺术家", value: LibraryRoute.artist(artist.id))
        }
        Button("编辑歌曲信息", systemImage: "pencil") { editing = true }
        ShareLink(item: library.files.url(for: song.fileRelativePath)) { Label("分享音频文件", systemImage: "square.and.arrow.up") }
        Button("从资料库移除", systemImage: "trash", role: .destructive) { removing = true }
    }
}

struct MetadataEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var genre = ""
    var body: some View {
        Form {
            Section("歌曲信息") {
                TextField("标题", text: $title)
                TextField("艺术家", text: $artist)
                TextField("专辑", text: $album)
                TextField("流派", text: $genre)
            }
            Section("音频文件") {
                LabeledContent("格式", value: song.format)
                LabeledContent("时长", value: playbackTime(song.duration))
                LabeledContent("采样率", value: "\(Int(song.sampleRate)) Hz")
                LabeledContent("声道", value: "\(song.channels)")
                if let depth = song.bitDepth { LabeledContent("位深度", value: "\(depth) bit") }
                LabeledContent("文件大小", value: ByteCountFormatter.string(fromByteCount: song.fileSize, countStyle: .file))
                Text("编辑只修改本地资料库，不改写音频文件。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("编辑歌曲信息").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { library.edit(song, title: title, artist: artist, album: album, genre: genre); if library.error == nil { dismiss() } }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { title = song.title; artist = song.artist; album = song.albumTitle; genre = song.genre }
    }
}
