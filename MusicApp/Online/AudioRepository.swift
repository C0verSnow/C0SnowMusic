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

    func audio(for track: OnlineTrack, cookies: [WebCookie], cloud: CloudMusicStore?, diagnosticID: UUID? = nil) async throws -> ResolvedAudio {
        try Task.checkCancellation()
        AppDiagnostics.shared.step(diagnosticID, "Checking local cache")
        if let url = await cache.url(for: track.id) {
            AppDiagnostics.shared.step(diagnosticID, "Local cache hit")
            return ResolvedAudio(url: url, warehouseError: nil)
        }
        let directory = URL.cachesDirectory.appending(path: "OnlineStaging/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var warehouseError: String?
        if let cloud, cloud.connected {
            AppDiagnostics.shared.step(diagnosticID, "Warehouse lookup / download")
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
                AppDiagnostics.shared.step(diagnosticID, "Warehouse failed; trying on-device extraction", detail: AppDiagnostics.describe(error))
                downloaded = nil
            }
            if let downloaded {
                AppDiagnostics.shared.step(diagnosticID, "Caching warehouse audio")
                let url = try await cache.insert(downloaded, track: track)
                return ResolvedAudio(url: url, warehouseError: nil)
            }
        }
        guard track.kind != .telegram else { throw OnlineMusicError.invalidAudio }
        AppDiagnostics.shared.step(diagnosticID, "On-device extraction")
        let downloaded = try await downloader.download(track, directory: directory, cookies: cookies)
        AppDiagnostics.shared.step(diagnosticID, "Caching extracted audio")
        let url = try await cache.insert(downloaded, track: track)
        return ResolvedAudio(url: url, warehouseError: warehouseError)
    }
}
