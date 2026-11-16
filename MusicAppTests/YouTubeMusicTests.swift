import XCTest
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
        XCTAssertEqual(page.sections.map(\.title), ["Top result", "Songs", "Albums"])
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

    func testOldAudioCacheMetadataStillDecodes() throws {
        let original = Data(#"{"id":"abcdefghijk","title":"Existing song","artist":"Existing artist"}"#.utf8)
        let track = try JSONDecoder().decode(OnlineTrack.self, from: original)
        XCTAssertTrue(track.isPlayable)
        XCTAssertNil(track.kind)
        XCTAssertEqual(track.title, "Existing song")
    }
}
