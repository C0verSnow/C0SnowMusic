import MediaPlayer
import UIKit

@MainActor final class RemoteCommandManager {
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artworkID: String?
    private var artwork: MPMediaItemArtwork?

    func connect(_ store: PlaybackStore) {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { [weak store] in store?.resume() }
        register(center.pauseCommand) { [weak store] in store?.pause() }
        register(center.togglePlayPauseCommand) { [weak store] in store?.toggle() }
        register(center.nextTrackCommand) { [weak store] in store?.next() }
        register(center.previousTrackCommand) { [weak store] in store?.previous() }
        let target = center.changePlaybackPositionCommand.addTarget { [weak store] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak store] in store?.seek(to: position) }
            return .success
        }
        targets.append((center.changePlaybackPositionCommand, target))
    }

    func update(_ store: PlaybackStore) {
        guard let song = store.currentSong else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.albumTitle,
            MPMediaItemPropertyPlaybackDuration: store.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: store.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: store.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if artworkID != song.artworkID {
            artworkID = song.artworkID; artwork = nil
            if let id = song.artworkID {
                Task { [weak self, weak store] in
                    guard let store, let payload = await ArtworkCache.shared.load(id: id, files: store.files, thumbnail: false),
                          store.currentSong?.artworkID == id else { return }
                    // MediaPlayer requests the image on its own queue, outside MainActor.
                    self?.artwork = MPMediaItemArtwork(boundsSize: payload.image.size) { @Sendable _ in payload.image }
                    self?.update(store)
                }
            }
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor @Sendable () -> Void) {
        let target = command.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
        targets.append((command, target))
    }

    isolated deinit { for (command, target) in targets { command.removeTarget(target) } }
}
