import XCTest

@MainActor final class MusicAppUITests: XCTestCase {
    func testAccountMusicSettingsLanguageAndOnlineSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["accountSettings"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["accountSettings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["googleSignIn"].waitForExistence(timeout: 5))
        app.buttons["musicSettings"].tap()
        XCTAssertTrue(app.navigationBars["Music Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appLanguage"].exists)
        app.buttons["appLanguage"].tap()
        app.buttons["English"].tap()
        let language = app.buttons["appLanguage"]
        let english = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Language"), object: language)
        wait(for: [english], timeout: 5)
        captureScreen("Music settings in English")
        language.tap()
        app.buttons["简体中文"].tap()
        let chinese = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "语言"), object: language)
        wait(for: [chinese], timeout: 5)
        app.terminate()
        app.launch()
        app.tabBars.buttons["搜索"].tap()
        app.buttons["YouTube"].tap()
        XCTAssertTrue(app.searchFields["YouTube 歌名、歌手"].waitForExistence(timeout: 5))
        captureScreen("YouTube search entry")
    }

    func testEmptyLibraryTabsAndImportEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["importMusic"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["你的音乐，从这里开始"].exists)
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.staticTexts["重新发现你的音乐"].exists)
        app.tabBars.buttons["资料库"].tap()
        XCTAssertTrue(app.buttons["importMusic"].firstMatch.exists)
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        app.buttons["importMusic"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testRealImportedSongMiniPlayerQueueLyricsAndCollapse() {
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--picker-fixture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let importButton = app.buttons["importMusic"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        importButton.tap()
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Test Tone")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        file.tap()
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "打开"])).firstMatch
        if open.waitForExistence(timeout: 3) { open.tap() }
        app.tabBars.buttons["资料库"].tap()
        let song = app.buttons["播放 Test Tone，未知艺术家"].firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let mini = app.buttons["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
        mini.tap()
        let collapse = app.buttons["collapsePlayer"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playerPlayPause"].exists)
        captureScreen("Full screen player")
        app.buttons["showQueue"].tap()
        XCTAssertTrue(app.navigationBars["播放队列"].waitForExistence(timeout: 5))
        captureScreen("Playback queue")
        app.buttons["完成"].tap()
        app.buttons["showLyrics"].tap()
        XCTAssertTrue(app.staticTexts["暂无歌词"].waitForExistence(timeout: 5))
        app.buttons["lookupLyrics"].tap()
        XCTAssertTrue(app.textFields["lookupTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["lookupTitle"].value as? String, "Test Tone")
        app.navigationBars["歌词与封面"].buttons["完成"].tap()
        app.buttons["导入 LRC"].tap()
        let lyricFile = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Fixture")).firstMatch
        XCTAssertTrue(lyricFile.waitForExistence(timeout: 15))
        lyricFile.tap()
        let lyricsOpen = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "打开"])).firstMatch
        if lyricsOpen.waitForExistence(timeout: 2) { lyricsOpen.tap() }
        XCTAssertTrue(app.buttons["First line，跳到 0:00"].waitForExistence(timeout: 10))
        let firstLine = app.buttons["lyric-line-0"]
        firstLine.tap()
        XCTAssertEqual(firstLine.value as? String, "当前歌词")
        captureScreen("Imported synchronized LRC")
        app.buttons["完成"].tap()
        collapse.tap()
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        captureScreen("Native library and mini player")
    }

    private func captureScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
