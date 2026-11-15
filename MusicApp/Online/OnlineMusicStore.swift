import AVFoundation
import Observation
import SwiftUI

@MainActor @Observable final class OnlineMusicStore {
    var results: [OnlineTrack] = []
    var cached: [CachedAudio] = []
    var searching = false
    var downloadingID: String?
    var error: String?
    @ObservationIgnored private var cache: OnlineAudioCache?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(cache: OnlineAudioCache? = nil) {
        do { self.cache = try cache ?? OnlineAudioCache() }
        catch { self.error = error.localizedDescription }
    }

    var cacheBytes: Int64 { cached.reduce(0) { $0 + $1.byteCount } }

    func refresh() async {
        cached = await cache?.all() ?? []
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []; error = nil
        guard !query.isEmpty else { searching = false; return }
        searching = true
        searchTask = Task {
            do {
                let matches = try await YouTubeSearchClient().search(query)
                try Task.checkCancellation()
                results = matches; searching = false
                if let first = matches.first, downloadingID == nil { prepare(first) }
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                searching = false; self.error = error.localizedDescription
            }
        }
    }

    func prepare(_ track: OnlineTrack, play: Bool = false, saveTo library: LibraryStore? = nil, playback: PlaybackStore? = nil) {
        guard downloadTask == nil else { return }
        downloadingID = track.id; error = nil
        downloadTask = Task {
            defer { downloadingID = nil; downloadTask = nil }
            do {
                guard let cache else { throw OnlineMusicError.runtimeUnavailable }
                let url: URL
                if let existing = await cache.url(for: track.id) { url = existing }
                else {
                    let directory = URL.cachesDirectory.appending(path: "OnlineStaging/\(UUID())")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let downloaded = try await OnDeviceDownloader.shared.download(track, directory: directory)
                    try Task.checkCancellation()
                    url = try await cache.insert(downloaded, track: track)
                }
                await refresh()
                if let library {
                    let existing = Set(library.songs.map(\.id))
                    let imported = try await library.importOne(url)
                    if imported, let song = library.songs.first(where: { !existing.contains($0.id) }) {
                        library.edit(song, title: track.title, artist: track.artist, album: song.albumTitle, genre: song.genre)
                    }
                }
                if play, let playback { try await playback.playCachedAudio(track, url: url) }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func remove(_ entry: CachedAudio) async {
        do {
            try await cache?.remove(entry.id); await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func clearCache() async {
        do { try await cache?.clear(); await refresh() }
        catch { self.error = error.localizedDescription }
    }

}
