import Foundation
import UniformTypeIdentifiers

struct ImportedAudio: Sendable {
    let id: UUID
    let metadata: AudioMetadata
    let relativePath: String
    let hash: String
    let size: Int64
    let artworkID: String?
}

struct FileFingerprint: Sendable {
    let hash: String
    let size: Int64
}

enum DuplicatePolicy: String, CaseIterable, Identifiable, Sendable {
    case skip = "跳过重复文件", keepCopy = "保留副本"
    var id: String { rawValue }
}

actor AudioImportService {
    let files: LibraryFiles
    static let extensions = ["mp3", "flac", "m4a", "aac", "alac", "wav", "aiff", "aif"]
    static var contentTypes: [UTType] {
        Array(Set(extensions.compactMap { UTType(filenameExtension: $0) } + [.audio]))
    }

    init(files: LibraryFiles) { self.files = files }

    func importFile(_ source: URL, existing: [FileFingerprint], policy: DuplicatePolicy) async throws -> ImportedAudio? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try files.createDirectories()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let byteCount = values.fileSize, byteCount > 0 else { throw MusicError.unreadableFile }
        let hash = try LibraryFiles.hash(source)
        if policy == .skip, existing.contains(where: { $0.size == byteCount && $0.hash == hash }) { return nil }
        let capacity = try files.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < Int64(byteCount) + 8_388_608 { throw MusicError.insufficientSpace }
        let id = UUID()
        let ext = source.pathExtension.lowercased()
        let staging = files.url(for: "Staging/\(id).\(ext)")
        let relativePath = "Audio/\(id).\(ext)"
        let destination = files.url(for: relativePath)
        var committed = false
        defer {
            try? FileManager.default.removeItem(at: staging)
            if !committed {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.removeItem(at: files.artworkURL(id.uuidString))
                try? FileManager.default.removeItem(at: files.artworkURL(id.uuidString, thumbnail: true))
            }
        }
        try files.copy(source, to: staging)
        var metadata = try await MetadataExtractor.extract(staging)
        // Staging names are internal UUIDs; a missing title must use the original name.
        if metadata.title == staging.deletingPathExtension().lastPathComponent {
            metadata.title = source.deletingPathExtension().lastPathComponent
        }
        try Task.checkCancellation()
        var artworkID: String?
        if let artwork = metadata.artwork {
            try await ArtworkCache.shared.save(artwork, id: id.uuidString, files: files)
            artworkID = id.uuidString
        }
        metadata.artwork = nil
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
        // User-owned originals are included in device backup unless the user opts out.
        var savedURL = destination
        var backup = URLResourceValues()
        backup.isExcludedFromBackup = UserDefaults.standard.bool(forKey: "excludeMusicFromBackup")
        try savedURL.setResourceValues(backup)
        committed = true
        return ImportedAudio(id: id, metadata: metadata, relativePath: relativePath, hash: hash, size: Int64(byteCount), artworkID: artworkID)
    }

    func discard(_ audio: ImportedAudio) {
        try? FileManager.default.removeItem(at: files.url(for: audio.relativePath))
        if let id = audio.artworkID {
            try? FileManager.default.removeItem(at: files.artworkURL(id))
            try? FileManager.default.removeItem(at: files.artworkURL(id, thumbnail: true))
        }
    }

    func setBackupExcluded(_ excluded: Bool) throws {
        for url in try FileManager.default.contentsOfDirectory(at: files.url(for: "Audio"), includingPropertiesForKeys: nil) {
            var mutableURL = url
            var values = URLResourceValues(); values.isExcludedFromBackup = excluded
            try mutableURL.setResourceValues(values)
        }
        UserDefaults.standard.set(excluded, forKey: "excludeMusicFromBackup")
    }

    func readLyrics(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw MusicError.invalidLyrics }
        return text
    }
}
