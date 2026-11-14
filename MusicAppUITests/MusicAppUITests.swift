import XCTest

@MainActor final class MusicAppUITests: XCTestCase {
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
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-library", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
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
        app.buttons["showQueue"].tap()
        XCTAssertTrue(app.navigationBars["播放队列"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.buttons["showLyrics"].tap()
        XCTAssertTrue(app.staticTexts["暂无歌词"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        collapse.tap()
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Native library and mini player"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
