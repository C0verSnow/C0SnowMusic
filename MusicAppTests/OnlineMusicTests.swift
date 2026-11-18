import XCTest
import AVFoundation
import SwiftData
import WebKit
@testable import C0SnowMusic

@MainActor final class OnlineMusicTests: XCTestCase {
    func testWebSessionRequiresLiveLoginAndRestoresKeychainCookies() async throws {
        let identifier = "test-\(UUID())"
        let account = YouTubeAccountStore(storageAccount: identifier)
        addTeardownBlock { await account.signOut() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = account.websiteData
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString("<script>window.ytcfg={get:()=>false};</script>", baseURL: URL(string: "https://m.youtube.com/"))
        var loaded = false
        for _ in 0..<100 {
            loaded = (try? await view.evaluateJavaScript("typeof window.ytcfg !== 'undefined'")) as? Bool ?? false
            if loaded { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(loaded)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "SID", .value: "synthetic-session", .domain: ".youtube.com", .path: "/", .secure: "TRUE",
            HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE",
        ]))
        await account.websiteData.httpCookieStore.setCookie(cookie)
        let cookieOnly = await account.capture(from: view)
        XCTAssertFalse(cookieOnly, "A Cookie alone must not claim login success")
        _ = try await view.evaluateJavaScript("window.ytcfg={get:()=>true};true")
        let verified = await account.capture(from: view)
        XCTAssertTrue(verified, account.error ?? "")
        let restored = YouTubeAccountStore(storageAccount: identifier)
        await restored.restore()
        XCTAssertTrue(restored.isSignedIn)
        XCTAssertEqual(restored.downloadCookies().first?.value, "synthetic-session")
        XCTAssertEqual(restored.downloadCookies().first?.httpOnly, true)
        await restored.signOut()
        let signedOut = YouTubeAccountStore(storageAccount: identifier)
        await signedOut.restore()
        XCTAssertFalse(signedOut.isSignedIn)
    }

