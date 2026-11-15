import Foundation

struct OnlineTrack: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let artist: String
    let coverURL: URL?
    var watchURL: URL { URL(string: "https://m.youtube.com/watch?v=\(id)")! }
}

enum OnlineMusicError: LocalizedError {
    case invalidResponse, searchLayoutChanged, runtimeUnavailable, invalidAudio, cacheFull
    var errorDescription: String? {
        switch self {
        case .invalidResponse: String(localized: "在线请求失败，请重试。")
        case .searchLayoutChanged: String(localized: "YouTube 返回了验证页面或搜索结构已变化，请稍后重试。")
        case .runtimeUnavailable: String(localized: "音频下载组件未安装，请使用包含下载组件的构建。")
        case .invalidAudio: String(localized: "下载结果不是可播放的纯音频文件。")
        case .cacheFull: String(localized: "音频超过 500MB 缓存上限。")
        }
    }
}

struct YouTubeSearchClient: Sendable {
    func search(_ query: String) async throws -> [OnlineTrack] {
        var url = URLComponents(string: "https://m.youtube.com/results")!
        url.queryItems = [URLQueryItem(name: "search_query", value: query)]
        var request = URLRequest(url: url.url!)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Version/26.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8) else {
            throw OnlineMusicError.invalidResponse
        }
        return try Self.parse(html)
    }

    static func parse(_ html: String) throws -> [OnlineTrack] {
        let data = try initialData(in: html)
        let root = try JSONSerialization.jsonObject(with: data)
        var results: [OnlineTrack] = []
        var seen: Set<String> = []
        collect(root, results: &results, seen: &seen)
        return results
    }

    private static func initialData(in html: String) throws -> Data {
        let markers = ["var ytInitialData =", "ytInitialData =", "window[\"ytInitialData\"] =", "ytInitialData="]
        for marker in markers {
            guard let range = html.range(of: marker), let start = html[range.upperBound...].firstIndex(of: "{") else { continue }
            var depth = 0; var quoted = false; var escaped = false
            for index in html[start...].indices {
                let character = html[index]
                if quoted {
                    if escaped { escaped = false }
                    else if character == "\\" { escaped = true }
                    else if character == "\"" { quoted = false }
                } else {
                    if character == "\"" { quoted = true }
                    else if character == "{" { depth += 1 }
                    else if character == "}" {
                        depth -= 1
                        if depth == 0 { return Data(html[start...index].utf8) }
                    }
                }
            }
        }
        throw OnlineMusicError.searchLayoutChanged
    }

    private static func collect(_ node: Any, results: inout [OnlineTrack], seen: inout Set<String>) {
        if let nodes = node as? [Any] {
            for child in nodes { collect(child, results: &results, seen: &seen) }
        } else if let object = node as? [String: Any] {
            if object["adSlotRenderer"] != nil || object["promotedSparklesWebRenderer"] != nil { return }
            for name in ["videoRenderer", "compactVideoRenderer", "videoWithContextRenderer"] {
                if let video = object[name] as? [String: Any], let track = track(video), seen.insert(track.id).inserted {
                    results.append(track)
                    return
                }
            }
            if let video = object["lockupViewModel"] as? [String: Any],
               video["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
               let id = video["contentId"] as? String,
               let metadata = (video["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any],
               let title = (metadata["title"] as? [String: Any])?["content"] as? String, validID(id), seen.insert(id).inserted {
                let rows = metadata["metadata"] as? [String: Any]
                let metadataRows = rows?["contentMetadataViewModel"] as? [String: Any]
                let firstRow = (metadataRows?["metadataRows"] as? [[String: Any]])?.first
                let part = (firstRow?["metadataParts"] as? [[String: Any]])?.first
                let artist = (part?["text"] as? [String: Any])?["content"] as? String ?? String(localized: "未知艺术家")
                let image = (video["contentImage"] as? [String: Any])?["thumbnailViewModel"] as? [String: Any]
                let sources = (image?["image"] as? [String: Any])?["sources"] as? [[String: Any]]
                results.append(OnlineTrack(id: id, title: title, artist: artist, coverURL: thumbnail(sources)))
                return
            }
            for key in object.keys.sorted() { collect(object[key]!, results: &results, seen: &seen) }
        }
    }

    private static func track(_ video: [String: Any]) -> OnlineTrack? {
        guard let id = video["videoId"] as? String, validID(id) else { return nil }
        let title = text(video["title"])
        guard !title.isEmpty else { return nil }
        let artist = text(video["shortBylineText"] ?? video["ownerText"] ?? video["longBylineText"])
        let images = (video["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        return OnlineTrack(id: id, title: title, artist: artist.isEmpty ? String(localized: "未知艺术家") : artist, coverURL: thumbnail(images))
    }

    private static func text(_ node: Any?) -> String {
        guard let object = node as? [String: Any] else { return "" }
        return object["simpleText"] as? String ?? (object["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
    }

    private static func thumbnail(_ images: [[String: Any]]?) -> URL? {
        guard let value = images?.last?["url"] as? String else { return nil }
        return URL(string: value.hasPrefix("//") ? "https:" + value : value).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    static func validID(_ id: String) -> Bool {
        id.count == 11 && id.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
}
