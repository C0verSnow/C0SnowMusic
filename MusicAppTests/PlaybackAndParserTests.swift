import XCTest
import AVFoundation
@testable import C0SnowMusic

final class ParserTests: XCTestCase {
    func testLRCMultipleTimestampsOffsetAndMalformedInput() {
        let lines = LRCParser.parse("[offset:100]\n[00:01.25][02:03.456]你好\n[artist:Test]\n[00:99.00]invalid\n[03:00]End")
        XCTAssertEqual(lines.map(\.text), ["你好", "你好", "End"])
        XCTAssertEqual(lines[0].time, 1.35, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 123.556, accuracy: 0.001)
        XCTAssertTrue(LRCParser.parse("Plain text without timestamps").isEmpty)
    }

    func testSHA256KnownDigest() throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try LibraryFiles.hash(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testQueueRepeatInsertionDuplicateIdentityAndRemoval() {
        let a = UUID(), b = UUID(), c = UUID()
        var queue = QueueManager()
        queue.replace([a, b, a], startingAt: 0)
        XCTAssertNotEqual(queue.entries[0].id, queue.entries[2].id)
        XCTAssertTrue(queue.advance(automatic: true, repeatMode: .one))
        XCTAssertEqual(queue.index, 0)
        XCTAssertTrue(queue.advance(automatic: false, repeatMode: .one))
        XCTAssertEqual(queue.current?.songID, b)
        queue.insert(c, next: true)
        XCTAssertEqual(queue.entries[2].songID, c)
        queue.remove(IndexSet(integer: 0))
        XCTAssertEqual(queue.current?.songID, b)
        queue.index = queue.entries.count - 1
        XCTAssertFalse(queue.advance(automatic: true, repeatMode: .off))
        XCTAssertTrue(queue.advance(automatic: true, repeatMode: .all))
        XCTAssertEqual(queue.index, 0)
        let first = queue.current
        queue.shuffleUpcoming()
        XCTAssertEqual(queue.current, first)
        XCTAssertEqual(Set(queue.entries.map(\.songID)), [a, b, c])
    }
}

@MainActor final class AVPlayerIntegrationTests: XCTestCase {
    func testActualPlaybackSeekPauseAndEndForEveryFormat() async throws {
        let engine = AVPlayerEngine()
        let audioSession = AudioSessionManager()
        try audioSession.activate()
        defer { engine.stop() }
        var elapsed: Double = 0
        var playing = false
        var ended = false
        var failure: String?
        engine.onTime = { elapsed = $0 }
        engine.onPlaying = { playing = $0 }
        engine.onEnded = { ended = true }
        engine.onError = { failure = $0 }
        for (name, ext) in [("Test Tone", "wav"), ("Fixture", "mp3"), ("Fixture", "flac"), ("Fixture", "m4a"),
                            ("Fixture", "aac"), ("Fixture-ALAC", "m4a"), ("Fixture", "aiff"), ("Fixture-24bit-96k", "flac")] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
            elapsed = 0; playing = false; ended = false; failure = nil
            try await engine.prepare(url)
            engine.play()
            try await waitUntil { (playing && elapsed > 0.25) || failure != nil }
            XCTAssertNil(failure, "\(name).\(ext)")
            XCTAssertGreaterThan(elapsed, 0.25)
            engine.pause()
            try await waitUntil { !playing }
            let sought = await engine.seek(to: 2)
            XCTAssertTrue(sought, "\(name).\(ext)")
            engine.play()
            try await waitUntil { ended || failure != nil }
            XCTAssertTrue(ended, "\(name).\(ext)")
            XCTAssertNil(failure)
            engine.stop()
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition(), "Playback condition timed out")
    }
}