    func testMobileSearchFiltersCardsAndPreservesEscapedTitles() throws {
        let html = #"""
        <script>var ytInitialData = {"contents":[
          {"videoWithContextRenderer":{"videoId":"abcdefghijk","title":{"runs":[{"text":"A } and \"quoted\" song"}]},"shortBylineText":{"runs":[{"text":"Artist"}]},"thumbnail":{"thumbnails":[{"url":"https://i.ytimg.com/vi/abcdefghijk/default.jpg"}]}}},
          {"compactVideoRenderer":{"videoId":"12345678901","title":{"simpleText":"Second"},"ownerText":{"runs":[{"text":"Another artist"}]}}},
          {"videoRenderer":{"videoId":"abcdefghijk","title":{"simpleText":"Duplicate"}}},
          {"playlistRenderer":{"playlistId":"PL123","title":{"simpleText":"Playlist"}}},
          {"adSlotRenderer":{"videoRenderer":{"videoId":"advertisement","title":{"simpleText":"Ad"}}}},
          {"videoRenderer":{"videoId":"../invalid","title":{"simpleText":"Invalid"}}}
        ]};</script>
        """#
        let results = try YouTubeSearchClient.parse(html)
        XCTAssertEqual(results.map(\.id), ["abcdefghijk", "12345678901"])
        XCTAssertEqual(results[0].title, "A } and \"quoted\" song")
        XCTAssertEqual(results[0].artist, "Artist")
        XCTAssertEqual(results[0].watchURL.host, "m.youtube.com")
        XCTAssertEqual(results[0].coverURL?.scheme, "https")
        XCTAssertThrowsError(try YouTubeSearchClient.parse("<html>Consent required</html>"))
    }

    func testAudioCacheEvictsOldestAndManualImportSurvives() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try OnlineAudioCache(root: root.appending(path: "cache"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "Fixture", withExtension: "m4a", subdirectory: "Fixtures"))
        let size = Int64(try fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let library = try LibraryStore(context: container.mainContext, files: LibraryFiles(root: root.appending(path: "manual")))
        for (index, id) in ["abcdefghijk", "12345678901", "ABCDEFGHIJK"].enumerated() {
            let staging = root.appending(path: "\(id).m4a")
            try FileManager.default.copyItem(at: fixture, to: staging)
            let saved = try await cache.insert(staging, track: OnlineTrack(id: id, title: "Song \(index)", artist: "Artist", coverURL: nil), maximumBytes: size * 2)
            if index == 0 { try await library.importOne(saved) }
        }
        let entries = await cache.all()
        XCTAssertEqual(entries.map(\.id), ["ABCDEFGHIJK", "12345678901"])
        XCTAssertLessThanOrEqual(entries.reduce(0) { $0 + $1.byteCount }, size * 2)
        let reopened = try OnlineAudioCache(root: root.appending(path: "cache"))
        let restored = await reopened.all()
        XCTAssertEqual(restored.map(\.id), entries.map(\.id))
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        let online = OnlineMusicStore(cache: cache)
        let current = try XCTUnwrap(entries.first)
        let currentURL = await cache.url(for: current.id)
        try await playback.playCachedAudio(current.track, url: XCTUnwrap(currentURL))
        playback.pause()
        await online.clearCache(playback: playback)
        XCTAssertNil(online.error)
        XCTAssertNil(playback.currentSong)
        XCTAssertTrue(playback.queue.entries.isEmpty)
        let song = try XCTUnwrap(library.songs.first)
        XCTAssertEqual(try LibraryFiles.hash(library.files.url(for: song.fileRelativePath)), try LibraryFiles.hash(fixture))
    }

    func testActualMobilePageHexEncodedInitialData() throws {
        let json = #"{"contents":[{"videoWithContextRenderer":{"videoId":"abcdefghijk","headline":{"runs":[{"text":"雪 and 🎵"}]},"shortBylineText":{"runs":[{"text":"Artist"}]}}}]}"#
        let escaped = json.utf16.map { String(format: "\\u%04x", $0) }.joined()
        let html = "<script>var ytInitialData = '" + escaped + "';</script>"
        XCTAssertEqual(try YouTubeSearchClient.parse(html).first?.title, "雪 and 🎵")
        let hex = json.utf16.map { $0 < 256 ? String(format: "\\x%02x", $0) : String(format: "\\u%04x", $0) }.joined()
        XCTAssertEqual(try YouTubeSearchClient.parse("<script>ytInitialData = '" + hex + "';</script>").first?.artist, "Artist")
    }

    func testCacheRejectsNonAudioWithoutCommitting() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try OnlineAudioCache(root: root)
        let source = root.appending(path: "page.m4a")
        try Data("<html>Not audio</html>".utf8).write(to: source)
        do {
            _ = try await cache.insert(source, track: OnlineTrack(id: "abcdefghijk", title: "Invalid", artist: "Artist", coverURL: nil))
            XCTFail("HTML must not become audio cache")
        } catch { }
        let entries = await cache.all()
        XCTAssertTrue(entries.isEmpty)
    }

    func testBundledPythonSSLAndWebKitProviderExecuteOnSimulator() async throws {
        let version = try await OnDeviceDownloader.shared.verifyRuntime()
        XCTAssertEqual(version, "2026.10.26")
        let repeated = try await OnDeviceDownloader.shared.verifyRuntime()
        XCTAssertEqual(repeated, version, "Consecutive checks must reuse registered plugins with fresh WebKit pages")
    }

    func testDASHAudioRemuxPreservesRealDurationAndPlayback() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "Fixture-DASH", withExtension: "m4a", subdirectory: "Fixtures"))
        let source = root.appending(path: "audio.m4a")
        try FileManager.default.copyItem(at: fixture, to: source)
        let normalized = try await OnDeviceDownloader.normalizeAudio(source, duration: 3)
        let metadata = try await MetadataExtractor.extract(normalized)
        XCTAssertEqual(metadata.duration, 3, accuracy: 0.1)
        let video = try await AVURLAsset(url: normalized).loadTracks(withMediaType: .video)
        XCTAssertTrue(video.isEmpty)
        let engine = AVPlayerEngine()
        try await engine.prepare(normalized)
        let sought = await engine.seek(to: 2.5)
        XCTAssertTrue(sought)
    }

    func testCachedPlaybackStartsWhenTheConnectedWarehouseFails() async throws {
        let previousHistory = UserDefaults.standard.data(forKey: "onlineListenAgain")
        defer { UserDefaults.standard.set(previousHistory, forKey: "onlineListenAgain") }
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try OnlineAudioCache(root: root.appending(path: "cache"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "Fixture-Online", withExtension: "m4a", subdirectory: "Fixtures"))
        let source = root.appending(path: "input.m4a")
        try FileManager.default.copyItem(at: fixture, to: source)
        let track = OnlineTrack(id: "abcdefghijk", title: "Cached song", artist: "Cached artist", coverURL: nil)
        _ = try await cache.insert(source, track: track)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let library = try LibraryStore(context: container.mainContext, files: LibraryFiles(root: root.appending(path: "library")))
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        defer { playback.pause() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingWarehouseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cloud = CloudMusicStore(session: session, storageAccount: "test-\(UUID())")
        defer { cloud.disconnect() }
        await cloud.connect(endpoint: "https://warehouse.example.test", apiKey: "synthetic-device-key")
        XCTAssertTrue(cloud.connected, cloud.error ?? "")
        let online = OnlineMusicStore(cache: cache)
        online.prepare(track, play: true, playback: playback, cloud: cloud)
        for _ in 0..<100 {
            if online.downloadingID == nil, online.backgroundError != nil, playback.currentTime > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(online.downloadingID)
        XCTAssertNil(online.error)
        XCTAssertEqual(online.backgroundError, "warehouse unavailable")
        XCTAssertEqual(playback.currentSong?.title, "Cached song")
        XCTAssertGreaterThan(playback.currentTime, 0)
        XCTAssertNil(playback.playbackError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playback.audioURL(for: try XCTUnwrap(playback.currentSong)).path))
    }

    func testPlayingOnlineAudioAutomaticallyLoadsAndPersistsLyricsCoverAndAlbum() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try OnlineAudioCache(root: root.appending(path: "cache"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "Fixture-Online", withExtension: "m4a", subdirectory: "Fixtures"))
        let source = root.appending(path: "input.m4a")
        try FileManager.default.copyItem(at: fixture, to: source)
        let track = OnlineTrack(id: "abcdefghijk", title: "Automatic song", artist: "Automatic artist", coverURL: URL(string: "https://example.com/automatic-cover.png"))
        let cached = try await cache.insert(source, track: track)
        let originalHash = try LibraryFiles.hash(cached)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let library = try LibraryStore(context: container.mainContext, files: LibraryFiles(root: root.appending(path: "library")))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OnlineEnrichmentProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let lookup = MusicLookupClient(session: session)
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: lookup)
        try await playback.playCachedAudio(track, url: cached)
        XCTAssertNotNil(playback.currentSong, "Starting playback must not await metadata requests")
        XCTAssertTrue(playback.isEnriching)
        for _ in 0..<100 {
            if !playback.isEnriching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        playback.pause()
        XCTAssertFalse(playback.isEnriching)
        XCTAssertNil(playback.enrichmentMessage)
        let song = try XCTUnwrap(playback.currentSong)
        XCTAssertEqual(song.lyrics, "[00:00.00]First line")
        XCTAssertEqual(song.albumTitle, "Automatic album")
        let artworkID = try XCTUnwrap(song.artworkID)
        let artwork = await ArtworkCache.shared.load(id: artworkID, files: library.files, thumbnail: false)
        XCTAssertNotNil(artwork)
        // Older cloud cache sidecars used an empty album even after manual lyrics/cover selection.
        song.albumTitle = ""
        try playback.setCachedLyrics(song.lyrics, for: song)
        let reopened = try PlaybackStore(library: library, systemIntegration: false, lookupClient: lookup)
        try await reopened.playCachedAudio(track, url: cached)
        for _ in 0..<100 {
            if !reopened.isEnriching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        reopened.pause()
        XCTAssertEqual(reopened.currentSong?.albumTitle, "Automatic album")
        XCTAssertEqual(reopened.currentSong?.lyrics, song.lyrics)
        XCTAssertEqual(reopened.currentSong?.artworkID, artworkID)
        XCTAssertEqual(try LibraryFiles.hash(cached), originalHash)
        XCTAssertTrue(library.songs.isEmpty)
    }

    func testOldCachedSongWithoutCoverRecoversArtworkWithoutLyricsMatch() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try OnlineAudioCache(root: root.appending(path: "cache"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "Fixture-Online", withExtension: "m4a", subdirectory: "Fixtures"))
        let source = root.appending(path: "input.m4a")
        try FileManager.default.copyItem(at: fixture, to: source)
        let track = OnlineTrack(id: "HgLfYfJtc8M", title: "One Of The Girls", artist: "The Weeknd", coverURL: nil)
        let cached = try await cache.insert(source, track: track)
        let originalHash = try LibraryFiles.hash(cached)
        let sidecar: [String: Any] = ["id": UUID().uuidString, "title": track.title, "artist": track.artist, "album": "", "lyrics": "Saved lyrics", "artworkID": "missing-old-cover"]
        try JSONSerialization.data(withJSONObject: sidecar).write(to: cached.appendingPathExtension("json"))
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let library = try LibraryStore(context: container.mainContext, files: LibraryFiles(root: root.appending(path: "library")))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MissingArtworkProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let lookup = MusicLookupClient(session: session)
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: lookup)
        try await playback.playCachedAudio(track, url: cached)
        for _ in 0..<100 {
            if !playback.isEnriching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        playback.pause()
        let song = try XCTUnwrap(playback.currentSong)
        let id = try XCTUnwrap(song.artworkID)
        let artwork = await ArtworkCache.shared.load(id: id, files: library.files, thumbnail: false)
        XCTAssertNotNil(artwork, "A missing old cover must recover from the video thumbnail even when LRCLIB is unavailable")
        XCTAssertNotEqual(id, "missing-old-cover")
        XCTAssertEqual(song.lyrics, "Saved lyrics")
        XCTAssertEqual(try LibraryFiles.hash(cached), originalHash)
        let reopened = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        try await reopened.playCachedAudio(track, url: cached)
        reopened.pause()
        XCTAssertEqual(reopened.currentSong?.artworkID, id)
        XCTAssertTrue(library.songs.isEmpty)
    }

    func testPreviouslySavedLibrarySongRecoversCoverFromMatchingYouTubeSong() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: root.appending(path: "Library.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let library = try LibraryStore(context: container.mainContext, files: LibraryFiles(root: root))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "Test Tone", withExtension: "wav", subdirectory: "Fixtures"))
        try await library.importOne(fixture)
        let song = try XCTUnwrap(library.songs.first)
        library.edit(song, title: "One of the Girls", artist: "The Weeknd", album: song.albumTitle, genre: song.genre)
        let originalHash = try LibraryFiles.hash(library.files.url(for: song.fileRelativePath))
        let network = URLSessionConfiguration.ephemeral
        network.protocolClasses = [LibraryArtworkProtocol.self]
        let session = URLSession(configuration: network)
        defer { session.invalidateAndCancel() }
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: MusicLookupClient(session: session), musicClient: YouTubeMusicClient(session: session))
        playback.play([song])
        for _ in 0..<100 {
            if !playback.isEnriching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        playback.pause()
        XCTAssertFalse(playback.isCachedSong)
        XCTAssertNil(playback.enrichmentMessage)
        let id = try XCTUnwrap(song.artworkID)
        let artwork = await ArtworkCache.shared.load(id: id, files: library.files, thumbnail: false)
        XCTAssertNotNil(artwork)
        XCTAssertEqual(try LibraryFiles.hash(library.files.url(for: song.fileRelativePath)), originalHash)
        let reopenedContainer = try ModelContainer(for: schema, configurations: [configuration])
        let reopened = try LibraryStore(context: reopenedContainer.mainContext, files: library.files)
        XCTAssertEqual(reopened.songs.first?.artworkID, id)
        XCTAssertEqual(reopened.songs.first?.title, "One of the Girls")
    }

    func testUnifiedLibraryIncludesYouTubeSongsFavoritesCacheAndHistory() throws {
        let online = OnlineMusicStore()
        let cloud = CloudMusicStore()
        let song = OnlineTrack(id: "abcdefghijk", title: "YouTube Song", artist: "Artist", coverURL: nil)
        let favorite = OnlineTrack(id: "12345678901", title: "Favorite", artist: "Artist", coverURL: nil)
        online.librarySongs = [song]; online.liked = [song, favorite]; online.history = [favorite]
        online.cached = [CachedAudio(track: song, filename: "song.m4a", byteCount: 10, createdAt: .now)]
        XCTAssertEqual(online.songs(for: .all, cloud: cloud).map(\.id), [song.id, favorite.id])
        XCTAssertEqual(online.songs(for: .favorites, cloud: cloud).map(\.id), [song.id, favorite.id])
        XCTAssertEqual(online.songs(for: .history, cloud: cloud).map(\.id), [favorite.id])
    }

    func testOnlineLyricsAndMetadataSurviveReopeningCachedAudio() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try OnlineAudioCache(root: root.appending(path: "cache"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "Fixture", withExtension: "m4a", subdirectory: "Fixtures"))
        let source = root.appending(path: "input.m4a")
        try FileManager.default.copyItem(at: fixture, to: source)
        let track = OnlineTrack(id: "abcdefghijk", title: "Online title", artist: "Online artist", coverURL: nil, albumTitle: "Online album")
        let cached = try await cache.insert(source, track: track)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let library = try LibraryStore(context: container.mainContext, files: LibraryFiles(root: root.appending(path: "library")))
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        try await playback.playCachedAudio(track, url: cached)
        playback.pause()
        let song = try XCTUnwrap(playback.currentSong)
        let identity = song.id
        let match = try JSONDecoder().decode(LyricsMatch.self, from: Data(#"{"id":1,"trackName":"Online title","artistName":"Online artist","albumName":"Matched album","duration":3,"instrumental":false,"plainLyrics":null,"syncedLyrics":"[00:00.00]Saved online lyrics"}"#.utf8))
        try playback.applyCachedMatch(match, to: song)
        let reopened = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        try await reopened.playCachedAudio(track, url: cached)
        reopened.pause()
        XCTAssertEqual(reopened.currentSong?.id, identity)
        XCTAssertEqual(reopened.currentSong?.lyrics, "[00:00.00]Saved online lyrics")
        XCTAssertEqual(reopened.currentSong?.albumTitle, "Matched album")
        XCTAssertTrue(library.songs.isEmpty, "Cache metadata must not create library records")
        try await cache.remove(track.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cached.appendingPathExtension("json").path))
    }
}

// Only the external HTTP boundary is replaced; playback, image decoding and cache persistence are real.
private final class OnlineEnrichmentProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let image = url.host == "example.com"
        let data = image ? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg==")! : Data(#"{"id":1,"trackName":"Automatic song","artistName":"Automatic artist","albumName":"Automatic album","duration":3,"instrumental":false,"plainLyrics":null,"syncedLyrics":"[00:00.00]First line"}"#.utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": image ? "image/png" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class FailingWarehouseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let failure = url.query?.contains("source_id=") == true
        let response = HTTPURLResponse(url: url, statusCode: failure ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let data = Data((failure ? #"{"error":"warehouse unavailable"}"# : #"{"items":[],"trending":[]}"#).utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class MissingArtworkProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let image = url.host == "i.ytimg.com" && url.path == "/vi/HgLfYfJtc8M/hqdefault.jpg"
        let data = image ? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg==")! : Data()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: image ? 200 : 503, httpVersion: nil, headerFields: ["Content-Type": image ? "image/png" : "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class LibraryArtworkProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let image = url.host == "i.ytimg.com"
        let data: Data
        if image {
            data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg==")!
        } else if request.httpMethod != "POST" {
            data = Data(#"<script>ytcfg.set({"INNERTUBE_CONTEXT":{"client":{"clientVersion":"test"}}});</script>"#.utf8)
        } else {
            data = Data(#"""
            {"contents":{"musicShelfRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
              "playlistItemData":{"videoId":"HgLfYfJtc8M"},
              "flexColumns":[
                {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"One Of The Girls"}]}}},
                {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[
                  {"text":"The Weeknd","navigationEndpoint":{"browseEndpoint":{"browseId":"UC_main"}}},
                  {"text":", "},{"text":"JENNIE","navigationEndpoint":{"browseEndpoint":{"browseId":"UC_guest"}}}
                ]}}}
              ]
            }}]}}}
            """#.utf8)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": image ? "image/png" : "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
