import AVFoundation
import Foundation

struct CachedAudio: Codable, Identifiable, Sendable {
    let track: OnlineTrack
    let filename: String
    let byteCount: Int64
    let createdAt: Date
    var id: String { track.id }
}

actor OnlineAudioCache {
    static let maximumBytes: Int64 = 500_000_000
    let root: URL
    private var entries: [CachedAudio]

    init(root: URL = URL.cachesDirectory.appending(path: "OnlineAudio")) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let index = root.appending(path: "index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            entries = try JSONDecoder().decode([CachedAudio].self, from: Data(contentsOf: index))
                .filter { FileManager.default.fileExists(atPath: root.appending(path: $0.filename).path) }
        } else { entries = [] }
    }

    func all() -> [CachedAudio] {
        entries.removeAll { !FileManager.default.fileExists(atPath: root.appending(path: $0.filename).path) }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }
    func url(for id: String) -> URL? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        let url = root.appending(path: entry.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            entries.removeAll { $0.id == id }
            return nil
        }
        return url
    }

    func insert(_ source: URL, track: OnlineTrack, maximumBytes: Int64 = OnlineAudioCache.maximumBytes) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        guard !audio.isEmpty, video.isEmpty, try await asset.load(.isPlayable) else { throw OnlineMusicError.invalidAudio }
        let size = Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size > 0, size <= maximumBytes else { throw OnlineMusicError.cacheFull }
        try Task.checkCancellation()
        while entries.reduce(size, { $0 + $1.byteCount }) > maximumBytes, let oldest = entries.min(by: { $0.createdAt < $1.createdAt }) {
            try remove(oldest.id)
        }
        let filename = "\(track.id).\(source.pathExtension.lowercased() == "mp3" ? "mp3" : "m4a")"
        let destination = root.appending(path: filename)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: source, to: destination)
        entries.removeAll { $0.id == track.id }
        entries.append(CachedAudio(track: track, filename: filename, byteCount: size, createdAt: .now))
        do { try save() }
        catch {
            entries.removeAll { $0.id == track.id }
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    func remove(_ id: String) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let url = root.appending(path: entry.filename)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        entries.removeAll { $0.id == id }
        try save()
    }

    func clear() throws {
        for entry in entries { try remove(entry.id) }
    }

    private func save() throws {
        try JSONEncoder().encode(entries).write(to: root.appending(path: "index.json"), options: .atomic)
    }
}
