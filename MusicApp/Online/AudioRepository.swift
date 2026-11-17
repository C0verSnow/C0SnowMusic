import Foundation

protocol AudioDownloading: Sendable {
    func download(_ track: OnlineTrack, directory: URL, cookies: [WebCookie]) async throws -> URL
}

struct ResolvedAudio {
    let url: URL
    let warehouseError: String?
}

@MainActor struct AudioRepository {
    let cache: OnlineAudioCache
    let downloader: any AudioDownloading

    func audio(for track: OnlineTrack, cookies: [WebCookie], cloud: CloudMusicStore?) async throws -> ResolvedAudio {
        try Task.checkCancellation()
        if let url = await cache.url(for: track.id) {
            return ResolvedAudio(url: url, warehouseError: nil)
        }
        let directory = URL.cachesDirectory.appending(path: "OnlineStaging/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var warehouseError: String?
        if let cloud, cloud.connected {
            let downloaded: URL?
            do {
                downloaded = try await cloud.download(track, directory: directory)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // Telegram-only songs have no YouTube source to recover from.
                guard track.kind != .telegram else { throw error }
                warehouseError = error.localizedDescription
                downloaded = nil
            }
            if let downloaded {
                let url = try await cache.insert(downloaded, track: track)
                return ResolvedAudio(url: url, warehouseError: nil)
            }
        }
        guard track.kind != .telegram else { throw OnlineMusicError.invalidAudio }
        let downloaded = try await downloader.download(track, directory: directory, cookies: cookies)
        let url = try await cache.insert(downloaded, track: track)
        return ResolvedAudio(url: url, warehouseError: warehouseError)
    }
}
