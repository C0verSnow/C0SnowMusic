import AVFoundation
import Foundation
import SwiftUI
import Observation
import SwiftData

@MainActor @Observable final class PlaybackStore {
    let files: LibraryFiles
    var currentSong: Song?
    var isPlaying = false
    var isLoading = false
    var currentTime: Double = 0
    var duration: Double { currentSong?.duration ?? 0 }
    var queue = QueueManager()
    var currentQueueIndex: Int { queue.index }
    var repeatMode: RepeatMode = .off
    var shuffleEnabled = false
    var playbackError: String?
    var isEnriching = false
    var enrichmentMessage: String?
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private var engine: any PlayerEngine
    @ObservationIgnored private let audioSession = AudioSessionManager()
    @ObservationIgnored private let remote = RemoteCommandManager()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var lastSavedTime: Double = 0
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var session: PlaybackSession
    @ObservationIgnored private var enrichmentTask: Task<Void, Never>?
    @ObservationIgnored private let lookupClient: MusicLookupClient?
    @ObservationIgnored private let musicClient: YouTubeMusicClient
    @ObservationIgnored private var cachedSongs: [UUID: Song] = [:]
    @ObservationIgnored private var cachedURLs: [UUID: URL] = [:]

    var isCachedSong: Bool { currentSong.map { cachedURLs[$0.id] != nil } ?? false }

