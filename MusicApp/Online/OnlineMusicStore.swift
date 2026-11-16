import AVFoundation
import Observation
import SwiftUI

@MainActor @Observable final class OnlineMusicStore {
    var results: [OnlineTrack] = []
    var sections: [MusicSection] = []
    var home: [MusicSection] = []
    var liked: [OnlineTrack] = []
    var history: [OnlineTrack] = (UserDefaults.standard.data(forKey: "onlineListenAgain").flatMap { try? JSONDecoder().decode([OnlineTrack].self, from: $0) }) ?? []
    var searchHistory: [String] = UserDefaults.standard.stringArray(forKey: "musicSearchHistory") ?? []
    var filter: MusicSearchFilter = .all
    var continuation: String?
    var syncing = false
    var loadingHome = false
    var cached: [CachedAudio] = []
    var searching = false
    var downloadingID: String?
    var error: String?
    @ObservationIgnored private var cache: OnlineAudioCache?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(cache: OnlineAudioCache? = nil) {
        do { self.cache = try cache ?? OnlineAudioCache() }
        catch { self.error = error.localizedDescription }
    }

    var cacheBytes: Int64 { cached.reduce(0) { $0 + $1.byteCount } }

    func refresh() async {
        cached = await cache?.all() ?? []
    }

    func search(_ query: String, cookies: [WebCookie] = [], more: Bool = false) {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = more ? continuation : nil
        if !more { results = []; sections = []; continuation = nil }
        error = nil
        guard !query.isEmpty else { searching = false; return }
        searchHistory.removeAll { $0 == query }; searchHistory.insert(query, at: 0)
        searchHistory = Array(searchHistory.prefix(20))
        UserDefaults.standard.set(searchHistory, forKey: "musicSearchHistory")
        searching = true
        searchTask = Task {
            do {
                let page = try await YouTubeMusicClient().search(query, filter: filter, continuation: token, cookies: cookies)
                try Task.checkCancellation()
                sections += page.sections.enumerated().map { index, section in MusicSection(id: "\(sections.count + index)", title: section.title, items: section.items) }
                results = sections.flatMap(\.items)
                continuation = page.continuation; searching = false
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                searching = false; self.error = error.localizedDescription
            }
        }
    }

    func prepare(_ track: OnlineTrack, play: Bool = false, saveTo library: LibraryStore? = nil, playback: PlaybackStore? = nil, cookies: [WebCookie] = [], cloud: CloudMusicStore? = nil) {
        guard track.isPlayable, downloadTask == nil else { return }
        downloadingID = track.id; error = nil
        downloadTask = Task {
            defer { downloadingID = nil; downloadTask = nil }
            do {
                guard let cache else { throw OnlineMusicError.runtimeUnavailable }
                let url: URL
                let cachedURL = await cache.url(for: track.id)
                if let cachedURL {
                    url = cachedURL
                } else {
                    let directory = URL.cachesDirectory.appending(path: "OnlineStaging/\(UUID())")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    var stored: URL?
                    if let cloud, cloud.connected { stored = try await cloud.download(track, directory: directory) }
                    let downloaded: URL
                    if let stored { downloaded = stored }
                    else {
                        guard track.kind != .telegram else { throw OnlineMusicError.invalidAudio }
                        downloaded = try await OnDeviceDownloader.shared.download(track, directory: directory, cookies: cookies)
                        if let cloud, cloud.connected { try await cloud.upload(track, file: downloaded) }
                    }
                    try Task.checkCancellation()
                    url = try await cache.insert(downloaded, track: track)
                }
                await refresh()
                if let library {
                    let existing = Set(library.songs.map(\.id))
                    let imported = try await library.importOne(url)
                    if imported, let song = library.songs.first(where: { !existing.contains($0.id) }) {
                        library.edit(song, title: track.title, artist: track.artist, album: track.albumTitle ?? song.albumTitle, genre: song.genre)
                        if song.artworkID == nil, let cover = track.coverURL, let data = try? await MusicLookupClient.shared.artwork(at: cover) {
                            try await library.setDownloadedCover(song, data: data)
                        }
                    }
                }
                if play, let playback {
                    try await playback.playCachedAudio(track, url: url)
                    history.removeAll { $0.id == track.id }; history.insert(track, at: 0)
                    history = Array(history.prefix(30))
                    UserDefaults.standard.set(try JSONEncoder().encode(history), forKey: "onlineListenAgain")
                }
                if let cloud, cloud.connected {
                    // A slow or unavailable warehouse must not block cached playback.
                    Task {
                        do {
                            if let cachedURL, try await cloud.existing(track)?.files.contains(where: \.available) != true {
                                try await cloud.upload(track, file: cachedURL)
                            }
                            if play { await cloud.recordPlay(track) }
                        } catch { self.error = error.localizedDescription }
                    }
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func resetSession() {
        searchTask?.cancel(); downloadTask?.cancel(); results = []; sections = []; home = []; liked = []; history = []; continuation = nil; searching = false; error = nil
        UserDefaults.standard.removeObject(forKey: "onlineListenAgain")
    }

    func resetSearch() {
        searchTask?.cancel(); results = []; sections = []; continuation = nil; searching = false; error = nil
    }

    func clearSearchHistory() { searchHistory = []; UserDefaults.standard.removeObject(forKey: "musicSearchHistory") }

    func loadHome(cookies: [WebCookie]) async {
        guard !loadingHome else { return }
        loadingHome = true
        defer { loadingHome = false }
        do { home = try await YouTubeMusicClient().browse("FEmusic_home", cookies: cookies).sections }
        catch { self.error = error.localizedDescription }
    }

    func syncFavorites(cookies: [WebCookie], cloud: CloudMusicStore) async {
        guard !syncing else { return }
        syncing = true; error = nil
        defer { syncing = false }
        do {
            let complete = try await YouTubeMusicClient().likedTracks(cookies: cookies)
            try Task.checkCancellation()
            if cloud.connected { try await cloud.syncYouTubeFavorites(complete) }
            liked = complete
        } catch { self.error = error.localizedDescription }
    }

    func setLiked(_ track: OnlineTrack, liked value: Bool, cookies: [WebCookie], cloud: CloudMusicStore) async {
        guard !syncing else { return }
        syncing = true; error = nil
        defer { syncing = false }
        do {
            try await YouTubeMusicClient().setLiked(value, id: track.id, cookies: cookies)
            let complete = try await YouTubeMusicClient().likedTracks(cookies: cookies)
            if cloud.connected { try await cloud.syncYouTubeFavorites(complete) }
            liked = complete
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ entry: CachedAudio, playback: PlaybackStore) async {
        do {
            playback.forgetCachedAudio(entry.id)
            try await cache?.remove(entry.id); await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func clearCache(playback: PlaybackStore) async {
        do { playback.forgetCachedAudio(); try await cache?.clear(); await refresh() }
        catch { self.error = error.localizedDescription }
    }

}
