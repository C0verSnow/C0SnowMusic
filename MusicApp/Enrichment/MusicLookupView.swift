import SwiftUI

struct MusicLookupView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var results: [LyricsMatch] = []
    @State private var searching = false
    @State private var downloading: Int?
    @State private var error: String?
    @State private var notice: String?
    @State private var requestID = 0
    @State private var includeCover = true
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("Song title", text: $title).accessibilityIdentifier("lookupTitle")
                TextField("Artists", text: $artist).accessibilityIdentifier("lookupArtist")
                TextField("Album (optional)", text: $album)
                Button { requestID += 1 } label: {
                    HStack { Text("Search lyrics"); Spacer(); if searching { ProgressView() } }
                }.disabled(searching || downloading != nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Toggle("Also download missing artwork", isOn: $includeCover)
            } footer: {
                Text("Search sends the title, artist, and album to LRCLIB. Artwork uses MusicBrainz and Cover Art Archive. Audio files are never sent.")
            }
            .disabled(downloading != nil)
            if error != nil { Section { Text("Couldn’t update this song. Check your connection and try again.").foregroundStyle(.secondary) } }
            if let notice { Section { Text(notice) } }
            Section("Choose a version · Duration \(playbackTime(song.duration))") {
                if !searching, results.isEmpty { Text("Edit the search fields and retry. Clear the album to broaden the search.").foregroundStyle(.secondary) }
                ForEach(results) { match in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(match.trackName).font(.headline)
                        Text("\(match.artistName) · \(match.albumName)").font(.subheadline)
                        HStack {
                            Label(match.isSynced ? "Synchronized lyrics" : (match.instrumental ? "Instrumental" : "Plain lyrics"), systemImage: match.isSynced ? "clock" : "text.alignleft")
                            Spacer()
                            Text(match.duration.map(playbackTime) ?? "Unknown duration").monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                        if let duration = match.duration, abs(duration - song.duration) > 2 {
                            Text("Duration differs by \(Int(abs(duration - song.duration))) seconds. Check the recording version.").font(.caption).foregroundStyle(.orange)
                        } else if match.duration == nil {
                            Text("No duration is provided. Check the recording version.").font(.caption).foregroundStyle(.orange)
                        }
                        Button {
                            downloadTask = Task { await apply(match) }
                        } label: {
                            HStack {
                                Text(match.text == nil ? (song.artworkID == nil ? "Download artwork" : "Artwork available") : "Use this version")
                                if downloading == match.id { ProgressView() }
                            }
                        }.disabled(downloading != nil || (match.text == nil && (!includeCover || song.artworkID != nil)))
                    }.padding(.vertical, 6)
                }
            }
            Section {
                Link("Lyrics source: LRCLIB", destination: URL(string: "https://lrclib.net")!)
                Link("Artwork source: MusicBrainz / CAA", destination: URL(string: "https://musicbrainz.org/doc/Cover_Art_Archive")!)
                Text("Check the album and recording version. Downloads are stored locally. Plain lyrics have no generated timestamps.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .localizedNavigationTitle("Lyrics and artwork").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            let query = SongLookupQuery(title: song.title, artist: song.artist, album: song.albumTitle, duration: song.duration)
            title = query.title; artist = query.artist; album = query.album
        }
        .task(id: requestID) {
            guard requestID > 0 else { return }
            searching = true; error = nil; notice = nil
            defer { searching = false }
            do {
                results = try await MusicLookupClient.shared.search(SongLookupQuery(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    artist: artist.trimmingCharacters(in: .whitespacesAndNewlines), album: album.trimmingCharacters(in: .whitespacesAndNewlines), duration: song.duration))
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .onDisappear { downloadTask?.cancel() }
    }

    private func apply(_ match: LyricsMatch) async {
        downloading = match.id; error = nil; notice = nil
        defer { downloading = nil }
        if playback.isCachedSong {
            do { try playback.applyCachedMatch(match, to: song) }
            catch { self.error = error.localizedDescription; return }
        } else {
            library.applyDownloadedMatch(match, to: song)
            if let error = library.error { self.error = error; return }
        }
        title = match.trackName; artist = match.artistName
        playback.refreshMediaInfo()
        notice = "Title and artist updated."
        if match.text != nil {
            notice = (notice ?? "") + (match.isSynced ? "Synchronized lyrics saved for offline playback." : "Plain lyrics saved. This version has no timestamps.")
        }
        if includeCover, song.artworkID == nil {
            do {
                let data = try await MusicLookupClient.shared.cover(for: match)
                try Task.checkCancellation()
                if playback.isCachedSong { try await playback.setCachedCover(data, for: song) }
                else { try await library.setDownloadedCover(song, data: data) }
                playback.refreshMediaInfo()
                notice = (notice.map { $0 + "\n" } ?? "") + "Album artwork saved."
            } catch {
                if !Task.isCancelled { self.error = "\(match.text != nil ? "Lyrics saved. " : "")Artwork: \(error.localizedDescription)" }
            }
        }
        if match.text == nil, !includeCover { error = MusicLookupError.noLyrics.localizedDescription }
    }
}
