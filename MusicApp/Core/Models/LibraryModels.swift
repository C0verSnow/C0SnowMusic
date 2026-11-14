import Foundation
import SwiftData

enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Song.self, Album.self, Artist.self, Playlist.self, PlaylistItem.self, PlaybackSession.self]
    }
}

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@Model final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var artistID: UUID?
    var albumID: UUID?
    var albumTitle: String
    var albumArtist: String
    var duration: Double
    var fileRelativePath: String
    var artworkID: String?
    var format: String
    var fileHash: String
    var fileSize: Int64
    var sampleRate: Double
    var channels: Int
    var bitDepth: Int?
    var trackNumber: Int
    var discNumber: Int
    var genre: String
    var releaseYear: Int?
    var lyrics: String
    var dateAdded: Date
    var lastPlayedAt: Date?
    var playCount: Int
    var isFavorite: Bool

    init(id: UUID = UUID(), metadata: AudioMetadata, path: String, hash: String, size: Int64, artworkID: String?) {
        self.id = id
        title = metadata.title; artist = metadata.artist
        albumTitle = metadata.album; albumArtist = metadata.albumArtist
        duration = metadata.duration; fileRelativePath = path
        self.artworkID = artworkID; format = metadata.format
        fileHash = hash; fileSize = size
        sampleRate = metadata.sampleRate; channels = metadata.channels; bitDepth = metadata.bitDepth
        trackNumber = metadata.track; discNumber = metadata.disc
        genre = metadata.genre; releaseYear = metadata.year; lyrics = metadata.lyrics
        dateAdded = .now; playCount = 0; isFavorite = false
    }
}

@Model final class Album {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var artworkID: String?
    var releaseYear: Int?
    init(title: String, artist: String, artworkID: String?, releaseYear: Int?) {
        id = UUID(); self.title = title; self.artist = artist
        self.artworkID = artworkID; self.releaseYear = releaseYear
    }
}

@Model final class Artist {
    @Attribute(.unique) var id: UUID
    var name: String
    init(name: String) { id = UUID(); self.name = name }
}

@Model final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var artworkID: String?
    var createdAt: Date
    var updatedAt: Date
    init(name: String) {
        id = UUID(); self.name = name; createdAt = .now; updatedAt = .now
    }
}

@Model final class PlaylistItem {
    @Attribute(.unique) var id: UUID
    var playlistID: UUID
    var songID: UUID
    var sortOrder: Int
    init(playlistID: UUID, songID: UUID, sortOrder: Int) {
        id = UUID(); self.playlistID = playlistID; self.songID = songID; self.sortOrder = sortOrder
    }
}

@Model final class PlaybackSession {
    @Attribute(.unique) var id: String
    var currentSongID: UUID?
    var currentPosition: Double
    var repeatMode: String
    var shuffleEnabled: Bool
    var queueSnapshot: [UUID]
    var currentQueueIndex: Int
    init() {
        id = "current"; currentPosition = 0; repeatMode = "off"
        shuffleEnabled = false; queueSnapshot = []; currentQueueIndex = 0
    }
}
