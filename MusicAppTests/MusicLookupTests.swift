import XCTest
@testable import C0SnowMusic

final class MusicLookupTests: XCTestCase {
    func testFilenameFallbackAndEditionMatching() throws {
        let query = SongLookupQuery(title: "The Weeknd – Die For You", artist: "未知艺术家", album: "未知专辑", duration: 260)
        XCTAssertEqual(query.title, "Die For You")
        XCTAssertEqual(query.artist, "The Weeknd")
        XCTAssertEqual(query.album, "")
        let matches = try JSONDecoder().decode([LyricsMatch].self, from: Data("""
        [{"id":1,"trackName":"Die For You","artistName":"The Weeknd","albumName":"Starboy","duration":260,"instrumental":false,"plainLyrics":"First line","syncedLyrics":"[00:01.00]First line"},
         {"id":2,"trackName":"Die For You (Live)","artistName":"The Weeknd","albumName":"Live","duration":260,"instrumental":false,"plainLyrics":"First line","syncedLyrics":null},
         {"id":3,"trackName":"Die For You","artistName":"The Weeknd","albumName":"Another edition","duration":195,"instrumental":false,"plainLyrics":"First line","syncedLyrics":null}]
        """.utf8))
        XCTAssertTrue(matches[0].matches(query))
        XCTAssertTrue(matches[0].isSynced)
        XCTAssertFalse(matches[1].matches(query))
        XCTAssertFalse(matches[1].isSynced)
        XCTAssertFalse(matches[2].matches(query))
        let albumQuery = SongLookupQuery(title: query.title, artist: query.artist, album: "Live", duration: 260)
        XCTAssertFalse(matches[0].matches(albumQuery))
    }

    func testPlainTextAndInstrumentalDoNotInventTimestamps() throws {
        let matches = try JSONDecoder().decode([LyricsMatch].self, from: Data("""
        [{"id":1,"trackName":"Example","artistName":"Example artist","albumName":"Example album","duration":3,"instrumental":false,"plainLyrics":"First line\\nSecond line","syncedLyrics":null},
         {"id":2,"trackName":"Instrumental","artistName":"Example artist","albumName":"Example album","duration":3,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}]
        """.utf8))
        XCTAssertEqual(matches[0].text, "First line\nSecond line")
        XCTAssertFalse(matches[0].isSynced)
        XCTAssertTrue(matches[1].instrumental)
        XCTAssertNil(matches[1].text)
    }

    func testOffsetUsesTheSameClockForHighlightAndSeek() throws {
        let lines = LRCParser.parse("[00:01.00]First\n[00:03.00]Second")
        let timeline = LyricTimeline(lines: lines, offset: 0.5)
        XCTAssertNil(timeline.activeLine(at: 1.4))
        XCTAssertEqual(timeline.activeLine(at: 1.5), lines[0].id)
        XCTAssertEqual(timeline.activeLine(at: 3.6), lines[1].id)
        XCTAssertEqual(timeline.playbackTime(for: lines[1]), 3.5, accuracy: 0.001)
        let early = LyricTimeline(lines: lines, offset: -2)
        XCTAssertEqual(early.playbackTime(for: lines[0]), 0)
    }

    func testMissingDurationRemainsUnknown() throws {
        let match = try JSONDecoder().decode(LyricsMatch.self, from: Data("""
        {"id":1,"trackName":"Example","artistName":"Artist","albumName":"Album","duration":null,"instrumental":false,"plainLyrics":"Text","syncedLyrics":null}
        """.utf8))
        XCTAssertNil(match.duration)
        XCTAssertFalse(match.matches(SongLookupQuery(title: "Example", artist: "Artist", album: "Album", duration: 3)))
    }

    func testRetryAfterSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(MusicLookupClient.retryDelay("12", now: now), 12)
        XCTAssertEqual(MusicLookupClient.retryDelay("Thu, 01 Jan 1970 00:00:45 GMT", now: now), 45)
        XCTAssertEqual(MusicLookupClient.retryDelay("invalid", now: now), 30)
    }

    func testCoverMatchKeepsAlbumAndArtistTogether() throws {
        let data = Data("""
        {"release-groups":[{"id":"2f49b57a-705c-4bd6-ae22-b3446a2018f9","title":"Example album","artist-credit":[{"name":"Example artist"}]}]}
        """.utf8)
        let release = try XCTUnwrap(JSONDecoder().decode(CoverSearchResponse.self, from: data).groups.first)
        XCTAssertEqual(release.artworkURL.absoluteString, "https://coverartarchive.org/release-group/2f49b57a-705c-4bd6-ae22-b3446a2018f9/front-500")
        XCTAssertTrue(release.matches(album: "Example album", artist: "example ARTIST"))
        XCTAssertFalse(release.matches(album: "Live album", artist: "Example artist"))
        XCTAssertFalse(release.matches(album: "Example album", artist: "Different artist"))
    }
}
