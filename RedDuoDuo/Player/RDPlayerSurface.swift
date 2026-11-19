import SwiftUI
import UIKit

/// 双引擎视频表面：一个常驻宿主 UIView 同时容纳两个同样常驻的渲染视图
/// （VLC 的 `VLCVideoView` 与 AVPlayer 的 `AVPlayerVideoView`），按活动引擎切可见性。
///
/// 宿主视图在 SwiftUI 视图树中的身份保持稳定；横竖屏、折叠/展开、填充模式切换
/// 只改 frame / transform / videoGravity，绝不重建宿主视图或 AVPlayerLayer。
struct RDPlayerSurface: UIViewRepresentable {
    let controller: RDPlayerController
    var fillScreen: Bool
    var videoSize: CGSize

    func makeUIView(context: Context) -> RDPlayerSurfaceHost {
        let host = RDPlayerSurfaceHost(vlcVideo: controller.vlc.videoView,
                                       avVideo: controller.av.videoView)
        host.render(engine: controller.activeEngine, fillScreen: fillScreen)
        return host
    }

    func updateUIView(_ uiView: RDPlayerSurfaceHost, context: Context) {
        uiView.render(engine: controller.activeEngine, fillScreen: fillScreen)
    }

    // 不 detach 任一引擎的视频视图：它们由 controller 常驻持有，
    // 宿主若被 SwiftUI 重建，由新宿主重新认领（1.2 (1) 横屏黑屏教训）。
    static func dismantleUIView(_ uiView: RDPlayerSurfaceHost, coordinator: ()) {
        uiView.release()
    }
}

final class RDPlayerSurfaceHost: UIView {
    private let vlcHost: VLCSurfaceHost
    private let avVideo: AVPlayerVideoView
    private var shownEngine: RDPlaybackEngine?
    private var fillScreen = true

    init(vlcVideo: VLCVideoView, avVideo: AVPlayerVideoView) {
        self.vlcHost = VLCSurfaceHost(video: vlcVideo)
        self.avVideo = avVideo
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        // 纯渲染宿主不参与命中测试，手势全部交给 RDPlayerGestureOverlay。
        isUserInteractionEnabled = false
        avVideo.host = self
        addSubview(vlcHost)
        addSubview(avVideo)
        vlcHost.isHidden = true
        avVideo.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(engine: RDPlaybackEngine?, fillScreen: Bool) {
        let modeChanged = self.fillScreen != fillScreen
        self.fillScreen = fillScreen

        vlcHost.video.fillScreen = fillScreen
        vlcHost.video.applyLayout(animated: modeChanged)
        avVideo.fillScreen = fillScreen
        avVideo.applyGravity()

        if shownEngine != engine {
            shownEngine = engine
            switch engine {
            case .avPlayer:
                vlcHost.isHidden = true
                avVideo.isHidden = false
            case .vlc:
                avVideo.isHidden = true
                vlcHost.isHidden = false
            case nil:
                avVideo.isHidden = true
                vlcHost.isHidden = true
            }
        }
        adopt()
    }

    func release() {
        vlcHost.release()
        if avVideo.host === self { avVideo.host = nil }
    }

    private func adopt() {
        if vlcHost.frame != bounds { vlcHost.frame = bounds }
        vlcHost.adopt()
        if avVideo.host === self {
            if avVideo.superview !== self {
                avVideo.removeFromSuperview()
                addSubview(avVideo)
            }
            if avVideo.frame != bounds { avVideo.frame = bounds }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        adopt()
    }
}
