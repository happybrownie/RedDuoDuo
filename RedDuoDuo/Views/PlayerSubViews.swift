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
                    .frame(width: 118, height: 172)
                    .rdGemPosterChrome()

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

// MARK: - A6: 屏内浮层选集抽屉（自动定位当前集）

struct PlayerEpisodeDrawer: View {
    let series: Series
    let episodes: [Episode]
    let currentIndex: Int
    let isLandscapeOrWide: Bool
    let onSelect: (Int) -> Void
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
        isLandscapeOrWide: Bool,
        onSelect: @escaping (Int) -> Void,
        onCacheNext10: @escaping () -> Void,
        onCacheAll: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.series = series
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.isLandscapeOrWide = isLandscapeOrWide
        self.onSelect = onSelect
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
            // 标题栏
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("选集 · \(series.title)")
                        .font(RD.Font.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("当前第 \(episodes[safe: currentIndex]?.index ?? 1) 集 / 共 \(episodes.count) 集 · 已缓存 \(offline.cachedCount(for: series.id, episodes: episodes)) 集")
                        .font(.caption2)
                        .foregroundStyle(RD.Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }

            // 离线追剧快捷入口
            HStack(spacing: 8) {
                Button(action: onCacheNext10) {
                    Label("存后10集", systemImage: "arrow.down.circle.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 11, verticalPadding: 6))

                Button(action: onCacheAll) {
                    Label("存全集", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 11, verticalPadding: 6))

                Spacer(minLength: 0)
                if let batchTitle = offline.activeBatchTitle {
                    Text("\(offline.batchDoneCount)/\(offline.batchTotalCount) · \(batchTitle)")
                        .font(.caption2)
                        .foregroundStyle(RD.Palette.gemRim)
                        .lineLimit(1)
                }
            }

            // 分段胶囊
            if rangeCount > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<rangeCount, id: \.self) { i in
                            let start = i * rangeSize + 1
                            let end = min((i + 1) * rangeSize, episodes.count)
                            Button {
                                RDHaptics.shared.playRangeTabSwitch()
                                withAnimation(RD.Motion.snappy) { rangeIndex = i }
                            } label: {
                                Text("\(start)-\(end)")
                                    .font(RD.Font.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(i == safeRange ? .white : RD.Palette.textSecondary)
                                    .background {
                                        if i == safeRange {
                                            RDGemFacetSurface(shape: Capsule(), shadowRadius: 5, borderWidth: 0.8)
                                        } else {
                                            Capsule()
                                                .fill(RD.Palette.surfaceRaised)
                                                .overlay(Capsule().strokeBorder(RD.Palette.hairline, lineWidth: 0.6))
                                        }
                                    }
                            }
                            .buttonStyle(RDPosterButtonStyle())
                        }
                    }
                }
            }

