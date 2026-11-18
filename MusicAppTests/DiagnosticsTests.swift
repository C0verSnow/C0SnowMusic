import XCTest
@testable import C0SnowMusic

@MainActor final class DiagnosticsTests: XCTestCase {
    func testActiveStageAndFailureRemainVisibleWithoutLeakingRequestCredentials() {
        let diagnostics = AppDiagnostics()
        let id = diagnostics.begin("Prepare audio")
        diagnostics.step(id, "HTTP request", detail: "https://media.test/audio?signature=secret-signature")
        XCTAssertEqual(diagnostics.active.first?.stage, "HTTP request")
        XCTAssertFalse(diagnostics.active.first?.detail.contains("secret-signature") ?? true)
        diagnostics.finish(id, error: URLError(.timedOut))
        XCTAssertTrue(diagnostics.active.isEmpty)
        XCTAssertTrue(diagnostics.report.contains("-1001"))
        XCTAssertTrue(diagnostics.report.contains("media.test"))
        XCTAssertFalse(diagnostics.report.contains("secret-signature"))
    }

    func testSecretRedactionCoversHeadersBearerBotTokenAndSignedURLs() {
        let raw = """
        Authorization: Bearer device-secret
        Cookie: SAPISID=cookie-secret
        X-Admin-Key: admin-secret
        request https://api.telegram.org/bot123456789:abcdefghijklmnopqrstuvwxyz012345/getFile?file_id=private
        https://user:password@media.test/audio?sig=signed-secret
        Bearer bare-secret
        """
        let output = AppDiagnostics.redact(raw)
        for secret in ["device-secret", "cookie-secret", "admin-secret", "abcdefghijklmnopqrstuvwxyz", "password", "private", "signed-secret", "bare-secret"] {
            XCTAssertFalse(output.contains(secret), secret)
        }
        XCTAssertTrue(output.contains("api.telegram.org"))
        XCTAssertTrue(output.contains("media.test"))
    }

    func testRealDownloaderEventFileUpdatesOnceAndDefersIncompleteLines() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "diagnostics.jsonl")
        let diagnostics = AppDiagnostics()
        let id = diagnostics.begin("On-device download")
        let first = #"{"stage":"YouTube extraction","message":"Downloading webpage"}"#
        let second = #"{"stage":"Downloading audio","message":"65536 bytes received","timestamp":1700000000.25}"#
        try (first + "\n" + second).write(to: file, atomically: true, encoding: .utf8)
        diagnostics.collectDownloadEvents(from: file, operation: id)
        XCTAssertEqual(diagnostics.active.first?.detail, "Downloading webpage")
        let count = diagnostics.events.count
        diagnostics.collectDownloadEvents(from: file, operation: id)
        XCTAssertEqual(diagnostics.events.count, count)
        try (first + "\n" + second + "\n").write(to: file, atomically: true, encoding: .utf8)
        diagnostics.collectDownloadEvents(from: file, operation: id)
        XCTAssertEqual(diagnostics.active.first?.stage, "Downloading audio")
        XCTAssertEqual(diagnostics.active.first?.detail, "65536 bytes received")
        XCTAssertEqual(diagnostics.events.count, count + 1)
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000.25)
        XCTAssertEqual(diagnostics.active.first?.stageStarted, occurredAt)
        XCTAssertEqual(diagnostics.events.last?.date, occurredAt)
        XCTAssertTrue(diagnostics.report.contains("2023-11-14T22:13:20.250Z"))
    }

    func testSessionHistoryIsBoundedAndCanBeCleared() {
        let diagnostics = AppDiagnostics()
        let id = diagnostics.begin("Preparation")
        for index in 0..<350 { diagnostics.step(id, "Downloading", detail: "\(index) bytes") }
        XCTAssertEqual(diagnostics.events.count, 300)
        XCTAssertTrue(diagnostics.report.contains("349 bytes"))
        diagnostics.finish(id)
        XCTAssertEqual(diagnostics.events.count, 300)
        XCTAssertTrue(diagnostics.active.isEmpty)
        diagnostics.clear()
        XCTAssertTrue(diagnostics.events.isEmpty)
    }
}
