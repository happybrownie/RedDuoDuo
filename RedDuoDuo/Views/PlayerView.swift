import Combine
import SwiftUI
import UIKit

@MainActor
private final class PlayerBackgroundObserver: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    private var lastAVState = ""
    private var lastVLCState = ""

    func bind(controller: RDPlayerController, onEndedInBackground: @escaping () -> Void) {
        guard cancellables.isEmpty else { return }
        controller.av.$stateText
            .sink { [weak self] state in
                guard let self else { return }
                let prev = self.lastAVState
                self.lastAVState = state
                if state == "ended", prev != "ended",
                   controller.activeEngine == .avPlayer,
                   UIApplication.shared.applicationState != .active {
                    onEndedInBackground()
                }
            }
            .store(in: &cancellables)
        controller.vlc.$stateText
            .sink { [weak self] state in
                guard let self else { return }
                let prev = self.lastVLCState
                self.lastVLCState = state
                if state == "ended", prev != "ended",
                   controller.activeEngine == .vlc,
                   UIApplication.shared.applicationState != .active {
                    onEndedInBackground()
                }
            }
            .store(in: &cancellables)
    }
}

struct PlayerView: View {
    @State private var activeSeries: Series
    @State private var activeEpisodes: [Episode]
    @State private var index: Int
    @State private var seriesSwitchToken = 0
    @StateObject private var controller = RDPlayerController()
    @ObservedObject private var prefs = RDPlaybackPrefs.shared
    @ObservedObject private var preloader = EpisodePreloader.shared
    @ObservedObject private var offline = OfflineCacheManager.shared
    @AppStorage(RDVideoFit.preferenceKey) private var fillScreen = RDVideoFit.defaultFillScreen

    @State private var loading = true
    @State private var error: String?
    @State private var stream: StreamInfo?
    @State private var showControls = true
    @State private var phaseText = "正在本地签名取流…"
    @State private var resumeBanner: String?
    @State private var modeToast: String?
    @State private var modeToastTask: Task<Void, Never>?
    @State private var pinchScale: CGFloat = RDVideoFit.releasedScale
    @State private var pinchCrossedMode: Bool?
    @State private var isPinching = false
    @State private var centerFlashIcon: String?
    @State private var centerFlashID = UUID()
    @State private var centerFlashTask: Task<Void, Never>?
    @State private var isSpeedBoosting = false
    @State private var rateBeforeBoost: Float = 1.0
    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var lastSavedAt: TimeInterval = 0
    @State private var lastSeekReportAt: TimeInterval = 0
    @State private var resumeTargetSeconds: Double = 0
    @State private var activeLoadID = UUID()
    @State private var loadedEpisodeKey = ""
    @State private var backgroundLoadTask: Task<Void, Never>?
    @State private var retryTask: Task<Void, Never>?
    @StateObject private var bgObserver = PlayerBackgroundObserver()

    // 1.4 新增状态：竖滑切集 / 选集抽屉 / 倍速条 / 跳片头片尾 / 自动连播 / 听剧 / 追剧台 / 接档 / 震动状态
    @State private var dragOffsetY: CGFloat = 0
    @State private var swipeThresholdCrossed = false
    @State private var didFireBoundaryHaptic = false
    @State private var showEpisodeDrawer = false
    @State private var showRatePicker = false
    @State private var isAudioMode = false
    @State private var manualWorkbench = false

    @State private var firedAutoNextCountdownBeats: Set<Int> = []
    @State private var showFinaleOverlay = false
    @State private var finaleRecommendations: [Series] = []

    @State private var didFirePremiereHaptic = false
    @State private var didAutoSkipIntro = false
    @State private var didHandleEpisodeEnd = false
    @State private var pendingCleanupEpisode: Episode?

    // 进度条精细触感跟踪
    @State private var isDraggingSlider = false
    @State private var lastSliderValue: Double = 0
    @State private var lastSliderUpdateTime: TimeInterval = 0
    @State private var didHitSliderEdge = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let accent = RD.Palette.accent
    @State private var hideTask: Task<Void, Never>?

    init(series: Series, episodes: [Episode], startIndex: Int) {
        _activeSeries = State(initialValue: series)
        _activeEpisodes = State(initialValue: episodes)
        _index = State(initialValue: min(max(0, startIndex), max(0, episodes.count - 1)))
    }

    private var current: Episode? {
        guard activeEpisodes.indices.contains(index) else { return nil }
        return activeEpisodes[index]
    }

    private var currentSeriesRate: Float {
        prefs.rate(for: activeSeries.id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 不忽略安全区的探针：实时读取折叠/展开/旋转下的物理刘海、圆角与手势区尺寸
            RDSafeAreaProbe(insets: $safeInsets)

            // 全幅出血视频 + Duo 半折追剧台 + 悬浮控件（全程单一 RDPlayerSurface，折叠/旋转绝不重建）
            GeometryReader { fullGeo in
                let fullW = fullGeo.size.width
                let fullH = fullGeo.size.height
                let panes = DuoFoldLayout.resolvePanes(in: fullGeo, manualWorkbench: manualWorkbench)
                let videoRect = panes?.videoRect ?? CGRect(origin: .zero, size: fullGeo.size)
                let w = max(1, videoRect.width)
                let h = max(1, videoRect.height)
                let isCompact = !RD.isWide(w)

                let topTouchesEdge = videoRect.minY <= 1
                let bottomTouchesEdge = abs(videoRect.maxY - fullH) <= 1
                let leadingTouchesEdge = videoRect.minX <= 1
                let trailingTouchesEdge = abs(videoRect.maxX - fullW) <= 1

                let topPad = topTouchesEdge ? max(safeInsets.top + 6, 14) : 12
                let bottomPad = bottomTouchesEdge ? max(safeInsets.bottom + 8, 16) : 12
                let leadingPad = leadingTouchesEdge ? max(safeInsets.leading, 16) : 12
                let trailingPad = trailingTouchesEdge ? max(safeInsets.trailing, 16) : 12

                ZStack(alignment: .topLeading) {
                    // 1. 视频渲染 + 手势层 + 视频区内浮层（固定唯一树位置）
                    ZStack {
                        videoViewport(width: w, height: h)
                            .frame(width: w, height: h)

                        if isAudioMode {
                            AudioModeCoverOverlay(
                                series: activeSeries,
                                episode: current,
                                totalCount: activeEpisodes.count,
                                isPlaying: controller.isPlaying,
                                time: controller.time,
                                duration: controller.duration,
                                onTogglePlay: { togglePlayPause() },
                                onPrev: {
                                    RDHaptics.shared.playGlassTap(disabled: index <= 0)
                                    go(-1)
                                },
                                onNext: {
                                    RDHaptics.shared.playGlassTap(disabled: index >= activeEpisodes.count - 1)
                                    go(1)
                                },
                                onExitAudioMode: { toggleAudioMode() }
                            )
                            .frame(width: w, height: h)
                            .transition(.opacity)
                        }

                        // 控件可见时上下边缘渐隐 scrim（不占位、不挤压视频画面）
                        if !isAudioMode {
                            VStack(spacing: 0) {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black.opacity(0.72), location: 0),
                                        .init(color: .black.opacity(0.35), location: 0.55),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: topPad + 76)
                                .opacity(showControls ? 1 : 0)
                                Spacer(minLength: 0)
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black.opacity(0.42), location: 0.40),
                                        .init(color: .black.opacity(0.82), location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: bottomPad + (isCompact ? 220 : 164))
                                .opacity(showControls && !loading ? 1 : 0)
                            }
                            .allowsHitTesting(false)
                            .animation(RD.Motion.fade, value: showControls)
                        }

                        // 悬浮顶栏与底栏
                        VStack(spacing: 0) {
                            floatingTopBar(compact: isCompact, isPhysicalFold: panes?.isPhysicalFold == true)
                                .padding(.top, topPad)
                                .padding(.leading, leadingPad)
                                .padding(.trailing, trailingPad)
                                .opacity((showControls || isAudioMode) ? 1 : 0)
                                .allowsHitTesting(showControls || isAudioMode)
                                .disabled(!(showControls || isAudioMode))

                            Spacer(minLength: 0)

                            if !isAudioMode {
                                VStack(spacing: 10) {
                                    if showRatePicker && showControls && !loading {
                                        rateSelectorBar
                                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    }

                                    floatingBottomBar(compact: isCompact)
                                }
                                .padding(.bottom, bottomPad)
                                .padding(.leading, leadingPad)
                                .padding(.trailing, trailingPad)
                                .opacity(showControls && !loading ? 1 : 0)
                                .allowsHitTesting(showControls && !loading)
                                .disabled(!(showControls && !loading))
                            }
                        }
                        .animation(RD.Motion.fade, value: showControls)
                        .animation(RD.Motion.snappy, value: showRatePicker)

                        // A7: 一键跳过片头 / 片尾悬浮按钮（在片头/片尾窗口内浮现）
                        if !loading && error == nil && !isAudioMode && !showEpisodeDrawer && !showFinaleOverlay {
                            skipIntroOutroPillOverlay(
                                bottomPad: showControls ? bottomPad + (isCompact ? 186 : 136) : bottomPad + 28,
                                trailingPad: trailingPad
                            )
                        }

                        if isSpeedBoosting {
                            VStack {
                                speedBoostPill
                                    .padding(.top, showControls ? topPad + 54 : topPad + 14)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, max(leadingPad, trailingPad))
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }

                        if let icon = centerFlashIcon {
                            centerPlayPauseFeedback(icon: icon)
                                .id(centerFlashID)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .scale(scale: 0.82)))
                        }

