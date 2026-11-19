import Foundation
import MediaPlayer
import UIKit

/// A8：锁屏 / 控制中心 / 画中画协同的 Now Playing 元数据与远程指令中心。
@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()

    struct Handlers {
        var onTogglePlayPause: (() -> Void)?
        var onPlay: (() -> Void)?
        var onPause: (() -> Void)?
        var onNext: (() -> Void)?
        var onPrev: (() -> Void)?
        var onSeek: ((Double) -> Void)?
    }

    private var handlers = Handlers()
    private var commandsInstalled = false
    private var cachedArtworkURL: String = ""
    private var cachedArtwork: MPMediaItemArtwork?

    private init() {}

    func attach(handlers: Handlers) {
        self.handlers = handlers
        installRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    func update(
        seriesTitle: String,
        episodeIndex: Int,
        episodeTitle: String,
        coverURL: String,
        elapsed: Double,
        duration: Double,
        rate: Float,
        isPlaying: Bool
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episodeTitle.isEmpty ? "第\(episodeIndex)集" : "第\(episodeIndex)集 · \(episodeTitle)",
            MPMediaItemPropertyArtist: seriesTitle,
            MPMediaItemPropertyAlbumTitle: seriesTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(max(rate, 0.5)) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(max(rate, 0.5)),
        ]
        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let cachedArtwork, cachedArtworkURL == coverURL {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if !coverURL.isEmpty, coverURL != cachedArtworkURL, let url = URL(string: coverURL) {
            cachedArtworkURL = coverURL
            cachedArtwork = nil
            Task.detached(priority: .utility) {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    if self.cachedArtworkURL == coverURL {
                        self.cachedArtwork = artwork
                        var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        current[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                    }
                }
            }
        }
    }

    func clear() {
        handlers = Handlers()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func installRemoteCommandsIfNeeded() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.onPlay?() }
            return .success
        }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.onPause?() }
            return .success
        }

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.onTogglePlayPause?() }
            return .success
        }

        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.onNext?() }
            return .success
        }

        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.onPrev?() }
            return .success
        }

        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let target = posEvent.positionTime
            Task { @MainActor in self?.handlers.onSeek?(target) }
            return .success
        }
    }
}
