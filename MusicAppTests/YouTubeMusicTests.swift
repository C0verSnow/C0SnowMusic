import XCTest
import Synchronization
@testable import C0SnowMusic

final class YouTubeMusicTests: XCTestCase {
    func testMixedMusicRenderersKeepTopSongsVideosAlbumsAndArtists() throws {
        let data = Data(#"""
        {"contents":{"sectionListRenderer":{"contents":[
          {"musicCardShelfRenderer":{"title":{"runs":[{"text":"Top result"}]},"navigationEndpoint":{"watchEndpoint":{"videoId":"abcdefghijk","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}},"contents":[]}},
          {"musicShelfRenderer":{"title":{"runs":[{"text":"Songs"}]},"contents":[{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"12345678901"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"雪の音","navigationEndpoint":{"watchEndpoint":{"videoId":"12345678901"}}}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist"}]}}}]}}],"continuations":[{"nextContinuationData":{"continuation":"next-page"}}]}},
          {"musicCarouselShelfRenderer":{"header":{"musicCarouselShelfBasicHeaderRenderer":{"title":{"runs":[{"text":"Albums"}]}}},"contents":[{"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Album"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"MPREb_album","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}}}}},{"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Artist"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"UC_artist","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}}}}}]}}
        ]}}}
        """#.utf8)
        let page = try YouTubeMusicClient.parse(data)
        XCTAssertEqual(page.sections.dropFirst().map(\.title), ["Songs", "Albums"])
        XCTAssertEqual(page.tracks.map(\.id), ["abcdefghijk", "12345678901"])
        XCTAssertEqual(page.sections[2].items.map(\.kind), [.album, .artist])
        XCTAssertFalse(page.sections[2].items[0].isPlayable)
        XCTAssertEqual(page.continuation, "next-page")
    }

    func testContinuationAndEmptyShelvesAreRecognizedButConsentIsNot() throws {
        let empty = try YouTubeMusicClient.parse(Data(#"{"contents":{"musicShelfRenderer":{"contents":[]}}}"#.utf8))
        XCTAssertTrue(empty.tracks.isEmpty)
        let continuation = try YouTubeMusicClient.parse(Data(#"{"onResponseReceivedActions":[{"appendContinuationItemsAction":{"continuationItems":[{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"abcdefghijk"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Continued"}]}}}]}},{"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"more"}}}}]}}]}"#.utf8))
        XCTAssertEqual(continuation.tracks.first?.title, "Continued")
        XCTAssertEqual(continuation.continuation, "more")
        XCTAssertThrowsError(try YouTubeMusicClient.parse(Data(#"{"error":{"code":403}}"#.utf8)))
        let inline = try YouTubeMusicClient.parse(Data(#"{"contents":{"musicPlaylistShelfRenderer":{"contents":[{"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"inline-next"}}}}]}}}"#.utf8))
        XCTAssertEqual(inline.continuation, "inline-next", "Do not mistake the first liked-playlist page for a complete snapshot")
    }

    func testBootstrapMergesConfigurationAndRejectsTruncatedData() throws {
        let config = try YouTubeMusicClient.configuration(#"<script>ytcfg.set({"INNERTUBE_CONTEXT":{"client":{"clientVersion":"current","name":"A } quoted"}}});ytcfg.set({"OTHER":true});</script>"#)
        XCTAssertNotNil(config["INNERTUBE_CONTEXT"])
        XCTAssertEqual(config["OTHER"] as? Bool, true)
        XCTAssertThrowsError(try YouTubeMusicClient.configuration("ytcfg.set({\"truncated\":"))
    }

    func testAccountMenuFindsActualNameAndAvatarAndRejectsSignInPage() throws {
        let data = Data(#"{"actions":[{"openPopupAction":{"popup":{"multiPageMenuRenderer":{"header":{"activeAccountHeaderRenderer":{"accountName":{"runs":[{"text":"Music listener"}]},"channelHandle":{"runs":[{"text":"@listener"}]},"accountPhoto":{"thumbnails":[{"url":"https://example.com/avatar.jpg"}]}}}}}}}]}"#.utf8)
        let profile = YouTubeMusicClient.profile(in: try JSONSerialization.jsonObject(with: data))
        XCTAssertEqual(profile?.name, "Music listener")
        XCTAssertEqual(profile?.handle, "@listener")
        XCTAssertEqual(profile?.avatarURL?.absoluteString, "https://example.com/avatar.jpg")
        XCTAssertNil(YouTubeMusicClient.profile(in: ["signIn": true]))
    }

    func testCurrentLiveMusicSearchItemSections() throws {
        // Reduced public response captured 2026-11-15, preserving the provider's renderer topology.
        let data = Data(#"""
        {"contents":[{"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{"thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[{"url":"https://yt3.googleusercontent.com/mxqDOrw4zbfDBdd4kOnD2qBUtMklnAucEfrQUbr30pRLie0P3JIhJhBJ9wJq3NEeg2yVrT9lgrYid-w=w60-h60-l90-rj"},{"url":"https://yt3.googleusercontent.com/mxqDOrw4zbfDBdd4kOnD2qBUtMklnAucEfrQUbr30pRLie0P3JIhJhBJ9wJq3NEeg2yVrT9lgrYid-w=w120-h120-l90-rj"}]}}},"overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{"playNavigationEndpoint":{"watchEndpoint":{"videoId":"HgLfYfJtc8M","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}}}}},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"One Of The Girls","navigationEndpoint":{"watchEndpoint":{"videoId":"HgLfYfJtc8M","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song"},{"text":" • "},{"text":"The Weeknd","navigationEndpoint":{"browseEndpoint":{"browseId":"UClYV6hHlupm_S_ObS1W-DYw","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}}}},{"text":", "},{"text":"JENNIE","navigationEndpoint":{"browseEndpoint":{"browseId":"UCAl7xQ6q0PEgZMQD7zr4AKQ","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}}}},{"text":" & "},{"text":"Lily Rose Depp","navigationEndpoint":{"browseEndpoint":{"browseId":"UChGTI8sivCDh1AWues5lrDA","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}}}}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"1.6B plays"}]}}}],"playlistItemData":{"videoId":"HgLfYfJtc8M"}}}]}},{"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{"thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[{"url":"https://yt3.googleusercontent.com/5KPa09mXAuCZk4qr5s3oqZWPfSIhunC1zXdhhvCzMr-ZWOEGoBsULZZSWdKwYrew_-bItSOZFH1IXoA=w60-h60-l90-rj"},{"url":"https://yt3.googleusercontent.com/5KPa09mXAuCZk4qr5s3oqZWPfSIhunC1zXdhhvCzMr-ZWOEGoBsULZZSWdKwYrew_-bItSOZFH1IXoA=w120-h120-l90-rj"}]}}},"overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{"playNavigationEndpoint":{"watchEndpoint":{"videoId":"FQjnHJW69N8","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}}}}},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Good For You x One Of The Girls","navigationEndpoint":{"watchEndpoint":{"videoId":"FQjnHJW69N8","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song"},{"text":" • "},{"text":"dreamsoda","navigationEndpoint":{"browseEndpoint":{"browseId":"UCKNonPO42O0U2peuM6a_-lQ","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}}}}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"16M plays"}]}}}],"playlistItemData":{"videoId":"FQjnHJW69N8"}}}]}},{"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{"thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[{"url":"https://lh3.googleusercontent.com/U-SAmNOu4TynE818gLCfKsuHZ0U5YNEtO9mrjSI9WCCKERs98LzrCal5kajBBTQNwdcisoB2Bn-pHp4=w60-h60-p-l90-rj"},{"url":"https://lh3.googleusercontent.com/U-SAmNOu4TynE818gLCfKsuHZ0U5YNEtO9mrjSI9WCCKERs98LzrCal5kajBBTQNwdcisoB2Bn-pHp4=w120-h120-p-l90-rj"}]}}},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"The Weeknd"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist"},{"text":" • "},{"text":"236M monthly audience"}]}}}],"navigationEndpoint":{"browseEndpoint":{"browseId":"UClYV6hHlupm_S_ObS1W-DYw","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}}}}}]}},{"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{"thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[{"url":"https://yt3.googleusercontent.com/zqc2gYfTaa9enohFH8TdA75Ua7_40Zfr_96JheSkBOppz-XHZo41pUUmf8Y-abeOWxat0iJesNNClda1=w60-h60-l90-rj"},{"url":"https://yt3.googleusercontent.com/zqc2gYfTaa9enohFH8TdA75Ua7_40Zfr_96JheSkBOppz-XHZo41pUUmf8Y-abeOWxat0iJesNNClda1=w120-h120-l90-rj"}]}}},"overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{"playNavigationEndpoint":{"watchEndpoint":{"videoId":"4hPqE_oxlDQ","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}}}}},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"One Of Your Girls","navigationEndpoint":{"watchEndpoint":{"videoId":"4hPqE_oxlDQ","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song"},{"text":" • "},{"text":"Troye Sivan","navigationEndpoint":{"browseEndpoint":{"browseId":"UC11RplprGRVVtT2tgtcYzWg","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}}}}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"105M plays"}]}}}],"playlistItemData":{"videoId":"4hPqE_oxlDQ"}}}]}}]}
        """#.utf8)
        let page = try YouTubeMusicClient.parse(data)
        XCTAssertEqual(page.sections.flatMap(\.items).count, 4)
        XCTAssertTrue(page.sections.flatMap(\.items).contains { $0.kind == .artist })
        XCTAssertTrue(page.tracks.contains { $0.id == "HgLfYfJtc8M" })
    }

    func testPlaylistAlbumInThirdColumnIsKept() throws {
        let page = try YouTubeMusicClient.parse(Data(#"""
        {"contents":{"musicPlaylistShelfRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
          "playlistItemData":{"videoId":"abcdefghijk"},
          "flexColumns":[
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song"}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist","navigationEndpoint":{"browseEndpoint":{"browseId":"UC_artist"}}}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Album","navigationEndpoint":{"browseEndpoint":{"browseId":"MPREb_album"}}}]}}}
          ]
        }}]}}}
        """#.utf8))
        XCTAssertEqual(page.tracks.first?.artist, "Artist")
        XCTAssertEqual(page.tracks.first?.albumTitle, "Album")
    }

    func testLibraryGridsAndContinuationPreserveCollectionTypes() throws {
        let first = try YouTubeMusicClient.parse(Data(#"""
        {"contents":{"gridRenderer":{"items":[
          {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Saved playlist"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"VLsaved"}}}},
          {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Saved album"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"MPREb_saved"}}}},
          {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Saved artist"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"UC_saved"}}}}
        ],"continuations":[{"nextContinuationData":{"continuation":"next-grid"}}]}}}
        """#.utf8))
        XCTAssertEqual(first.sections.flatMap(\.items).map(\.kind), [.playlist, .album, .artist])
        XCTAssertEqual(first.continuation, "next-grid")
        let next = try YouTubeMusicClient.parse(Data(#"{"continuationContents":{"gridContinuation":{"items":[{"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Second playlist"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"VLsecond"}}}}]}}}"#.utf8))
        XCTAssertEqual(next.sections.flatMap(\.items).map(\.id), ["VLsecond"])
    }

    func testCompleteLibraryCollectionRequestsEveryPageAndDeduplicates() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryCollectionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let items = try await YouTubeMusicClient(session: session).collectionItems("FEmusic_liked_playlists", cookies: [])
        XCTAssertEqual(items.map(\.id), ["VLfirst", "VLsecond"])
        XCTAssertEqual(items.map(\.kind), [.playlist, .playlist])
    }

    func testBootstrapIsReusedAcrossReadsAndReplacedAfterAccountChange() async throws {
        let fixture = musicSession()
        defer { fixture.session.invalidateAndCancel() }
        _ = try await fixture.client.search("First", cookies: [])
        _ = try await fixture.client.browse("VLLM", cookies: [])
        XCTAssertEqual(BootstrapProtocol.paths(host: fixture.host).filter { $0 == "/" }.count, 1)
        let cookie = WebCookie(try XCTUnwrap(HTTPCookie(properties: [.name: "SAPISID", .value: "new-account", .domain: ".youtube.com", .path: "/", .secure: "TRUE"])))
        _ = try await fixture.client.search("Second", cookies: [cookie])
        XCTAssertEqual(BootstrapProtocol.paths(host: fixture.host).filter { $0 == "/" }.count, 2)
        _ = try await fixture.client.search("Signed out", cookies: [])
        XCTAssertEqual(BootstrapProtocol.paths(host: fixture.host).filter { $0 == "/" }.count, 3)
    }

    func testExpiredBootstrapIsReloaded() async throws {
        let fixture = musicSession(bootstrap: YouTubeMusicBootstrap(lifetime: 0))
        defer { fixture.session.invalidateAndCancel() }
        _ = try await fixture.client.search("First", cookies: [])
        _ = try await fixture.client.search("Second", cookies: [])
        XCTAssertEqual(BootstrapProtocol.paths(host: fixture.host).filter { $0 == "/" }.count, 2)
    }

    func testRejectedReadRefreshesBootstrapOnceAndLikeIsNeverRetried() async throws {
        let fixture = musicSession()
        defer { fixture.session.invalidateAndCancel() }
        _ = try await fixture.client.search("reject-first", cookies: [])
        let paths = BootstrapProtocol.paths(host: fixture.host)
        XCTAssertEqual(paths.filter { $0 == "/" }.count, 2)
        XCTAssertEqual(paths.filter { $0 == "/youtubei/v1/search" }.count, 2)
        do {
            try await fixture.client.setLiked(true, id: "abcdefghijk", cookies: [])
            XCTFail("Rejected likes must propagate the original failure")
        } catch { }
        XCTAssertEqual(BootstrapProtocol.paths(host: fixture.host).filter { $0 == "/youtubei/v1/like/like" }.count, 1)
    }

    func testFailedBootstrapCanBeRetriedAndConcurrentReadsShareOneLoad() async throws {
        let fixture = musicSession()
        defer { fixture.session.invalidateAndCancel() }
        BootstrapProtocol.failNextBootstrap(host: fixture.host)
        do {
            _ = try await fixture.client.search("Failure", cookies: [])
            XCTFail("Failed bootstrap must not be cached")
        } catch { }
        async let first = fixture.client.search("First", cookies: [])
        async let second = fixture.client.browse("VLLM", cookies: [])
        _ = try await (first, second)
        XCTAssertEqual(BootstrapProtocol.paths(host: fixture.host).filter { $0 == "/" }.count, 2)
    }

    private func musicSession(bootstrap: YouTubeMusicBootstrap = YouTubeMusicBootstrap()) -> (client: YouTubeMusicClient, session: URLSession, host: String) {
        let host = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BootstrapProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-Session": host]
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        return (YouTubeMusicClient(session: session, bootstrap: bootstrap), session, host)
    }

    func testOldAudioCacheMetadataStillDecodes() throws {
        let original = Data(#"{"id":"abcdefghijk","title":"Existing song","artist":"Existing artist"}"#.utf8)
        let track = try JSONDecoder().decode(OnlineTrack.self, from: original)
        XCTAssertTrue(track.isPlayable)
        XCTAssertNil(track.kind)
        XCTAssertEqual(track.title, "Existing song")
    }

    func testCookiesOnlyGoToTheirActualHostAndPath() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "SID", .value: "test", .domain: ".youtube.com", .path: "/", .secure: "TRUE"]))
        let shared = WebCookie(cookie)
        XCTAssertTrue(shared.matches(URL(string: "https://music.youtube.com/youtubei/v1/search")!))
        XCTAssertFalse(shared.matches(URL(string: "https://youtube.com.evil.example/")!))
        XCTAssertFalse(shared.matches(URL(string: "http://music.youtube.com/")!))
        let hostCookie = WebCookie(try XCTUnwrap(HTTPCookie(properties: [.name: "SID", .value: "test", .domain: "m.youtube.com", .path: "/"])))
        XCTAssertFalse(hostCookie.matches(URL(string: "https://music.youtube.com/")!))
    }
}

private final class BootstrapProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var paths: [String: [String]] = [:]
        var failedBootstraps: Set<String> = []
    }
    private static let state = Mutex(State())
    static func paths(host: String) -> [String] { state.withLock { $0.paths[host] ?? [] } }
    static func failNextBootstrap(host: String) { state.withLock { _ = $0.failedBootstraps.insert(host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let host = request.value(forHTTPHeaderField: "X-Test-Session")!
        let result = Self.state.withLock { state -> (Int, String) in
            state.paths[host, default: []].append(url.path)
            if url.path == "/" {
                if state.failedBootstraps.remove(host) != nil { return (503, "Unavailable") }
                return (200, #"<script>ytcfg.set({"INNERTUBE_CONTEXT":{"client":{"clientVersion":"test"}}});</script>"#)
            }
            let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
                stream.open(); defer { stream.close() }
                var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
                return data
            } ?? Data()
            if url.path.contains("like/like") || (String(decoding: body, as: UTF8.self).contains("reject-first") && state.paths[host]!.filter { $0 == url.path }.count == 1) {
                return (403, #"{"error":{"code":403}}"#)
            }
            return (200, #"{"contents":{"musicShelfRenderer":{"contents":[]}}}"#)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: result.0, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class LibraryCollectionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let payload: String
        if request.httpMethod != "POST" {
            payload = #"<script>ytcfg.set({"INNERTUBE_CONTEXT":{"client":{"clientVersion":"test"}}});</script>"#
        } else if url.query?.contains("continuation=next-grid") == true {
            payload = #"{"continuationContents":{"gridContinuation":{"items":[{"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"First"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"VLfirst"}}}},{"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Second"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"VLsecond"}}}}]}}}"#
        } else {
            payload = #"{"contents":{"gridRenderer":{"items":[{"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"First"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"VLfirst"}}}}],"continuations":[{"nextContinuationData":{"continuation":"next-grid"}}]}}}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
