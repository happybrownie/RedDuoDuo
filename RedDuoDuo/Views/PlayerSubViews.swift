import SwiftUI

// MARK: - A5: 上下滑跟手切集相邻集预览卡

struct SwipeAdjacentPreviewCard: View {
    let episode: Episode
    let isNext: Bool
    let crossedThreshold: Bool
    let fallbackCover: String

    var body: some View {
        ZStack {
            RD.Palette.background
            RemoteCover(url: episode.cover.isEmpty ? fallbackCover : episode.cover, thumbnailMaxPixel: 800)
                .opacity(0.38)
                .blur(radius: 12)
            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                RemoteCover(url: episode.cover.isEmpty ? fallbackCover : episode.cover, thumbnailMaxPixel: 600)
                    .frame(width: 118, height: 157)
                    .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.poster, style: .continuous))
                    .shadow(color: RDAlbum.C.posterShadow, radius: 20, x: 0, y: 10)

                RDBadgePill(text: isNext ? "下一集" : "上一集", accent: crossedThreshold)

                Text("第 \(episode.index) 集")
                    .font(RD.Font.title)
                    .foregroundStyle(.white)
                    .rdMediaShadow()

                if !episode.title.isEmpty && episode.title != "第\(episode.index)集" {
                    Text(episode.title)
                        .font(RD.Font.body)
                        .foregroundStyle(RD.Palette.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Image(systemName: crossedThreshold ? "checkmark.circle.fill" : (isNext ? "arrow.up.circle" : "arrow.down.circle"))
                    Text(crossedThreshold ? "松手立即切换" : (isNext ? "继续上滑切下一集" : "继续下滑回上一集"))
                }
                .font(RD.Font.caption.weight(.bold))
                .foregroundStyle(crossedThreshold ? RD.Palette.gemRim : RD.Palette.textSecondary)
                .padding(.top, 4)
            }
            .padding(24)
        }
    }
}

// MARK: - A6 / 1.4.8: 屏内浮层选集抽屉（玻璃浮板 + 横滑胶囊带 + 倍速/离线/听剧/画中画胶囊）

struct PlayerEpisodeDrawer: View {
    let series: Series
    let episodes: [Episode]
    let currentIndex: Int
    let currentRate: Float
    let isLandscapeOrWide: Bool
    let isAudioMode: Bool
    let isPiPPossible: Bool
    let onSelect: (Int) -> Void
    let onSelectRate: (Float) -> Void
    let onToggleAudioMode: () -> Void
    let onTogglePiP: () -> Void
    let onCacheNext10: () -> Void
    let onCacheAll: () -> Void
    let onClose: () -> Void

    @ObservedObject private var prefs = RDPlaybackPrefs.shared
    @ObservedObject private var offline = OfflineCacheManager.shared
    @ObservedObject private var preloader = EpisodePreloader.shared

    @State private var rangeIndex: Int
    private let rangeSize = 30

    init(
        series: Series,
        episodes: [Episode],
        currentIndex: Int,
        currentRate: Float,
        isLandscapeOrWide: Bool,
        isAudioMode: Bool,
        isPiPPossible: Bool,
        onSelect: @escaping (Int) -> Void,
        onSelectRate: @escaping (Float) -> Void,
        onToggleAudioMode: @escaping () -> Void,
        onTogglePiP: @escaping () -> Void,
        onCacheNext10: @escaping () -> Void,
        onCacheAll: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.series = series
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.currentRate = currentRate
        self.isLandscapeOrWide = isLandscapeOrWide
        self.isAudioMode = isAudioMode
        self.isPiPPossible = isPiPPossible
        self.onSelect = onSelect
        self.onSelectRate = onSelectRate
        self.onToggleAudioMode = onToggleAudioMode
        self.onTogglePiP = onTogglePiP
        self.onCacheNext10 = onCacheNext10
        self.onCacheAll = onCacheAll
        self.onClose = onClose
        let totalRanges = max(1, (episodes.count + 29) / 30)
        _rangeIndex = State(initialValue: max(0, min(totalRanges - 1, currentIndex / 30)))
    }

    private var rangeCount: Int {
        max(1, (episodes.count + rangeSize - 1) / rangeSize)
    }

