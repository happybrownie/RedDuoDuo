import AVFoundation
import Combine
import CoreGraphics
import Foundation

/// 播放引擎顺序：每档候选内先 AVPlayer（系统播放器，吃本地解密 MP4），失败再回退现有 VLCKit。
/// 两个引擎都失败才降下一档。原始顺序即 `CaseIterable` 声明顺序。
enum RDPlaybackEngine: String, CaseIterable {
    case avPlayer
    case vlc

    var label: String {
        switch self {
        case .avPlayer: return "AVPlayer"
        case .vlc: return "VLC"
        }
    }
}

/// 双引擎路由：对播放页暴露与旧 `VLCPlayerController` 完全一致的观察面，
/// 内部持有两个常驻引擎（AVPlayer 与 VLC），同一时刻只有一个处于活动状态。
///
/// 设计要点：
/// - 两个引擎对象、两个视频承载 View 都只创建一次；换引擎只切可见性，不重建宿主/layer；
/// - 状态属性按 `activeEngine` 计算并转发两个引擎的 `objectWillChange`，
///   播放页 UI / 手势 / 续播逻辑无需区分引擎；
/// - 引擎级失败细节由播放页通过 `av` / `vlc` 直接读取，用于错误层与日志。
@MainActor
final class RDPlayerController: ObservableObject {
    let av = AVPlayerController()
    let vlc = VLCPlayerController()

    @Published private(set) var activeEngine: RDPlaybackEngine?

    private var cancellables: Set<AnyCancellable> = []

    init() {
        forward(av)
        forward(vlc)
    }

    // MARK: - 对外统一状态

    var time: Double {
        switch activeEngine {
        case .avPlayer: return av.time
        case .vlc: return vlc.time
        case nil: return 0
        }
    }

    var duration: Double {
        switch activeEngine {
        case .avPlayer: return av.duration
        case .vlc: return vlc.duration
        case nil: return 0
        }
    }

    var stateText: String {
        switch activeEngine {
        case .avPlayer: return av.stateText
        case .vlc: return vlc.stateText
        case nil: return "idle"
        }
    }

    var isPlaying: Bool {
        switch activeEngine {
        case .avPlayer: return av.isPlaying
        case .vlc: return vlc.isPlaying
        case nil: return false
        }
    }

    var videoSize: CGSize {
        switch activeEngine {
        case .avPlayer: return av.videoSize
        case .vlc: return vlc.videoSize
        case nil: return .zero
        }
    }

    var playbackRate: Float {
        switch activeEngine {
        case .avPlayer: return av.playbackRate
        case .vlc: return vlc.playbackRate
        case nil: return 1.0
        }
    }

    var hasVideoOut: Bool {
        switch activeEngine {
        case .avPlayer: return av.hasVideoOut
        case .vlc: return vlc.hasVideoOut
        case nil: return false
        }
    }

    /// 续播初始定位是否已完成（播放页用它避免把旧进度覆盖成 0）。
    var hasCompletedInitialSeek: Bool {
        switch activeEngine {
        case .avPlayer: return av.hasCompletedInitialSeek
        case .vlc: return vlc.hasCompletedInitialSeek
        case nil: return true
        }
    }

    var isPiPActive: Bool {
        activeEngine == .avPlayer && av.isPiPActive
    }

    var isPiPPossible: Bool {
        activeEngine == .avPlayer && av.isPiPPossible
    }

    /// 当前活动引擎的紧凑诊断串，用于起播超时日志与错误层。
    var activeDiagnostic: String {
        switch activeEngine {
        case .avPlayer:
            return av.diagnosticSummary
        case .vlc:
            return "state=\(vlc.stateText) t=\(String(format: "%.1f", vlc.time)) vout=\(vlc.hasVideoOut ? 1 : 0)"
        case nil:
            return "no-engine"
        }
    }

    // MARK: - 对外统一控制

    func load(url: URL, startAt: Double, engine: RDPlaybackEngine) {
        activeEngine = engine
        switch engine {
        case .avPlayer:
            vlc.stop()
            av.load(url: url, startAt: startAt)
        case .vlc:
            av.stop()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try? AVAudioSession.sharedInstance().setActive(true)
            vlc.load(url: url, startAt: startAt)
        }
    }

    @discardableResult
    func startPictureInPicture() -> Bool {
        guard activeEngine == .avPlayer else { return false }
        return av.startPictureInPicture()
    }

    func stopPictureInPicture() {
        av.stopPictureInPicture()
    }

    func setAudioOnlyMode(_ enabled: Bool) {
        av.audioOnlyMode = enabled
    }

    func setBackgroundAudioEnabled(_ enabled: Bool) {
        av.backgroundAudioEnabled = enabled
    }

    func playPause() {
        switch activeEngine {
        case .avPlayer: av.playPause()
        case .vlc: vlc.playPause()
        case nil: break
        }
    }

    func seek(to seconds: Double) {
        switch activeEngine {
        case .avPlayer: av.seek(to: seconds)
        case .vlc: vlc.seek(to: seconds)
        case nil: break
        }
    }

    func setRate(_ rate: Float) {
        switch activeEngine {
        case .avPlayer: av.setRate(rate)
        case .vlc: vlc.setRate(rate)
        case nil: break
        }
    }

    func stop() {
        av.stop()
        vlc.stop()
        activeEngine = nil
    }

    // MARK: - 变更转发

    private func forward<E: ObservableObject>(_ engine: E) {
        engine.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }.store(in: &cancellables)
    }
}
