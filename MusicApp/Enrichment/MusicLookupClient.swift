import Foundation

struct SongLookupQuery: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: Double

    init(title: String, artist: String, album: String, duration: Double) {
        self.title = title
        self.artist = artist == "未知艺术家" ? "" : artist
        self.album = album == "未知专辑" ? "" : album
        self.duration = duration
        if self.artist.isEmpty {
            for separator in [" – ", " — ", " - "] {
                if let range = title.range(of: separator) {
                    self.artist = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    self.title = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
    }
}

struct LyricsMatch: Decodable, Identifiable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double?
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    let isSynced: Bool

    enum CodingKeys: String, CodingKey { case id, trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        trackName = try values.decode(String.self, forKey: .trackName)
        artistName = try values.decode(String.self, forKey: .artistName)
        albumName = try values.decode(String.self, forKey: .albumName)
        let seconds = try values.decodeIfPresent(Double.self, forKey: .duration)
        duration = seconds.flatMap { $0 >= 0 ? $0 : nil }
        instrumental = try values.decode(Bool.self, forKey: .instrumental)
        plainLyrics = try values.decodeIfPresent(String.self, forKey: .plainLyrics)
        syncedLyrics = try values.decodeIfPresent(String.self, forKey: .syncedLyrics)
        isSynced = !LRCParser.parse(syncedLyrics ?? "").isEmpty
    }

    var text: String? {
        if let syncedLyrics, !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return syncedLyrics }
        if let plainLyrics, !plainLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return plainLyrics }
        return nil
    }
    func matches(_ query: SongLookupQuery) -> Bool {
        guard let duration else { return false }
        return Self.normalized(trackName) == Self.normalized(query.title)
        && (query.artist.isEmpty || Self.normalized(artistName) == Self.normalized(query.artist))
        && (query.album.isEmpty || Self.normalized(albumName) == Self.normalized(query.album))
        && abs(duration - query.duration) <= 2
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct CoverReleaseGroup: Decodable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artistCredit: [ArtistCredit]
    enum CodingKeys: String, CodingKey { case id, title; case artistCredit = "artist-credit" }
    struct ArtistCredit: Decodable, Sendable { let name: String; let joinphrase: String? }

    // CAA rejects uppercase UUIDs even though UUID.uuidString emits uppercase.
    var artworkURL: URL {
        URL(string: "https://coverartarchive.org/release-group/\(id.uuidString.lowercased())/front-500")!
    }

    func matches(album: String, artist: String) -> Bool {
        LyricsMatch.normalized(title) == LyricsMatch.normalized(album)
        && LyricsMatch.normalized(artistCredit.map { $0.name + ($0.joinphrase ?? "") }.joined()) == LyricsMatch.normalized(artist)
    }
}

struct CoverSearchResponse: Decodable, Sendable {
    let groups: [CoverReleaseGroup]
    enum CodingKeys: String, CodingKey { case groups = "release-groups" }
}

enum MusicLookupError: LocalizedError {
    case unavailable(Int), retryLater(Int), invalidResponse, noLyrics, noCover
    var errorDescription: String? {
        switch self {
        case .unavailable(let status): "在线服务暂时不可用（\(status)），请稍后重试。"
        case .retryLater(let seconds): "在线服务繁忙，请在 \(seconds) 秒后重试。"
        case .invalidResponse: "在线服务返回了无法读取的数据。"
        case .noLyrics: "这一版本没有可下载的歌词。"
        case .noCover: "未找到这个专辑的封面。歌词仍可单独保存。"
        }
    }
}

