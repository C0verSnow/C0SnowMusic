import CryptoKit
import Foundation

struct MusicSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [OnlineTrack]
}

struct MusicPage: Sendable {
    var sections: [MusicSection]
    var continuation: String?
    var tracks: [OnlineTrack] { sections.flatMap(\.items).filter(\.isPlayable) }
}

struct YouTubeProfile: Codable, Sendable, Equatable {
    let name: String
    let handle: String?
    let avatarURL: URL?
}

enum MusicSearchFilter: String, CaseIterable, Identifiable {
    case all = "All", songs = "Songs", videos = "Videos", albums = "Albums", artists = "Artists", playlists = "Playlists"
    var id: String { rawValue }
    var params: String? {
        switch self {
        case .all: nil
        case .songs: "EgWKAQIIAWoMEA4QChADEAQQCRAF"
        case .videos: "EgWKAQIQAWoMEA4QChADEAQQCRAF"
        case .albums: "EgWKAQIYAWoMEA4QChADEAQQCRAF"
        case .artists: "EgWKAQIgAWoMEA4QChADEAQQCRAF"
        case .playlists: "EgeKAQQoAEABagwQDhAKEAMQBBAJEAU%3D"
        }
    }
}

// Independent implementation; renderer/API design references are in TELEGRAM_MUSIC_RESEARCH.md.
struct YouTubeMusicClient: Sendable {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func search(_ query: String, filter: MusicSearchFilter = .all, continuation: String? = nil, cookies: [WebCookie]) async throws -> MusicPage {
        var body: [String: Any] = ["query": query]
        if let params = filter.params { body["params"] = params }
        return try Self.parse(await call("search", body: body, continuation: continuation, cookies: cookies))
    }

    func browse(_ id: String, continuation: String? = nil, cookies: [WebCookie]) async throws -> MusicPage {
        try Self.parse(await call("browse", body: ["browseId": id], continuation: continuation, cookies: cookies))
    }

    func likedTracks(cookies: [WebCookie]) async throws -> [OnlineTrack] {
        try await collectionItems("VLLM", cookies: cookies).filter(\.isPlayable)
    }

    func collectionItems(_ browseID: String, cookies: [WebCookie]) async throws -> [OnlineTrack] {
        var page = try await browse(browseID, cookies: cookies)
        var items = page.sections.flatMap(\.items)
        var seenTokens: Set<String> = []
        while let token = page.continuation {
            guard seenTokens.insert(token).inserted else { throw OnlineMusicError.searchLayoutChanged }
            try Task.checkCancellation()
            page = try await browse(browseID, continuation: token, cookies: cookies)
            items += page.sections.flatMap(\.items)
        }
        var ids: Set<String> = []
        return items.filter { ids.insert($0.id).inserted }
    }

    func profile(cookies: [WebCookie]) async throws -> YouTubeProfile {
        let data = try await call("account/account_menu", body: [:], cookies: cookies)
        guard let profile = Self.profile(in: try JSONSerialization.jsonObject(with: data)) else { throw OnlineMusicError.invalidResponse }
        return profile
    }

    func setLiked(_ liked: Bool, id: String, cookies: [WebCookie]) async throws {
        _ = try await call(liked ? "like/like" : "like/removelike", body: ["target": ["videoId": id]], cookies: cookies)
        let actual = try await likedTracks(cookies: cookies)
        guard actual.contains(where: { $0.id == id }) == liked else { throw OnlineMusicError.invalidResponse }
    }

