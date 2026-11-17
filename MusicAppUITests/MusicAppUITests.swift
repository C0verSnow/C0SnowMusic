import XCTest

@MainActor final class MusicAppUITests: XCTestCase {
    func testEnglishProductInterfaceIgnoresPreviousChinesePreference() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appLanguage", "zh-Hans", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        app.buttons["accountSettings"].firstMatch.tap()
        let accountTitle = app.staticTexts["c0versnow music Account"]
        XCTAssertTrue(accountTitle.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(accountTitle.frame.width, 150, "The account title must remain readable in the toolbar")
        XCTAssertTrue(app.buttons["googleSignIn"].exists)
        captureScreen("Account title and grouped controls")
        app.buttons["musicSettings"].tap()
        XCTAssertTrue(app.navigationBars["Music Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["appLanguage"].exists)
        captureScreen("English music settings on Chinese device")
        app.terminate()
        app.launch()
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls.buttons["c0versnow music"].exists)
        captureScreen("Search browse categories")
        app.searchFields.firstMatch.tap()
        XCTAssertTrue(app.segmentedControls.buttons["c0versnow music"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Library"].exists)
        captureScreen("Focused search scopes")
    }

    func testEmptyLibraryTabsAndImportEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["importMusic"].exists)
        XCTAssertTrue(app.staticTexts["Not Playing"].exists)
        XCTAssertTrue(app.staticTexts["Music just for you."].exists)
        captureScreen("Home feature card and persistent player")
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
        let artists = app.buttons["libraryCategory-artists"]
        XCTAssertTrue(artists.waitForExistence(timeout: 5))
        XCTAssertEqual(artists.value as? String, "Shown")
        XCTAssertFalse(app.navigationBars["Library"].buttons["accountSettings"].exists)
        artists.tap()
        XCTAssertEqual(artists.value as? String, "Hidden")
        captureScreen("Library category selection and reorder controls")
        app.buttons["editLibrary"].tap()
        XCTAssertFalse(app.buttons["Artists"].exists)
        app.buttons["editLibrary"].tap()
        artists.tap()
        XCTAssertEqual(artists.value as? String, "Shown")
        app.buttons["editLibrary"].tap()
        XCTAssertTrue(app.buttons["Artists"].exists)
        app.buttons["newLibraryPlaylist"].tap()
        XCTAssertTrue(app.navigationBars["New Playlist"].waitForExistence(timeout: 5))
        captureScreen("New Playlist artwork and title layout")
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
        guard app.buttons["First line, skip to 0:00"].waitForExistence(timeout: 10) else {
            XCTFail("The selected LRC file did not produce synchronized lyrics")
            return
        }
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
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        guard picker.waitForExistence(timeout: 30) else {
            XCTFail("The system document picker did not finish presenting")
            return
        }
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH[c] %@", name)).firstMatch
        guard file.waitForExistence(timeout: 15) else {
            XCTFail("The system document picker did not show \(name)")
            return
        }
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "\u{6253}\u{5f00}"])).firstMatch
        for _ in 0..<2 {
            file.tap()
            if open.waitForExistence(timeout: 3) { open.tap() }
            if picker.waitForNonExistence(timeout: 5) { return }
        }
        XCTFail("The system document picker did not finish selecting \(name)")
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