                        if loading {
                            loadingOverlay
                                .padding(.horizontal, max(leadingPad, trailingPad))
                                .allowsHitTesting(false)
                        }

                        if let error {
                            errorOverlay(error)
                                .padding(.horizontal, max(leadingPad, trailingPad))
                        }

                        // A10: 大结局「同款接档」推荐浮层
                        if showFinaleOverlay && !loading && error == nil {
                            ZStack {
                                Color.black.opacity(0.55)
                                    .ignoresSafeArea()
                                    .onTapGesture {
                                        withAnimation(RD.Motion.fade) { showFinaleOverlay = false }
                                    }
                                FinaleRelatedOverlay(
                                    series: activeSeries,
                                    recommendations: finaleRecommendations,
                                    onPickSeries: { nextSeries in
                                        Task { await switchToRecommendedSeries(nextSeries) }
                                    },
                                    onReplay: {
                                        withAnimation(RD.Motion.fade) { showFinaleOverlay = false }
                                        controller.seek(to: 0)
                                        if !controller.isPlaying { controller.playPause() }
                                        didHandleEpisodeEnd = false
                                    },
                                    onClose: {
                                        withAnimation(RD.Motion.fade) { showFinaleOverlay = false }
                                    }
                                )
                                .padding(16)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }

                        // A6: 屏内浮层选集抽屉
                        if showEpisodeDrawer {
                            episodeDrawerLayer(w: w, h: h, leadingPad: leadingPad, trailingPad: trailingPad, bottomPad: bottomPad)
                                .transition(.opacity.combined(with: .move(edge: w > h ? .trailing : .bottom)))
                        }

                        VStack(spacing: 8) {
                            Spacer()
                            if let modeToast {
                                toastPill(modeToast, accentBorder: true)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                            if let resumeBanner, !loading {
                                toastPill(resumeBanner, accentBorder: false)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.bottom, showControls && !loading ? bottomPad + (isCompact ? 180 : 128) + (showRatePicker ? 46 : 0) : bottomPad + 24)
                        .padding(.horizontal, max(leadingPad, trailingPad))
                        .allowsHitTesting(false)
                        .animation(RD.Motion.snappy, value: modeToast)
                        .animation(RD.Motion.snappy, value: resumeBanner)
                    }
                    .frame(width: w, height: h)
                    .position(x: videoRect.midX, y: videoRect.midY)
                    .animation(RD.Motion.snappy, value: isSpeedBoosting)
                    .animation(RD.Motion.press, value: centerFlashIcon)
                    .animation(RD.Motion.snappy, value: showEpisodeDrawer)

                    // 2. A2: Duo 半折「追剧台」常驻控制屏（严格避开物理折痕）
                    if let panes {
                        DuoBingeWorkbench(
                            series: activeSeries,
                            episodes: activeEpisodes,
                            currentIndex: index,
                            isBookPosture: panes.isBookPosture,
                            isPhysicalFold: panes.isPhysicalFold,
                            isPlaying: controller.isPlaying,
                            currentTime: controller.time,
                            duration: controller.duration,
                            currentRate: currentSeriesRate,
                            isAudioMode: isAudioMode,
                            isPiPPossible: controller.isPiPPossible,
                            onPlayPause: { togglePlayPause() },
                            onPrev: {
                                RDHaptics.shared.playGlassTap(disabled: index <= 0)
                                go(-1)
                            },
                            onNext: {
                                RDHaptics.shared.playGlassTap(disabled: index >= activeEpisodes.count - 1)
                                go(1)
                            },
                            onSeek: { sec in seekAndPersist(sec, forceReport: false) },
                            onSelectEpisode: { targetIdx in
                                jumpToEpisode(targetIdx)
                            },
                            onSelectRate: { rate in
                                selectSeriesRate(rate)
                            },
                            onSkipIntro: { performSkipIntro(manual: true) },
                            onSkipOutro: { performSkipOutro(manual: true) },
                            onToggleAudioMode: { toggleAudioMode() },
                            onTogglePiP: { togglePictureInPicture() },
                            onCacheNext10: {
                                OfflineCacheManager.shared.cacheNext10(series: activeSeries, episodes: activeEpisodes, fromIndex: index)
                                showToast("已加入离线缓存：后续 10 集")
                            },
                            onExitWorkbench: panes.isPhysicalFold ? nil : {
                                RDHaptics.shared.playDrawerToggle(open: false)
                                withAnimation(RD.Motion.snappy) { manualWorkbench = false }
                            }
                        )
                        .frame(width: panes.panelRect.width, height: panes.panelRect.height)
                        .position(x: panes.panelRect.midX, y: panes.panelRect.midY)
                        .transition(.opacity)
                    }
                }
                .frame(width: fullW, height: fullH)
                .onChange(of: panes?.isPhysicalFold) { _, isFold in
                    if let isFold {
                        RDHaptics.shared.playWideTransition(toWide: !isFold)
                    }
                }
            }
            .ignoresSafeArea()

            // 供 UI 验收读取的稳定信号：真正推进到 0.5s 后才算起播
            Text(controller.time > 0.5 ? "started" : "waiting")
                .font(.system(size: 1))
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("player-started")

            // 供 UI 验收读取的当前集号
            Text("ep-\(current?.index ?? 1)")
                .font(.system(size: 1))
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("player-episode")

