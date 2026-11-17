import XCTest
import SwiftData
import Synchronization
@testable import C0SnowMusic

@MainActor final class AudioRepositoryTests: XCTestCase {
    private let track = OnlineTrack(id: "abcdefghijk", title: "Repository song", artist: "CI", coverURL: nil)

    func testLocalCacheWinsWithoutWarehouseOrExtractorRequests() async throws {
        let files = try AudioFixtures()
        defer { files.remove() }
        let cached = try await files.seed(track)
        let cloud = await warehouse("offline")
        defer { cloud.disconnect() }
        let resolved = try await files.repository.audio(for: track, cookies: [], cloud: cloud)
        let downloads = await files.downloader.calls
        XCTAssertEqual(resolved.url, cached)
        XCTAssertNil(resolved.warehouseError)
        XCTAssertEqual(downloads, 0)
        XCTAssertFalse(WarehouseAudioProtocol.paths(host: "offline").contains { $0.contains("source_id=") })
    }

    func testWarehouseAudioIsValidatedAndCachedBeforeDelivery() async throws {
        let files = try AudioFixtures()
        defer { files.remove() }
        let cloud = await warehouse("stored")
        defer { cloud.disconnect() }
        let resolved = try await files.repository.audio(for: track, cookies: [], cloud: cloud)
        let cached = await files.cache.url(for: track.id)
        let downloads = await files.downloader.calls
        XCTAssertEqual(resolved.url, cached)
        XCTAssertEqual(try LibraryFiles.hash(resolved.url), try LibraryFiles.hash(files.fixture))
        XCTAssertEqual(downloads, 0)
        XCTAssertNil(resolved.warehouseError)
    }

    func testWithoutWarehouseExtractorAudioIsCachedAndReusable() async throws {
        let files = try AudioFixtures()
        defer { files.remove() }
        let resolved = try await files.repository.audio(for: track, cookies: [], cloud: nil)
        let reopened = try OnlineAudioCache(root: files.root.appending(path: "cache"))
        let cached = await reopened.url(for: track.id)
        let downloads = await files.downloader.calls
        XCTAssertEqual(resolved.url, cached)
        XCTAssertEqual(downloads, 1)
        XCTAssertNil(resolved.warehouseError)
    }

    func testMissingFailedAndOversizedWarehouseAudioFallsBackToExtractor() async throws {
        for host in ["empty", "offline-fallback", "missing", "pending", "oversized", "deleted-content"] {
            let files = try AudioFixtures()
            defer { files.remove() }
            let cloud = await warehouse(host)
            defer { cloud.disconnect() }
            let operation = "Repository recovery \(host)"
            let diagnosticID = AppDiagnostics.shared.begin(operation)
            defer { AppDiagnostics.shared.finish(diagnosticID) }
            let resolved = try await files.repository.audio(for: track, cookies: [], cloud: cloud, diagnosticID: diagnosticID)
            let downloads = await files.downloader.calls
            let cached = await files.cache.url(for: track.id)
            XCTAssertEqual(downloads, 1, host)
            XCTAssertEqual(resolved.url, cached, host)
            XCTAssertEqual(try LibraryFiles.hash(resolved.url), try LibraryFiles.hash(files.fixture), host)
            let messages = AppDiagnostics.shared.events.filter { $0.operation == operation }.map(\.message)
            XCTAssertTrue(messages.contains("On-device extraction"), host)
            XCTAssertTrue(messages.contains("Caching extracted audio"), host)
            if host == "empty" { XCTAssertNil(resolved.warehouseError) }
            else { XCTAssertNotNil(resolved.warehouseError, host) }
        }
    }

    func testTelegramOnlyFailureNeverInvokesYouTubeExtractor() async throws {
        let files = try AudioFixtures()
        defer { files.remove() }
        let cloud = await warehouse("telegram-missing")
        defer { cloud.disconnect() }
        let telegram = OnlineTrack(id: "tg_123_9", title: "Telegram audio", artist: "CI", coverURL: nil, kind: .telegram)
        do {
            _ = try await files.repository.audio(for: telegram, cookies: [], cloud: cloud)
            XCTFail("A Telegram-only file cannot fall back to YouTube")
        } catch { }
        let downloads = await files.downloader.calls
        let cached = await files.cache.all()
        XCTAssertEqual(downloads, 0)
        XCTAssertTrue(cached.isEmpty)
    }

    func testCancelledResolutionDoesNotStartExtractor() async throws {
        let files = try AudioFixtures()
        defer { files.remove() }
        let task = Task { @MainActor in
            try await files.repository.audio(for: track, cookies: [], cloud: nil)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled resolution must stop")
        } catch is CancellationError { }
        let downloads = await files.downloader.calls
        XCTAssertEqual(downloads, 0)
    }

