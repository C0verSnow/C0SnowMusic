import Foundation
import Python
import WebKit

final class OnDeviceDownloader: @unchecked Sendable {
    static let shared = OnDeviceDownloader()
    // Python owns process-wide state. Every C API call stays on this serial queue.
    private let queue = DispatchQueue(label: "org.c0versnow.youtube-python", qos: .userInitiated)
    private var initialized = false

    func download(_ track: OnlineTrack, directory: URL) async throws -> URL {
        let cancel = directory.appending(path: "cancel")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try self.initialize()
                        let parameters = ["video_id": track.id, "directory": directory.path]
                        let response = try self.execute(parameters)
                        if FileManager.default.fileExists(atPath: cancel.path) { throw CancellationError() }
                        if let error = response.error { throw DownloadError(message: error) }
                        continuation.resume(returning: directory.appending(path: "audio.m4a"))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { try? Data().write(to: cancel) }
    }

    func verifyRuntime() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.initialize()
                    let directory = URL.temporaryDirectory.appending(path: "RuntimeCheck-\(UUID())")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let response = try self.execute(["directory": directory.path, "action": "verify"])
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