    private func call(_ endpoint: String, body: [String: Any], continuation: String? = nil, cookies: [WebCookie]) async throws -> Data {
        var bootstrap = URLRequest(url: URL(string: "https://music.youtube.com/")!)
        headers(&bootstrap, cookies: cookies)
        let (page, response) = try await session.data(for: bootstrap)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let html = String(data: page, encoding: .utf8) else { throw OnlineMusicError.invalidResponse }
        let config = try Self.configuration(html)
        guard var context = config["INNERTUBE_CONTEXT"] as? [String: Any] else { throw OnlineMusicError.searchLayoutChanged }
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        if let continuation { components.queryItems?.append(URLQueryItem(name: "continuation", value: continuation)) }
        if var client = context["client"] as? [String: Any] {
            client["hl"] = "en"
            context["client"] = client
        }
        var payload = body
        payload["context"] = context
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        headers(&request, cookies: cookies)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let client = context["client"] as? [String: Any] {
            request.setValue("67", forHTTPHeaderField: "X-Youtube-Client-Name")
            request.setValue(client["clientVersion"] as? String, forHTTPHeaderField: "X-Youtube-Client-Version")
            request.setValue(client["visitorData"] as? String, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, result) = try await session.data(for: request)
        guard (result as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else { throw OnlineMusicError.invalidResponse }
        return data
    }

    private func headers(_ request: inout URLRequest, cookies: [WebCookie]) {
        request.timeoutInterval = 30
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        let eligible = cookies.filter { $0.isYouTube && $0.matches(request.url!) }
        for (key, value) in HTTPCookie.requestHeaderFields(with: eligible.compactMap(\.cookie)) { request.setValue(value, forHTTPHeaderField: key) }
        if let sapisid = eligible.first(where: { $0.name == "SAPISID" }) ?? eligible.first(where: { $0.name == "__Secure-3PAPISID" }) {
            let timestamp = Int(Date.now.timeIntervalSince1970)
            let input = "\(timestamp) \(sapisid.value) https://music.youtube.com"
            let digest = Insecure.SHA1.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
            request.setValue("SAPISIDHASH \(timestamp)_\(digest)", forHTTPHeaderField: "Authorization")
            request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        }
    }

    static func configuration(_ html: String) throws -> [String: Any] {
        var config: [String: Any] = [:]
        var remainder = html[...]
        while let marker = remainder.range(of: "ytcfg.set(") {
            remainder = remainder[marker.upperBound...]
            guard let start = remainder.firstIndex(of: "{") else { break }
            var depth = 0; var quoted = false; var escaped = false
            var complete = false
            for index in remainder[start...].indices {
                let c = remainder[index]
                if quoted {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
                } else {
                    if c == "\"" { quoted = true } else if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }
                }
                if depth == 0 {
                    if let object = try? JSONSerialization.jsonObject(with: Data(remainder[start...index].utf8)) as? [String: Any] { config.merge(object) { _, new in new } }
                    remainder = remainder[remainder.index(after: index)...]
                    complete = true
                    break
                }
            }
            if !complete { throw OnlineMusicError.searchLayoutChanged }
        }
        guard !config.isEmpty else { throw OnlineMusicError.searchLayoutChanged }
        return config
    }

    static func parse(_ data: Data) throws -> MusicPage {
        let root = try JSONSerialization.jsonObject(with: data)
        var sections: [MusicSection] = []
        var continuation: String?
        var recognized = false
        func visit(_ node: Any) {
            if let array = node as? [Any] { for child in array { visit(child) }; return }
            guard let object = node as? [String: Any] else { return }
            if let section = object["itemSectionRenderer"] as? [String: Any], let contents = section["contents"] as? [[String: Any]] {
                let items = contents.compactMap { child -> OnlineTrack? in
                    guard let value = child["musicResponsiveListItemRenderer"] as? [String: Any] else { visit(child); return nil }
                    return item(value)
                }
                if !items.isEmpty {
                    recognized = true
                    // Current search responses use one itemSection per result, without shelf titles.
                    let title: String
                    switch items[0].kind {
                    case .song: title = AppLanguage.text("Songs")
                    case .video: title = AppLanguage.text("Videos")
                    case .album: title = AppLanguage.text("Albums")
                    case .artist: title = AppLanguage.text("Artists")
                    default: title = AppLanguage.text("Playlists")
                    }
                    if let last = sections.last, last.title == title {
                        sections[sections.count - 1] = MusicSection(id: last.id, title: title, items: last.items + items)
                    } else { sections.append(MusicSection(id: "section-\(sections.count)", title: title, items: items)) }
                }
                return
            }
            if let action = object["appendContinuationItemsAction"] as? [String: Any], let contents = action["continuationItems"] as? [[String: Any]] {
                recognized = true
                let items = contents.compactMap { content -> OnlineTrack? in
                    guard let value = (content["musicResponsiveListItemRenderer"] ?? content["musicTwoRowItemRenderer"]) as? [String: Any] else { visit(content); return nil }
                    return item(value)
                }
                if !items.isEmpty { sections.append(MusicSection(id: "section-\(sections.count)", title: AppLanguage.text("Songs"), items: items)) }
                return
            }
            if let next = object["nextContinuationData"] as? [String: Any] { continuation = next["continuation"] as? String }
            if let next = object["continuationCommand"] as? [String: Any] { continuation = next["token"] as? String }
            for name in ["musicShelfRenderer", "musicShelfContinuation", "musicPlaylistShelfRenderer", "musicPlaylistShelfContinuation", "musicCardShelfRenderer", "musicCarouselShelfRenderer", "gridRenderer", "gridContinuation"] {
                if let shelf = object[name] as? [String: Any] {
                    recognized = true
                    var items: [OnlineTrack] = []
                    if let top = item(shelf) { items.append(top) }
                    for content in (shelf["contents"] ?? shelf["items"]) as? [[String: Any]] ?? [] {
                        if content["continuationItemRenderer"] != nil { visit(content); continue }
                        for renderer in ["musicResponsiveListItemRenderer", "musicTwoRowItemRenderer"] {
                            if let value = content[renderer] as? [String: Any], let parsed = item(value) { items.append(parsed) }
                        }
                    }
                    let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
                    let title = name == "musicCardShelfRenderer" ? AppLanguage.text("Top result") : text(shelf["title"] ?? header?["title"])
                    if !items.isEmpty { sections.append(MusicSection(id: "section-\(sections.count)", title: title.isEmpty ? AppLanguage.text("Songs") : title, items: items)) }
                    if let next = (shelf["continuations"] as? [[String: Any]])?.first?["nextContinuationData"] as? [String: Any] { continuation = next["continuation"] as? String }
                    return
                }
            }
            if object["messageRenderer"] != nil { recognized = true }
            for key in object.keys.sorted() { visit(object[key]!) }
        }
        visit(root)
        guard recognized else { throw OnlineMusicError.searchLayoutChanged }
        return MusicPage(sections: sections, continuation: continuation)
    }

    private static func item(_ value: [String: Any]) -> OnlineTrack? {
        let columns = value["flexColumns"] as? [[String: Any]] ?? []
        let first = columns.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        let second = columns.dropFirst().first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        let titleNode = value["title"] ?? first?["text"]
        let title = text(titleNode)
        guard !title.isEmpty else { return nil }
        let runs = (titleNode as? [String: Any])?["runs"] as? [[String: Any]]
        let endpoint = value["navigationEndpoint"] as? [String: Any] ?? runs?.first?["navigationEndpoint"] as? [String: Any]
        let play = (value["overlay"] as? [String: Any])?["musicItemThumbnailOverlayRenderer"] as? [String: Any]
        let button = (play?["content"] as? [String: Any])?["musicPlayButtonRenderer"] as? [String: Any]
        let watch = endpoint?["watchEndpoint"] as? [String: Any] ?? (button?["playNavigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any]
        let playlistData = value["playlistItemData"] as? [String: Any]
        let videoID = playlistData?["videoId"] as? String ?? watch?["videoId"] as? String
        let browse = endpoint?["browseEndpoint"] as? [String: Any]
        let browseID = browse?["browseId"] as? String
        let config = browse?["browseEndpointContextSupportedConfigs"] as? [String: Any]
        let page = (config?["browseEndpointContextMusicConfig"] as? [String: Any])?["pageType"] as? String ?? ""
        let musicConfig = (watch?["watchEndpointMusicSupportedConfigs"] as? [String: Any])?["watchEndpointMusicConfig"] as? [String: Any]
        let videoType = musicConfig?["musicVideoType"] as? String ?? ""
        let kind: MusicItemKind
        if page.contains("ARTIST") || browseID?.hasPrefix("UC") == true { kind = .artist }
        else if page.contains("ALBUM") || browseID?.hasPrefix("MPRE") == true { kind = .album }
        else if browseID != nil { kind = .playlist }
        else if let videoID, YouTubeSearchClient.validID(videoID) { kind = videoType.contains("ATV") ? .song : .video }
        else { return nil }
        let thumb = (value["thumbnail"] ?? value["thumbnailRenderer"]) as? [String: Any]
        let musicThumb = thumb?["musicThumbnailRenderer"] as? [String: Any]
        let images = (musicThumb?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let cover = (images?.last?["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        let subtitle = value["subtitle"] ?? second?["text"]
        let subtitleRuns = ((value["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []) + columns.dropFirst().flatMap { column -> [[String: Any]] in
            let renderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
            return (renderer?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
        }
        let album = subtitleRuns.first { run in
            let destination = (run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
            return (destination?["browseId"] as? String)?.hasPrefix("MPRE") == true
        }?["text"] as? String
        let artist = subtitleRuns.filter { run in
            let destination = (run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
            return (destination?["browseId"] as? String)?.hasPrefix("UC") == true
        }.compactMap { $0["text"] as? String }.joined(separator: ", ")
        let id = (kind == .song || kind == .video) ? videoID! : browseID!
        return OnlineTrack(id: id, title: title, artist: artist.isEmpty ? text(subtitle) : artist, coverURL: cover, kind: kind, browseID: browseID, albumTitle: album)
    }

    static func profile(in node: Any) -> YouTubeProfile? {
        if let array = node as? [Any] { return array.lazy.compactMap { profile(in: $0) }.first }
        guard let object = node as? [String: Any] else { return nil }
        if let header = object["activeAccountHeaderRenderer"] as? [String: Any] {
            let name = text(header["accountName"])
            guard !name.isEmpty else { return nil }
            let photos = (header["accountPhoto"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let avatar = (photos?.last?["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return YouTubeProfile(name: name, handle: text(header["channelHandle"]), avatarURL: avatar)
        }
        return object.values.lazy.compactMap { profile(in: $0) }.first
    }

    private static func text(_ node: Any?) -> String {
        guard let object = node as? [String: Any] else { return "" }
        return object["simpleText"] as? String ?? (object["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
    }
}
