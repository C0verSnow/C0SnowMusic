import XCTest
import SwiftData
import UIKit
@testable import C0SnowMusic

@MainActor final class LibraryIntegrationTests: XCTestCase {
    private func makeLibrary(root: URL? = nil) throws -> LibraryStore {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration: ModelConfiguration
        if let root { configuration = ModelConfiguration(schema: schema, url: root.appending(path: "library.store"), cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration])
        let directory = root ?? URL.temporaryDirectory.appending(path: UUID().uuidString)
        return try LibraryStore(context: container.mainContext, files: LibraryFiles(root: directory))
    }

    private func fixture(_ name: String, ext: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    func testImportEveryTargetFormatAndHighResolutionPCM() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        for (name, ext) in [("Test Tone", "wav"), ("Fixture", "mp3"), ("Fixture", "flac"), ("Fixture", "m4a"),
                            ("Fixture", "aac"), ("Fixture-ALAC", "m4a"), ("Fixture", "aiff"),
                            ("Fixture-24bit-96k", "flac"), ("Fixture-24bit-96k", "wav")] {
            let imported = try await library.importOne(fixture(name, ext: ext))
            XCTAssertTrue(imported, "\(name).\(ext)")
        }
        XCTAssertEqual(library.songs.count, 9)
        XCTAssertTrue(library.songs.allSatisfy { $0.duration > 2.5 && $0.duration < 3.5 })
        XCTAssertTrue(library.songs.allSatisfy { FileManager.default.fileExists(atPath: library.files.url(for: $0.fileRelativePath).path) })
        let flac = try XCTUnwrap(library.songs.first { $0.format == "FLAC" })
        XCTAssertEqual(flac.title, "雪の音")
        XCTAssertEqual(flac.artist, "C0Snow CI")
        XCTAssertEqual(flac.trackNumber, 2)
        XCTAssertTrue(library.songs.contains { $0.sampleRate == 96_000 && $0.channels == 2 })
        XCTAssertNotNil(flac.albumID)
        XCTAssertNotNil(flac.artistID)
    }

