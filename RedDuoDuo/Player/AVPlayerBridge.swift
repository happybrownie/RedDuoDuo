import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// AVPlayerLayer 的常驻宿主 UIView。
///
/// 关键纪律（1.2 (1) 横屏黑屏的教训）：
/// - `layerClass` 固定为 `AVPlayerLayer`，layer 的创建由 UIKit 在视图生命周期内完成一次；
/// - 横竖屏、折叠/展开、填充模式切换只改 frame / videoGravity，绝不重建宿主视图或 layer；
/// - `AVPlayer` 实例同样只创建一次，换集只 `replaceCurrentItem`，避免 play()/layer 绑定失效。
final class AVPlayerVideoView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    weak var host: RDPlayerSurfaceHost?

    /// 填充 = resizeAspectFill（铺满、裁掉溢出边）；全屏 = resizeAspect（完整显示、留黑边）。
    var fillScreen = true

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyGravity()
    }

    /// 按现行 RDVideoFit 口径切换视频重力：填充=resizeAspectFill、全屏=resizeAspect。
    func applyGravity() {
        let gravity: AVLayerVideoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
        guard playerLayer.videoGravity != gravity else { return }
        playerLayer.videoGravity = gravity
    }
}

/// 系统 AVPlayer 引擎，专吃备流层产出的本地解密文件（progressive MP4 / hvc1 / AAC）。
///
/// 状态语义与 `VLCPlayerController` 对齐，供播放页无差别复用：
/// time / duration / stateText / isPlaying / videoSize / playbackRate / hasVideoOut /
/// playPause / seek / setRate / stop / load。
@MainActor
final class AVPlayerController: NSObject, ObservableObject {
    let player: AVPlayer
    let videoView: AVPlayerVideoView

    @Published var time: Double = 0
    @Published var duration: Double = 0
    /// 与 VLC 桥接层同一套徽标文案：idle / opening / ready / buffering / playing / paused / stopped / ended / error。
    @Published var stateText: String = "idle"
    @Published var isPlaying = false
    @Published var videoSize: CGSize = .zero
    @Published var playbackRate: Float = 1.0
    /// 首帧已真正渲染（AVPlayerLayer.isReadyForDisplay）。起播成功判定的主信号之一。
    @Published private(set) var hasVideoOut = false
    /// 真实时间轴已在播放态推进（排除人工 seek 跳变），作为无首帧回调时的并列起播判定信号。
    @Published private(set) var hasTimelineAdvanced = false
    /// 1.4 画中画状态。
    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false

    private(set) var hasCompletedInitialSeek = true
    private(set) var itemStatusText = "none"
    private(set) var failureDetail: String?

    var backgroundAudioEnabled = true {
        didSet { syncAutoPiPSetting() }
    }
    var audioOnlyMode = false {
        didSet { syncAutoPiPSetting() }
    }

    private var item: AVPlayerItem?
    private var isPiPStarting = false
    private var pendingSeekSeconds: Double?
    private var activeSeekToken: UUID?
    private var firstPlayingPeriodicTime: Double?

    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var presentationSizeObservation: NSKeyValueObservation?
    private var readyForDisplayObservation: NSKeyValueObservation?
    private var pipActiveObservation: NSKeyValueObservation?
    private var pipPossibleObservation: NSKeyValueObservation?
    private var pipController: AVPictureInPictureController?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedEndObserver: NSObjectProtocol?
    private var bgObserver: NSObjectProtocol?
    private var fgObserver: NSObjectProtocol?
    /// 区分“当前 item 生命周期”与已替换/已停止旧 item 的迟到异步回调。
    private var itemToken = UUID()

    override init() {
        let p = AVPlayer()
        player = p
        videoView = AVPlayerVideoView(player: p)
        super.init()
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = true
        videoView.isUserInteractionEnabled = false
        observeLayer()
        observePlayerTimeControls()
        installPeriodicTimeObserver()
        setupPictureInPicture()
        observeAppLifecycleForAudio()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failedEndObserver {
            NotificationCenter.default.removeObserver(failedEndObserver)
        }
        if let bgObserver {
            NotificationCenter.default.removeObserver(bgObserver)
        }
        if let fgObserver {
            NotificationCenter.default.removeObserver(fgObserver)
        }
    }

    // MARK: - 对外诊断

    var isItemReady: Bool { item?.status == .readyToPlay }
    var isItemFailed: Bool { item?.status == .failed || failureDetail != nil }

    var diagnosticSummary: String {
        "item=\(itemStatusText) t=\(String(format: "%.1f", time)) vout=\(hasVideoOut ? 1 : 0) adv=\(hasTimelineAdvanced ? 1 : 0) status=\(stateText)"
    }

