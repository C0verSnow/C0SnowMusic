import CryptoKit
import Foundation
import Observation
import Security

struct CloudTrack: Decodable, Identifiable, Sendable {
    struct AudioFile: Decodable, Sendable {
        let id: String
        let available: Bool
        let mime_type: String
    }
    let id: String
    let source_id: String?
    let title: String
    let artist: String
    let album: String?
    let cover_url: URL?
    let files: [AudioFile]
    var onlineTrack: OnlineTrack { OnlineTrack(id: source_id ?? id, title: title, artist: artist, coverURL: cover_url, kind: source_id == nil ? .telegram : nil, albumTitle: album) }
}

struct CloudConnection: Codable, Sendable {
    let endpoint: URL
    let apiKey: String
}

@MainActor @Observable final class CloudMusicStore {
    var endpoint = ""
    var connected = false
    var busy = false
    var error: String?
    var favorites: [CloudTrack] = []
    var trending: [OnlineTrack] = []
    @ObservationIgnored private var connection: CloudConnection?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let storageAccount: String

    init(session: URLSession = .shared, storageAccount: String = "cloud-library") {
        self.session = session; self.storageAccount = storageAccount
    }

    func restore() {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status != errSecItemNotFound else { return }
        guard status == errSecSuccess, let data = value as? Data else { error = AppLanguage.text("Cannot read music warehouse settings."); return }
        do {
            let saved = try JSONDecoder().decode(CloudConnection.self, from: data)
            connection = saved; endpoint = saved.endpoint.absoluteString; connected = true
        } catch { self.error = error.localizedDescription }
    }

