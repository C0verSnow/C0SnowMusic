import XCTest
import SwiftData
@testable import C0SnowMusic

@MainActor final class OnlineMusicTests: XCTestCase {
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
        try await cache.clear()
        let song = try XCTUnwrap(library.songs.first)
        XCTAssertEqual(try LibraryFiles.hash(library.files.url(for: song.fileRelativePath)), try LibraryFiles.hash(fixture))
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
    }
}
