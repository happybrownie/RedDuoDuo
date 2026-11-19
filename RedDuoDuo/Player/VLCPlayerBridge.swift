// Copyright (c) 2026 DouDuo contributors (https://github.com/81199000/DouDuo)
// License: MIT — see Licenses/DouDuo-MIT.txt.
// Derived from DouDuo's VLC playback bridge (VLC soft-decode fallback; upstream lineage:
// 無為 影库播放器). Depends on tylerjonesio/vlckit-spm.
// Modified for RedDuoDuo: persistent single VLCVideoView (fixes landscape black
// screen), RDPlayerController integration.
import SwiftUI
import UIKit
import VLCKitSPM

/// 视频表面（避免横屏黑屏）：
/// 旧实现里 PlayerView 在竖/横布局分支间切换会重建 UIViewRepresentable，VLC 的 vout 仍绑在
/// 被销毁的旧 UIView 上 → 播放照常推进但画面全黑。现在 VLCVideoView 由 controller 持有且全程唯一
/// （player.drawable 永不改变），SwiftUI 每次只创建一个轻量 Host 容器，把唯一的视频 View 挂进去并随几何变化铺满。
struct VLCPlayerSurface: UIViewRepresentable {
    let controller: VLCPlayerController
    var fillScreen: Bool = true
    var videoSize: CGSize = .zero

    func makeUIView(context: Context) -> VLCSurfaceHost {
        let host = VLCSurfaceHost(video: controller.videoView)
        controller.videoView.fillScreen = fillScreen
        return host
    }

    func updateUIView(_ uiView: VLCSurfaceHost, context: Context) {
        let modeChanged = uiView.video.fillScreen != fillScreen
        uiView.video.fillScreen = fillScreen
        uiView.adopt()
        uiView.video.applyLayout(animated: modeChanged)
    }

    // 注意：不在此处 detach drawable——布局分支切换会触发 dismantle，而视频 View 要继续存活。
    static func dismantleUIView(_ uiView: VLCSurfaceHost, coordinator: ()) {
        uiView.release()
    }
}

/// 轻量宿主：每次 SwiftUI 重建都是新实例，但始终把同一个 VLCVideoView 挂在自己 bounds 内。
final class VLCSurfaceHost: UIView {
    let video: VLCVideoView

    init(video: VLCVideoView) {
        self.video = video
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        // 纯渲染宿主不参与 UIKit 命中测试，防止 VLC 内部 vout 子视图吞掉单击/双击/长按手势。
        isUserInteractionEnabled = false
        video.host = self
        adopt()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 仅当自己是当前宿主时才认领视频 View（避免旧宿主在销毁前把它抢回去）。
    /// 使用 bounds + center 而不是 frame，避免 layer.transform 缩放后设置 frame 反向缩小 bounds。
    func adopt() {
        guard video.host === self else { return }
        if video.superview !== self {
            video.removeFromSuperview()
            addSubview(video)
        }
        let targetBounds = CGRect(origin: .zero, size: bounds.size)
        let targetCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        if video.bounds != targetBounds { video.bounds = targetBounds }
        if video.center != targetCenter { video.center = targetCenter }
    }

    func release() {
        if video.host === self { video.host = nil }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        adopt()
        video.setNeedsLayout()
        video.layoutIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        adopt()
    }
}

final class VLCVideoView: UIView {
    weak var controller: VLCPlayerController?
    weak var host: VLCSurfaceHost?
    var fillScreen = true

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { controller?.surfaceDidMoveToWindow(self) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // VLC 在 drawable 内自建 vout 子视图/子层；几何变化（旋转、折叠/展开）后强制它们跟随 bounds，
        // 否则会停在旧尺寸/旧位置（例如竖屏尺寸被带到横屏）→ 画面落在可视区外而呈黑屏。
        for sub in subviews where sub.frame != bounds { sub.frame = bounds }
        for l in layer.sublayers ?? [] where l.delegate == nil && l.frame != bounds {
            l.frame = bounds
        }
        applyLayout()
    }