    func testTelegramCachedPlaybackRecordsPlayWithoutYouTubeUpload() async throws {
        let history = UserDefaults.standard.data(forKey: "onlineListenAgain")
        defer { UserDefaults.standard.set(history, forKey: "onlineListenAgain") }
        let files = try AudioFixtures()
        defer { files.remove() }
        let track = OnlineTrack(id: "tg_123_9", title: "Telegram audio", artist: "CI", coverURL: nil, kind: .telegram)
        _ = try await files.seed(track)
        let library = try files.library()
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        defer { playback.pause() }
        let cloud = await warehouse("telegram-cached")
        defer { cloud.disconnect() }
        let online = OnlineMusicStore(cache: files.cache, downloader: files.downloader)
        online.prepare(track, play: true, playback: playback, cloud: cloud)
        for _ in 0..<100 {
            if online.downloadingID == nil, WarehouseAudioProtocol.paths(host: "telegram-cached").contains("/api/tracks/tg_123_9/play") { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let paths = WarehouseAudioProtocol.paths(host: "telegram-cached")
        XCTAssertTrue(paths.contains("/api/tracks/tg_123_9/play"))
        XCTAssertFalse(paths.contains("/api/tracks"), "Telegram tracks must not enter the YouTube upload API")
        XCTAssertNil(online.error)
        XCTAssertNil(online.backgroundError)
        XCTAssertEqual(playback.currentSong?.title, track.title)
    }

    func testCacheEvictionClearsPlaybackReferenceAndKeepsLibraryCopy() async throws {
        let files = try AudioFixtures()
        defer { files.remove() }
        let cached = try await files.seed(track)
        let library = try files.library()
        try await library.importOne(cached)
        let playback = try PlaybackStore(library: library, systemIntegration: false, lookupClient: nil)
        try await playback.playCachedAudio(track, url: cached)
        playback.pause()
        let size = Int64(try files.fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
        _ = try await files.seed(OnlineTrack(id: "12345678901", title: "Next", artist: "CI", coverURL: nil), maximumBytes: size)
        let online = OnlineMusicStore(cache: files.cache)
        await online.refresh(playback: playback)
        XCTAssertNil(playback.currentSong)
        XCTAssertTrue(playback.queue.entries.isEmpty)
        XCTAssertEqual(online.cached.map(\.id), ["12345678901"])
        let imported = try XCTUnwrap(library.songs.first)
        XCTAssertEqual(try LibraryFiles.hash(library.files.url(for: imported.fileRelativePath)), try LibraryFiles.hash(files.fixture))
    }

    private func warehouse(_ host: String) async -> CloudMusicStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WarehouseAudioProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        let cloud = CloudMusicStore(session: session, storageAccount: "test-\(UUID())")
        await cloud.connect(endpoint: "https://\(host).example.test", apiKey: "synthetic-key")
        XCTAssertTrue(cloud.connected, cloud.error ?? "")
        return cloud
    }
}

@MainActor private struct AudioFixtures {
    let root: URL
    let fixture: URL
    let cache: OnlineAudioCache
    let downloader: FixtureAudioDownloader
    var repository: AudioRepository { AudioRepository(cache: cache, downloader: downloader) }

    init() throws {
        root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        fixture = try XCTUnwrap(Bundle.main.url(forResource: "Fixture-Online", withExtension: "m4a", subdirectory: "Fixtures"))
        cache = try OnlineAudioCache(root: root.appending(path: "cache"))
        downloader = FixtureAudioDownloader(fixture: fixture)
    }

    func seed(_ track: OnlineTrack, maximumBytes: Int64 = OnlineAudioCache.maximumBytes) async throws -> URL {
        let source = root.appending(path: "\(UUID()).m4a")
        try FileManager.default.copyItem(at: fixture, to: source)
        return try await cache.insert(source, track: track, maximumBytes: maximumBytes)
    }

    func library() throws -> LibraryStore {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return try LibraryStore(context: container.mainContext, files: LibraryFiles(root: root.appending(path: "library")))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

// Replace external services only; cache validation, file persistence, SwiftData and playback stay real.
private actor FixtureAudioDownloader: AudioDownloading {
    let fixture: URL
    private(set) var calls = 0
    init(fixture: URL) { self.fixture = fixture }
    func download(_ track: OnlineTrack, directory: URL, cookies: [WebCookie]) async throws -> URL {
        calls += 1
        let url = directory.appending(path: "extracted.m4a")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }
}

private final class WarehouseAudioProtocol: URLProtocol, @unchecked Sendable {
    private static let requests = Mutex<[URL]>([])
    static func paths(host: String) -> [String] {
        requests.withLock { $0.filter { $0.host == "\(host).example.test" }.map { $0.path + ($0.query.map { "?" + $0 } ?? "") } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requests.withLock { $0.append(url) }
        let host = url.host!.components(separatedBy: ".")[0]
        var status = 200
        var data = Data(#"{"items":[],"trending":[]}"#.utf8)
        if url.query?.contains("source_id=") == true || url.path == "/api/tracks/tg_123_9" {
            if host.hasPrefix("offline") {
                status = 503; data = Data(#"{"error":"Warehouse offline"}"#.utf8)
            } else if host != "empty" {
                let available = host == "stored" || host == "deleted-content"
                let id = host.hasPrefix("telegram") ? "tg_123_9" : "yt_abcdefghijk"
                let source = host.hasPrefix("telegram") ? "null" : "\"abcdefghijk\""
                let track = """
                {"id":"\(id)","source_id":\(source),"title":"Repository song","artist":"CI","files":[{"id":"audio","available":\(available),"mime_type":"audio/mp4"}]}
                """
                data = Data((host.hasPrefix("telegram") ? track : "{\"items\":[\(track)]}").utf8)
            }
        } else if url.path.hasSuffix("/content") {
            if host == "deleted-content" { status = 404; data = Data(#"{"error":"Audio missing"}"#.utf8) }
            else {
                let fixture = Bundle.main.url(forResource: "Fixture-Online", withExtension: "m4a", subdirectory: "Fixtures")!
                data = try! Data(contentsOf: fixture)
            }
        } else if url.path == "/api/tracks" && request.httpMethod == "POST" {
            status = 400; data = Data(#"{"error":"Unexpected YouTube upload"}"#.utf8)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