actor MusicLookupClient {
    static let shared = MusicLookupClient()
    private static let userAgent = "C0SnowMusic/1.0.4 (https://github.com/C0verSnow/C0SnowMusic)"
    private let session: URLSession
    private var retryDates: [String: Date] = [:]
    private var lastMusicBrainzRequest = Date.distantPast

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            self.session = URLSession(configuration: configuration)
        }
    }

    func search(_ query: SongLookupQuery) async throws -> [LyricsMatch] {
        var exact: LyricsMatch?
        if !query.artist.isEmpty, (1...3600).contains(query.duration) {
            var lookup = URLComponents(string: "https://lrclib.net/api/get")!
            lookup.queryItems = [URLQueryItem(name: "track_name", value: query.title), URLQueryItem(name: "artist_name", value: query.artist),
                                 URLQueryItem(name: "duration", value: String(query.duration))]
            if !query.album.isEmpty { lookup.queryItems?.append(URLQueryItem(name: "album_name", value: query.album)) }
            do {
                let match = try JSONDecoder().decode(LyricsMatch.self, from: await fetch(lookup.url!))
                if match.matches(query) {
                    if match.isSynced || match.instrumental { return [match] }
                    exact = match
                }
            } catch MusicLookupError.unavailable(404) { }
            try await Task.sleep(for: .milliseconds(300))
        }
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "track_name", value: query.title)]
        if !query.artist.isEmpty { components.queryItems?.append(URLQueryItem(name: "artist_name", value: query.artist)) }
        if !query.album.isEmpty { components.queryItems?.append(URLQueryItem(name: "album_name", value: query.album)) }
        let data = try await fetch(components.url!)
        var matches = try JSONDecoder().decode([LyricsMatch].self, from: data)
        if let exact, !matches.contains(where: { $0.id == exact.id }) { matches.insert(exact, at: 0) }
        return matches.filter { !$0.trackName.isEmpty }.sorted { lhs, rhs in
            if lhs.matches(query) != rhs.matches(query) { return lhs.matches(query) }
            if lhs.isSynced != rhs.isSynced { return lhs.isSynced }
            return (lhs.duration.map { abs($0 - query.duration) } ?? .infinity) < (rhs.duration.map { abs($0 - query.duration) } ?? .infinity)
        }
    }

    func cover(for match: LyricsMatch) async throws -> Data {
        guard !match.albumName.isEmpty else { throw MusicLookupError.noCover }
        let interval = Date.now.timeIntervalSince(lastMusicBrainzRequest)
        if interval < 1 { try await Task.sleep(for: .seconds(1 - interval)) }
        lastMusicBrainzRequest = .now
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release-group/")!
        let album = Self.phrase(match.albumName)
        let artist = Self.phrase(match.artistName)
        components.queryItems = [URLQueryItem(name: "query", value: "releasegroup:\"\(album)\" AND artist:\"\(artist)\""),
                                 URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "10")]
        let data = try await fetch(components.url!)
        let result = try JSONDecoder().decode(CoverSearchResponse.self, from: data)
        let groups = result.groups.filter { $0.matches(album: match.albumName, artist: match.artistName) }
        for group in groups {
            do { return try await fetch(group.artworkURL) }
            catch MusicLookupError.unavailable(404) { continue }
        }
        throw MusicLookupError.noCover
    }

    private func fetch(_ url: URL) async throws -> Data {
        let host = url.host() ?? ""
        if let retry = retryDates[host], retry > .now { throw MusicLookupError.retryLater(Int(ceil(retry.timeIntervalSinceNow))) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MusicLookupError.invalidResponse }
        if response.statusCode == 429 || response.statusCode == 503 {
            let delay = Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"), now: .now)
            retryDates[host] = .now.addingTimeInterval(delay)
            throw MusicLookupError.retryLater(Int(ceil(delay)))
        }
        guard (200...299).contains(response.statusCode) else { throw MusicLookupError.unavailable(response.statusCode) }
        return data
    }

    static func retryDelay(_ value: String?, now: Date) -> Double {
        if let value, let seconds = Double(value), seconds >= 0 { return seconds }
        if let value {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let date = formatter.date(from: value) { return max(0, date.timeIntervalSince(now)) }
        }
        return 30
    }

    private static func phrase(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
