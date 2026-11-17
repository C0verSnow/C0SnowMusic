import AVFoundation
import Observation
import SwiftUI

@MainActor @Observable final class OnlineMusicStore {
    var results: [OnlineTrack] = []
    var sections: [MusicSection] = []
    var home: [MusicSection] = []
    var liked: [OnlineTrack] = []
    var librarySongs: [OnlineTrack] = []
    var playlists: [OnlineTrack] = []
    var albums: [OnlineTrack] = []
    var artists: [OnlineTrack] = []
    var libraryError: String?
    var homeError: String?
    var loadingLibrary = false
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
    var searchError: String?
    var backgroundError: String?
    @ObservationIgnored private var cache: OnlineAudioCache?
    @ObservationIgnored private let downloader: any AudioDownloading
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(cache: OnlineAudioCache? = nil, downloader: any AudioDownloading = OnDeviceDownloader.shared) {
        self.downloader = downloader
        do { self.cache = try cache ?? OnlineAudioCache() }
        catch { self.error = error.localizedDescription }
    }

    var cacheBytes: Int64 { cached.reduce(0) { $0 + $1.byteCount } }

    func refresh(playback: PlaybackStore? = nil) async {
        cached = await cache?.all() ?? []
        playback?.forgetMissingCachedAudio()
    }

    func search(_ query: String, cookies: [WebCookie] = [], more: Bool = false) {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = more ? continuation : nil
        if !more { results = []; sections = []; continuation = nil }
        searchError = nil
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
                searching = false; searchError = error.localizedDescription
            }
        }
    }

    func prepare(_ track: OnlineTrack, play: Bool = false, saveTo library: LibraryStore? = nil, playback: PlaybackStore? = nil, cookies: [WebCookie] = [], cloud: CloudMusicStore? = nil) {
        guard track.isPlayable, downloadTask == nil else { return }
        downloadingID = track.id; error = nil; backgroundError = nil
        downloadTask = Task {
            defer { playback?.forgetMissingCachedAudio(); downloadingID = nil; downloadTask = nil }
            do {
                guard let cache else { throw OnlineMusicError.runtimeUnavailable }
                let resolved = try await AudioRepository(cache: cache, downloader: downloader).audio(for: track, cookies: cookies, cloud: cloud)
                let url = resolved.url
                backgroundError = resolved.warehouseError
                try Task.checkCancellation()
                await refresh()
                if let library {
                    let existing = Set(library.songs.map(\.id))
                    let imported = try await library.importOne(url)
                    if imported, let song = library.songs.first(where: { !existing.contains($0.id) }) {
                        library.edit(song, title: track.title, artist: track.artist, album: track.albumTitle ?? song.albumTitle, genre: song.genre)
                        if song.artworkID == nil {
                            for cover in track.artworkURLs {
                                do {
                                    let data = try await MusicLookupClient.shared.artwork(at: cover)
                                    try await library.setDownloadedCover(song, data: data)
                                    break
                                } catch { continue }
                            }
                        }
                    }
                }
                try Task.checkCancellation()
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
                            if track.kind != .telegram, try await cloud.existing(track)?.files.contains(where: \.available) != true {
                                try await cloud.upload(track, file: url)
                            }
                            if play { await cloud.recordPlay(track) }
                        } catch { backgroundError = error.localizedDescription }
                    }
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func resetSession() {
        searchTask?.cancel(); downloadTask?.cancel(); results = []; sections = []; home = []; liked = []; librarySongs = []; playlists = []; albums = []; artists = []; libraryError = nil; homeError = nil; history = []; continuation = nil; searching = false; error = nil; searchError = nil
        UserDefaults.standard.removeObject(forKey: "onlineListenAgain")
    }

    func resetSearch() {
        searchTask?.cancel(); results = []; sections = []; continuation = nil; searching = false; searchError = nil
    }

    func clearSearchHistory() { searchHistory = []; UserDefaults.standard.removeObject(forKey: "musicSearchHistory") }

    func loadHome(cookies: [WebCookie]) async {
        guard !loadingHome else { return }
        loadingHome = true; homeError = nil
        defer { loadingHome = false }
        do { home = try await YouTubeMusicClient().browse("FEmusic_home", cookies: cookies).sections }
        catch { homeError = error.localizedDescription }
    }

    func loadLibrary(cookies: [WebCookie], cloud: CloudMusicStore, client: YouTubeMusicClient = YouTubeMusicClient()) async {
        guard !loadingLibrary else { return }
        loadingLibrary = true; libraryError = nil
        defer { loadingLibrary = false }
        // A failed category retains its previous contents; categories refresh independently.
        for id in ["VLLM", "FEmusic_liked_videos", "FEmusic_liked_playlists", "FEmusic_liked_albums", "FEmusic_library_corpus_track_artists", "FEmusic_library_corpus_artists"] {
            do {
                let items = try await client.collectionItems(id, cookies: cookies)
                try Task.checkCancellation()
                switch id {
                case "VLLM":
                    liked = items.filter(\.isPlayable)
                    if cloud.connected { try await cloud.syncYouTubeFavorites(liked) }
                case "FEmusic_liked_videos": librarySongs = items.filter(\.isPlayable)
                case "FEmusic_liked_playlists": playlists = items.filter { $0.kind == .playlist }
                case "FEmusic_liked_albums": albums = items.filter { $0.kind == .album }
                case "FEmusic_library_corpus_track_artists": artists = items.filter { $0.kind == .artist }
                default:
                    var seen = Set(artists.map(\.id))
                    artists += items.filter { $0.kind == .artist && seen.insert($0.id).inserted }
                }
            } catch is CancellationError { return }
            catch { libraryError = error.localizedDescription }
        }
        if cloud.connected { await cloud.refresh() }
    }

    func songs(for filter: SongFilter, cloud: CloudMusicStore) -> [OnlineTrack] {
        let items: [OnlineTrack]
        switch filter {
        case .history: items = history
        case .favorites: items = liked + cloud.favorites.map(\.onlineTrack)
        case .all, .recent: items = librarySongs + liked + cloud.favorites.map(\.onlineTrack) + cached.map(\.track)
        }
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
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
