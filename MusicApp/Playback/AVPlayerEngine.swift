import AVFoundation
import Foundation

@MainActor final class AVPlayerEngine: PlayerEngine {
    var onTime: ((Double) -> Void)?
    var onPlaying: ((Bool) -> Void)?
    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = self.player.currentTime().seconds
                if seconds.isFinite { self.onTime?(seconds) }
            }
        }
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onPlaying?(self.player.timeControlStatus == .playing)
            }
        }
    }

    func prepare(_ url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw MusicError.unreadableFile }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw MusicError.unsupportedAudio }
        try Task.checkCancellation()
        clearItemObservers()
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        itemObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            let message = observed.status == .failed ? observed.error?.localizedDescription ?? "播放失败" : nil
            Task { @MainActor [weak self, weak observed] in
                guard let self, self.player.currentItem === observed, let message else { return }
                self.onError?(message)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, self.player.currentItem === item else { return }
                self.onEnded?()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak item] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "音频解码失败"
            Task { @MainActor [weak self, weak item] in
                guard let self, self.player.currentItem === item else { return }
                self.onError?(message)
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func seek(to seconds: Double) async -> Bool {
        await player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func stop() { player.pause(); clearItemObservers(); player.replaceCurrentItem(with: nil) }

    private func clearItemObservers() {
        itemObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil; failureObserver = nil
    }

    isolated deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }
}
