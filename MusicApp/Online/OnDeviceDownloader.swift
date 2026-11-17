import AVFoundation
import Foundation
import WebKit

final class OnDeviceDownloader: AudioDownloading, @unchecked Sendable {
    static let shared = OnDeviceDownloader()
    // Python owns process-wide state. Every C API call stays on this serial queue.
    private let queue = DispatchQueue(label: "org.c0versnow.youtube-python", qos: .userInitiated)
    private var initialized = false

    func download(_ track: OnlineTrack, directory: URL, cookies: [WebCookie] = []) async throws -> URL {
        let cancel = directory.appending(path: "cancel")
        let diagnosticID = await AppDiagnostics.shared.begin("On-device download \(track.id)")
        let diagnosticFile = directory.appending(path: "diagnostics.jsonl")
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                AppDiagnostics.shared.collectDownloadEvents(from: diagnosticFile, operation: diagnosticID)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        defer { monitor.cancel() }
        await AppDiagnostics.shared.step(diagnosticID, "Downloader queue / Python startup")
        do {
            let response: DownloadResponse = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    queue.async {
                        do {
                            try self.initialize()
                            let cookieData = try JSONEncoder().encode(cookies)
                            let parameters = ["video_id": track.id, "directory": directory.path, "cookies": String(decoding: cookieData, as: UTF8.self)]
                            let response = try self.execute(parameters)
                            if FileManager.default.fileExists(atPath: cancel.path) { throw CancellationError() }
                            if let error = response.error { throw DownloadError(message: error) }
                            continuation.resume(returning: response)
                        } catch { continuation.resume(throwing: error) }
                    }
                }
            } onCancel: { try? Data().write(to: cancel) }
            await AppDiagnostics.shared.collectDownloadEvents(from: diagnosticFile, operation: diagnosticID)
            guard let duration = response.duration, duration.isFinite, duration > 0 else { throw OnlineMusicError.invalidAudio }
            monitor.cancel()
            await AppDiagnostics.shared.step(diagnosticID, "Normalizing audio container")
            let result = try await Self.normalizeAudio(directory.appending(path: "audio.m4a"), duration: duration)
            await AppDiagnostics.shared.finish(diagnosticID)
            return result
        } catch {
            monitor.cancel()
            await AppDiagnostics.shared.collectDownloadEvents(from: diagnosticFile, operation: diagnosticID)
            await AppDiagnostics.shared.finish(diagnosticID, error: error)
            throw error
        }
    }

    static func normalizeAudio(_ source: URL, duration: Double) async throws -> URL {
        // YouTube DASH headers can make AVFoundation count the duration twice.
        // Like yt-dlp's FixupM4a, remux without re-encoding; use the source's
        // declared duration to exclude the empty tail observed on iPhone.
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw OnlineMusicError.invalidAudio
        }
        export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        let destination = source.deletingLastPathComponent().appending(path: "normalized.m4a")
        try await export.export(to: destination, as: .m4a)
        try Task.checkCancellation()
        return destination
    }

    func verifyRuntime() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.initialize()
                    let directory = URL.temporaryDirectory.appending(path: "RuntimeCheck-\(UUID())")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let fixture = Bundle.main.url(forResource: "Fixture", withExtension: "m4a", subdirectory: "Fixtures")
                    let response = try self.execute(["directory": directory.path, "action": "verify", "fixture": fixture?.path ?? ""])
                    if let error = response.error { throw DownloadError(message: error) }
                    continuation.resume(returning: response.version ?? "")
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func initialize() throws {
        guard !initialized else { return }
        guard let resources = Bundle.main.resourceURL,
              FileManager.default.fileExists(atPath: resources.appending(path: "python/lib/python3.13/encodings").path),
              FileManager.default.fileExists(atPath: resources.appending(path: "app/c0snow_downloader.py").path) else {
            throw OnlineMusicError.runtimeUnavailable
        }
        setenv("PYTHONHOME", resources.appending(path: "python").path, 1)
        setenv("PYTHONPATH", resources.appending(path: "app").path + ":" + resources.appending(path: "app_packages").path, 1)
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
        setenv("PYTHONUTF8", "1", 1)
        Py_Initialize()
        PyEval_SaveThread()
        initialized = true
    }

    private func execute(_ parameters: [String: String]) throws -> DownloadResponse {
        let state = PyGILState_Ensure()
        defer { PyGILState_Release(state) }
        let encoded = try JSONEncoder().encode(parameters).base64EncodedString()
        let callback: @convention(c) (UInt) -> Void = restrictChallengeNavigation
        let address = unsafeBitCast(callback, to: UInt.self)
        let script = """
        import base64, json
        import c0snow_downloader
        c0snow_downloader.run(json.loads(base64.b64decode('\(encoded)')), \(address))
        """
        guard PyRun_SimpleStringFlags(script, nil) == 0 else {
            PyErr_Print()
            throw OnlineMusicError.runtimeUnavailable
        }
        let result = URL(fileURLWithPath: parameters["directory"]!).appending(path: "result.json")
        return try JSONDecoder().decode(DownloadResponse.self, from: Data(contentsOf: result))
    }
}

private struct DownloadResponse: Decodable {
    let error: String?
    let version: String?
    let duration: Double?
}

private struct DownloadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func restrictChallengeNavigation(_ address: UInt) {
    DispatchQueue.main.sync {
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
            let view = Unmanaged<WKWebView>.fromOpaque(pointer).takeUnretainedValue()
            view.navigationDelegate = ChallengeNavigationDelegate.shared
            view.uiDelegate = ChallengeNavigationDelegate.shared
        }
    }
}

@MainActor final class ChallengeNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = ChallengeNavigationDelegate()

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // EJS assigns window.location. Challenge execution must never open YouTube.
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}
