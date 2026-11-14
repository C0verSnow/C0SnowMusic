import Foundation
import SwiftUI
import Observation
import SwiftData

@MainActor @Observable final class LibraryStore {
    let context: ModelContext
    let files: LibraryFiles
    let importer: AudioImportService
    var songs: [Song] = []
    var albums: [Album] = []
    var artists: [Artist] = []
    var playlists: [Playlist] = []
    var items: [PlaylistItem] = []
    var error: String?
    var importProgress: Double?
    var importStatus = ""
    var importFailures: [String] = []
    var duplicatePolicy = DuplicatePolicy.skip
    @ObservationIgnored private var importTask: Task<Void, Never>?

    init(context: ModelContext, files: LibraryFiles) throws {
        self.context = context; self.files = files
        importer = AudioImportService(files: files)
        context.autosaveEnabled = false
        try files.createDirectories()
        try refresh()
    }

    func refresh() throws {
        songs = try context.fetch(FetchDescriptor<Song>(sortBy: [SortDescriptor(\.title)]))
        albums = try context.fetch(FetchDescriptor<Album>(sortBy: [SortDescriptor(\.title)]))
        artists = try context.fetch(FetchDescriptor<Artist>(sortBy: [SortDescriptor(\.name)]))
        playlists = try context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        items = try context.fetch(FetchDescriptor<PlaylistItem>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    func startImport(_ urls: [URL]) {
        guard importTask == nil else { return }
        importProgress = 0; importFailures = []
        importTask = Task {
            var imported = 0; var skipped = 0
            for (index, url) in urls.enumerated() {
                if Task.isCancelled { break }
                importStatus = "正在导入 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"
                do {
                    if try await importOne(url) { imported += 1 } else { skipped += 1 }
                } catch is CancellationError { break }
                catch { importFailures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
                importProgress = Double(index + 1) / Double(urls.count)
            }
            importStatus = "\(Task.isCancelled ? "已取消。" : "")已导入 \(imported) 首，跳过 \(skipped) 首，失败 \(importFailures.count) 首。"
            importProgress = nil; importTask = nil
        }
    }

    func cancelImport() { importTask?.cancel() }

    @discardableResult func importOne(_ url: URL) async throws -> Bool {
        let existing = songs.map { FileFingerprint(hash: $0.fileHash, size: $0.fileSize) }
        guard let audio = try await importer.importFile(url, existing: existing, policy: duplicatePolicy) else { return false }
        let song = Song(id: audio.id, metadata: audio.metadata, path: audio.relativePath, hash: audio.hash, size: audio.size, artworkID: audio.artworkID)
        do {
            context.insert(song)
            assignGroups(song)
            try context.save()
            try refresh()
            return true
        } catch {
            context.rollback()
            await importer.discard(audio)
            throw error
        }
    }

    func transaction(_ change: () throws -> Void) {
        do {
            try change()
            try context.save()
            try refresh()
        } catch {
            context.rollback()
            self.error = error.localizedDescription
            try? refresh()
        }
    }

    func toggleFavorite(_ song: Song) { transaction { song.isFavorite.toggle() } }

    func edit(_ song: Song, title: String, artist: String, album: String, genre: String) {
        transaction {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MusicError.emptyName }
            song.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            song.artist = artist.isEmpty ? "未知艺术家" : artist
            song.albumTitle = album.isEmpty ? "未知专辑" : album
            song.genre = genre.isEmpty ? "未分类" : genre
            song.albumArtist = song.artist
            assignGroups(song)
            pruneGroups(excluding: nil)
        }
    }

    func remove(_ song: Song, deleteFile: Bool, playback: PlaybackStore) {
        let source = files.url(for: song.fileRelativePath)
        let tombstone = files.url(for: "Staging/deleting-\(song.id)")
        let retained = files.url(for: "Removed/\(song.id).\(source.pathExtension)")
        let moved = FileManager.default.fileExists(atPath: source.path)
        do {
            if moved { try FileManager.default.moveItem(at: source, to: deleteFile ? tombstone : retained) }
            let songID = song.id
            for item in items where item.songID == songID { context.delete(item) }
            context.delete(song)
            pruneGroups(excluding: songID)
            try context.save()
            playback.removeSong(songID)
            try refresh()
            if deleteFile, moved { try FileManager.default.removeItem(at: tombstone) }
        } catch {
            context.rollback()
            let movedURL = deleteFile ? tombstone : retained
            if moved, FileManager.default.fileExists(atPath: movedURL.path) { try? FileManager.default.moveItem(at: movedURL, to: source) }
            self.error = error.localizedDescription
            try? refresh()
        }
    }

    func restoreRemovedFiles() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: files.url(for: "Removed"), includingPropertiesForKeys: nil)
            startImport(urls)
        } catch { self.error = error.localizedDescription }
    }

    func createPlaylist(_ name: String) {
        transaction {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MusicError.emptyName }
            context.insert(Playlist(name: trimmed))
        }
    }

    func rename(_ playlist: Playlist, name: String) {
        transaction {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MusicError.emptyName }
            playlist.name = trimmed; playlist.updatedAt = .now
        }
    }

    func deletePlaylist(_ playlist: Playlist) {
        transaction {
            for item in items where item.playlistID == playlist.id { context.delete(item) }
            context.delete(playlist)
        }
    }

    func add(_ song: Song, to playlist: Playlist) {
        transaction {
            let position = (items.filter { $0.playlistID == playlist.id }.map(\.sortOrder).max() ?? -1) + 1
            context.insert(PlaylistItem(playlistID: playlist.id, songID: song.id, sortOrder: position))
            playlist.updatedAt = .now
        }
    }

    func playlistSongs(_ playlist: Playlist) -> [(item: PlaylistItem, song: Song)] {
        let lookup = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        return items.filter { $0.playlistID == playlist.id }.sorted { $0.sortOrder < $1.sortOrder }.compactMap { item in
            lookup[item.songID].map { (item, $0) }
        }
    }

    func removeItems(_ playlist: Playlist, at offsets: IndexSet) {
        let list = playlistSongs(playlist)
        transaction {
            for offset in offsets { context.delete(list[offset].item) }
            playlist.updatedAt = .now
        }
    }

    func moveItems(_ playlist: Playlist, from offsets: IndexSet, to destination: Int) {
        var list = playlistSongs(playlist).map(\.item)
        list.move(fromOffsets: offsets, toOffset: destination)
        transaction {
            for (position, item) in list.enumerated() { item.sortOrder = position }
            playlist.updatedAt = .now
        }
    }

    func setCover(_ playlist: Playlist, data: Data) async {
        do {
            let id = UUID().uuidString
            try await ArtworkCache.shared.save(data, id: id, files: files)
            transaction { playlist.artworkID = id; playlist.updatedAt = .now }
        } catch { self.error = error.localizedDescription }
    }

    private func assignGroups(_ song: Song) {
        let allArtists = (try? context.fetch(FetchDescriptor<Artist>())) ?? []
        let artist = allArtists.first { $0.name == song.artist } ?? Artist(name: song.artist)
        if artist.modelContext == nil { context.insert(artist) }
        song.artistID = artist.id
        let allAlbums = (try? context.fetch(FetchDescriptor<Album>())) ?? []
        let album = allAlbums.first { $0.title == song.albumTitle && $0.artist == song.albumArtist }
            ?? Album(title: song.albumTitle, artist: song.albumArtist, artworkID: song.artworkID, releaseYear: song.releaseYear)
        if album.modelContext == nil { context.insert(album) }
        if album.artworkID == nil { album.artworkID = song.artworkID }
        song.albumID = album.id
    }

    private func pruneGroups(excluding id: UUID?) {
        let remaining = ((try? context.fetch(FetchDescriptor<Song>())) ?? []).filter { $0.id != id }
        let albumIDs = Set(remaining.compactMap(\.albumID))
        let artistIDs = Set(remaining.compactMap(\.artistID))
        for album in (try? context.fetch(FetchDescriptor<Album>())) ?? [] where !albumIDs.contains(album.id) { context.delete(album) }
        for artist in (try? context.fetch(FetchDescriptor<Artist>())) ?? [] where !artistIDs.contains(artist.id) { context.delete(artist) }
    }
}