            // 供 UI 验收读取的当前秒数
            Text(String(format: "%.0f", controller.time))
                .font(.system(size: 1))
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("player-time-sec")
        }
        .statusBarHidden(true)
        .onAppear {
            controller.setBackgroundAudioEnabled(prefs.backgroundAudioEnabled)
            controller.setAudioOnlyMode(isAudioMode)
            attachNowPlayingHandlers()
            bgObserver.bind(controller: controller) {
                handlePlayerStateChanged("ended")
            }
            RDHaptics.shared.prepareLightweight()
        }
        .onChange(of: prefs.backgroundAudioEnabled) { _, val in
            controller.setBackgroundAudioEnabled(val)
        }
        .onChange(of: controller.isPlaying) { _, playing in
            if !playing { endSpeedBoostIfNeeded() }
            scheduleAutoHide()
            syncNowPlayingInfo()
        }
        .onChange(of: controller.stateText) { _, state in
            handlePlayerStateChanged(state)
        }
        .onChange(of: loading) { _, _ in scheduleAutoHide() }
        .onChange(of: showControls) { _, _ in scheduleAutoHide() }
        .onChange(of: showEpisodeDrawer) { _, _ in scheduleAutoHide() }
        .onChange(of: index) { _, _ in
            endSpeedBoostIfNeeded()
            firedAutoNextCountdownBeats.removeAll()
            showFinaleOverlay = false
        }
        .task(id: "\(activeSeries.id)-\(index)-\(seriesSwitchToken)") {
            await load(index, forceNew: false)
        }
        .onChange(of: controller.time) { _, newTime in
            guard !loading, error == nil else { return }
            handlePlaybackTimeTick(newTime)
            let now = Date().timeIntervalSince1970
            if now - lastSavedAt >= 3.0 {
                // 每 3 秒自动存档绝不震动（不打断沉浸观看）
                persistProgress(force: false, explicitTime: newTime)
                lastSavedAt = now
                syncNowPlayingInfo()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                endSpeedBoostIfNeeded()
                persistProgress(force: true)
                syncNowPlayingInfo()
            }
        }
        .onDisappear {
            hideTask?.cancel()
            modeToastTask?.cancel()
            centerFlashTask?.cancel()
            retryTask?.cancel()
            backgroundLoadTask?.cancel()
            preloader.cancel()
            activeLoadID = UUID()
            loadedEpisodeKey = ""
            RDHaptics.shared.stopDynamicField()
            endSpeedBoostIfNeeded()
            persistProgress(force: true)
            if let ep = pendingCleanupEpisode {
                pendingCleanupEpisode = nil
                OfflineCacheManager.shared.autoCleanFinishedEpisodeIfEnabled(ep, seriesID: activeSeries.id)
            }
            NowPlayingService.shared.clear()
            controller.stopPictureInPicture()
            controller.stop()
        }
    }

    // MARK: - 视频视图（单一 RDPlayerSurface 双引擎宿主 + 独立 UIKit 手势层：单击 / 双击 / 长按 2x / 双指捏合 / 上下滑跟手切集）

    private var allowVerticalSwipe: Bool {
        prefs.verticalSwipeEnabled
            && !showControls
            && !showEpisodeDrawer
            && !showRatePicker
            && !loading
            && error == nil
            && !showFinaleOverlay
            && !isSpeedBoosting
            && !isAudioMode
    }

    private func videoViewport(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            Color.clear
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("player-video-box")
                .allowsHitTesting(false)

            // 上滑即将出现的下一集 / 下滑即将出现的上一集预览卡（紧贴视频上/下沿）
            if dragOffsetY < -1, let nextEp = activeEpisodes[safe: index + 1] {
                SwipeAdjacentPreviewCard(
                    episode: nextEp,
                    isNext: true,
                    crossedThreshold: swipeThresholdCrossed,
                    fallbackCover: activeSeries.cover
                )
                .frame(width: width, height: height)
                .offset(y: height + dragOffsetY)
                .allowsHitTesting(false)
            } else if dragOffsetY > 1, let prevEp = activeEpisodes[safe: index - 1] {
                SwipeAdjacentPreviewCard(
                    episode: prevEp,
                    isNext: false,
                    crossedThreshold: swipeThresholdCrossed,
                    fallbackCover: activeSeries.cover
                )
                .frame(width: width, height: height)
                .offset(y: -height + dragOffsetY)
                .allowsHitTesting(false)
            }

            RDPlayerSurface(controller: controller, fillScreen: fillScreen, videoSize: controller.videoSize)
                .scaleEffect(pinchScale)
                .offset(y: dragOffsetY)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("player-video-surface")

            RDPlayerGestureOverlay(
                allowPlaybackGestures: !loading && error == nil,
                allowVerticalSwipe: allowVerticalSwipe,
                onSingleTap: {
                    let nextVisible = !showControls
                    if !nextVisible { showRatePicker = false }
                    withAnimation(RD.Motion.fade) { showControls = nextVisible }
                    RDHaptics.shared.playControlsToggle(visible: nextVisible)
                    scheduleAutoHide()
                },
                onDoubleTap: {
                    handleDoubleTapToggle()
                },
                onLongPress: { boosting in
                    handleLongPressSpeed(boosting)
                },
                onPinchBegan: {
                    isPinching = true
                },
                onPinchChanged: { scale in
                    let clamped = min(1.2, max(0.8, scale))
                    pinchScale = clamped
                    RDHaptics.shared.updatePinchDynamic(scale: clamped)
                    let thresholdMode = RDVideoFit.pinchCommit(magnitude: clamped)
                    if let thresholdMode, thresholdMode != pinchCrossedMode {
                        pinchCrossedMode = thresholdMode
                        RDHaptics.shared.playPinchThresholdCrossed(toFill: thresholdMode)
                    } else if thresholdMode == nil {
                        pinchCrossedMode = nil
                    }
                },
                onPinchEnded: { scale in
                    isPinching = false
                    pinchCrossedMode = nil
                    if let committed = RDVideoFit.pinchCommit(magnitude: scale) {
                        applyFillMode(committed, showFeedback: true, fromPinch: true)
                    } else {
                        RDHaptics.shared.playPinchDeadzoneCancel()
                    }
                    withAnimation(RD.Motion.snappy) {
                        pinchScale = RDVideoFit.releasedScale
                    }
                },
                onPinchCancelled: {
                    isPinching = false
                    pinchCrossedMode = nil
                    RDHaptics.shared.playPinchDeadzoneCancel()
                    withAnimation(RD.Motion.snappy) {
                        pinchScale = RDVideoFit.releasedScale
                    }
                },
                onVerticalPanChanged: { translationY, velocityY in
                    handleVerticalPanChanged(translationY: translationY, velocityY: velocityY, viewportHeight: height)
                },
                onVerticalPanEnded: { translationY, velocityY in
                    handleVerticalPanEnded(translationY: translationY, velocityY: velocityY, viewportHeight: height)
                },
                onVerticalPanCancelled: {
                    handleVerticalPanCancelled()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
    }

    // MARK: - 悬浮顶栏 & 底栏

    private func floatingTopBar(compact: Bool, isPhysicalFold: Bool) -> some View {
        let iconSize: CGFloat = compact ? 32 : 34
        return HStack(alignment: .center, spacing: compact ? 6 : 10) {
            Button {
                RDHaptics.shared.playGlassTap()
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font((compact ? Font.subheadline : Font.headline).bold())
                    .frame(width: compact ? 38 : 40, height: compact ? 38 : 40)
                    .rdGlassCircle()
                    .frame(minHeight: 44)
                    .contentShape(Circle())
            }
            .accessibilityIdentifier("player-close")

            VStack(alignment: .leading, spacing: 2) {
                Text(activeSeries.title)
                    .font(compact ? .system(size: 16, weight: .bold) : RD.Font.rowTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .rdMediaShadow()
                Button {
                    openEpisodeDrawer()
                } label: {
                    HStack(spacing: 3) {
                        Text("第\(current?.index ?? 1)集 / 共\(activeEpisodes.count)集")
                            .layoutPriority(1)
                        if let def = stream?.definition, !def.isEmpty {
                            Text("· \(def)")
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .layoutPriority(1)
                    }
                    .font(RD.Font.caption)
                    .foregroundStyle(RD.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .rdMediaShadow()
                    .frame(minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A8: 息屏听剧按钮
            Button {
                toggleAudioMode()
            } label: {
                Image(systemName: isAudioMode ? "headphones.circle.fill" : "headphones")
                    .font(.system(size: compact ? 14 : 15, weight: .semibold))
                    .foregroundStyle(isAudioMode ? RD.Palette.gemRim : .white)
                    .frame(width: iconSize, height: iconSize)
                    .rdGlassCircle()
            }
            .accessibilityLabel("息屏听剧")

            // A8: 画中画悬浮小窗按钮
            if !isAudioMode {
                Button {
                    togglePictureInPicture()
                } label: {
                    Image(systemName: controller.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .frame(width: iconSize, height: iconSize)
                        .rdGlassCircle()
                }
                .accessibilityLabel("画中画小窗")
            }

            // A2: 手动双屏追剧台切换（物理半折时自动开启）
            if !isPhysicalFold {
                Button {
                    RDHaptics.shared.playDrawerToggle(open: !manualWorkbench)
                    withAnimation(RD.Motion.snappy) { manualWorkbench.toggle() }
                    pokeControls()
                } label: {
                    Image(systemName: manualWorkbench ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .foregroundStyle(manualWorkbench ? RD.Palette.gemRim : .white)
                        .frame(width: iconSize, height: iconSize)
                        .rdGlassCircle()
                }
                .accessibilityLabel("追剧台")
            }

            stateBadge(dotOnly: compact)
        }
    }

    private func floatingBottomBar(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            progressSliderSection

            if compact {
                compactBottomControls
            } else {
                wideBottomControls
            }
        }
    }

    private var progressSliderSection: some View {
        VStack(spacing: 4) {
            let maxDur = max(controller.duration, 1)
            Slider(
                value: Binding(
                    get: { min(max(controller.time, 0), maxDur) },
                    set: { newVal in
                        handleSliderDragValueChanged(newVal, maxDuration: maxDur)
                        seekAndPersist(newVal, forceReport: false)
                    }
                ),
                in: 0...maxDur,
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if editing {
                        lastSliderValue = controller.time
                        lastSliderUpdateTime = CACurrentMediaTime()
                        didHitSliderEdge = false
                        RDHaptics.shared.playSliderGrab()
                    } else {
                        RDHaptics.shared.playSliderRelease()
                        persistProgress(force: true)
                    }
                }
            )
            .tint(accent)
            .accessibilityIdentifier("player-slider")
            HStack {
                Text(format(controller.time))
                Spacer()
                if currentSeriesRate != 1.0 {
                    Text("\(RDPlaybackPrefs.rateLabel(currentSeriesRate))")
                        .foregroundStyle(RD.Palette.gemRim)
                }
                Spacer()
                Text(format(controller.duration))
            }
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.78))
            .rdMediaShadow()
        }
    }

    /// 宽屏/展开/横屏：保持现行单排布局不动。
    private var wideBottomControls: some View {
        ZStack {
            HStack(spacing: 8) {
                if current != nil {
                    episodeDrawerButton(expanded: false)
                }

                Spacer()

                ratePickerButton(expanded: false)

                fitModeButton(expanded: false)
            }

            HStack(spacing: 28) {
                prevEpisodeButton(compact: false)
                playPauseButton
                nextEpisodeButton(compact: false)
            }
            .foregroundStyle(.white)
        }
    }

    /// 小屏/折叠/紧凑宽度：双排控件（第一排居中传输，第二排三胶囊功能区 >= 44pt 可点）。
    private var compactBottomControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 40) {
                prevEpisodeButton(compact: true)
                playPauseButton
                nextEpisodeButton(compact: true)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                episodeDrawerButton(expanded: true)
                ratePickerButton(expanded: true)
                fitModeButton(expanded: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func prevEpisodeButton(compact: Bool) -> some View {
        Button {
            RDHaptics.shared.playGlassTap(disabled: index <= 0)
            go(-1)
        } label: {
            Image(systemName: "backward.end.fill")
                .font(.title3)
                .frame(width: compact ? 44 : 40, height: compact ? 44 : 40)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("player-prev")
        .disabled(index <= 0)
        .opacity(index <= 0 ? 0.4 : 1)
    }

    private var playPauseButton: some View {
        Button { togglePlayPause() } label: {
            Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                .frame(minWidth: 52, minHeight: 52)
                .contentShape(Circle())
        }
        .accessibilityIdentifier("player-play-pause")
    }

    private func nextEpisodeButton(compact: Bool) -> some View {
        Button {
            RDHaptics.shared.playGlassTap(disabled: index >= activeEpisodes.count - 1)
            go(1)
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.title3)
                .frame(width: compact ? 44 : 40, height: compact ? 44 : 40)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("player-next")
        .disabled(index >= activeEpisodes.count - 1)
        .opacity(index >= activeEpisodes.count - 1 ? 0.4 : 1)
    }

    private func episodeDrawerButton(expanded: Bool) -> some View {
        let title = current.map { "第\($0.index)/\(activeEpisodes.count)集" } ?? "选集"
        return Button {
            openEpisodeDrawer()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(RD.Font.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 10)
            .frame(maxWidth: expanded ? .infinity : nil)
            .frame(height: expanded ? 36 : 34)
            .rdGlassCircleCapsule()
            .frame(minWidth: expanded ? 44 : nil, minHeight: expanded ? 44 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(RDPosterButtonStyle())
        .accessibilityIdentifier("player-episode-drawer-button")
    }

    private func ratePickerButton(expanded: Bool) -> some View {
        Button {
            RDHaptics.shared.playGlassTap()
            withAnimation(RD.Motion.snappy) { showRatePicker.toggle() }
            pokeControls()
        } label: {
            HStack(spacing: 4) {
                if expanded {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(RDPlaybackPrefs.rateLabel(currentSeriesRate))
                    .lineLimit(1)
            }
            .font(RD.Font.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(currentSeriesRate != 1.0 ? RD.Palette.gemRim : .white)
            .padding(.horizontal, 10)
            .frame(maxWidth: expanded ? .infinity : nil)
            .frame(height: expanded ? 36 : 34)
            .rdGlassCircleCapsule()
            .frame(minWidth: expanded ? 44 : nil, minHeight: expanded ? 44 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(RDPosterButtonStyle())
        .accessibilityLabel("倍速")
    }

    private var rateSelectorBar: some View {
        ViewThatFits(in: .horizontal) {
            rateSelectorRow
            ScrollView(.horizontal, showsIndicators: false) {
                rateSelectorRow
            }
        }
        .clipShape(Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.7))
        .environment(\.colorScheme, .dark)
    }

    private var rateSelectorRow: some View {
        HStack(spacing: 8) {
            Text("本剧倍速")
                .font(.caption2.bold())
                .foregroundStyle(RD.Palette.textSecondary)

            ForEach(RDPlaybackPrefs.supportedRates, id: \.self) { rate in
                let selected = abs(currentSeriesRate - rate) < 0.01
                Button {
                    selectSeriesRate(rate)
                } label: {
                    Text(RDPlaybackPrefs.rateLabel(rate))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(selected ? .white : .white.opacity(0.84))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                RDGemFacetSurface(shape: Capsule(), shadowRadius: 5, borderWidth: 0.8)
                            } else {
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                            }
                        }
                }
                .buttonStyle(RDPosterButtonStyle())
            }

            Divider().frame(height: 16).background(RD.Palette.hairline)

            Button {
                prefs.skipIntroOutroEnabled.toggle()
                RDHaptics.shared.playChipSelect()
                showToast(prefs.skipIntroOutroEnabled ? "已开启自动跳过片头片尾" : "已关闭自动跳过片头片尾")
                pokeControls()
            } label: {
                Text(prefs.skipIntroOutroEnabled ? "自动跳片头尾·开" : "跳过片头尾")
                    .font(.caption2.bold())
                    .foregroundStyle(prefs.skipIntroOutroEnabled ? RD.Palette.gemRim : .white.opacity(0.84))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(RDPosterButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func skipIntroOutroPillOverlay(bottomPad: CGFloat, trailingPad: CGFloat) -> some View {
        let dur = controller.duration
        let t = controller.time
        if let introTarget = RDPlaybackPrefs.introSkipTarget(duration: dur),
           t >= 0.5 && t < introTarget - 1.5 {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        performSkipIntro(manual: true)
                    } label: {
                        Label("跳过片头", systemImage: "forward.frame.fill")
                            .font(RD.Font.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                RDGemFacetSurface(shape: Capsule(), shadowRadius: 8)
                            }
                    }
                    .buttonStyle(RDPosterButtonStyle())
                }
                .padding(.trailing, trailingPad)
                .padding(.bottom, bottomPad)
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if let outroStart = RDPlaybackPrefs.outroSkipStart(duration: dur),
                  t >= outroStart && index < activeEpisodes.count - 1 {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        performSkipOutro(manual: true)
                    } label: {
                        Label("跳过片尾 · 下一集", systemImage: "forward.end.alt.fill")
                            .font(RD.Font.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                RDGemFacetSurface(shape: Capsule(), shadowRadius: 8)
                            }
                    }
                    .buttonStyle(RDPosterButtonStyle())
                }
                .padding(.trailing, trailingPad)
                .padding(.bottom, bottomPad)
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private func episodeDrawerLayer(w: CGFloat, h: CGFloat, leadingPad: CGFloat, trailingPad: CGFloat, bottomPad: CGFloat) -> some View {
        let sideMode = w > h && w >= 520
        return ZStack(alignment: sideMode ? .trailing : .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { closeEpisodeDrawer() }

            PlayerEpisodeDrawer(
                series: activeSeries,
                episodes: activeEpisodes,
                currentIndex: index,
                isLandscapeOrWide: sideMode,
                onSelect: { targetIdx in
                    closeEpisodeDrawer()
                    jumpToEpisode(targetIdx)
                },
                onCacheNext10: {
                    OfflineCacheManager.shared.cacheNext10(series: activeSeries, episodes: activeEpisodes, fromIndex: index)
                    showToast("已加入离线缓存：后续 10 集")
                },
                onCacheAll: {
                    OfflineCacheManager.shared.cacheAll(series: activeSeries, episodes: activeEpisodes)
                    showToast("已加入离线缓存：全 \(activeEpisodes.count) 集")
                },
                onClose: { closeEpisodeDrawer() }
            )
            .frame(
                width: sideMode ? min(w * 0.48, 370) : max(260, w - leadingPad - trailingPad),
                height: sideMode ? max(240, h - 32) : min(h * 0.56, 440)
            )
            .padding(.trailing, sideMode ? trailingPad : 0)
            .padding(.bottom, sideMode ? 16 : max(bottomPad, 16))
            .padding(.top, sideMode ? 16 : 0)
        }
    }

    /// 填充 / 全屏（完整显示）切换按钮：图标形态沿用 DouDuo `DYFitCornerGlyph` 约定 + 模式标签。
    private func fitModeButton(expanded: Bool) -> some View {
        Button {
            applyFillMode(!fillScreen, showFeedback: true, fromPinch: false)
            pokeControls()
        } label: {
            HStack(spacing: 6) {
                RDVideoFitGlyph(inward: fillScreen)
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 17, height: 17)
                Text(RDVideoFit.mode(fillScreen: fillScreen).title)
                    .font(RD.Font.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, expanded ? 10 : 12)
            .frame(maxWidth: expanded ? .infinity : nil)
            .frame(height: expanded ? 36 : 34)
            .rdGlassCircleCapsule()
            .frame(minWidth: expanded ? 44 : nil, minHeight: expanded ? 44 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(RDPosterButtonStyle())
        .accessibilityLabel(fillScreen ? "填充模式，点按切回全屏完整显示" : "全屏完整显示，点按切换为填充铺满")
        .accessibilityIdentifier("player-fit-toggle")
    }

    private func stateBadge(dotOnly: Bool) -> some View {
        let isPlaying = controller.stateText == "playing"
        let isBuffering = controller.stateText == "buffering" || controller.stateText == "opening"
        let dotColor: Color = isPlaying
            ? (dotOnly ? RD.Palette.gemBright : accent)
            : (isBuffering ? RD.Palette.warning : RD.Palette.textTertiary)
        return HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: dotOnly ? 8 : 6, height: dotOnly ? 8 : 6)
                .shadow(color: (dotOnly && isPlaying) ? RD.Palette.gemBright.opacity(0.75) : .clear, radius: 3)
            if !dotOnly {
                Text(controller.stateText)
            }
        }
        .accessibilityIdentifier("player-state")
        .accessibilityLabel("播放状态：\(controller.stateText)")
        .font(RD.Font.micro)
        .foregroundStyle(.white)
        .padding(.horizontal, dotOnly ? 9 : 10)
        .padding(.vertical, dotOnly ? 8 : 6)
        .rdGlassCircleCapsule()
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView().tint(accent).scaleEffect(1.2)
            Text(phaseText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            if let current {
                Text("\(activeSeries.title) · 第\(current.index)集")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RD.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RD.Radius.sheet, style: .continuous)
                .strokeBorder(RD.Palette.hairline, lineWidth: 0.7)
        )
        .environment(\.colorScheme, .dark)
        .padding(16)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(RD.Palette.warning)
            Text("播放失败")
                .font(.headline)
                .foregroundStyle(.white)
            ViewThatFits(in: .vertical) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 200)
            }
            HStack(spacing: 12) {
                Button("重试") {
                    RDHaptics.shared.playRetryTap()
                    retryTask?.cancel()
                    retryTask = Task { await load(index, forceNew: true) }
                }
                .buttonStyle(RDPrimaryButtonStyle())
                Button("返回") {
                    RDHaptics.shared.playGlassTap()
                    close()
                }
                .buttonStyle(RDPrimaryButtonStyle(filled: false))
            }
        }
        .padding(22)
        .frame(maxWidth: 360)
        .rdCard(radius: RD.Radius.sheet, fill: RD.Palette.surface.opacity(0.95))
        .padding(20)
    }

    private func toastPill(_ text: String, accentBorder: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.black.opacity(0.76), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    accentBorder ? RD.Palette.gemBorder : Color.white.opacity(0.18),
                    lineWidth: 0.8
                )
            )
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
    }

    private func centerPlayPauseFeedback(icon: String) -> some View {
        ZStack {
            Circle()
                .fill(RD.Palette.gemVoid.opacity(0.84))
                .frame(width: 78, height: 78)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [RD.Palette.gemDeep.opacity(0.42), .clear],
                                center: .center,
                                startRadius: 4,
                                endRadius: 38
                            )
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(RD.Gem.anchorBorderGradient, lineWidth: 1.0)
                )
                .shadow(color: RD.Palette.gemCore.opacity(0.36), radius: 10, y: 3)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)

            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: icon == "play.fill" ? 2 : 0)
                .rdMediaShadow()
        }
    }

    private var speedBoostPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(RD.Palette.gemCaustic)
                .frame(width: 6, height: 6)
                .shadow(color: RD.Palette.gemBright, radius: 3)
            Text("2.0x »")
                .font(.caption.monospacedDigit().weight(.heavy))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(RD.Palette.gemVoid.opacity(0.86), in: Capsule())
        .overlay(
            Capsule().strokeBorder(RD.Gem.anchorBorderGradient, lineWidth: 0.9)
        )
        .shadow(color: RD.Palette.gemCore.opacity(0.38), radius: 8, y: 2)
    }

    // MARK: - 手势响应（竖滑切集 / 双击 / 长按 2x / 捏合 / 进度刻度）

    private func handleVerticalPanChanged(translationY: CGFloat, velocityY: CGFloat, viewportHeight: CGFloat) {
        let movingUp = translationY < 0
        let hasTarget = movingUp ? (index < activeEpisodes.count - 1) : (index > 0)
        if !hasTarget {
            dragOffsetY = translationY * 0.22
            if abs(translationY) > 48 && !didFireBoundaryHaptic {
                didFireBoundaryHaptic = true
                RDHaptics.shared.playSwipeBoundaryWall()
                showToast(index == 0 ? "已到第一集" : "已到最后一集")
            }
            return
        }

        dragOffsetY = translationY
        let threshold = max(viewportHeight / 3.0, 90)
        let progress = min(abs(translationY) / threshold, 1.0)
        RDHaptics.shared.updateSwipeDragField(progress: progress, velocityY: velocityY)

        let crossed = abs(translationY) >= threshold
        if crossed != swipeThresholdCrossed {
            swipeThresholdCrossed = crossed
            if crossed {
                RDHaptics.shared.playSwipeThresholdCrossed()
            }
        }
    }

    private func handleVerticalPanEnded(translationY: CGFloat, velocityY: CGFloat, viewportHeight: CGFloat) {
        let threshold = max(viewportHeight / 3.0, 90)
        let isNext = dragOffsetY < 0
        let hasTarget = isNext ? (index < activeEpisodes.count - 1) : (index > 0)
        let shouldSwitch = hasTarget && abs(dragOffsetY) >= threshold

        swipeThresholdCrossed = false
        didFireBoundaryHaptic = false

        if shouldSwitch {
            RDHaptics.shared.playEpisodeSwitch(next: isNext)
            withAnimation(.easeOut(duration: 0.16)) {
                dragOffsetY = isNext ? -viewportHeight : viewportHeight
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 140_000_000)
                dragOffsetY = 0
                go(isNext ? 1 : -1)
            }
        } else {
            if hasTarget {
                RDHaptics.shared.playSwipeBounceBack()
            } else {
                RDHaptics.shared.stopDynamicField()
            }
            withAnimation(RD.Motion.snappy) {
                dragOffsetY = 0
            }
        }
    }

    private func handleVerticalPanCancelled() {
        swipeThresholdCrossed = false
        didFireBoundaryHaptic = false
        RDHaptics.shared.playSwipeBounceBack()
        withAnimation(RD.Motion.snappy) {
            dragOffsetY = 0
        }
    }

    private func handleDoubleTapToggle() {
        guard !loading, error == nil else { return }
        endSpeedBoostIfNeeded(withHaptic: false)
        persistProgress(force: true)
        controller.playPause()
        RDHaptics.shared.playDoubleTapToggle(nowPlaying: controller.isPlaying)
        let icon = controller.isPlaying ? "play.fill" : "pause.fill"
        triggerCenterFlash(icon)
        if showControls {
            scheduleAutoHide()
        }
    }

    private func triggerCenterFlash(_ icon: String) {
        centerFlashTask?.cancel()
        let token = UUID()
        centerFlashID = token
        withAnimation(RD.Motion.press) {
            centerFlashIcon = icon
        }
        centerFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 580_000_000)
            if !Task.isCancelled && self.centerFlashID == token {
                withAnimation(RD.Motion.fade) {
                    self.centerFlashIcon = nil
                }
            }
        }
    }

    private func handleLongPressSpeed(_ pressing: Bool) {
        if pressing {
            guard !loading, error == nil, controller.isPlaying, !isSpeedBoosting else { return }
            rateBeforeBoost = controller.playbackRate > 0 ? controller.playbackRate : currentSeriesRate
            controller.setRate(2.0)
            withAnimation(RD.Motion.snappy) {
                isSpeedBoosting = true
            }
            // 按住持续期绝不嗡震，仅在 0.35s 达标瞬间给上扬锁钉
            RDHaptics.shared.playSpeedBoostEngage()
        } else {
            let interruptedByPinch = isPinching || pinchScale != RDVideoFit.releasedScale
            endSpeedBoostIfNeeded(withHaptic: true, interruptedByPinch: interruptedByPinch)
        }
    }

    private func endSpeedBoostIfNeeded(withHaptic: Bool = false, interruptedByPinch: Bool = false) {
        guard isSpeedBoosting else { return }
        let restoreRate = rateBeforeBoost > 0 ? rateBeforeBoost : currentSeriesRate
        controller.setRate(restoreRate)
        withAnimation(RD.Motion.fade) {
            isSpeedBoosting = false
        }
        if withHaptic {
            if interruptedByPinch {
                RDHaptics.shared.playSpeedBoostInterruptedByPinch()
            } else {
                RDHaptics.shared.playSpeedBoostRelease()
            }
        }
    }

    private func applyFillMode(_ nextFill: Bool, showFeedback: Bool, fromPinch: Bool) {
        if fillScreen != nextFill {
            fillScreen = nextFill
            if fromPinch {
                RDHaptics.shared.playPinchCommit(fillScreen: nextFill)
            } else {
                RDHaptics.shared.playGlassTap()
            }
        } else if fromPinch {
            RDHaptics.shared.playPinchCommit(fillScreen: nextFill)
        }
        guard showFeedback else { return }
        showToast(RDVideoFit.mode(fillScreen: nextFill).toastText)
    }

    private func handleSliderDragValueChanged(_ newVal: Double, maxDuration: Double) {
        guard isDraggingSlider else { return }
        let now = CACurrentMediaTime()
        let dt = max(now - lastSliderUpdateTime, 0.016)
        let fractionDelta = abs(newVal - lastSliderValue) / max(maxDuration, 1)
        let velocity = fractionDelta / dt

        if newVal <= 0.1 || newVal >= maxDuration - 0.1 {
            if !didHitSliderEdge {
                didHitSliderEdge = true
                RDHaptics.shared.playSliderBoundary()
            }
        } else {
            didHitSliderEdge = false
            // 掠过上次续播点或整分锚点时给磁吸卡槽
            let crossedResume = resumeTargetSeconds >= 5.0
                && ((lastSliderValue < resumeTargetSeconds && newVal >= resumeTargetSeconds)
                    || (lastSliderValue > resumeTargetSeconds && newVal <= resumeTargetSeconds))
            let prevMin = Int(lastSliderValue / 60.0)
            let newMin = Int(newVal / 60.0)
            if crossedResume || (prevMin != newMin && newVal > 5.0) {
                RDHaptics.shared.playSliderAnchorSnap()
            } else if abs(newVal - lastSliderValue) >= max(maxDuration * 0.015, 1.5) {
                RDHaptics.shared.playSliderTick(velocity: velocity)
            }
        }

        lastSliderValue = newVal
        lastSliderUpdateTime = now
    }

    private func showToast(_ msg: String) {
        modeToastTask?.cancel()
        modeToast = msg
        modeToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled && self.modeToast == msg {
                self.modeToast = nil
            }
        }
    }

    /// 沉浸式：播放中控件 4 秒无操作自动淡出（自动隐藏绝不震动）。
    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard showControls, controller.isPlaying, !loading, error == nil,
              !showEpisodeDrawer, !showRatePicker, !isAudioMode, !showFinaleOverlay else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if Task.isCancelled { return }
            withAnimation(RD.Motion.fade) { showControls = false }
        }
    }

    private func pokeControls() {
        withAnimation(RD.Motion.fade) { showControls = true }
        scheduleAutoHide()
    }

    // MARK: - 1.4 交互动作（抽屉 / 倍速 / 跳过 / 连播 / 听剧 / 画中画 / 接档）

    private func openEpisodeDrawer() {
        RDHaptics.shared.playDrawerToggle(open: true)
        withAnimation(RD.Motion.snappy) {
            showRatePicker = false
            showEpisodeDrawer = true
        }
    }

    private func closeEpisodeDrawer() {
        RDHaptics.shared.playDrawerToggle(open: false)
        withAnimation(RD.Motion.snappy) {
            showEpisodeDrawer = false
        }
    }

    private func selectSeriesRate(_ rate: Float) {
        prefs.setRate(rate, for: activeSeries.id)
        rateBeforeBoost = rate
        controller.setRate(rate)
        RDHaptics.shared.playRateSelected()
        showToast("倍速 \(RDPlaybackPrefs.rateLabel(rate)) · 已为本剧记住")
        pokeControls()
    }

    private func performSkipIntro(manual: Bool) {
        let dur = controller.duration
        guard let target = RDPlaybackPrefs.introSkipTarget(duration: dur) else {
            if manual { showToast("该集较短，无需跳过片头") }
            return
        }
        didAutoSkipIntro = true
        controller.seek(to: target)
        RDHaptics.shared.playSkipAction()
        showToast("已跳过片头 · \(format(target))")
        if manual { pokeControls() }
    }

    private func performSkipOutro(manual: Bool) {
        guard index < activeEpisodes.count - 1 else {
            if manual { showToast("已是最后一集") }
            return
        }
        didHandleEpisodeEnd = true
        if let ep = current {
            prefs.markEpisodeWatched(seriesID: activeSeries.id, episodeIndex: ep.index)
            pendingCleanupEpisode = ep
        }
        RDHaptics.shared.playSkipAction()
        showToast("已跳过片尾 · 进入下一集")
        go(1)
    }

    private func toggleAudioMode() {
        let next = !isAudioMode
        withAnimation(RD.Motion.snappy) {
            isAudioMode = next
            if next { showEpisodeDrawer = false; showRatePicker = false }
        }
        controller.setAudioOnlyMode(next)
        RDHaptics.shared.playAudioModeToggle(active: next)
        showToast(next ? "已切入息屏听剧 · 支持锁屏后台连播" : "已恢复视频画面")
        syncNowPlayingInfo()
    }

    private func togglePictureInPicture() {
        if controller.isPiPActive {
            controller.stopPictureInPicture()
            RDHaptics.shared.playPiPToggle(active: false)
        } else if controller.startPictureInPicture() {
            RDHaptics.shared.playPiPToggle(active: true)
        } else {
            RDHaptics.shared.playGlassTap(disabled: true)
            showToast(controller.activeEngine == .vlc ? "当前回退解码暂不支持小窗，可开启息屏听剧" : "视频就绪后可开启画中画小窗")
        }
    }

    private func handlePlaybackTimeTick(_ newTime: Double) {
        // 签名震动：正片第一帧真正亮屏起播（controller.time > 0.5）瞬间
        if !didFirePremiereHaptic, newTime > 0.5, controller.isPlaying || controller.hasVideoOut {
            didFirePremiereHaptic = true
            RDHaptics.shared.playSignaturePremiere()
        }

        // A7: 自动跳过片头
        if prefs.skipIntroOutroEnabled,
           !didAutoSkipIntro,
           resumeTargetSeconds < 2.0,
           controller.duration >= 45,
           let target = RDPlaybackPrefs.introSkipTarget(duration: controller.duration),
           newTime >= 0.3 && newTime < target - 1.5 {
            didAutoSkipIntro = true
            controller.seek(to: target)
            RDHaptics.shared.playSkipAction()
            showToast("已自动跳过片头")
            return
        }

        // A7: 自动跳过片尾进下一集
        if prefs.skipIntroOutroEnabled,
           !didHandleEpisodeEnd,
           controller.duration >= 45,
           let outroStart = RDPlaybackPrefs.outroSkipStart(duration: controller.duration),
           newTime >= outroStart {
            if index < activeEpisodes.count - 1 {
                didHandleEpisodeEnd = true
                if let ep = current {
                    prefs.markEpisodeWatched(seriesID: activeSeries.id, episodeIndex: ep.index)
                    pendingCleanupEpisode = ep
                }
                RDHaptics.shared.playSkipAction()
                showToast("已自动跳过片尾")
                go(1)
            }
        }

        // A1: 无视觉提示连播渐紧震动（进入最后 3 秒触发 3 → 2 → 1 震动序列；沉浸静音档由 RDHaptics 内部屏蔽）
        if prefs.autoPlayNextEnabled,
           !didHandleEpisodeEnd,
           !isDraggingSlider,
           index < activeEpisodes.count - 1,
           controller.isPlaying,
           UIApplication.shared.applicationState == .active,
           controller.duration >= 5.0,
           newTime >= 1.0 {
            let remaining = controller.duration - newTime
            if remaining > 3.5 {
                if !firedAutoNextCountdownBeats.isEmpty {
                    firedAutoNextCountdownBeats.removeAll()
                }
            } else if remaining > 0.15 && remaining <= 3.0 {
                let beat = Int(ceil(remaining))
                if (1...3).contains(beat), !firedAutoNextCountdownBeats.contains(beat) {
                    firedAutoNextCountdownBeats.insert(beat)
                    RDHaptics.shared.playUpNextCountdown(remaining: beat)
                }
            }
        }
    }

    private func handlePlayerStateChanged(_ state: String) {
        syncNowPlayingInfo()
        guard !loading, error == nil else { return }
        if state == "error" {
            RDHaptics.shared.playPlaybackError()
            return
        }
        guard state == "ended", !didHandleEpisodeEnd else { return }
        didHandleEpisodeEnd = true

        if let ep = current {
            prefs.markEpisodeWatched(seriesID: activeSeries.id, episodeIndex: ep.index)
            pendingCleanupEpisode = ep
        }

        if index < activeEpisodes.count - 1 {
            guard prefs.autoPlayNextEnabled else { return }
            if UIApplication.shared.applicationState == .active {
                RDHaptics.shared.playUpNextAutoAdvance()
            }
            go(1)
        } else {
            // 大结局：加载「同款接档」推荐
            presentFinaleRecommendations()
        }
    }

    private func presentFinaleRecommendations() {
        finaleRecommendations = CatalogCache.shared.relatedSeries(for: activeSeries, limit: 8)
        withAnimation(RD.Motion.snappy) {
            showFinaleOverlay = true
        }
        if finaleRecommendations.isEmpty {
            Task {
                if let page = try? await ManjuAPI.shared.homeFeedFirstPage() {
                    CatalogCache.shared.ingest(page.items)
                    finaleRecommendations = CatalogCache.shared.relatedSeries(for: activeSeries, limit: 8)
                }
            }
        }
    }

    private func switchToRecommendedSeries(_ nextSeries: Series) async {
        withAnimation(RD.Motion.fade) { showFinaleOverlay = false }
        loading = true
        phaseText = "正在接档《\(nextSeries.title)》…"
        do {
            let detail = try await ManjuAPI.shared.album(seriesID: nextSeries.id)
            CatalogCache.shared.ingestAlbum(detail)
            activeSeries = detail.series
            activeEpisodes = detail.episodes
            index = 0
            seriesSwitchToken += 1
        } catch {
            if let vid = nextSeries.firstVid {
                let ep = Episode(vid: vid, index: nextSeries.firstIndex, title: "第\(nextSeries.firstIndex)集",
                                 cover: nextSeries.cover, duration: nextSeries.estimatedEpisodeDuration, seriesID: nextSeries.id)
                activeSeries = nextSeries
                activeEpisodes = [ep]
                index = 0
                seriesSwitchToken += 1
            } else {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }

    // MARK: - Now Playing 协同

    private func attachNowPlayingHandlers() {
        NowPlayingService.shared.attach(handlers: .init(
            onTogglePlayPause: { controller.playPause(); syncNowPlayingInfo() },
            onPlay: { if !controller.isPlaying { controller.playPause(); syncNowPlayingInfo() } },
            onPause: { if controller.isPlaying { controller.playPause(); syncNowPlayingInfo() } },
            onNext: { if index < activeEpisodes.count - 1 { go(1) } },
            onPrev: { if index > 0 { go(-1) } },
            onSeek: { sec in seekAndPersist(sec, forceReport: true) }
        ))
    }

    private func syncNowPlayingInfo() {
        guard let ep = current else { return }
        NowPlayingService.shared.update(
            seriesTitle: activeSeries.title,
            episodeIndex: ep.index,
            episodeTitle: ep.title,
            coverURL: ep.cover.isEmpty ? activeSeries.cover : ep.cover,
            elapsed: controller.time,
            duration: controller.duration > 0 ? controller.duration : Double(ep.duration),
            rate: controller.playbackRate,
            isPlaying: controller.isPlaying
        )
    }

    // MARK: - 控制与记忆播放

    private func togglePlayPause() {
        pokeControls()
        persistProgress(force: true)
        controller.playPause()
        RDHaptics.shared.playDoubleTapToggle(nowPlaying: controller.isPlaying)
        syncNowPlayingInfo()
    }

    private func seekAndPersist(_ seconds: Double, forceReport: Bool) {
        pokeControls()
        controller.seek(to: seconds)
        let now = Date().timeIntervalSince1970
        let shouldForce = forceReport || (now - lastSeekReportAt >= 1.0)
        if shouldForce { lastSeekReportAt = now }
        persistProgress(force: shouldForce, explicitTime: seconds)
    }

    private func jumpToEpisode(_ nextIdx: Int) {
        guard activeEpisodes.indices.contains(nextIdx) else { return }
        if nextIdx == index { return }
        let finished = didHandleEpisodeEnd || (controller.duration > 10 && controller.time >= controller.duration * 0.85)
        if finished, let ep = current {
            prefs.markEpisodeWatched(seriesID: activeSeries.id, episodeIndex: ep.index)
            pendingCleanupEpisode = ep
        }
        persistProgress(force: true)
        index = nextIdx
        if UIApplication.shared.applicationState != .active {
            backgroundLoadTask?.cancel()
            backgroundLoadTask = Task { await load(nextIdx, forceNew: false) }
        }
    }

    private func go(_ delta: Int) {
        let next = index + delta
        guard activeEpisodes.indices.contains(next) else { return }
        jumpToEpisode(next)
    }

    private func close() {
        persistProgress(force: true)
        activeLoadID = UUID()
        loadedEpisodeKey = ""
        retryTask?.cancel()
        retryTask = nil
        backgroundLoadTask?.cancel()
        backgroundLoadTask = nil
        preloader.cancel()
        controller.stopPictureInPicture()
        controller.stop()
        if let ep = pendingCleanupEpisode {
            pendingCleanupEpisode = nil
            OfflineCacheManager.shared.autoCleanFinishedEpisodeIfEnabled(ep, seriesID: activeSeries.id)
        }
        dismiss()
    }

    private func persistProgress(force: Bool, explicitTime: Double? = nil) {
        guard let ep = current else { return }
        // 已停播 / 加载中 / 错误态下不覆盖既有续播进度为 0（避免 close() 后 onDisappear 二次清零）
        if explicitTime == nil {
            guard !loading, error == nil, controller.activeEngine != nil else { return }
        }
        let sec = explicitTime ?? controller.time
        // 若刚起播准备续播且尚未完成初始定位，不把原有进度覆盖成 0
        if !controller.hasCompletedInitialSeek && resumeTargetSeconds > 1.0 && sec < 1.0 {
            return
        }
        let effectivePos = max(0, sec)
        let dur = controller.duration > 0 ? controller.duration : Double(ep.duration)
        if !force && effectivePos < 0.5 { return }
        WatchHistory.shared.record(series: activeSeries, episode: ep, position: effectivePos, duration: dur, log: force)
        if force, effectivePos >= 1.0 {
            let sid = activeSeries.id, vid = ep.vid, epIdx = ep.index
            Task {
                await ManjuAPI.shared.reportWatchProgress(seriesID: sid, vid: vid, episodeIndex: epIdx, positionSeconds: effectivePos)
            }
        }
    }

    /// 起播安全网（1.3 (4) 已验证口径，严禁改动取流/备流/双引擎/候选阶梯）。
    private let startupTimeout: TimeInterval = 8.0
    private let maxStartupAttempts = 8

    private func load(_ idx: Int, forceNew: Bool) async {
        guard activeEpisodes.indices.contains(idx) else { return }
        let episodeKey = "\(activeSeries.id)-\(idx)-\(seriesSwitchToken)"
        if !forceNew && loadedEpisodeKey == episodeKey { return }
        loadedEpisodeKey = episodeKey

        let loadID = UUID()
        activeLoadID = loadID
        if !forceNew {
            retryTask?.cancel()
            retryTask = nil
        }
        controller.stop()
        preloader.cancel()

        // 切集前先安全清理上一集已看完且可自动清理的离线文件（此时播放器已停播，无文件占用冲突）
        if let cleanupEp = pendingCleanupEpisode, cleanupEp.vid != activeEpisodes[idx].vid {
            pendingCleanupEpisode = nil
            OfflineCacheManager.shared.autoCleanFinishedEpisodeIfEnabled(cleanupEp, seriesID: activeSeries.id)
        }

        didFirePremiereHaptic = false
        didAutoSkipIntro = false
        didHandleEpisodeEnd = false
        firedAutoNextCountdownBeats.removeAll()
        showFinaleOverlay = false

        let ep = activeEpisodes[idx]
        loading = true
        error = nil
        stream = nil
        resumeBanner = nil
        phaseText = "正在本地签名取流…"

        // 记忆播放：若该剧保存了同集且进度 >= 1.5s，自动续播到上次秒数
        var resumeAt: Double = 0
        if let saved = WatchHistory.shared.entry(for: activeSeries.id),
           (saved.lastVid == ep.vid || saved.lastIndex == ep.index),
           saved.lastPosition >= 1.5,
           (saved.lastDuration <= 0 || saved.lastPosition < saved.lastDuration - 2.0) {
            resumeAt = saved.lastPosition
        }
        resumeTargetSeconds = resumeAt

        func isStale() -> Bool {
            Task.isCancelled || activeLoadID != loadID
        }

        AppLog.write("PLAYER load series=\(activeSeries.id) title=\(activeSeries.title) ep=\(ep.index) vid=\(ep.vid) resumeAt=\(String(format: "%.1f", resumeAt))s forceNew=\(forceNew)")
        do {
            // 1.2 (2) 口径排序后的全部可播候选：H.264 优先，其余编码兜底；按顺序逐档起播。
            let candidates = try await ManjuAPI.shared.playbackCandidates(vid: ep.vid, seriesID: activeSeries.id)
            if isStale() { return }
            guard !candidates.isEmpty else { throw ManjuError.noMainURL("播放取流没有可用候选") }
            AppLog.write("PLAYER candidates ep=\(ep.index) count=\(candidates.count) order=\(candidates.map { "\($0.definition):\($0.codec)" }.joined(separator: ","))")

            var failures: [String] = []
            let limit = min(candidates.count, maxStartupAttempts)
            for (attemptIndex, info) in candidates.prefix(limit).enumerated() {
                if isStale() { return }
                phaseText = attemptIndex == 0
                    ? "正在准备 \(info.definition) 视频…"
                    : "\(info.definition) 起播未成功，降档重试（\(attemptIndex + 1)/\(limit)）…"
                AppLog.write("PLAYER candidate pick ep=\(ep.index) idx=\(attemptIndex + 1)/\(limit) def=\(info.definition) codec=\(info.codec) size=\(info.fileSize) encrypted=\(info.isEncrypted)")

                let local: URL
                do {
                    if info.isEncrypted {
                        phaseText = "加密流：下载并解密中…"
                        local = try await StreamPreparer.shared.prepare(info) { msg in
                            Task { @MainActor in
                                if !Task.isCancelled, self.activeLoadID == loadID {
                                    self.phaseText = msg
                                }
                            }
                        }
                    } else {
                        guard let url = URL(string: info.url) else { throw ManjuError.noMainURL("URL 无法构造") }
                        local = url
                    }
                } catch {
                    if isStale() { return }
                    failures.append("\(info.definition) 准备失败(\(error.localizedDescription))")
                    AppLog.write("PLAYER candidate prepare failed ep=\(ep.index) def=\(info.definition) error=\(error.localizedDescription)")
                    continue
                }

                if isStale() { return }
                AppLog.write("PLAYER prepared ep=\(ep.index) domain=\(info.domain) codec=\(info.codec) def=\(info.definition) local=\(local.lastPathComponent) file=\(local.isFileURL ? 1 : 0)")

                // 每档候选内：先 AVPlayer（系统播放器，吃本地解密 MP4），失败再回退现有 VLCKit；
                // 两个引擎都失败才降下一档。清晰度标识只认最终真正起播的档位。
                var engineResults: [String] = []
                var startedEngine: RDPlaybackEngine?
                for engine in RDPlaybackEngine.allCases {
                    if isStale() { return }
                    phaseText = "正在起播 \(info.definition)（\(engine.label)）…"
                    AppLog.write("PLAYER engine pick ep=\(ep.index) def=\(info.definition) engine=\(engine.label) source=\(local.isFileURL ? "local" : "remote")")
                    controller.load(url: local, startAt: resumeAt, engine: engine)

                    let outcome = await waitForPlaybackStart(engine: engine, timeout: startupTimeout, loadID: loadID)
                    if isStale() {
                        if activeLoadID == loadID { controller.stop() }
                        return
                    }
                    switch outcome {
                    case .started:
                        startedEngine = engine
                        AppLog.write("PLAYER engine ok ep=\(ep.index) def=\(info.definition) engine=\(engine.label) time=\(String(format: "%.1f", controller.time)) duration=\(String(format: "%.1f", controller.duration)) vout=\(controller.hasVideoOut)")
                    case .failed(let detail):
                        engineResults.append(formatEngineFailure(engine: engine, detail: detail))
                        AppLog.write("PLAYER engine failed ep=\(ep.index) def=\(info.definition) engine=\(engine.label) detail=\(detail) diagnostic=\(controller.activeDiagnostic)")
                        controller.stop()
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    if startedEngine != nil { break }
                }

                if isStale() { return }
                if let startedEngine {
                    // 标题栏清晰度只在真正起播后按实际在播流更新。
                    stream = info
                    loading = false

                    // A7: 应用该剧记忆倍速
                    let savedRate = prefs.rate(for: activeSeries.id)
                    rateBeforeBoost = savedRate
                    if abs(savedRate - 1.0) > 0.01 {
                        controller.setRate(savedRate)
                    }

                    let dur = controller.duration > 0 ? controller.duration : Double(ep.duration)
                    WatchHistory.shared.record(series: activeSeries, episode: ep, position: resumeAt, duration: dur, log: true)
                    if resumeAt >= 1.5 {
                        let text = "已续播至第\(ep.index)集 \(format(resumeAt))"
                        resumeBanner = text
                        RDHaptics.shared.playResumeBookmarkApplied()
                        AppLog.write("PLAYER resume series=\(activeSeries.id) ep=\(ep.index) target=\(String(format: "%.1f", resumeAt))s")
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_800_000_000)
                            if self.resumeBanner == text {
                                withAnimation { self.resumeBanner = nil }
                            }
                        }
                    }

                    if controller.time > 0.5 && !didFirePremiereHaptic {
                        didFirePremiereHaptic = true
                        if resumeAt >= 1.5 {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 160_000_000)
                                guard !Task.isCancelled, self.activeLoadID == loadID else { return }
                                RDHaptics.shared.playSignaturePremiere()
                            }
                        } else {
                            RDHaptics.shared.playSignaturePremiere()
                        }
                    }

                    syncNowPlayingInfo()

                    // A1: 当前集起播成功后，静默提前备好后续两集（调用现行 StreamPreparer）
                    preloader.scheduleUpcoming(seriesID: activeSeries.id, episodes: activeEpisodes, currentIndex: idx)

                    AppLog.write("PLAYER started ep=\(ep.index) domain=\(info.domain) encrypted=\(info.isEncrypted) def=\(info.definition) engine=\(startedEngine.label) attempt=\(attemptIndex + 1) state=\(controller.stateText)")
                    return
                }

                failures.append("\(info.definition) \(engineResults.joined(separator: "/"))")
                AppLog.write("PLAYER candidate failed ep=\(ep.index) def=\(info.definition) engines=\(engineResults.joined(separator: " | "))")
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if isStale() { return }
            throw ManjuError.noMainURL("该集所有清晰度均无法起播（\(failures.joined(separator: "；"))）")
        } catch is CancellationError {
            // 切集 / 退出播放页：静默结束，交给新的 load 任务接管。
        } catch {
            if isStale() { return }
            self.error = error.localizedDescription
            loading = false
            RDHaptics.shared.playPlaybackError()
            AppLog.write("PLAYER failed ep=\(ep.index) vid=\(ep.vid) error=\(error.localizedDescription)")
        }
    }

    private func formatEngineFailure(engine: RDPlaybackEngine, detail: String) -> String {
        switch engine {
        case .avPlayer:
            return detail.isEmpty ? "AVPlayer 失败" : "AVPlayer 失败(\(detail))"
        case .vlc:
            if detail == "stopped" || detail == "error" || detail == "ended" {
                return "VLC \(detail)"
            }
            return "VLC 失败(\(detail))"
        }
    }

    private enum StartupOutcome {
        case started
        case failed(String)
    }

    private func waitForPlaybackStart(engine: RDPlaybackEngine, timeout: TimeInterval, loadID: UUID) async -> StartupOutcome {
        let deadline = Date().addingTimeInterval(timeout)
        var stoppedSince: Date?

        while Date() < deadline {
            if Task.isCancelled || activeLoadID != loadID { return .failed("cancelled") }

            switch engine {
            case .avPlayer:
                if controller.av.isItemFailed || controller.av.stateText == "error" {
                    return .failed(controller.av.shortFailure)
                }
                if controller.stateText == "ended" {
                    return (controller.av.hasTimelineAdvanced || controller.time >= 1.0)
                        ? .started
                        : .failed("立即 ended")
                }
                if controller.av.isItemReady && (controller.av.hasVideoOut || controller.av.hasTimelineAdvanced) {
                    return .started
                }
            case .vlc:
                if controller.vlc.hasVideoOut && controller.time > 0.05 { return .started }
                if controller.time > 1.0 { return .started }
                if controller.stateText == "error" { return .failed("error") }
                if controller.stateText == "ended" {
                    return controller.time >= 1.0 ? .started : .failed("ended")
                }
                if controller.stateText == "stopped" {
                    if let stoppedSince, Date().timeIntervalSince(stoppedSince) > 1.2 { return .failed("stopped") }
                    if stoppedSince == nil { stoppedSince = Date() }
                } else {
                    stoppedSince = nil
                }
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if Task.isCancelled || activeLoadID != loadID { return .failed("cancelled") }
        switch engine {
        case .avPlayer:
            return .failed("8s 未起播·\(controller.av.diagnosticSummary)")
        case .vlc:
            return .failed("8s 未起播·state=\(controller.vlc.stateText) t=\(String(format: "%.1f", controller.time)) vout=\(controller.vlc.hasVideoOut ? 1 : 0)")
        }
    }

    private func format(_ seconds: Double) -> String {
        HistoryEntry.formatTime(seconds)
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
