import AVFoundation
import Foundation
import SwiftUI
import Observation
import SwiftData

@MainActor @Observable final class PlaybackStore {
    let files: LibraryFiles
    var currentSong: Song?
    var isPlaying = false
    var isLoading = false
    var currentTime: Double = 0
    var duration: Double { currentSong?.duration ?? 0 }
    var queue = QueueManager()
    var currentQueueIndex: Int { queue.index }
    var repeatMode: RepeatMode = .off
    var shuffleEnabled = false
    var playbackError: String?
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private var engine: any PlayerEngine
    @ObservationIgnored private let audioSession = AudioSessionManager()
    @ObservationIgnored private let remote = RemoteCommandManager()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var lastSavedTime: Double = 0
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var session: PlaybackSession

    init(library: LibraryStore, engine: any PlayerEngine = AVPlayerEngine(), systemIntegration: Bool = true) throws {
        self.library = library; files = library.files; self.engine = engine
        if let saved = try library.context.fetch(FetchDescriptor<PlaybackSession>()).first { session = saved }
        else {
            session = PlaybackSession()
            library.context.insert(session)
            try library.context.save()
        }
        bindEngine()
        if systemIntegration { audioSession.observe(self); remote.connect(self) }
        restore()
    }

    func play(_ songs: [Song], startingAt index: Int = 0, shuffled: Bool = false) {
        guard !songs.isEmpty else { return }
        queue.replace(songs.map(\.id), startingAt: index)
        shuffleEnabled = shuffled
        if shuffled { queue.shuffleUpcoming() }
        loadCurrent(autoplay: true)
    }

    func resume() {
        guard currentSong != nil else { return }
        wantsPlayback = true
        if !prepared { loadCurrent(autoplay: true, position: currentTime); return }
        do { try audioSession.activate(); engine.play() }
        catch { playbackError = error.localizedDescription; wantsPlayback = false }
    }

    func pause() {
        wantsPlayback = false; engine.pause(); isPlaying = false
        saveSession(); remote.update(self)
    }

    func toggle() { if isPlaying || wantsPlayback { pause() } else { resume() } }

    func seek(to seconds: Double) {
        let position = min(max(0, seconds), duration)
        currentTime = position
        guard prepared else { saveSession(); return }
        let entryID = queue.current?.id
        seekTask?.cancel()
        seekTask = Task {
            let success = await engine.seek(to: position)
            guard !Task.isCancelled, queue.current?.id == entryID else { return }
            if !success { playbackError = "无法跳转到该播放位置。" }
            currentTime = position; saveSession(); remote.update(self)
            seekTask = nil
        }
    }

    func next(automatic: Bool = false) {
        if queue.advance(automatic: automatic, repeatMode: repeatMode) {
            loadCurrent(autoplay: true)
        } else {
            pause()
            if automatic { currentTime = 0; prepared = false; engine.stop() }
            saveSession()
        }
    }

    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        if queue.index > 0 { queue.index -= 1 }
        else if repeatMode == .all { queue.index = max(0, queue.entries.count - 1) }
        loadCurrent(autoplay: true)
    }

    func enqueue(_ song: Song, next: Bool) {
        queue.insert(song.id, next: next)
        if currentSong == nil { loadCurrent(autoplay: false) }
        saveSession()
    }

    func jump(to index: Int) { queue.index = index; loadCurrent(autoplay: true) }

    func removeQueueEntries(at offsets: IndexSet) {
        let playingEntry = queue.current?.id
        queue.remove(offsets)
        if playingEntry != queue.current?.id { loadCurrent(autoplay: isPlaying) }
        saveSession()
    }

    func moveQueueEntries(from offsets: IndexSet, to destination: Int) {
        let playingID = queue.current?.id
        queue.entries.move(fromOffsets: offsets, toOffset: destination)
        queue.index = queue.entries.firstIndex { $0.id == playingID } ?? 0
        saveSession()
    }

    func removeSong(_ id: UUID) {
        removeQueueEntries(at: IndexSet(queue.entries.indices.filter { queue.entries[$0].songID == id }))
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled { queue.shuffleUpcoming() }
        saveSession()
    }

    func cycleRepeat() {
        switch repeatMode { case .off: repeatMode = .all; case .all: repeatMode = .one; case .one: repeatMode = .off }
        saveSession()
    }

    func song(for entry: QueueEntry) -> Song? { library.songs.first { $0.id == entry.songID } }

    func saveSession() {
        session.currentSongID = currentSong?.id; session.currentPosition = currentTime
        session.repeatMode = repeatMode.rawValue; session.shuffleEnabled = shuffleEnabled
        session.queueSnapshot = queue.entries.map(\.songID); session.currentQueueIndex = queue.index
        do { try library.context.save(); lastSavedTime = currentTime }
        catch { playbackError = "保存播放进度失败：\(error.localizedDescription)" }
    }

    func reloadAfterAudioReset() {
        pause(); engine.stop(); engine = AVPlayerEngine(); bindEngine()
        loadCurrent(autoplay: false, position: currentTime)
    }

    private func bindEngine() {
        engine.onTime = { [weak self] seconds in
            guard let self, !self.isLoading, self.seekTask == nil || self.seekTask?.isCancelled == true else { return }
            self.currentTime = seconds
            if abs(seconds - self.lastSavedTime) >= 5 { self.saveSession() }
            self.remote.update(self)
        }
        engine.onPlaying = { [weak self] playing in
            guard let self else { return }
            self.isPlaying = playing
            self.remote.update(self)
        }
        engine.onEnded = { [weak self] in self?.next(automatic: true) }
        engine.onError = { [weak self] message in self?.pause(); self?.prepared = false; self?.playbackError = message }
    }

    private func loadCurrent(autoplay: Bool, position: Double = 0) {
        loadTask?.cancel(); seekTask?.cancel(); seekTask = nil
        engine.pause(); isPlaying = false; prepared = false
        guard let entry = queue.current, let song = song(for: entry) else {
            currentSong = nil; currentTime = 0; isLoading = false; wantsPlayback = false
            engine.stop(); saveSession(); remote.update(self); return
        }
        currentSong = song; currentTime = position; isLoading = true
        wantsPlayback = autoplay; playbackError = nil
        saveSession(); remote.update(self)
        loadTask = Task {
            do {
                try await engine.prepare(files.url(for: song.fileRelativePath))
                try Task.checkCancellation()
                if position > 0 { _ = await engine.seek(to: min(position, song.duration)) }
                try Task.checkCancellation()
                prepared = true; isLoading = false
                if wantsPlayback {
                    try audioSession.activate()
                    song.lastPlayedAt = .now; song.playCount += 1
                    saveSession(); engine.play()
                }
                remote.update(self)
            } catch is CancellationError { }
            catch {
                isLoading = false; wantsPlayback = false
                playbackError = error.localizedDescription
            }
        }
    }

    private func restore() {
        let available = Set(library.songs.map(\.id))
        let savedQueue = session.queueSnapshot
        let oldIndex = session.currentQueueIndex
        let keptBefore = savedQueue.prefix(max(0, min(oldIndex, savedQueue.count))).filter { available.contains($0) }.count
        queue.replace(savedQueue.filter { available.contains($0) }, startingAt: keptBefore)
        repeatMode = RepeatMode(rawValue: session.repeatMode) ?? .off
        shuffleEnabled = session.shuffleEnabled
        currentSong = queue.current.flatMap { song(for: $0) }
        currentTime = min(session.currentPosition, currentSong?.duration ?? 0)
        // Restoration never activates the audio session or starts sound.
        remote.update(self)
    }
}
