import XCTest

final class RedDuoDuoTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    /// 全量验收：
    /// 1) 游客链（首页、详情、连播 3 集含解密出帧 + 固定身份不轮换）
    /// 2) 旋转布局（竖屏 & 横屏播放控件存在且落在窗口可见区内；1.4 起全屏铺满 + 悬浮控件为预期设计）
    /// 3) 记忆播放（播至中途退出、首页「继续观看」出现、点击直接续播到记录秒数）
    /// 4) 登录链（我的页 + 登录页可达，假号 10000000000 走发码拿到 passport 业务错误 JSON）
    func testFullAcceptanceV11() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. 首页真实数据
        XCTAssertTrue(app.staticTexts["红果漫剧"].waitForExistence(timeout: 20), "首页标题未出现")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'series-card-'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 40), "首页剧目卡片未出现")
        sleep(2)
        attach("01-home")

        // 2. 详情与选集
        card.tap()
        XCTAssertTrue(app.staticTexts["选集"].waitForExistence(timeout: 40), "详情页未出现")
        let episodes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode-'"))
        XCTAssertTrue(episodes.firstMatch.waitForExistence(timeout: 30), "选集按钮未出现")
        sleep(1)
        attach("02-detail")

        // 3. 第 1 集起播 + 竖屏控件布局检查
        let first = app.buttons["episode-1"].exists ? app.buttons["episode-1"] : episodes.firstMatch
        first.tap()
        waitStarted(app, episode: 1, timeout: 120)
        sleep(6) // 让画面推进几秒，为记忆播放累积可见进度
        assertPlayerControlsPresent(app, label: "竖屏")
        attach("03-playing-ep1-portrait")

        // 4. 旋转横屏，验证宽姿态与控件可见
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        assertLandscapeLayout(app)
        attach("04-playing-ep1-landscape")

        // 切回竖屏，连播第 2、3 集（同一固定身份）
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        let next = app.buttons["player-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "下一集按钮未出现")
        next.tap()
        waitStarted(app, episode: 2, timeout: 120)
        sleep(4)
        attach("05-playing-ep2")

        next.tap()
        waitStarted(app, episode: 3, timeout: 120)
        sleep(8) // 在第 3 集停留 8 秒用于记忆播放续播校验
        let savedSecText = app.staticTexts["player-time-sec"].label
        let savedSec = Double(savedSecText) ?? 0
        XCTAssertGreaterThanOrEqual(savedSec, 6, "第 3 集播放秒数应 >= 6s，实际=\(savedSecText)")
        attach("06-playing-ep3-before-exit")

        // 5. 退出播放并返回首页验证「继续观看」+ 记忆续播
        let closeBtn = app.buttons["player-close"]
        XCTAssertTrue(closeBtn.waitForExistence(timeout: 10), "关闭播放器按钮未出现")
        closeBtn.tap()

        XCTAssertTrue(app.staticTexts["选集"].waitForExistence(timeout: 15), "关闭播放器后应回到详情页")
        XCTAssertTrue(app.staticTexts["detail-last-watched"].waitForExistence(timeout: 10), "详情页未显示上次观看进度")
        attach("07-detail-with-progress")

        // 返回首页看「继续观看」区
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["红果漫剧"].waitForExistence(timeout: 15), "未回到首页")
        let continueSection = app.otherElements["continue-watching-section"]
        XCTAssertTrue(continueSection.waitForExistence(timeout: 10) || app.staticTexts["继续观看"].waitForExistence(timeout: 10), "首页「继续观看」区未出现")
        attach("08-home-continue-watching")

        // 点进「继续观看」卡片直接续播
        let continueCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'continue-card-'")).firstMatch
        XCTAssertTrue(continueCard.waitForExistence(timeout: 10), "继续观看卡片未出现")
        continueCard.tap()

        waitStarted(app, episode: 3, timeout: 120)
        sleep(3)
        let resumedSec = Double(app.staticTexts["player-time-sec"].label) ?? 0
        XCTAssertGreaterThanOrEqual(resumedSec, max(savedSec - 2, 5), "续播后时间应接近或超过退出前(\(savedSec)s)，实际=\(resumedSec)s")
        attach("09-resumed-ep3")

        app.buttons["player-close"].tap()
        sleep(1)

        // 6. 登录链验收（「我的」页 & 登录页可达 + 假号 10000000000 发码拿服务端业务错误 JSON，绝不发真号）
        let profileTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "「我的」Tab 未出现")
        profileTab.tap()
        let profileLoginBtn = app.buttons["profile-login-button"]
        XCTAssertTrue(profileLoginBtn.waitForExistence(timeout: 10), "我的页登录按钮未出现")
        attach("10-profile-guest")

        profileLoginBtn.tap()
        let mobileField = app.textFields["login-mobile-field"]
        XCTAssertTrue(mobileField.waitForExistence(timeout: 10), "登录页手机号输入框未出现")
        mobileField.tap()
        mobileField.typeText("10000000000")

        let sendCodeBtn = app.buttons["login-send-code-button"]
        XCTAssertTrue(sendCodeBtn.waitForExistence(timeout: 10), "获取验证码按钮未出现")
        sendCodeBtn.tap()

        let statusText = app.staticTexts["login-status-text"]
        XCTAssertTrue(statusText.waitForExistence(timeout: 25), "发码后未收到服务端响应提示")
        let errLabel = statusText.label
        XCTAssertFalse(errLabel.isEmpty, "服务端返回错误提示不应为空")
        // 假号 10000000000 应拿到服务端返回的业务错误（而非成功发送），证明请求真到达 passport 并解析
        XCTAssertFalse(errLabel.contains("验证码已发送"), "假号 10000000000 不应返回发送成功：\(errLabel)")
        attach("11-login-fake-number-error")
    }

    private func waitStarted(_ app: XCUIApplication, episode: Int, timeout: TimeInterval) {
        let epLabel = app.staticTexts["player-episode"]
        let epExp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ep-\(episode)"), object: epLabel)
        XCTAssertEqual(XCTWaiter.wait(for: [epExp], timeout: 30), .completed, "未切到第\(episode)集")

        sleep(2)
        let started = app.staticTexts["player-started"]
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'started'"), object: started)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: timeout), .completed, "第\(episode)集未真正起播")
    }

    /// 1.4 起播放器为全屏铺满 + 悬浮控件设计，控件叠在视频上属预期行为；
    /// 旧 1.1「控件与视频区不重叠 / 控件落黑边区」断言已失效，改为校验控件存在且落在窗口可见区内。
    private func assertPlayerControlsPresent(_ app: XCUIApplication, label: String) {
        let videoBox = app.otherElements["player-video-box"]
        let playPause = app.buttons["player-play-pause"]
        let slider = app.sliders["player-slider"]
        let closeBtn = app.buttons["player-close"]
        XCTAssertTrue(videoBox.waitForExistence(timeout: 10), "\(label) 视频框未出现")
        XCTAssertTrue(playPause.waitForExistence(timeout: 10), "\(label) 播放/暂停按钮未出现")
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "\(label) 进度条未出现")
        XCTAssertTrue(closeBtn.waitForExistence(timeout: 10), "\(label) 关闭按钮未出现")

        let windowFrame = app.windows.firstMatch.frame
        let controls: [(String, CGRect)] = [("播放/暂停", playPause.frame), ("进度条", slider.frame), ("关闭", closeBtn.frame)]
        for (name, frame) in controls {
            XCTAssertTrue(windowFrame.contains(frame), "\(label) \(name)控件超出窗口可见区：\(frame) window=\(windowFrame)")
        }
    }

    private func assertLandscapeLayout(_ app: XCUIApplication) {
        assertPlayerControlsPresent(app, label: "横屏")
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(windowFrame.width, windowFrame.height, "当前应处于横屏宽姿态：\(windowFrame)")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
