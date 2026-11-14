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
        app.buttons["导入 LRC"].tap()
        let lyricFile = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Fixture")).firstMatch
        XCTAssertTrue(lyricFile.waitForExistence(timeout: 15))
        lyricFile.tap()
        let lyricsOpen = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "打开"])).firstMatch
        if lyricsOpen.waitForExistence(timeout: 2) { lyricsOpen.tap() }
        XCTAssertTrue(app.buttons["First line，跳到 0:00"].waitForExistence(timeout: 10))
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