    var body: some View {
        let safeRange = min(max(0, rangeIndex), rangeCount - 1)
        let lo = safeRange * rangeSize
        let hi = min(lo + rangeSize, episodes.count)
        let visible = lo < hi ? Array(episodes[lo..<hi]) : []

        VStack(alignment: .leading, spacing: 12) {
            headerRow

            quickCapsules

            rateCapsules

            if rangeCount > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<rangeCount, id: \.self) { i in
                            let start = i * rangeSize + 1
                            let end = min((i + 1) * rangeSize, episodes.count)
                            Button {
                                RDHaptics.shared.playRangeTabSwitch()
                                withAnimation(RDAlbum.Motion.rearrange) { rangeIndex = i }
                            } label: {
                                Text("\(start)-\(end)")
                                    .font(RDAlbum.Font.rounded(12, .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(i == safeRange ? RDAlbum.C.inverse : .white.opacity(0.82))
                                    .padding(.horizontal, 12)
                                    .frame(height: 30)
                                    .background {
                                        if i == safeRange {
                                            Capsule(style: .continuous).fill(Color.white)
                                        } else {
                                            Capsule(style: .continuous).fill(Color.white.opacity(0.10))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // 选集横滑胶囊带（禁用方格选集）
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(visible) { ep in
                            let epIdx = episodes.firstIndex(where: { $0.vid == ep.vid }) ?? 0
                            let isCurrent = epIdx == currentIndex
                            let watched = prefs.isEpisodeWatched(seriesID: series.id, episodeIndex: ep.index)
                            let state: RDAlbumEpisodeState = isCurrent ? .current : (watched ? .watched : .unwatched)
                            RDAlbumEpisodeCapsule(
                                index: ep.index,
                                state: state,
                                cached: offline.isCached(ep.vid) || preloader.isPrepared(ep.vid)
                            ) {
                                RDHaptics.shared.playEpisodeCellTap(watched: watched || isCurrent)
                                onSelect(epIdx)
                            }
                            .id(ep.vid)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    syncRangeToCurrent()
                    if let cur = episodes[safe: currentIndex] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            proxy.scrollTo(cur.vid, anchor: .center)
                        }
                    }
                }
                .onChange(of: currentIndex) { _, newIdx in
                    syncRangeToCurrent(index: newIdx)
                    if let cur = episodes[safe: newIdx] {
                        withAnimation(RDAlbum.Motion.rearrange) {
                            proxy.scrollTo(cur.vid, anchor: .center)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous)
                .fill(Color(rdHex: 0x15161D, opacity: 0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.5), radius: 28, x: 0, y: 12)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("选集 · \(series.title)")
                    .font(RDAlbum.Font.rounded(17, .semibold))
                    .foregroundStyle(RDAlbum.C.mediaPrimary)
                    .lineLimit(1)
                Text("当前第 \(episodes[safe: currentIndex]?.index ?? 1) 集 / 共 \(episodes.count) 集 · 已缓存 \(offline.cachedCount(for: series.id, episodes: episodes)) 集")
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.mediaSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RDAlbum.C.mediaPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var quickCapsules: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: onCacheNext10) {
                    Label("存后10集", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))

                Button(action: onCacheAll) {
                    Label("存全集", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))

                Button(action: onToggleAudioMode) {
                    Label(isAudioMode ? "听剧中" : "听剧", systemImage: isAudioMode ? "headphones.circle.fill" : "headphones")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))

                if isPiPPossible {
                    Button(action: onTogglePiP) {
                        Label("画中画", systemImage: "pip.enter")
                    }
                    .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))
                }

                if let batchTitle = offline.activeBatchTitle {
                    Text("\(offline.batchDoneCount)/\(offline.batchTotalCount) · \(batchTitle)")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RD.Palette.gemRim)
                        .lineLimit(1)
                }
            }
        }
    }

    private var rateCapsules: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("倍速")
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.mediaSecondary)
                ForEach(RDPlaybackPrefs.supportedRates, id: \.self) { rate in
                    let selected = abs(currentRate - rate) < 0.01
                    Button {
                        onSelectRate(rate)
                    } label: {
                        Text(RDPlaybackPrefs.rateLabel(rate))
                            .font(RDAlbum.Font.rounded(12, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(selected ? RDAlbum.C.inverse : .white.opacity(0.84))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background {
                                if selected {
                                    Capsule(style: .continuous).fill(Color.white)
                                } else {
                                    Capsule(style: .continuous).fill(Color.white.opacity(0.10))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func syncRangeToCurrent(index: Int? = nil) {
        let idx = index ?? currentIndex
        rangeIndex = max(0, min(rangeCount - 1, idx / rangeSize))
    }
}

// MARK: - A2 / 1.4.8: Duo 半折「追剧台」常驻控制面板（顶大丸 + 常驻选集/倍速/离线胶囊）

struct DuoBingeWorkbench: View {
    let series: Series
    let episodes: [Episode]
    let currentIndex: Int
    let isBookPosture: Bool
    let isPhysicalFold: Bool
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
    let currentRate: Float
    let isAudioMode: Bool
    let isPiPPossible: Bool
    let onPlayPause: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void
    let onSelectEpisode: (Int) -> Void
    let onSelectRate: (Float) -> Void
    let onSkipIntro: () -> Void
    let onSkipOutro: () -> Void
    let onToggleAudioMode: () -> Void
    let onTogglePiP: () -> Void
    let onCacheNext10: () -> Void
    let onExitWorkbench: (() -> Void)?

    @ObservedObject private var prefs = RDPlaybackPrefs.shared
    @ObservedObject private var offline = OfflineCacheManager.shared
    @ObservedObject private var preloader = EpisodePreloader.shared

    var body: some View {
        ZStack {
            Color(rdHex: 0x0C0C0F)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    headerRow
                    bigTransportPill
                    quickControlPills
                    nextEpisodeCard
                    rateRow
                    episodeBand
                }
                .padding(14)
                .padding(.bottom, 8)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            RDBadgePill(text: isPhysicalFold ? "Duo 半折追剧台" : "追剧台", accent: true)
            Text(series.title)
                .font(RDAlbum.Font.rounded(15, .semibold))
                .foregroundStyle(RDAlbum.C.mediaPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let nextEp = episodes[safe: currentIndex + 1], preloader.isPrepared(nextEp.vid) {
                RDStatusBadgePill(text: "下集已备好", kind: .offline)
            }
            if let onExitWorkbench {
                Button(action: onExitWorkbench) {
                    Text("全屏")
                        .font(RDAlbum.Font.rounded(11, .semibold))
                        .foregroundStyle(RDAlbum.C.mediaSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 追剧台顶大丸：高 64、宽 -40。
    private var bigTransportPill: some View {
        HStack(spacing: 12) {
            Button(action: onPrev) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(currentIndex <= 0)
            .opacity(currentIndex <= 0 ? 0.38 : 1)

            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(RDAlbum.C.inverse)
                        .offset(x: isPlaying ? 0 : 1)
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: onNext) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= episodes.count - 1)
            .opacity(currentIndex >= episodes.count - 1 ? 0.38 : 1)

            VStack(alignment: .leading, spacing: 1) {
                RDAlbumScrubber(
                    time: currentTime,
                    duration: max(duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            RDHaptics.shared.playSliderGrab()
                        } else {
                            RDHaptics.shared.playSliderRelease()
                        }
                    },
                    onSeek: { onSeek($0) }
                )
                HStack(spacing: 4) {
                    Text("\(HistoryEntry.formatTime(currentTime))")
                        .foregroundStyle(RDAlbum.C.mediaPrimary)
                    Spacer(minLength: 2)
                    if abs(currentRate - 1.0) > 0.01 {
                        Text(RDPlaybackPrefs.rateLabel(currentRate))
                            .foregroundStyle(RD.Palette.gemRim)
                        Spacer(minLength: 2)
                    }
                    Text("\(HistoryEntry.formatTime(duration))")
                        .foregroundStyle(RDAlbum.C.mediaSecondary)
                }
                .font(RDAlbum.Font.timecode.monospacedDigit())
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .background(Color(rdHex: 0x14151B, opacity: 0.68), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.5), radius: 28, x: 0, y: 12)
        .padding(.horizontal, 6)
    }

    private var quickControlPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                toggleChip(
                    title: "自动连播",
                    icon: "play.square.stack.fill",
                    isOn: prefs.autoPlayNextEnabled
                ) {
                    prefs.autoPlayNextEnabled.toggle()
                    RDHaptics.shared.playChipSelect()
                }

                toggleChip(
                    title: "跳过片头尾",
                    icon: "scissors",
                    isOn: prefs.skipIntroOutroEnabled
                ) {
                    prefs.skipIntroOutroEnabled.toggle()
                    RDHaptics.shared.playChipSelect()
                }

                toggleChip(
                    title: isAudioMode ? "音频听剧中" : "息屏听剧",
                    icon: isAudioMode ? "headphones.circle.fill" : "headphones",
                    isOn: isAudioMode,
                    action: onToggleAudioMode
                )

                if isPiPPossible {
                    Button(action: onTogglePiP) {
                        Label("小窗", systemImage: "pip.enter")
                    }
                    .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))
                }

                Button(action: onCacheNext10) {
                    Label("缓存后10集", systemImage: "arrow.down.circle")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))

                Button(action: onSkipIntro) {
                    Label("跳片头", systemImage: "forward.frame.fill")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))

                Button(action: onSkipOutro) {
                    Label("跳片尾", systemImage: "forward.end.alt.fill")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 12, mediaOverlay: true))
            }
        }
    }

    /// 接下来连播卡（大屏右板 / 半折追剧台常驻）。
    @ViewBuilder
    private var nextEpisodeCard: some View {
        if let next = episodes[safe: currentIndex + 1] {
            Button {
                RDHaptics.shared.playUpNextPlayNow()
                onSelectEpisode(currentIndex + 1)
            } label: {
                HStack(spacing: 12) {
                    RemoteCover(url: next.cover.isEmpty ? series.cover : next.cover, thumbnailMaxPixel: 240)
                        .frame(width: 54, height: 72)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("接下来")
                            .font(RDAlbum.Font.rounded(10, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(RDAlbum.C.mediaSecondary)
                        Text("第 \(next.index) 集")
                            .font(RDAlbum.Font.plateName)
                            .foregroundStyle(RDAlbum.C.mediaPrimary)
                            .lineLimit(1)
                        Text(preloader.isPrepared(next.vid) ? "已备好 · 点播即看" : "点击直接播放")
                            .font(RDAlbum.Font.plateSub)
                            .foregroundStyle(RDAlbum.C.mediaTertiary)
                    }
                    Spacer(minLength: 0)
                    RDAlbumPlayCircle(size: 34)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous))
                .background(Color(rdHex: 0x14151B, opacity: 0.55), in: RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var rateRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("倍速")
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.mediaSecondary)
                ForEach(RDPlaybackPrefs.supportedRates, id: \.self) { r in
                    let selected = abs(currentRate - r) < 0.01
                    Button {
                        onSelectRate(r)
                    } label: {
                        Text(RDPlaybackPrefs.rateLabel(r))
                            .font(RDAlbum.Font.rounded(12, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(selected ? RDAlbum.C.inverse : .white.opacity(0.84))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background {
                                if selected {
                                    Capsule(style: .continuous).fill(Color.white)
                                } else {
                                    Capsule(style: .continuous).fill(Color.white.opacity(0.10))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleChip(title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(RDAlbum.Font.rounded(11, .semibold))
                .foregroundStyle(isOn ? RDAlbum.C.inverse : .white.opacity(0.84))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background {
                    if isOn {
                        Capsule(style: .continuous).fill(Color.white)
                    } else {
                        Capsule(style: .continuous).fill(Color.white.opacity(0.10))
                            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var episodeBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常驻选集 · 第 \(episodes[safe: currentIndex]?.index ?? 1)/\(episodes.count) 集")
                .font(RDAlbum.Font.rounded(12, .semibold))
                .foregroundStyle(RDAlbum.C.mediaSecondary)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(episodes.enumerated()), id: \.element.vid) { idx, ep in
                            let isCur = idx == currentIndex
                            let watched = prefs.isEpisodeWatched(seriesID: series.id, episodeIndex: ep.index)
                            let state: RDAlbumEpisodeState = isCur ? .current : (watched ? .watched : .unwatched)
                            RDAlbumEpisodeCapsule(
                                index: ep.index,
                                state: state,
                                cached: offline.isCached(ep.vid)
                            ) {
                                RDHaptics.shared.playEpisodeCellTap(watched: watched || isCur)
                                onSelectEpisode(idx)
                            }
                            .id(ep.vid)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    if let cur = episodes[safe: currentIndex] {
                        proxy.scrollTo(cur.vid, anchor: .center)
                    }
                }
                .onChange(of: currentIndex) { _, newIdx in
                    if let cur = episodes[safe: newIdx] {
                        withAnimation(RDAlbum.Motion.rearrange) {
                            proxy.scrollTo(cur.vid, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - A10: 大结局「同款接档」推荐浮层

struct FinaleRelatedOverlay: View {
    let series: Series
    let recommendations: [Series]
    let onPickSeries: (Series) -> Void
    let onReplay: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    RDBadgePill(text: "全剧终 · 同款接档", accent: true)
                    Text("《\(series.title)》已播完")
                        .font(RD.Font.title)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
            }

            if recommendations.isEmpty {
                Text("暂无同题材推荐，可重播或返回首页探索更多好剧")
                    .font(RDAlbum.Font.body)
                    .foregroundStyle(RDAlbum.C.mediaSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recommendations.prefix(8)) { rec in
                            Button {
                                RDHaptics.shared.playResumeCardTap()
                                onPickSeries(rec)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    RemoteCover(url: rec.cover)
                                        .frame(width: 108, height: 144)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.poster, style: .continuous))
                                        .overlay(alignment: .bottomTrailing) {
                                            Text("全\(rec.episodeCount)集")
                                                .font(RDAlbum.Font.plateSub)
                                                .foregroundStyle(RDAlbum.C.mediaPrimary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.black.opacity(0.60), in: Capsule())
                                                .padding(5)
                                        }
                                        .shadow(color: RDAlbum.C.posterShadow, radius: 16, y: 8)
                                    Text(rec.title)
                                        .font(RDAlbum.Font.plateName)
                                        .foregroundStyle(RDAlbum.C.mediaPrimary)
                                        .lineLimit(1)
                                    if !rec.tags.isEmpty {
                                        Text(rec.tags.prefix(2).joined(separator: "·"))
                                            .font(RDAlbum.Font.plateSub)
                                            .foregroundStyle(RD.Palette.gemRim)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 108)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onReplay) {
                    Label("重播本集", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 42, horizontalPadding: 16, mediaOverlay: true))

                if let first = recommendations.first {
                    Button {
                        RDHaptics.shared.playGemButtonRelease()
                        onPickSeries(first)
                    } label: {
                        Label("接档：\(first.title)", systemImage: "play.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(RDAlbumPrimaryPillStyle(height: 42, horizontalPadding: 18))
                } else {
                    Button("返回剧集", action: onClose)
                        .buttonStyle(RDAlbumPrimaryPillStyle(height: 42, horizontalPadding: 18))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous))
        .background(Color(rdHex: 0x15161D, opacity: 0.92), in: RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.5), radius: 28, x: 0, y: 12)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - A8: 息屏听剧（音频模式封面交互面板）

struct AudioModeCoverOverlay: View {
    let series: Series
    let episode: Episode?
    let totalCount: Int
    let isPlaying: Bool
    let time: Double
    let duration: Double
    let onTogglePlay: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let onExitAudioMode: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            RD.Palette.background
            RemoteCover(url: series.cover, thumbnailMaxPixel: 600)
                .opacity(0.24)
                .blur(radius: 26)
            LinearGradient(
                colors: [.black.opacity(0.55), RD.Palette.gemAbyss.opacity(0.45), .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 18) {
                Spacer(minLength: 20)

                ZStack {
                    Circle()
                        .stroke(RD.Palette.gemCore.opacity(pulse ? 0.14 : 0.46), lineWidth: 1.5)
                        .frame(width: pulse ? 210 : 178, height: pulse ? 210 : 178)
                        .animation(isPlaying ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : .default, value: pulse)

                    RemoteCover(url: series.cover, thumbnailMaxPixel: 600)
                        .frame(width: 152, height: 152)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(RD.Gem.anchorBorderGradient, lineWidth: 1.5))
                        .shadow(color: RD.Palette.gemCore.opacity(0.40), radius: 14)
                }

                VStack(spacing: 6) {
                    RDBadgePill(text: "息屏听剧中 · 支持锁屏后台连播", accent: true)
                    Text(series.title)
                        .font(RD.Font.title)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let episode {
                        Text("第 \(episode.index)/\(totalCount) 集 · \(HistoryEntry.formatTime(time)) / \(HistoryEntry.formatTime(duration))")
                            .font(RD.Font.caption.monospacedDigit())
                            .foregroundStyle(RD.Palette.textSecondary)
                    }
                }

                HStack(spacing: 28) {
                    Button(action: onPrev) {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    Button(action: onTogglePlay) {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 58, height: 58)
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(RDAlbum.C.inverse)
                                .offset(x: isPlaying ? 0 : 1)
                        }
                    }
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                }
                .foregroundStyle(.white)

                Button(action: onExitAudioMode) {
                    Label("恢复看画面", systemImage: "tv.fill")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 40, horizontalPadding: 18, mediaOverlay: true))

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .onAppear { pulse = isPlaying }
        .onChange(of: isPlaying) { _, playing in pulse = playing }
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
