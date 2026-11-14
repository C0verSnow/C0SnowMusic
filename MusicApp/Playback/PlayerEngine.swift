import Foundation

@MainActor protocol PlayerEngine: AnyObject {
    var onTime: ((Double) -> Void)? { get set }
    var onPlaying: ((Bool) -> Void)? { get set }
    var onEnded: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func prepare(_ url: URL) async throws
    func play()
    func pause()
    func seek(to seconds: Double) async -> Bool
    func stop()
}
