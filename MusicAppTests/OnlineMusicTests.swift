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
        XCTAssertEqual(repeated, version, "Consecutive downloads must reuse registered plugins")
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
        let reopened = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        try await reopened.playCachedAudio(track, url: cached)
        reopened.pause()
        XCTAssertEqual(reopened.currentSong?.albumTitle, "Automatic album")
        XCTAssertEqual(reopened.currentSong?.lyrics, song.lyrics)
        XCTAssertEqual(reopened.currentSong?.artworkID, artworkID)
        XCTAssertEqual(try LibraryFiles.hash(cached), originalHash)
        XCTAssertTrue(library.songs.isEmpty)
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