    func applyLayout(animated: Bool = false) {
        clipsToBounds = true
        let targetTransform: CATransform3D
        if !fillScreen {
            // 「全屏」完整显示模式：aspect fit，黑边留空
            targetTransform = CATransform3DIdentity
        } else if let player = controller?.player,
                  bounds.width > 1, bounds.height > 1,
                  player.videoSize.width > 1, player.videoSize.height > 1 {
            let s = RDVideoFit.vlcScale(
                fillScreen: true,
                videoAspect: Double(player.videoSize.width / player.videoSize.height),
                screenAspect: Double(bounds.width / bounds.height)
            )
            targetTransform = CATransform3DMakeScale(s, s, 1)
        } else {
            targetTransform = CATransform3DIdentity
        }
        guard !CATransform3DEqualToTransform(layer.transform, targetTransform) else { return }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.layer.transform = targetTransform
            }
        } else {
            layer.transform = targetTransform
        }
    }
}

@MainActor
final class VLCPlayerController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer(options: [
        "--codec=videotoolbox,avcodec",
        "--avcodec-hw=videotoolbox",
        "--network-caching=1500",
        "--file-caching=1500",
        "--clock-jitter=0",
        "--clock-synchro=0",
    ])
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var stateText: String = "idle"
    @Published var isPlaying: Bool = false
    @Published var videoSize: CGSize = .zero
    @Published var playbackRate: Float = 1.0
    /// VLC 是否已建立视频输出（首帧已出的可靠信号）。1.3 (2) 起播安全网据此判断是否需要降档重试。
    @Published private(set) var hasVideoOut: Bool = false

    /// 全程唯一的视频 View（见 VLCPlayerSurface 注释）。
    let videoView = VLCVideoView()
    private weak var surface: UIView?
    private var pendingURL: URL?
    private var pendingSeekSeconds: Double?
    private(set) var hasCompletedInitialSeek = false

    override init() {
        super.init()
        player.delegate = self
        player.scaleFactor = 0
        videoView.backgroundColor = .black
        videoView.clipsToBounds = true
        videoView.isUserInteractionEnabled = false
        videoView.controller = self
        attach(videoView)
    }

    func attach(_ view: UIView) {
        surface = view
        player.drawable = view
        AppLog.write("VLC attach window=\(view.window == nil ? 0 : 1) drawable=\(player.drawable == nil ? 0 : 1)")
    }

    /// SwiftUI 的 UIView 真正进入 window 之后，VLC 才有视频输出目标；此时才允许 play。
    func surfaceDidMoveToWindow(_ view: UIView) {
        guard surface === view, view.window != nil else { return }
        player.drawable = view
        AppLog.write("VLC surface ready window=1 drawable=\(player.drawable == nil ? 0 : 1) pending=\(pendingURL == nil ? 0 : 1)")
        if let url = pendingURL {
            pendingURL = nil
            start(url)
        }
    }

    func detach(_ view: UIView) {
        if player.drawable as? UIView === view { player.drawable = nil }
        if surface === view { surface = nil }
    }

    func load(url: URL, startAt: Double = 0) {
        time = 0
        duration = 0
        videoSize = .zero
        hasVideoOut = false
        hasCompletedInitialSeek = startAt <= 1.0
        pendingSeekSeconds = startAt > 1.0 ? startAt : nil
        if surface == nil || surface?.window == nil {
            pendingURL = url
            AppLog.write("VLC pending url host=\(url.host ?? "?") startAt=\(String(format: "%.1f", startAt))s (surface not ready)")
            return
        }
        start(url)
    }

    private func start(_ url: URL) {
        if player.state != .stopped { player.stop() }
        if let surface, surface.window != nil { player.drawable = surface }
        let media = VLCMedia(url: url)
        media.addOption(":http-user-agent=Dalvik/2.1.0 (Linux; U; Android 13; Pixel 5) Kylin/7.2.7.32")
        media.addOption(":avcodec-hw=videotoolbox")
        media.addOption(":codec=videotoolbox,avcodec")
        media.addOption(":network-caching=1500")
        media.addOption(":file-caching=1500")
        media.addOption(":clock-jitter=0")
        media.addOption(":clock-synchro=0")
        player.media = media
        player.rate = 1.0
        playbackRate = 1.0
        time = 0
        duration = 0
        stateText = "opening"
        hasVideoOut = false
        isPlaying = true
        player.play()
        AppLog.write("VLC start host=\(url.host ?? "?") startAt=\(String(format: "%.1f", pendingSeekSeconds ?? 0))s url_prefix=\(String(url.absoluteString.prefix(120)))")
    }

    func setRate(_ rate: Float) {
        let clamped = max(0.5, min(4.0, rate))
        player.rate = clamped
        playbackRate = clamped
        AppLog.write("VLC rate=\(String(format: "%.1f", clamped))x")
    }

    func playPause() {
        switch player.state {
        case .playing, .buffering, .opening:
            player.pause()
            isPlaying = false
            AppLog.write("VLC pause state=\(stateText) time=\(String(format: "%.1f", time))")
        default:
            player.play()
            isPlaying = true
            AppLog.write("VLC resume state=\(stateText) time=\(String(format: "%.1f", time))")
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        let ms = Int32(clamped * 1000)
        player.time = VLCTime(int: ms)
        time = clamped
        AppLog.write("VLC seek to=\(String(format: "%.1f", clamped))s")
    }

    func stop() {
        pendingURL = nil
        pendingSeekSeconds = nil
        player.rate = 1.0
        playbackRate = 1.0
        player.stop()
        hasVideoOut = false
        isPlaying = false
        stateText = "stopped"
    }

    private func applyPendingSeekIfReady() {
        guard let target = pendingSeekSeconds else { return }
        guard player.state == .playing || time > 0.1 else { return }
        if duration > 0, target >= duration - 1.5 {
            pendingSeekSeconds = nil
            hasCompletedInitialSeek = true
            return
        }
        pendingSeekSeconds = nil
        hasCompletedInitialSeek = true
        let ms = Int32(target * 1000)
        player.time = VLCTime(int: ms)
        time = target
        AppLog.write("VLC resume_seek applied target=\(String(format: "%.1f", target))s duration=\(String(format: "%.1f", duration))s")
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        let raw = player.state.rawValue
        let text: String
        switch player.state {
        case .stopped: text = "stopped"
        case .opening: text = "opening"
        case .buffering: text = time > 0.5 ? "playing" : "buffering"
        case .ended: text = "ended"
        case .error: text = "error"
        case .playing: text = "playing"
        case .paused: text = "paused"
        case .esAdded: text = "esAdded"
        @unknown default: text = "unknown"
        }
        stateText = text
        hasVideoOut = player.hasVideoOut
        isPlaying = player.state == .playing || (player.state == .buffering && time > 0.5)
        if let length = player.media?.length, length.intValue > 0 {
            duration = Double(length.intValue) / 1000.0
        }
        let vs = player.videoSize
        if vs.width > 1, vs.height > 1, vs != videoSize {
            videoSize = vs
            (surface as? VLCVideoView)?.applyLayout()
        }
        applyPendingSeekIfReady()
        AppLog.write("VLC state raw=\(raw) text=\(text) time=\(String(format: "%.1f", time)) hasVideoOut=\(player.hasVideoOut) size=\(Int(vs.width))x\(Int(vs.height)) duration=\(String(format: "%.1f", duration))")
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let currentSec = Double(player.time.intValue) / 1000.0
        if pendingSeekSeconds == nil {
            time = currentSec
        }
        if duration <= 0, let length = player.media?.length, length.intValue > 0 {
            duration = Double(length.intValue) / 1000.0
        }
        hasVideoOut = player.hasVideoOut
        let vs = player.videoSize
        if vs.width > 1, vs.height > 1, vs != videoSize {
            videoSize = vs
            (surface as? VLCVideoView)?.applyLayout()
        }
        applyPendingSeekIfReady()
        if time > 0.5, stateText == "buffering" {
            stateText = "playing"
            isPlaying = true
        }
    }
}