    func connect(endpoint: String, apiKey: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, ["", "/"].contains(url.path), !apiKey.isEmpty else { throw CloudMusicError(message: "Enter an HTTPS warehouse endpoint and device key.") }
            let next = CloudConnection(endpoint: url, apiKey: apiKey)
            _ = try await request("/api/tracks?limit=1", connection: next)
            let data = try JSONEncoder().encode(next)
            let status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var entry = keychainQuery
                entry[kSecValueData as String] = data
                entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw CloudMusicError(message: "Cannot save music warehouse settings.") }
            } else if status != errSecSuccess { throw CloudMusicError(message: "Cannot save music warehouse settings.") }
            connection = next; self.endpoint = url.absoluteString; connected = true
            favorites = []; trending = []
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func disconnect() {
        let status = SecItemDelete(keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { error = AppLanguage.text("Cannot clear music warehouse settings."); return }
        connection = nil; endpoint = ""; connected = false; favorites = []; trending = []; error = nil
    }

    func refresh() async {
        guard connected else { return }
        do {
            var complete: [CloudTrack] = []
            while true {
                let page = try JSONDecoder().decode(TrackList.self, from: await request("/api/favorites?offset=\(complete.count)")).items
                complete += page
                if page.count < 100 { break }
            }
            favorites = complete
            let home = try JSONDecoder().decode(CloudHome.self, from: await request("/api/home"))
            trending = home.trending.compactMap { $0.onlineTrack }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func existing(_ track: OnlineTrack) async throws -> CloudTrack? {
        if track.kind == .telegram { return try JSONDecoder().decode(CloudTrack.self, from: await request("/api/tracks/\(track.id)")) }
        let list = try JSONDecoder().decode(TrackList.self, from: await request("/api/tracks?source_id=\(track.id)"))
        return list.items.first
    }

    func search(_ query: String) async throws -> [CloudTrack] {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "search", value: query)]
        return try JSONDecoder().decode(TrackList.self, from: await request("/api/tracks?\(components.percentEncodedQuery ?? "")")).items
    }

    func download(_ track: OnlineTrack, directory: URL) async throws -> URL? {
        guard let saved = try await existing(track) else { return nil }
        guard let audio = saved.files.first(where: \.available) else {
            if !saved.files.isEmpty { throw CloudMusicError(message: "Warehouse audio is not available. Check file status or size limits.") }
            return nil
        }
        let data = try await request("/api/tracks/\(saved.id)/content")
        let destination = directory.appending(path: audio.mime_type == "audio/mpeg" ? "audio.mp3" : "audio.m4a")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func upload(_ track: OnlineTrack, file: URL) async throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20_000_000 else { throw CloudMusicError(message: "Telegram cloud delivery is limited to 20 MB. The file was not uploaded.") }
        let bytes = try Data(contentsOf: file)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let boundary = UUID().uuidString
        var body = Data()
        let metadata = try JSONSerialization.data(withJSONObject: Self.metadata(track))
        for (name, value) in [("track", metadata), ("sha256", Data(hash.utf8))] {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(value); body.append(Data("\r\n".utf8))
        }
        let mp3 = file.pathExtension.lowercased() == "mp3"
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"audio.\(mp3 ? "mp3" : "m4a")\"\r\nContent-Type: \(mp3 ? "audio/mpeg" : "audio/mp4")\r\n\r\n".utf8))
        body.append(bytes); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        _ = try await request("/api/tracks", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    func syncYouTubeFavorites(_ tracks: [OnlineTrack]) async throws {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: await request("/api/favorites/snapshots", method: "POST"))
        for start in stride(from: 0, to: tracks.count, by: 20) {
            try Task.checkCancellation()
            let chunk = Array(tracks[start..<min(start + 20, tracks.count)])
            let data = try JSONSerialization.data(withJSONObject: ["tracks": chunk.map(Self.metadata)])
            _ = try await request("/api/favorites/snapshots/\(snapshot.id)", method: "PUT", body: data)
        }
        let complete = try JSONSerialization.data(withJSONObject: ["complete": true, "count": tracks.count])
        _ = try await request("/api/favorites/snapshots/\(snapshot.id)/commit", method: "POST", body: complete)
        await refresh()
    }

    func recordPlay(_ track: OnlineTrack) async {
        do {
            guard let saved = try await existing(track) else { return }
            _ = try await request("/api/tracks/\(saved.id)/play", method: "POST")
        } catch { self.error = error.localizedDescription }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json", connection supplied: CloudConnection? = nil) async throws -> Data {
        guard let settings = supplied ?? connection else { throw CloudMusicError(message: "Connect a music warehouse first.") }
        let url = URL(string: path, relativeTo: settings.endpoint)!.absoluteURL
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 180
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineMusicError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(CloudFailure.self, from: data)
            var message = failure?.error ?? "Music warehouse HTTP \(http.statusCode)"
            if let retry = http.value(forHTTPHeaderField: "Retry-After") { message += " (Retry-After: \(retry)s)" }
            if let job = failure?.job_id { message += " [\(job)]" }
            throw CloudMusicError(message: message)
        }
        return data
    }

    private static func metadata(_ track: OnlineTrack) -> [String: Any] {
        var value: [String: Any] = ["source_id": track.id, "title": track.title, "artist": track.artist, "album": track.albumTitle ?? ""]
        if let cover = track.coverURL { value["cover_url"] = cover.absoluteString }
        return value
    }

    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.c0versnow.C0SnowMusic.cloud", kSecAttrAccount as String: storageAccount]
    }
}

private struct TrackList: Decodable { let items: [CloudTrack] }
private struct Snapshot: Decodable { let id: String }
private struct CloudFailure: Decodable { let error: String; let job_id: String? }
private struct CloudHome: Decodable {
    struct Track: Decodable {
        let source_id: String?
        let title: String
        let artist: String
        let cover_url: URL?
        var onlineTrack: OnlineTrack? { source_id.map { OnlineTrack(id: $0, title: title, artist: artist, coverURL: cover_url) } }
    }
    let trending: [Track]
}
private struct CloudMusicError: LocalizedError {
    let message: String
    var errorDescription: String? { AppLanguage.text(message) }
}