    func testEmbeddedLyricsSurviveMP3AndFLACImport() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        for ext in ["mp3", "flac"] {
            try await library.importOne(fixture("Fixture", ext: ext))
        }
        XCTAssertEqual(library.songs.count, 2)
        for song in library.songs { XCTAssertTrue(song.lyrics.contains("First line"), song.format) }
    }

    func testDuplicateBytesWithDifferentNamesAndKeepCopy() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        let original = try fixture("Fixture", ext: "mp3")
        let renamed = try fixture("中文 日本語 & ♫", ext: "mp3")
        let first = try await library.importOne(original)
        let duplicate = try await library.importOne(renamed)
        XCTAssertTrue(first); XCTAssertFalse(duplicate)
        library.duplicatePolicy = .keepCopy
        let copy = try await library.importOne(renamed)
        XCTAssertTrue(copy)
        XCTAssertEqual(library.songs.count, 2)
        XCTAssertEqual(Set(library.songs.map(\.fileHash)).count, 1)
        XCTAssertEqual(Set(library.songs.map(\.fileRelativePath)).count, 2)
    }

    func testCorruptImportCleansStagingAndDoesNotWriteDatabase() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        do { try await library.importOne(fixture("Corrupt", ext: "flac")); XCTFail("Corrupt file was accepted") }
        catch { XCTAssertTrue(library.songs.isEmpty) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.files.url(for: "Staging").path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.files.url(for: "Audio").path).isEmpty)
    }

    func testMissingMetadataUsesOriginalFilename() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        try await library.importOne(fixture("Test Tone", ext: "wav"))
        let song = try XCTUnwrap(library.songs.first)
        XCTAssertEqual(song.title, "Test Tone")
        XCTAssertEqual(song.artist, "未知艺术家")
        XCTAssertNil(song.artworkID)
    }

    func testDiskPersistenceAndSilentSessionRestoration() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var first: LibraryStore? = try makeLibrary(root: root)
        try await first!.importOne(fixture("Test Tone", ext: "wav"))
        let player = try PlaybackStore(library: first!, systemIntegration: false)
        player.enqueue(try XCTUnwrap(first?.songs.first), next: false)
        player.pause(); player.seek(to: 1.25); player.cycleRepeat(); player.toggleShuffle(); player.saveSession()
        let second = try makeLibrary(root: root)
        let restored = try PlaybackStore(library: second, systemIntegration: false)
        XCTAssertEqual(second.songs.count, 1)
        XCTAssertEqual(restored.currentSong?.title, "Test Tone")
        XCTAssertEqual(restored.currentTime, 1.25, accuracy: 0.01)
        XCTAssertEqual(restored.repeatMode, .all)
        XCTAssertTrue(restored.shuffleEnabled)
        XCTAssertFalse(restored.isPlaying)
        first = nil
    }

    func testPlaylistOrderMetadataRegroupFavoriteAndDeletion() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        try await library.importOne(fixture("Test Tone", ext: "wav"))
        try await library.importOne(fixture("Fixture", ext: "mp3"))
        let first = library.songs[0], second = library.songs[1]
        library.createPlaylist("本地收藏")
        let playlist = try XCTUnwrap(library.playlists.first)
        library.add(first, to: playlist); library.add(second, to: playlist)
        library.moveItems(playlist, from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(library.playlistSongs(playlist).map(\.song.id), [second.id, first.id])
        library.rename(playlist, name: "新名称")
        XCTAssertEqual(playlist.name, "新名称")
        library.edit(first, title: "新标题", artist: "新艺术家", album: "新专辑", genre: "新流派")
        library.toggleFavorite(first)
        XCTAssertTrue(first.isFavorite)
        XCTAssertTrue(library.albums.contains { $0.title == "新专辑" && $0.id == first.albumID })
        let player = try PlaybackStore(library: library, systemIntegration: false)
        let path = library.files.url(for: first.fileRelativePath)
        library.remove(first, deleteFile: true, playback: player)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(library.playlistSongs(playlist).count, 1)
        library.remove(second, deleteFile: false, playback: player)
        XCTAssertTrue(library.songs.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.files.url(for: "Removed").path).count, 1)
        XCTAssertTrue(library.albums.isEmpty)
        XCTAssertTrue(library.artists.isEmpty)
        XCTAssertNil(library.error)
    }

    func testSharedPlaybackStoreAutomaticallyAdvancesQueue() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        try await library.importOne(fixture("Test Tone", ext: "wav"))
        try await library.importOne(fixture("Fixture", ext: "flac"))
        let songs = library.songs
        let player = try PlaybackStore(library: library, systemIntegration: false)
        player.play(songs)
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while player.currentSong?.id != songs[1].id, player.playbackError == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(player.playbackError)
        XCTAssertEqual(player.currentSong?.id, songs[1].id)
        XCTAssertEqual(player.currentQueueIndex, 1)
        player.pause()
        player.seek(to: 1.25)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 1.25, accuracy: 0.1)
        player.saveSession()
        let session = try XCTUnwrap(library.context.fetch(FetchDescriptor<PlaybackSession>()).first)
        XCTAssertEqual(session.currentPosition, 1.25, accuracy: 0.1)
    }

    func testArtworkDownsamplingAndDiskCache() async throws {
        let files = LibraryFiles(root: URL.temporaryDirectory.appending(path: UUID().uuidString))
        try files.createDirectories()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2_000, height: 2_000), format: format)
        let data = renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 2_000))
        }
        let cache = ArtworkCache()
        try await cache.save(data, id: "cover", files: files)
        let full = await cache.load(id: "cover", files: files, thumbnail: false)
        let thumbnail = await ArtworkCache().load(id: "cover", files: files, thumbnail: true)
        XCTAssertLessThanOrEqual(try XCTUnwrap(full?.image.cgImage).width, 1_024)
        XCTAssertLessThanOrEqual(try XCTUnwrap(thumbnail?.image.cgImage).width, 160)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.artworkURL("cover", thumbnail: true).path))
    }

    func testDownloadedLyricsAndArtworkPersistWithoutChangingAudio() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try makeLibrary(root: root)
        try await library.importOne(fixture("Test Tone", ext: "wav"))
        let song = try XCTUnwrap(library.songs.first)
        let originalHash = song.fileHash
        library.transaction { song.lyrics = "[00:01.00]First line" }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        try await library.setDownloadedCover(song, data: cover)
        let restored = try makeLibrary(root: root)
        let saved = try XCTUnwrap(restored.songs.first)
        XCTAssertEqual(saved.lyrics, "[00:01.00]First line")
        let artworkID = try XCTUnwrap(saved.artworkID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.files.artworkURL(artworkID).path))
        XCTAssertEqual(try LibraryFiles.hash(restored.files.url(for: saved.fileRelativePath)), originalHash)
    }

    func testCancelledImportDoesNotCommit() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.files.root) }
        let url = try fixture("Fixture", ext: "flac")
        let task = Task { try await library.importOne(url) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled import should throw") }
        catch is CancellationError { }
        XCTAssertTrue(library.songs.isEmpty)
    }
}
