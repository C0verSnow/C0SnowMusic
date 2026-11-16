import XCTest

@MainActor final class MusicAppUITests: XCTestCase {
    func testEnglishProductInterfaceIgnoresPreviousChinesePreference() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appLanguage", "zh-Hans", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        app.buttons["accountSettings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["c0vermusic Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["googleSignIn"].exists)
        app.buttons["musicSettings"].tap()
        XCTAssertTrue(app.navigationBars["Music Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["appLanguage"].exists)
        captureScreen("English music settings on Chinese device")
        app.terminate()
        app.launch()
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls.buttons["c0vermusic"].exists)
        app.searchFields.firstMatch.tap()
        XCTAssertTrue(app.segmentedControls.buttons["c0vermusic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Library"].exists)
        captureScreen("Music search categories")
    }

    func testEmptyLibraryTabsAndImportEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["importMusic"].exists)
        XCTAssertTrue(app.staticTexts["Not Playing"].exists)
        XCTAssertTrue(app.staticTexts["Music just for you."].exists)
        app.tabBars.buttons["Radio"].tap()
        XCTAssertTrue(app.navigationBars["Radio"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Uncategorized"].exists)
        app.tabBars.buttons["Library"].tap()
        XCTAssertFalse(app.buttons["Online library"].exists)
        XCTAssertTrue(app.buttons["Playlists"].exists)
        XCTAssertTrue(app.buttons["Albums"].exists)
        XCTAssertTrue(app.buttons["Artists"].exists)
        XCTAssertTrue(app.buttons["newLibraryPlaylist"].exists)
        XCTAssertTrue(app.buttons["editLibrary"].exists)
        captureScreen("Unified library")
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        openImport(app)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testLibraryEditingAndNewPlaylistUseNativeControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Library"].tap()
        app.buttons["editLibrary"].tap()
        app.buttons["Artists"].tap()
        app.buttons["editLibrary"].tap()
        XCTAssertFalse(app.buttons["Artists"].exists)
        app.buttons["editLibrary"].tap()
        app.buttons["Artists"].tap()
        app.buttons["editLibrary"].tap()
        XCTAssertTrue(app.buttons["Artists"].exists)
        app.buttons["newLibraryPlaylist"].tap()
        XCTAssertTrue(app.navigationBars["New Playlist"].waitForExistence(timeout: 5))
        app.textFields["Playlist Title"].tap()
        app.textFields["Playlist Title"].typeText("CI Playlist")
        app.buttons["Create Playlist"].tap()
        app.buttons["Playlists"].tap()
        XCTAssertTrue(app.staticTexts["CI Playlist"].waitForExistence(timeout: 5))
        captureScreen("Playlist created from Library toolbar")
    }

    func testRealAudioDocumentPickerAddsSongToLibrary() {
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--picker-fixture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        openImport(app)
        selectDocument("Test Tone", in: app)
        let settings = app.navigationBars["Music Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.buttons.element(boundBy: 0).tap()
        app.buttons["closeAccount"].firstMatch.tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["Play Test Tone, Unknown artist"].firstMatch.waitForExistence(timeout: 15))
        captureScreen("Music imported through the system file picker")
    }

    func testImportedSongMiniPlayerQueueAndCollapse() {
        let app = launchFixturePlayer()
        XCTAssertTrue(app.buttons["playerPlayPause"].exists)
        captureScreen("Full screen player")
        app.buttons["showQueue"].tap()
        XCTAssertTrue(app.navigationBars["Playback queue"].waitForExistence(timeout: 5))
        captureScreen("Playback queue")
        app.buttons["Done"].tap()
        app.buttons["collapsePlayer"].tap()
        XCTAssertTrue(app.buttons["miniPlayer"].waitForExistence(timeout: 5))
        captureScreen("Native library and mini player")
    }

    func testLyricsSettingsLookupAndRealLRCImport() {
        executionTimeAllowance = 120
        let app = launchFixturePlayer()
        app.buttons["showLyrics"].tap()
        XCTAssertTrue(app.staticTexts["No lyrics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lyricsSettings"].exists)
        XCTAssertFalse(app.buttons["Import LRC"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)
        captureScreen("Lyrics with one settings entry")
        app.buttons["lyricsSettings"].tap()
        app.buttons["lookupLyrics"].tap()
        XCTAssertTrue(app.textFields["lookupTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["lookupTitle"].value as? String, "Test Tone")
        app.navigationBars["Lyrics and artwork"].buttons["Done"].tap()
        app.buttons["lyricsSettings"].tap()
        app.buttons["Import LRC"].tap()
        selectDocument("Fixture", in: app)
        XCTAssertTrue(app.buttons["First line, skip to 0:00"].waitForExistence(timeout: 10))
        let firstLine = app.buttons["lyric-line-0"]
        firstLine.tap()
        XCTAssertEqual(firstLine.value as? String, "Current lyric")
        captureScreen("Imported synchronized LRC")
        app.buttons["lyricsSettings"].tap()
        app.buttons["Close Lyrics"].tap()
        XCTAssertTrue(app.buttons["collapsePlayer"].waitForExistence(timeout: 5))
    }

    private func launchFixturePlayer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-library", "--picker-fixture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Library"].tap()
        let song = app.buttons["Play Test Tone, Unknown artist"].firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let mini = app.buttons["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
        mini.tap()
        XCTAssertTrue(app.buttons["collapsePlayer"].waitForExistence(timeout: 10))
        return app
    }

    private func selectDocument(_ name: String, in app: XCUIApplication) {
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        file.tap()
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "\u{6253}\u{5f00}"])).firstMatch
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    private func captureScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openImport(_ app: XCUIApplication) {
        app.buttons["accountSettings"].firstMatch.tap()
        app.buttons["musicSettings"].tap()
        let button = app.buttons["importMusic"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }
}