    func playCachedAudio(_ track: OnlineTrack, url: URL) async throws {
        enrichmentTask?.cancel(); isEnriching = false; enrichmentMessage = nil
        var metadata = try await MetadataExtractor.extract(url)
        metadata.title = track.title; metadata.artist = track.artist
        if let album = track.albumTitle { metadata.album = album }
        let saved = (try? Data(contentsOf: url.appendingPathExtension("json"))).flatMap { try? JSONDecoder().decode(CachedSongDetails.self, from: $0) }
        if let saved { metadata.title = saved.title; metadata.artist = LegacyMetadata.english(saved.artist); metadata.album = LegacyMetadata.english(saved.album); metadata.lyrics = saved.lyrics }
        if metadata.album.isEmpty { metadata.album = "Unknown album" }
        let song = Song(id: saved?.id ?? UUID(), metadata: metadata, path: url.path, hash: "", size: Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), artworkID: saved?.artworkID)
        if let id = song.artworkID, !FileManager.default.fileExists(atPath: files.artworkURL(id, thumbnail: false).path) {
            song.artworkID = nil
        }
        cachedSongs = [song.id: song]; cachedURLs = [song.id: url]
        if song.artworkID == nil, let embedded = metadata.artwork { try? await setCachedCover(embedded, for: song) }
        try saveCachedDetails(song)
        play([song])
        if let lookupClient, song.lyrics.isEmpty || song.artworkID == nil || song.albumTitle == "Unknown album" {
            isEnriching = true
            enrichmentTask = Task {
                defer { if currentSong?.id == song.id { isEnriching = false } }
                do { try await enrichOnlineSong(song, track: track, client: lookupClient) }
                catch is CancellationError { }
                catch { if currentSong?.id == song.id { enrichmentMessage = error.localizedDescription } }
            }
        }
    }

    func applyCachedMatch(_ match: LyricsMatch, to song: Song, keepExistingLyrics: Bool = false) throws {
        if !keepExistingLyrics { enrichmentTask?.cancel(); isEnriching = false; enrichmentMessage = nil }
        song.title = match.trackName; song.artist = match.artistName
        if !match.albumName.isEmpty { song.albumTitle = match.albumName }
        if let text = match.text, !keepExistingLyrics || song.lyrics.isEmpty { song.lyrics = text }
        try saveCachedDetails(song); refreshMediaInfo()
    }

    func setCachedLyrics(_ lyrics: String, for song: Song) throws {
        song.lyrics = lyrics; try saveCachedDetails(song)
    }

    func setCachedCover(_ data: Data, for song: Song) async throws {
        let id = song.artworkID ?? "online-\(song.id)"
        guard try await ArtworkCache.shared.save(data, id: id, files: files) else { throw MusicLookupError.invalidResponse }
        song.artworkID = id; try saveCachedDetails(song); refreshMediaInfo()
    }

    private func enrichOnlineSong(_ song: Song, track: OnlineTrack, client: MusicLookupClient) async throws {
        // Cover failure must not discard playable audio.
        if song.artworkID == nil {
            for cover in track.artworkURLs {
                do {
                    let data = try await client.artwork(at: cover)
                    try Task.checkCancellation()
                    try await setCachedCover(data, for: song)
                    break
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
            }
        }
        if song.lyrics.isEmpty || song.albumTitle == "Unknown album" || song.artworkID == nil {
            let query = SongLookupQuery(title: song.title, artist: song.artist, album: song.albumTitle, duration: song.duration)
            let matches = try await client.search(query)
            try Task.checkCancellation()
            guard let match = LyricsMatch.automatic(in: matches, for: query) else {
                enrichmentMessage = AppLanguage.text("Choose a lyrics and album version; no unique exact match was found.")
                return
            }
            try applyCachedMatch(match, to: song, keepExistingLyrics: true)
            if song.artworkID == nil {
                let data = try await client.cover(for: match)
                try Task.checkCancellation()
                try await setCachedCover(data, for: song)
            }
        }
    }

    private func enrichLibraryArtwork(_ song: Song, client: MusicLookupClient) async throws {
        let query = SongLookupQuery(title: song.title, artist: song.artist, album: song.albumTitle, duration: song.duration)
        if !query.artist.isEmpty {
            do {
                let page = try await musicClient.search("\(query.title) \(query.artist)", filter: .songs, cookies: [])
                let track = page.tracks.first {
                    LyricsMatch.normalized($0.title) == LyricsMatch.normalized(query.title)
                    && $0.artist.split(separator: ",").contains { LyricsMatch.normalized(String($0)) == LyricsMatch.normalized(query.artist) }
                }
                if let track {
                    for cover in track.artworkURLs {
                        do {
                            let data = try await client.artwork(at: cover)
                            try Task.checkCancellation()
                            try await library.setDownloadedCover(song, data: data)
                            refreshMediaInfo()
                            return
                        } catch is CancellationError { throw CancellationError() }
                        catch { continue }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { }
        }
        let matches = try await client.search(query)
        try Task.checkCancellation()
        if let match = LyricsMatch.automatic(in: matches, for: query) {
            let data = try await client.cover(for: match)
            try Task.checkCancellation()
            try await library.setDownloadedCover(song, data: data)
            refreshMediaInfo()
        }
    }

    private func saveCachedDetails(_ song: Song) throws {
        guard let url = cachedURLs[song.id] else { return }
        try JSONEncoder().encode(CachedSongDetails(id: song.id, title: song.title, artist: song.artist, album: song.albumTitle, lyrics: song.lyrics, artworkID: song.artworkID)).write(to: url.appendingPathExtension("json"), options: .atomic)
    }

    func audioURL(for song: Song) -> URL { cachedURLs[song.id] ?? files.url(for: song.fileRelativePath) }

    func forgetCachedAudio(_ videoID: String? = nil) {
        let ids = cachedURLs.filter { videoID == nil || $0.value.deletingPathExtension().lastPathComponent == videoID }.map(\.key)
        for id in ids {
            removeSong(id)
            cachedSongs.removeValue(forKey: id); cachedURLs.removeValue(forKey: id)
        }
    }

    func forgetMissingCachedAudio() {
        let missing = cachedURLs.values.filter { !FileManager.default.fileExists(atPath: $0.path) }
        for url in missing { forgetCachedAudio(url.deletingPathExtension().lastPathComponent) }
    }

    init(library: LibraryStore, engine: any PlayerEngine = AVPlayerEngine(), systemIntegration: Bool = true, lookupClient: MusicLookupClient? = .shared, musicClient: YouTubeMusicClient = YouTubeMusicClient()) throws {
        self.library = library; files = library.files; self.engine = engine; self.lookupClient = lookupClient; self.musicClient = musicClient
        if let saved = try library.context.fetch(FetchDescriptor<PlaybackSession>()).first { session = saved }
        else {
            session = PlaybackSession()
            library.context.insert(session)
            try library.context.save()
        }
        bindEngine()
        if systemIntegration { audioSession.observe(self); remote.connect(self) }
        restore()
    }

    func play(_ songs: [Song], startingAt index: Int = 0, shuffled: Bool = false) {
        guard !songs.isEmpty else { return }
        queue.replace(songs.map(\.id), startingAt: index)
        shuffleEnabled = shuffled
        if shuffled { queue.shuffleUpcoming() }
        loadCurrent(autoplay: true)
    }

    func resume() {
        guard currentSong != nil else { return }
        wantsPlayback = true
        if !prepared { loadCurrent(autoplay: true, position: currentTime); return }
        do { try audioSession.activate(); engine.play() }
        catch { playbackError = error.localizedDescription; wantsPlayback = false }
    }

    func pause() {
        wantsPlayback = false; engine.pause(); isPlaying = false
        saveSession(); remote.update(self)
    }

    func toggle() { if isPlaying || wantsPlayback { pause() } else { resume() } }

    func seek(to seconds: Double) {
        let position = min(max(0, seconds), duration)
        currentTime = position
        guard prepared else { saveSession(); return }
        let entryID = queue.current?.id
        seekTask?.cancel()
        seekTask = Task {
            let success = await engine.seek(to: position)
            guard !Task.isCancelled, queue.current?.id == entryID else { return }
            if !success { playbackError = "Cannot seek to this position." }
            currentTime = position; saveSession(); remote.update(self)
            seekTask = nil
        }
    }

    func next(automatic: Bool = false) {
        if queue.advance(automatic: automatic, repeatMode: repeatMode) {
            loadCurrent(autoplay: true)
        } else {
            pause()
            if automatic { currentTime = 0; prepared = false; engine.stop() }
            saveSession()
        }
    }

    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        if queue.index > 0 { queue.index -= 1 }
        else if repeatMode == .all { queue.index = max(0, queue.entries.count - 1) }
        loadCurrent(autoplay: true)
    }

    func enqueue(_ song: Song, next: Bool) {
        queue.insert(song.id, next: next)
        if currentSong == nil { loadCurrent(autoplay: false) }
        saveSession()
    }

    func jump(to index: Int) { queue.index = index; loadCurrent(autoplay: true) }

    func removeQueueEntries(at offsets: IndexSet) {
        let playingEntry = queue.current?.id
        queue.remove(offsets)
        if playingEntry != queue.current?.id { loadCurrent(autoplay: isPlaying) }
        saveSession()
    }

    func moveQueueEntries(from offsets: IndexSet, to destination: Int) {
        let playingID = queue.current?.id
        queue.entries.move(fromOffsets: offsets, toOffset: destination)
        queue.index = queue.entries.firstIndex { $0.id == playingID } ?? 0
        saveSession()
    }

    func removeSong(_ id: UUID) {
        removeQueueEntries(at: IndexSet(queue.entries.indices.filter { queue.entries[$0].songID == id }))
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled { queue.shuffleUpcoming() }
        saveSession()
    }

    func cycleRepeat() {
        switch repeatMode { case .off: repeatMode = .all; case .all: repeatMode = .one; case .one: repeatMode = .off }
        saveSession()
    }

    func song(for entry: QueueEntry) -> Song? { cachedSongs[entry.songID] ?? library.songs.first { $0.id == entry.songID } }

    func refreshMediaInfo() { remote.update(self) }

    func saveSession() {
        session.currentSongID = currentSong?.id; session.currentPosition = currentTime
        session.repeatMode = repeatMode.rawValue; session.shuffleEnabled = shuffleEnabled
        session.queueSnapshot = queue.entries.map(\.songID); session.currentQueueIndex = queue.index
        do { try library.context.save(); lastSavedTime = currentTime }
        catch { playbackError = "Unable to save playback progress." }
    }

    func reloadAfterAudioReset() {
        pause(); engine.stop(); engine = AVPlayerEngine(); bindEngine()
        loadCurrent(autoplay: false, position: currentTime)
    }

    private func bindEngine() {
        engine.onTime = { [weak self] seconds in
            guard let self, !self.isLoading, self.seekTask == nil || self.seekTask?.isCancelled == true else { return }
            self.currentTime = seconds
            if abs(seconds - self.lastSavedTime) >= 5 { self.saveSession() }
            self.remote.update(self)
        }
        engine.onPlaying = { [weak self] playing in
            guard let self else { return }
            self.isPlaying = playing
            self.remote.update(self)
        }
        engine.onEnded = { [weak self] in self?.next(automatic: true) }
        engine.onError = { [weak self] message in self?.pause(); self?.prepared = false; self?.playbackError = message }
    }

    private func loadCurrent(autoplay: Bool, position: Double = 0) {
        loadTask?.cancel(); seekTask?.cancel(); seekTask = nil
        engine.pause(); isPlaying = false; prepared = false
        guard let entry = queue.current, let song = song(for: entry) else {
            enrichmentTask?.cancel(); isEnriching = false; enrichmentMessage = nil
            currentSong = nil; currentTime = 0; isLoading = false; wantsPlayback = false
            engine.stop(); saveSession(); remote.update(self); return
        }
        if currentSong?.id != song.id {
            enrichmentTask?.cancel(); isEnriching = false; enrichmentMessage = nil
        }
        currentSong = song; currentTime = position; isLoading = true
        if cachedURLs[song.id] == nil, song.artworkID == nil, let lookupClient {
            isEnriching = true
            enrichmentTask = Task {
                defer { if currentSong?.id == song.id { isEnriching = false } }
                do { try await enrichLibraryArtwork(song, client: lookupClient) }
                catch is CancellationError { }
                catch { if currentSong?.id == song.id { enrichmentMessage = error.localizedDescription } }
            }
        }
        wantsPlayback = autoplay; playbackError = nil
        saveSession(); remote.update(self)
        loadTask = Task {
            do {
                try await engine.prepare(audioURL(for: song))
                try Task.checkCancellation()
                if position > 0 { _ = await engine.seek(to: min(position, song.duration)) }
                try Task.checkCancellation()
                prepared = true; isLoading = false
                if wantsPlayback {
                    try audioSession.activate()
                    song.lastPlayedAt = .now; song.playCount += 1
                    saveSession(); engine.play()
                }
                remote.update(self)
            } catch is CancellationError { }
            catch {
                isLoading = false; wantsPlayback = false
                playbackError = error.localizedDescription
            }
        }
    }

    private func restore() {
        let available = Set(library.songs.map(\.id))
        let savedQueue = session.queueSnapshot
        let oldIndex = session.currentQueueIndex
        let keptBefore = savedQueue.prefix(max(0, min(oldIndex, savedQueue.count))).filter { available.contains($0) }.count
        queue.replace(savedQueue.filter { available.contains($0) }, startingAt: keptBefore)
        repeatMode = RepeatMode(rawValue: session.repeatMode) ?? .off
        shuffleEnabled = session.shuffleEnabled
        currentSong = queue.current.flatMap { song(for: $0) }
        currentTime = min(session.currentPosition, currentSong?.duration ?? 0)
        // Restoration never activates the audio session or starts sound.
        remote.update(self)
    }
}

private struct CachedSongDetails: Codable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let lyrics: String
    let artworkID: String?
}