            // 选集网格 + 自动定位当前集
            ScrollViewReader { proxy in
                ScrollView {
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: isLandscapeOrWide ? 4 : 5)
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(visible) { ep in
                            let epIdx = episodes.firstIndex(where: { $0.vid == ep.vid }) ?? 0
                            let isCurrent = epIdx == currentIndex
                            let watched = prefs.isEpisodeWatched(seriesID: series.id, episodeIndex: ep.index)
                            let cached = offline.isCached(ep.vid)
                            let preloaded = preloader.isPrepared(ep.vid)

                            Button {
                                RDHaptics.shared.playEpisodeCellTap(watched: watched || isCurrent)
                                onSelect(epIdx)
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    VStack(spacing: 2) {
                                        Text("\(ep.index)")
                                            .font(RD.Font.headline.monospacedDigit())
                                            .foregroundStyle(isCurrent ? .white : (watched ? RD.Palette.textSecondary : .white))
                                        if isCurrent {
                                            Text("播放中")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white.opacity(0.92))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background {
                                        if isCurrent {
                                            RDGemFacetSurface(shape: RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous), shadowRadius: 6, borderWidth: 1.0)
                                        } else {
                                            RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                                                .fill(RD.Palette.surfaceRaised)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                                                        .strokeBorder(RD.Palette.hairline, lineWidth: 0.6)
                                                )
                                        }
                                    }

                                    if cached || preloaded {
                                        Image(systemName: cached ? "arrow.down.circle.fill" : "bolt.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(cached ? RD.Palette.pearl : RD.Palette.platinum)
                                            .padding(4)
                                    }
                                }
                            }
                            .buttonStyle(RDPosterButtonStyle())
                            .id(ep.vid)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    syncRangeToCurrent()
                    if let cur = episodes[safe: currentIndex] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(RD.Motion.snappy) {
                                proxy.scrollTo(cur.vid, anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: currentIndex) { _, newIdx in
                    syncRangeToCurrent(index: newIdx)
                    if let cur = episodes[safe: newIdx] {
                        withAnimation(RD.Motion.snappy) {
                            proxy.scrollTo(cur.vid, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RD.Radius.sheet, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: RD.Radius.sheet, style: .continuous)
                .fill(RD.Palette.background.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RD.Radius.sheet, style: .continuous)
                .strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.9)
        )
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
    }

    private func syncRangeToCurrent(index: Int? = nil) {
        let idx = index ?? currentIndex
        rangeIndex = max(0, min(rangeCount - 1, idx / rangeSize))
    }
}

// MARK: - A2: Duo 半折「追剧台」常驻控制面板（严格避开折痕）

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
            RD.Palette.background

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        headerRow
                        transportAndProgressCard
                        quickControlPills
                        episodeGridSection(proxy: proxy)
                    }
                    .padding(14)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            RDBadgePill(text: isPhysicalFold ? "Duo 半折追剧台" : "双屏追剧台", accent: true)
            Text(series.title)
                .font(RD.Font.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let nextEp = episodes[safe: currentIndex + 1], preloader.isPrepared(nextEp.vid) {
                RDStatusBadgePill(text: "下集已备好", kind: .offline)
            }
            if let onExitWorkbench {
                Button(action: onExitWorkbench) {
                    Text("收起台")
                        .font(.caption2.bold())
                        .foregroundStyle(RD.Palette.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RD.Palette.surfaceRaised, in: Capsule())
                }
            }
        }
    }

    private var transportAndProgressCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onPrev) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 34, height: 34)
                }
                .disabled(currentIndex <= 0)
                .opacity(currentIndex <= 0 ? 0.4 : 1)

                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 36)
                        .background {
                            RDGemFacetSurface(
                                shape: RoundedRectangle(cornerRadius: 9, style: .continuous),
                                shadowRadius: 6,
                                borderWidth: 0.9
                            )
                        }
                }

                Button(action: onNext) {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 34, height: 34)
                }
                .disabled(currentIndex >= episodes.count - 1)
                .opacity(currentIndex >= episodes.count - 1 ? 0.4 : 1)

                let maxDur = max(duration, 1)
                Slider(
                    value: Binding(
                        get: { min(max(currentTime, 0), maxDur) },
                        set: { onSeek($0) }
                    ),
                    in: 0...maxDur,
                    onEditingChanged: { editing in
                        if editing {
                            RDHaptics.shared.playSliderGrab()
                        } else {
                            RDHaptics.shared.playSliderRelease()
                        }
                    }
                )
                .tint(RD.Palette.accent)

                Text("\(HistoryEntry.formatTime(currentTime))/\(HistoryEntry.formatTime(duration))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(RD.Palette.textSecondary)
            }
            .foregroundStyle(.white)

            // 倍速挡位 + 一键跳片头/跳片尾
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RDPlaybackPrefs.supportedRates, id: \.self) { r in
                        let selected = abs(currentRate - r) < 0.01
                        Button {
                            onSelectRate(r)
                        } label: {
                            Text(RDPlaybackPrefs.rateLabel(r))
                                .font(.caption2.monospacedDigit().bold())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .foregroundStyle(selected ? .white : RD.Palette.textSecondary)
                                .background {
                                    if selected {
                                        RDGemFacetSurface(shape: Capsule(), shadowRadius: 5, borderWidth: 0.8)
                                    } else {
                                        Capsule()
                                            .fill(RD.Palette.surfaceRaised)
                                            .overlay(Capsule().strokeBorder(RD.Palette.hairline, lineWidth: 0.6))
                                    }
                                }
                        }
                        .buttonStyle(RDPosterButtonStyle())
                    }

                    Divider().frame(height: 16).background(RD.Palette.hairline)

                    Button(action: onSkipIntro) {
                        Label("跳片头", systemImage: "forward.frame.fill")
                            .font(.caption2.bold())
                    }
                    .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 9, verticalPadding: 5))

                    Button(action: onSkipOutro) {
                        Label("跳片尾", systemImage: "forward.end.alt.fill")
                            .font(.caption2.bold())
                    }
                    .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 9, verticalPadding: 5))
                }
            }
        }
        .padding(10)
        .rdGemCard()
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
                            .font(.caption2.bold())
                    }
                    .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 10, verticalPadding: 6))
                }

                Button(action: onCacheNext10) {
                    Label("缓存后10集", systemImage: "arrow.down.circle")
                        .font(.caption2.bold())
                }
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 10, verticalPadding: 6))
            }
        }
    }

    private func toggleChip(title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.bold())
                .foregroundStyle(isOn ? .white : RD.Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if isOn {
                        RDGemFacetSurface(shape: Capsule(), shadowRadius: 5, borderWidth: 0.8)
                    } else {
                        Capsule()
                            .fill(RD.Palette.surfaceRaised)
                            .overlay(Capsule().strokeBorder(RD.Palette.hairline, lineWidth: 0.7))
                    }
                }
        }
        .buttonStyle(RDPosterButtonStyle())
    }

    private func episodeGridSection(proxy: ScrollViewProxy) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 7), count: isBookPosture ? 4 : 6)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("常驻选集（第 \(episodes[safe: currentIndex]?.index ?? 1)/\(episodes.count) 集）")
                    .font(RD.Font.caption.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }

            LazyVGrid(columns: cols, spacing: 7) {
                ForEach(Array(episodes.enumerated()), id: \.element.vid) { idx, ep in
                    let isCur = idx == currentIndex
                    let watched = prefs.isEpisodeWatched(seriesID: series.id, episodeIndex: ep.index)
                    let cached = offline.isCached(ep.vid)
                    Button {
                        RDHaptics.shared.playEpisodeCellTap(watched: watched || isCur)
                        onSelectEpisode(idx)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Text("\(ep.index)")
                                .font(RD.Font.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(isCur ? .white : (watched ? RD.Palette.textSecondary : .white))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background {
                                    if isCur {
                                        RDGemFacetSurface(
                                            shape: RoundedRectangle(cornerRadius: 7, style: .continuous),
                                            shadowRadius: 5,
                                            borderWidth: 0.8
                                        )
                                    } else {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(RD.Palette.surfaceRaised)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .strokeBorder(RD.Palette.hairline, lineWidth: 0.6)
                                            )
                                    }
                                }
                            if cached {
                                Circle()
                                    .fill(RD.Palette.pearl)
                                    .frame(width: 5, height: 5)
                                    .padding(4)
                            }
                        }
                    }
                    .buttonStyle(RDPosterButtonStyle())
                    .id(ep.vid)
                }
            }
            .onAppear {
                if let cur = episodes[safe: currentIndex] {
                    proxy.scrollTo(cur.vid, anchor: .center)
                }
            }
            .onChange(of: currentIndex) { _, newIdx in
                if let cur = episodes[safe: newIdx] {
                    withAnimation(RD.Motion.snappy) {
                        proxy.scrollTo(cur.vid, anchor: .center)
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
                    .font(RD.Font.body)
                    .foregroundStyle(RD.Palette.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recommendations.prefix(8)) { rec in
                            Button {
                                RDHaptics.shared.playResumeCardTap()
                                onPickSeries(rec)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Color.clear
                                        .frame(width: 108, height: 156)
                                        .overlay { RemoteCover(url: rec.cover) }
                                        .overlay(alignment: .bottomTrailing) {
                                            Text("全\(rec.episodeCount)集")
                                                .font(RD.Font.micro)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                                                .padding(5)
                                        }
                                        .rdGemPosterChrome()
                                    Text(rec.title)
                                        .font(RD.Font.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    if !rec.tags.isEmpty {
                                        Text(rec.tags.prefix(2).joined(separator: "·"))
                                            .font(.caption2)
                                            .foregroundStyle(RD.Palette.gemRim)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 108)
                            }
                            .buttonStyle(RDPosterButtonStyle())
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onReplay) {
                    Label("重播本集", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: false, horizontalPadding: 14, verticalPadding: 10))

                if let first = recommendations.first {
                    Button {
                        RDHaptics.shared.playGemButtonRelease()
                        onPickSeries(first)
                    } label: {
                        Label("接档：\(first.title)", systemImage: "play.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(RDGemPrimaryButtonStyle(minHeight: 40, cornerRadius: 9))
                } else {
                    Button("返回剧集", action: onClose)
                        .buttonStyle(RDGemPrimaryButtonStyle(minHeight: 40, cornerRadius: 9))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 480)
        .rdGemCard(radius: RD.Radius.sheet, fill: RD.Palette.surface.opacity(0.95), glow: true)
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
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 58))
                            .foregroundStyle(.white)
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
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 18, verticalPadding: 9))

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