    /// 把 AVPlayerItem 的底层 error（domain/code）与 errorLog 摘成一行，供逐档日志与错误层使用。
    private func failureDescription(error: Error?, item: AVPlayerItem?) -> String {
        var parts: [String] = []
        if let ns = error as NSError? {
            parts.append("\(ns.domain) \(ns.code): \(ns.localizedDescription)")
        } else {
            parts.append("unknown")
        }
        if let events = item?.errorLog()?.events, !events.isEmpty {
            let log = events.suffix(3).map { event in
                "\(event.errorDomain)/\(event.errorStatusCode): \(event.errorComment ?? "-")"
            }.joined(separator: " | ")
            parts.append("errorLog[\(log)]")
        }
        return parts.joined(separator: " ")
    }

    var shortFailure: String {
        if let failureDetail, !failureDetail.isEmpty { return failureDetail }
        return "item \(itemStatusText)"
    }

    // MARK: - 加载 / 播放控制

    func load(url: URL, startAt: Double = 0) {
        itemToken = UUID()
        let token = itemToken
        removeItemObservers()
        pendingSeekSeconds = nil
        activeSeekToken = nil
        firstPlayingPeriodicTime = nil
        hasTimelineAdvanced = false
        time = 0
        duration = 0
        videoSize = .zero
        hasVideoOut = false
        failureDetail = nil
        itemStatusText = "unknown"
        playbackRate = 1.0
        hasCompletedInitialSeek = startAt <= 1.0
        if startAt > 1.0 { pendingSeekSeconds = startAt }

        configureAudioSession()

        let asset: AVURLAsset
        if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 13; Pixel 5) Kylin/7.2.7.32"
                ]
            ])
        }
        let next = AVPlayerItem(asset: asset)
        item = next
        observeItem(next, token: token)
        observeEnd(of: next, token: token)

        player.replaceCurrentItem(with: next)
        stateText = "opening"
        isPlaying = true
        player.defaultRate = 1.0
        player.rate = 1.0
        player.play()

        AppLog.write("AVPLAYER load url=\(url.isFileURL ? "local" : "remote") name=\(url.lastPathComponent) startAt=\(String(format: "%.1f", startAt))s")
    }

    func playPause() {
        guard item != nil else { return }
        let playing = player.timeControlStatus == .playing || player.rate > 0
        if playing {
            player.pause()
            isPlaying = false
            stateText = "paused"
            AppLog.write("AVPLAYER pause state=\(stateText) time=\(String(format: "%.1f", time))")
        } else {
            if stateText == "ended" && (duration <= 0 || time >= duration - 1.0) {
                time = 0
                performPlayerSeek(to: 0)
            }
            player.defaultRate = playbackRate
            player.play()
            if playbackRate != 1.0 {
                player.rate = playbackRate
            }
            isPlaying = true
            stateText = (item?.status == .readyToPlay) ? "playing" : "buffering"
            AppLog.write("AVPLAYER resume state=\(stateText) time=\(String(format: "%.1f", time))")
        }
    }

    func seek(to seconds: Double) {
        guard item != nil else { return }
        let clamped = duration > 0 ? min(max(0, seconds), duration) : max(0, seconds)
        pendingSeekSeconds = nil
        hasCompletedInitialSeek = true
        time = clamped
        if stateText == "ended" {
            stateText = (player.timeControlStatus == .playing || player.rate > 0) ? "playing" : "paused"
        }
        performPlayerSeek(to: clamped)
        AppLog.write("AVPLAYER seek to=\(String(format: "%.1f", clamped))s")
    }

    func setRate(_ rate: Float) {
        let clamped = max(0.5, min(4.0, rate))
        playbackRate = clamped
        player.defaultRate = clamped
        if player.rate > 0 || player.timeControlStatus != .paused {
            player.rate = clamped
        }
        AppLog.write("AVPLAYER rate=\(String(format: "%.1f", clamped))x")
    }

    func stop() {
        itemToken = UUID()
        pendingSeekSeconds = nil
        activeSeekToken = nil
        firstPlayingPeriodicTime = nil
        hasTimelineAdvanced = false
        removeItemObservers()
        player.pause()
        player.defaultRate = 1.0
        player.replaceCurrentItem(with: nil)
        item = nil
        time = 0
        duration = 0
        videoSize = .zero
        hasVideoOut = false
        isPlaying = false
        playbackRate = 1.0
        stateText = "stopped"
        itemStatusText = "none"
        failureDetail = nil
        hasCompletedInitialSeek = true
    }

    // MARK: - 观察与状态映射

    private func observeLayer() {
        readyForDisplayObservation = videoView.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyReadyForDisplay(self.videoView.playerLayer.isReadyForDisplay)
            }
        }
    }

    private func observePlayerTimeControls() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyTimeControlStatus(self.player.timeControlStatus)
            }
        }
    }

    private func installPeriodicTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] cmTime in
            let seconds = cmTime.seconds
            Task { @MainActor [weak self] in
                self?.handlePeriodicTime(seconds)
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem, token: UUID) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.itemToken == token, let currentItem = self.item else { return }
                self.applyItemStatus(currentItem.status, error: currentItem.error, item: currentItem)
            }
        }
        durationObservation = item.observe(\.duration, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.itemToken == token else { return }
                self.updateDuration()
            }
        }
        presentationSizeObservation = item.observe(\.presentationSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.itemToken == token, let currentItem = self.item else { return }
                let size = currentItem.presentationSize
                if size.width > 1, size.height > 1, size != self.videoSize {
                    self.videoSize = size
                }
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem, token: UUID) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failedEndObserver { NotificationCenter.default.removeObserver(failedEndObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.itemToken == token else { return }
                self.stateText = "ended"
                self.isPlaying = false
                AppLog.write("AVPLAYER ended time=\(String(format: "%.1f", self.time))")
            }
        }
        failedEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let failedItem = note.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self, self.itemToken == token else { return }
                let detail = self.failureDescription(error: reason, item: failedItem)
                self.itemStatusText = "failed: \(detail)"
                self.failureDetail = "play failed: \(detail)"
                self.stateText = "error"
                self.isPlaying = false
                AppLog.write("AVPLAYER failedToPlayToEnd \(detail)")
            }
        }
    }

    private func removeItemObservers() {
        statusObservation?.invalidate(); statusObservation = nil
        durationObservation?.invalidate(); durationObservation = nil
        presentationSizeObservation?.invalidate(); presentationSizeObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedEndObserver {
            NotificationCenter.default.removeObserver(failedEndObserver)
            self.failedEndObserver = nil
        }
    }

    private func applyItemStatus(_ status: AVPlayerItem.Status, error: Error?, item: AVPlayerItem?) {
        switch status {
        case .unknown:
            itemStatusText = "unknown"
            if item != nil, stateText != "ended", stateText != "error" { stateText = "opening" }
        case .readyToPlay:
            itemStatusText = "ready"
            if item != nil, stateText == "opening" { stateText = "ready" }
            updateDuration()
            applyPendingSeekIfReady()
            AppLog.write("AVPLAYER item ready duration=\(String(format: "%.1f", duration))s")
        case .failed:
            let detail = failureDescription(error: error, item: item)
            itemStatusText = "failed: \(detail)"
            failureDetail = "item failed: \(detail)"
            stateText = "error"
            isPlaying = false
            AppLog.write("AVPLAYER item failed \(detail)")
        @unknown default:
            itemStatusText = "unknown"
        }
    }

    private func applyTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard item != nil else {
            if stateText != "stopped" { stateText = "stopped" }
            isPlaying = false
            return
        }
        if stateText == "ended" || stateText == "error" {
            isPlaying = false
            return
        }
        switch status {
        case .playing:
            stateText = "playing"
            isPlaying = true
        case .waitingToPlayAtSpecifiedRate:
            let playingThrough = time > 0.5 && hasVideoOut
            stateText = playingThrough ? "playing" : "buffering"
            isPlaying = playingThrough
        case .paused:
            isPlaying = false
            if item?.status == .failed || failureDetail != nil {
                stateText = "error"
            } else if time > 0.05 || stateText == "paused" {
                stateText = "paused"
            } else if item?.status == .readyToPlay {
                stateText = "ready"
            } else {
                stateText = "opening"
            }
        @unknown default:
            break
        }
        AppLog.write("AVPLAYER tcs raw=\(status.rawValue) text=\(stateText) time=\(String(format: "%.1f", time))")
    }

    private func applyReadyForDisplay(_ ready: Bool) {
        let value = ready && item != nil
        guard hasVideoOut != value else { return }
        hasVideoOut = value
        if value {
            AppLog.write("AVPLAYER first frame ready time=\(String(format: "%.1f", time)) size=\(Int(videoSize.width))x\(Int(videoSize.height))")
        }
    }

    private func handlePeriodicTime(_ seconds: Double) {
        guard let item else { return }
        if duration <= 0 { updateDuration() }
        let size = item.presentationSize
        if size.width > 1, size.height > 1, size != videoSize { videoSize = size }
        applyPendingSeekIfReady()

        guard seconds.isFinite, pendingSeekSeconds == nil, activeSeekToken == nil else { return }
        let clamped = max(0, seconds)
        time = clamped

        if item.status == .readyToPlay, player.timeControlStatus == .playing {
            if let first = firstPlayingPeriodicTime {
                if clamped - first >= 0.15 {
                    hasTimelineAdvanced = true
                }
            } else {
                firstPlayingPeriodicTime = clamped
            }
        }
    }

    private func updateDuration() {
        guard let item else { return }
        let seconds = CMTimeGetSeconds(item.duration)
        guard seconds.isFinite, seconds > 0 else { return }
        if duration <= 0 || abs(duration - seconds) > 0.5 { duration = seconds }
    }

    private func applyPendingSeekIfReady() {
        guard let target = pendingSeekSeconds, item?.status == .readyToPlay else { return }
        pendingSeekSeconds = nil
        hasCompletedInitialSeek = true
        if duration > 0, target >= duration - 1.5 {
            AppLog.write("AVPLAYER resume_seek skipped target=\(String(format: "%.1f", target))s duration=\(String(format: "%.1f", duration))s")
            return
        }
        time = target
        performPlayerSeek(to: target)
        AppLog.write("AVPLAYER resume_seek applied target=\(String(format: "%.1f", target))s duration=\(String(format: "%.1f", duration))s")
    }

    private func performPlayerSeek(to target: Double) {
        let seekToken = UUID()
        activeSeekToken = seekToken
        let itemTok = itemToken
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.itemToken == itemTok else { return }
                if self.activeSeekToken == seekToken {
                    self.activeSeekToken = nil
                    self.firstPlayingPeriodicTime = nil
                }
            }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            AppLog.write("AVPLAYER audio session error=\(error.localizedDescription)")
        }
    }

    // MARK: - 1.4 画中画 & 息屏听剧协同

    private func setupPictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let pip = AVPictureInPictureController(playerLayer: videoView.playerLayer) else {
            return
        }
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = backgroundAudioEnabled && !audioOnlyMode
        pipController = pip

        pipActiveObservation = pip.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] controller, _ in
            let active = controller.isPictureInPictureActive
            Task { @MainActor [weak self] in
                self?.isPiPActive = active
            }
        }
        pipPossibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor [weak self] in
                self?.isPiPPossible = possible
            }
        }
    }

    private func syncAutoPiPSetting() {
        pipController?.canStartPictureInPictureAutomaticallyFromInline = backgroundAudioEnabled && !audioOnlyMode
    }

    @discardableResult
    func startPictureInPicture() -> Bool {
        guard let pipController, pipController.isPictureInPicturePossible else { return false }
        configureAudioSession()
        if videoView.playerLayer.player !== player {
            videoView.playerLayer.player = player
        }
        pipController.startPictureInPicture()
        return true
    }

    func stopPictureInPicture() {
        guard let pipController, pipController.isPictureInPictureActive else { return }
        pipController.stopPictureInPicture()
    }

    private func observeAppLifecycleForAudio() {
        let nc = NotificationCenter.default
        bgObserver = nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.item != nil else { return }
                // 未开启系统画中画且允许后台/息屏听剧时，在后台期间临时解绑 playerLayer 的 player，
                // 防止 iOS 自动暂停 AVPlayer，回前台立即恢复绑定，视图与 layer 全程不重建。
                let pipBusy = self.isPiPActive || self.isPiPStarting || (self.pipController?.isPictureInPictureActive ?? false)
                if !pipBusy && (self.audioOnlyMode || self.backgroundAudioEnabled) {
                    self.configureAudioSession()
                    self.videoView.playerLayer.player = nil
                }
            }
        }
        fgObserver = nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.videoView.playerLayer.player !== self.player {
                    self.videoView.playerLayer.player = self.player
                }
            }
        }
    }
}

extension AVPlayerController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.isPiPStarting = true
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.isPiPStarting = false
            self?.isPiPActive = true
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isPiPStarting = false
            self?.isPiPActive = false
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPiPStarting = false
            self.isPiPActive = false
            if UIApplication.shared.applicationState != .background,
               self.videoView.playerLayer.player !== self.player {
                self.videoView.playerLayer.player = self.player
            }
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor [weak self] in
            if let self, self.videoView.playerLayer.player !== self.player {
                self.videoView.playerLayer.player = self.player
            }
            completionHandler(true)
        }
    }
}
