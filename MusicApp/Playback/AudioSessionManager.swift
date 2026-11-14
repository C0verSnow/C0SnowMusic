import AVFoundation

@MainActor final class AudioSessionManager {
    private var tokens: [NSObjectProtocol] = []
    private var resumeAfterInterruption = false

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    func observe(_ store: PlaybackStore) {
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self, weak store] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor [weak self, weak store] in
                guard let self, let store else { return }
                if type == .began {
                    self.resumeAfterInterruption = store.isPlaying
                    store.pause()
                } else if type == .ended {
                    if self.resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { store.resume() }
                    self.resumeAfterInterruption = false
                }
            }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak store] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak store] in store?.pause() }
            }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak store] _ in
            Task { @MainActor [weak store] in store?.reloadAfterAudioReset() }
        })
    }

    isolated deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
