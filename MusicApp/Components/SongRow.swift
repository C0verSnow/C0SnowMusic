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
            .accessibilityLabel("Play \(song.title), \(song.artist)")
            Menu { actions } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("More options for \(song.title)")
        }
        .contextMenu { actions }
        .sheet(isPresented: $editing) { NavigationStack { MetadataEditor(song: song) } }
        .sheet(isPresented: $addingToPlaylist) { NavigationStack { AddToPlaylistView(song: song) } }
        .confirmationDialog("Remove “\(song.title)”", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove record, keep audio file") { library.remove(song, deleteFile: false, playback: playback) }
            Button("Also delete the in-app audio file", role: .destructive) { library.remove(song, deleteFile: true, playback: playback) }
        } message: { Text("Files whose records were removed can be reimported in Music Settings. Originals in Files remain unchanged.") }
    }

    @ViewBuilder private var actions: some View {
        Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { playback.enqueue(song, next: true) }
        Button("Add to queue", systemImage: "text.append") { playback.enqueue(song, next: false) }
        Button(song.isFavorite ? "Unfavorite" : "Favorite", systemImage: song.isFavorite ? "star.slash" : "star") { library.toggleFavorite(song) }
        Button("Add to playlist", systemImage: "text.badge.plus") { addingToPlaylist = true }
        if let album = library.albums.first(where: { $0.id == song.albumID }) {
            NavigationLink("View album", value: LibraryRoute.album(album.id))
        }
        if let artist = library.artists.first(where: { $0.id == song.artistID }) {
            NavigationLink("View artist", value: LibraryRoute.artist(artist.id))
        }
        Button("Edit song information", systemImage: "pencil") { editing = true }
        ShareLink(item: library.files.url(for: song.fileRelativePath)) { Label("Share audio file", systemImage: "square.and.arrow.up") }
        Button("Remove from library", systemImage: "trash", role: .destructive) { removing = true }
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
            Section("Song information") {
                TextField("Title", text: $title)
                TextField("Artists", text: $artist)
                TextField("Albums", text: $album)
                TextField("Genres", text: $genre)
            }
            Section("Audio files") {
                LabeledContent("Format", value: song.format)
                LabeledContent("Duration", value: playbackTime(song.duration))
                LabeledContent("Sample rate", value: "\(Int(song.sampleRate)) Hz")
                LabeledContent("Channels", value: "\(song.channels)")
                if let depth = song.bitDepth { LabeledContent("Bit depth", value: "\(depth) bit") }
                LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: song.fileSize, countStyle: .file))
                Text("Edits affect the local library only and do not rewrite audio files.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .localizedNavigationTitle("Edit song information").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { library.edit(song, title: title, artist: artist, album: album, genre: genre); if library.error == nil { dismiss() } }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { title = song.title; artist = song.artist; album = song.albumTitle; genre = song.genre }
    }
}
