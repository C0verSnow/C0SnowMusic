import SwiftUI
import PhotosUI

struct PlaylistsView: View {
    @Environment(OnlineMusicStore.self) private var online
    @Environment(LibraryStore.self) private var library
    @State private var creating = false
    var body: some View {
        List {
            Button("New Playlist", systemImage: "plus") { creating = true }
            ForEach(library.playlists) { playlist in
                NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                    HStack(spacing: 12) {
                        ArtworkView(id: playlist.artworkID).frame(width: 60, height: 60)
                        VStack(alignment: .leading) {
                            Text(playlist.name)
                            Text("\(library.playlistSongs(playlist).count) songs").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.onDelete { offsets in
                let selected = offsets.map { library.playlists[$0] }
                for playlist in selected { library.deletePlaylist(playlist) }
            }
            ForEach(online.playlists) { OnlineTrackRow(track: $0) }
        }
        .localizedNavigationTitle("Playlists")
        .sheet(isPresented: $creating) { NavigationStack { PlaylistCreationView() } }
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
            Button("New playlist", systemImage: "plus") { creating = true }
            ForEach(library.playlists) { playlist in
                Button(playlist.name) { library.add(song, to: playlist); dismiss() }
            }
        }
        .localizedNavigationTitle("Add to playlist").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .alert("New playlist", isPresented: $creating) {
            TextField("Playlist name", text: $name)
            Button("Create") { library.createPlaylist(name) }
            Button("Cancel", role: .cancel) { }
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
                    PhotosPicker(selection: $cover, matching: .images) { Label("Change artwork", systemImage: "photo") }
                    HStack {
                        Button("Play", systemImage: "play.fill") { playback.play(entries.map(\.song)) }
                        Spacer()
                        Button("Shuffle", systemImage: "shuffle") { playback.play(entries.map(\.song).shuffled(), shuffled: true) }
                    }.buttonStyle(.bordered).disabled(entries.isEmpty)
                }.padding(.vertical).frame(maxWidth: .infinity).listRowSeparator(.hidden)
                Button("Add songs", systemImage: "plus") { adding = true }
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
            Menu("Playlist actions", systemImage: "ellipsis.circle") {
                Button("Change name", systemImage: "pencil") { name = playlist.name; renaming = true }
                Button("Delete playlist", systemImage: "trash", role: .destructive) { deleting = true }
            }
        }
        .alert("Change name", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") { library.rename(playlist, name: name) }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this playlist? Songs will stay in your library.", isPresented: $deleting) {
            Button("Delete playlist", role: .destructive) { library.deletePlaylist(playlist); dismiss() }
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
        .searchable(text: $query, prompt: "Search songs")
        .localizedNavigationTitle("Add songs").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

struct PlaylistCreationView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var cover: PhotosPickerItem?
    @State private var artwork: Data?
    @State private var saving = false

    var body: some View {
        VStack(spacing: 42) {
            PhotosPicker(selection: $cover, matching: .images) {
                ZStack {
                    if let artwork, let image = UIImage(data: artwork) { Image(uiImage: image).resizable().scaledToFill() }
                    else {
                        Color.secondary.opacity(0.12)
                        Image(systemName: "photo").font(.title2).foregroundStyle(.white)
                            .frame(width: 64, height: 64).background(.pink, in: .circle)
                    }
                }.frame(width: 180, height: 180).clipShape(.rect(cornerRadius: 8))
            }.padding(.top, 30).accessibilityLabel("Choose Playlist Artwork")
            TextField("Playlist Title", text: $name).font(.title3.bold()).multilineTextAlignment(.center)
                .padding(.bottom, 10).overlay(alignment: .bottom) { Divider() }.padding(.horizontal, 16)
            Spacer()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("New Playlist").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Playlist", systemImage: "checkmark") {
                    saving = true
                    let existing = Set(library.playlists.map(\.id))
                    library.createPlaylist(name)
                    Task {
                        if let playlist = library.playlists.first(where: { !existing.contains($0.id) }) {
                            if let artwork { await library.setCover(playlist, data: artwork) }
                            dismiss()
                        }
                        saving = false
                    }
                }.labelStyle(.iconOnly).disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task(id: cover) { if let cover { artwork = try? await cover.loadTransferable(type: Data.self) } }
    }
}
