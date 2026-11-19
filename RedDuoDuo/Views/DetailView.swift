import SwiftUI

struct DetailView: View {
    let initial: Series
    @EnvironmentObject private var history: WatchHistory
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var offline = OfflineCacheManager.shared
    @ObservedObject private var prefs = RDPlaybackPrefs.shared
    @ObservedObject private var catalog = CatalogCache.shared

    @State private var series: Series
    @State private var episodes: [Episode] = []
    @State private var loading = false
    @State private var error: String?
    @State private var expandedIntro = false
    @State private var playing: Episode?
    @State private var isCollected = false
    @State private var collectBusy = false
    @State private var collectBanner: String?
    @State private var rangeIndex = 0
    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets

    private let rangeSize = 30

    init(initial: Series) {
        self.initial = initial
        _series = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            RD.Palette.background.ignoresSafeArea()
            RDSafeAreaProbe(insets: $safeInsets)

            GeometryReader { fullGeo in
                let fullWidth = fullGeo.size.width
                let wide = RD.isWide(fullWidth)
                let horiz = RDLayoutInsets.horizontal(in: fullGeo)
                let leadingPad = horiz.leading
                let trailingPad = horiz.trailing
                let navTopClearance = max(safeInsets.top + 8, 56)

                Group {
                    if wide {
                        // 展开：左 = 全幅海报 + 信息，右 = 选集 + 离线包 + 同款接档
                        let leftWidth = min(max(fullWidth * 0.42, 300), 440)
                        let rightWidth = max(1, fullWidth - leftWidth - RD.Space.gutter - trailingPad)
                        let rightCols = max(5, Int((rightWidth + RD.Space.sm) / (60 + RD.Space.sm)))
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: RD.Space.lg) {
                                    artworkHeader(width: leftWidth, wide: true, leadingPad: leadingPad, trailingPad: RD.Space.gutter)
                                    infoBlock(leadingPad: leadingPad, trailingPad: RD.Space.gutter)
                                }
                                .padding(.bottom, max(RD.Space.xl, safeInsets.bottom + RD.Space.md))
                            }
                            .frame(width: leftWidth)

                            ScrollView {
                                VStack(alignment: .leading, spacing: RD.Space.xl) {
                                    episodeSection(columns: rightCols, leadingPad: RD.Space.gutter, trailingPad: trailingPad)
                                    relatedSection(leadingPad: RD.Space.gutter, trailingPad: trailingPad)
                                }
                                .padding(.top, navTopClearance)
                                .padding(.bottom, max(RD.Space.xl, safeInsets.bottom + RD.Space.md))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        // 合上：单列全宽
                        let contentWidth = max(1, fullWidth - leadingPad - trailingPad)
                        let cols = max(5, Int((contentWidth + RD.Space.sm) / (56 + RD.Space.sm)))
                        ScrollView {
                            VStack(alignment: .leading, spacing: RD.Space.lg) {
                                artworkHeader(width: fullWidth, wide: false, leadingPad: leadingPad, trailingPad: trailingPad)
                                infoBlock(leadingPad: leadingPad, trailingPad: trailingPad)
                                episodeSection(columns: cols, leadingPad: leadingPad, trailingPad: trailingPad)
                                relatedSection(leadingPad: leadingPad, trailingPad: trailingPad)
                            }
                            .padding(.bottom, max(RD.Space.xl, safeInsets.bottom + RD.Space.md))
                        }
                    }
                }
                .frame(width: fullWidth, height: fullGeo.size.height)
            }
            .ignoresSafeArea(edges: .top)
        }
        .rdScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            isCollected = FollowStore.shared.isCollected(series.id)
            offline.isOfflineUIVisible = true
        }
        .onDisappear {
            offline.isOfflineUIVisible = false
        }
        .task { await load() }
        .fullScreenCover(item: $playing) { episode in
            let idx = episodes.firstIndex(where: { $0.vid == episode.vid }) ?? 0
            PlayerView(series: series, episodes: episodes, startIndex: idx)
        }
    }

    // MARK: 海报 / Hero

    private func artworkHeader(width: CGFloat, wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let height = wide ? max(width * 1.25, 400) : min(max(width * 1.12, 380), 520)
        return ZStack(alignment: .bottomLeading) {
            RemoteCover(url: series.cover, thumbnailMaxPixel: nil)
                .frame(width: width, height: height)
                .clipped()

            RDHeroScrim(wide: false)
                .frame(width: width, height: height)

            VStack(alignment: .leading, spacing: RD.Space.sm) {
                HStack(spacing: 6) {
                    if !series.badge.isEmpty {
                        RDBadgePill(text: series.badge, accent: true)
                    }
                    if series.isCompleted {
                        RDStatusBadgePill(text: "已完结", kind: .completed)
                    } else if series.isJustUpdated {
                        RDStatusBadgePill(text: "刚更新", kind: .updated)
                    }
                    if !series.seasonTag.isEmpty {
                        RDBadgePill(text: series.seasonTag, accent: false)
                    }
                    if !series.score.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(RD.Palette.platinum)
                            Text(series.score)
                        }
                        .font(RD.Font.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                Text(series.title.isEmpty ? initial.title : series.title)
                    .accessibilityIdentifier("detail-title")
                    .font(RD.Font.displayLarge)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .rdMediaShadow()

                HStack(spacing: 6) {
                    Text("漫剧")
                    Text("·")
                    Text("共\(max(series.episodeCount, episodes.count))集")
                    Text("·")
                    Text("免费")
                    if !series.heatText.isEmpty {
                        Text("·")
                        Text(series.heatText)
                            .lineLimit(1)
                    }
                }
                .font(RD.Font.caption.weight(.semibold))
                .foregroundStyle(RD.Palette.textSecondary)

                if !series.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(series.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(RD.Font.micro)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(Color.white.opacity(0.10), in: Capsule())
                                    .overlay(Capsule().strokeBorder(RD.Palette.hairline, lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
            .padding(.bottom, RD.Space.md)
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width, height: height)
    }

    // MARK: 信息块（操作 / 离线追剧包 / 状态 / 简介）

    private func infoBlock(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.lg) {
            actionRow

            if let collectBanner {
                Text(collectBanner)
                    .font(.caption.bold())
                    .foregroundStyle(RD.Palette.gemRim)
            }

            if !episodes.isEmpty {
                offlinePackCard
            }

            if let error {
                Text(error)
                    .font(RD.Font.caption)
                    .foregroundStyle(RD.Palette.warning)
                    .lineLimit(3)
            }

            if let entry = history.entry(for: series.id) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(RD.Palette.gemRim)
                    Text("上次看到第 \(entry.lastIndex) 集\(entry.lastPosition >= 1.5 ? " · \(entry.positionText)" : "")")
                        .font(RD.Font.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(RD.Palette.gemVoid.opacity(0.90), in: Capsule())
                .overlay(Capsule().strokeBorder(RD.Gem.anchorBorderGradient, lineWidth: 0.75))
                .accessibilityIdentifier("detail-last-watched")
            }

            introSection
        }
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
    }

    private var actionRow: some View {
        HStack(spacing: RD.Space.md) {
            Button {
                if let entry = history.entry(for: series.id),
                   let ep = episodes.first(where: { $0.vid == entry.lastVid || $0.index == entry.lastIndex }) ?? episodes.first {
                    playing = ep
                } else if let first = episodes.first {
                    playing = first
                }
            } label: {
                Label(continueTitle, systemImage: "play.fill")
                    .lineLimit(1)
            }
            .buttonStyle(RDGemPrimaryButtonStyle(haptics: true))
            .disabled(episodes.isEmpty)
            .accessibilityIdentifier("detail-continue-button")

            Button {
                Task { await toggleCollect() }
            } label: {
                Image(systemName: isCollected ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isCollected ? RD.Palette.gemBright : RD.Palette.textPrimary)
            }
            .buttonStyle(RDIconButtonStyle())
            .disabled(collectBusy)
            .accessibilityLabel(isCollected ? "取消追剧" : "加入追剧")

            Button {
                RDHaptics.shared.playSquareGlassTap()
                Task { await load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(RDIconButtonStyle())
        }
    }

    /// A3: 一键离线追剧包控制卡（后续 10 集 / 全集一键存、看完自动清理）
    private var offlinePackCard: some View {
        let cachedCount = offline.cachedCount(for: series.id, episodes: episodes)
        let currentIdx = resumeEpisodeArrayIndex
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(RD.Palette.gemRim)
                Text("离线追剧包")
                    .font(RD.Font.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("已存 \(cachedCount)/\(episodes.count) 集")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(cachedCount > 0 ? RD.Palette.pearl : RD.Palette.textSecondary)
            }

            if let batchTitle = offline.activeBatchTitle, offline.isDownloadingBatch {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(RD.Palette.gemBright)
                    Text("正在下载：\(batchTitle)（\(offline.batchDoneCount)/\(offline.batchTotalCount)）")
                        .font(.caption2)
                        .foregroundStyle(RD.Palette.gemRim)
                        .lineLimit(1)
                    Spacer()
                    Button("暂停") {
                        RDHaptics.shared.playGlassTap()
                        offline.cancelPendingQueue()
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(RD.Palette.warning)
                }
            }

            HStack(spacing: 8) {
                Button {
                    offline.cacheNext10(series: series, episodes: episodes, fromIndex: currentIdx)
                } label: {
                    Label("存后续 10 集", systemImage: "arrow.down.to.line")
                        .font(.caption.bold())
                }
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 12, verticalPadding: 7))

                Button {
                    offline.cacheAll(series: series, episodes: episodes)
                } label: {
                    Label("一键存全集", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 12, verticalPadding: 7))

                Spacer(minLength: 0)

                if cachedCount > 0 {
                    Button {
                        offline.removeSeries(seriesID: series.id)
                    } label: {
                        Text("清理本剧")
                            .font(.caption2.bold())
                            .foregroundStyle(RD.Palette.textTertiary)
                    }
                }
            }

            Text(prefs.autoCleanWatchedOffline ? "已开启「看完自动清理」，播完后自动释放磁盘空间" : "当前保留已看完离线剧集（可在「我的」开启自动清理）")
                .font(.caption2)
                .foregroundStyle(RD.Palette.textTertiary)
        }
        .padding(12)
        .rdGemCard(radius: RD.Radius.card, fill: RD.Palette.surface)
    }

    private var resumeEpisodeArrayIndex: Int {
        guard let entry = history.entry(for: series.id),
              let idx = episodes.firstIndex(where: { $0.vid == entry.lastVid || $0.index == entry.lastIndex }) else {
            return 0
        }
        return idx
    }

    private var continueTitle: String {
        if let entry = history.entry(for: series.id) {
            let pos = entry.lastPosition >= 1.5 ? " \(entry.positionText)" : ""
            return "继续看 第\(entry.lastIndex)集\(pos)"
        }
        return episodes.isEmpty ? "加载中…" : "从第\(episodes.first?.index ?? 1)集开始"
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            Text(series.intro.isEmpty ? "暂无简介" : series.intro)
                .font(RD.Font.body)
                .foregroundStyle(RD.Palette.textSecondary)
                .lineSpacing(3)
                .lineLimit(expandedIntro ? nil : 3)
                .onTapGesture {
                    let next = !expandedIntro
                    RDHaptics.shared.playIntroToggle(expanded: next)
                    withAnimation(RD.Motion.snappy) { expandedIntro = next }
                }
            if !series.intro.isEmpty {
                Button {
                    let next = !expandedIntro
                    RDHaptics.shared.playIntroToggle(expanded: next)
                    withAnimation(RD.Motion.snappy) { expandedIntro = next }
                } label: {
                    Text(expandedIntro ? "收起简介" : "展开全部")
                        .font(RD.Font.caption.weight(.bold))
                        .foregroundStyle(RD.Palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 选集（分段范围 + 网格）

    private var rangeCount: Int { max(1, (episodes.count + rangeSize - 1) / rangeSize) }

    private func episodeSection(columns: Int, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let safeRange = min(rangeIndex, rangeCount - 1)
        let lo = safeRange * rangeSize
        let hi = min(lo + rangeSize, episodes.count)
        let visible = lo < hi ? Array(episodes[lo..<hi]) : []
        return VStack(alignment: .leading, spacing: RD.Space.md) {
            RDSectionHeader(title: "选集", trailing: episodes.isEmpty ? nil : "\(episodes.count) 集", showsChevron: false, accentMark: true)

            if loading && episodes.isEmpty {
                RDDetailSkeletonView(columns: columns)
            } else {
                if rangeCount > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RD.Space.sm) {
                            ForEach(0..<rangeCount, id: \.self) { i in
                                let start = i * rangeSize + 1
                                let end = min((i + 1) * rangeSize, episodes.count)
                                Button {
                                    RDHaptics.shared.playRangeTabSwitch()
                                    withAnimation(RD.Motion.snappy) { rangeIndex = i }
                                } label: {
                                    Text("\(start)-\(end)")
                                        .font(RD.Font.caption.weight(.bold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(i == safeRange ? Color.white : RD.Palette.textSecondary)
                                        .background {
                                            if i == safeRange {
                                                RDGemFacetSurface(shape: Capsule(style: .continuous), shadowRadius: 4, borderWidth: 0.8)
                                            } else {
                                                Capsule()
                                                    .fill(RD.Palette.surfaceRaised)
                                                    .overlay(Capsule().strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.65))
                                            }
                                        }
                                }
                                .buttonStyle(RDPosterButtonStyle())
                            }
                        }
                    }
                }

                if episodes.isEmpty {
                    Text("选集为空，点上方刷新重试")
                        .font(RD.Font.caption)
                        .foregroundStyle(RD.Palette.textSecondary)
                } else {
                    let currentResumeIdx = history.entry(for: series.id)?.lastIndex
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: RD.Space.sm), count: columns), spacing: RD.Space.sm) {
                        ForEach(visible) { ep in
                            let isCurrent = currentResumeIdx == ep.index
                            let watched = isWatched(ep)
                            let cached = offline.isCached(ep.vid)
                            let state = offline.state(for: ep.vid)
                            let cellShape = RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                            Button {
                                RDHaptics.shared.playEpisodeCellTap(watched: watched)
                                playing = ep
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Text("\(ep.index)")
                                        .font(RD.Font.headline.monospacedDigit())
                                        .foregroundStyle(isCurrent ? .white : (watched ? Color.white.opacity(0.84) : .white))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background {
                                            if isCurrent {
                                                RDGemFacetSurface(shape: cellShape, shadowRadius: 5, borderWidth: 0.85)
                                            } else if watched {
                                                cellShape
                                                    .fill(RD.Palette.gemAbyss.opacity(0.62))
                                                    .overlay(cellShape.strokeBorder(RD.Palette.gemCore.opacity(0.36), lineWidth: 0.7))
                                            } else {
                                                cellShape
                                                    .fill(RD.Palette.surfaceRaised)
                                                    .overlay(cellShape.strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.65))
                                            }
                                        }

                                    if cached {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(RD.Palette.pearl)
                                            .padding(4)
                                    } else if state.isBusy {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .tint(RD.Palette.gemRim)
                                            .scaleEffect(0.65)
                                            .padding(4)
                                    }
                                }
                            }
                            .buttonStyle(RDPosterButtonStyle())
                            .accessibilityIdentifier("episode-\(ep.index)")
                            .contextMenu {
                                if cached {
                                    Button(role: .destructive) {
                                        offline.removeEpisode(vid: ep.vid)
                                    } label: {
                                        Label("删除离线缓存", systemImage: "trash")
                                    }
                                } else {
                                    Button {
                                        offline.cacheSingle(series: series, episode: ep)
                                    } label: {
                                        Label("离线缓存第 \(ep.index) 集", systemImage: "arrow.down.circle")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
    }

    // MARK: A10 同款接档推荐

    @ViewBuilder
    private func relatedSection(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let related = catalog.relatedSeries(for: series, limit: 8)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: RD.Space.sm) {
                RDSectionHeader(title: "同款接档推荐", trailing: "按题材匹配", showsChevron: false, accentMark: true)
                    .padding(.leading, leadingPad)
                    .padding(.trailing, trailingPad)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: RD.Space.md) {
                        ForEach(related) { item in
                            NavigationLink(value: item) {
                                SeriesCard(series: item, compact: true)
                                    .frame(width: 118)
                            }
                            .buttonStyle(RDPosterButtonStyle())
                        }
                    }
                    .padding(.leading, leadingPad)
                    .padding(.trailing, trailingPad)
                }
            }
        }
    }

    private func isWatched(_ ep: Episode) -> Bool {
        if let entry = history.entry(for: series.id), entry.lastIndex == ep.index {
            return true
        }
        return prefs.isEpisodeWatched(seriesID: series.id, episodeIndex: ep.index)
    }

    private func toggleCollect() async {
        guard !collectBusy else { return }
        RDHaptics.shared.playCollectPreTap()
        collectBusy = true
        let next = !isCollected

        if auth.isLoggedIn {
            do {
                try await ManjuAPI.shared.collectSeries(seriesID: series.id, collect: next)
                isCollected = next
                FollowStore.shared.setCollected(next, series: series)
                RDHaptics.shared.playCollectResult(collected: next)
                showCollectHint(next ? "已收藏并置顶到首页「在追片单」" : "已取消收藏")
            } catch {
                RDHaptics.shared.playCollectRollback()
                AppLog.write("DETAIL collect error=\(error.localizedDescription)")
                showCollectHint("收藏同步失败，状态已保留")
            }
        } else {
            isCollected = next
            FollowStore.shared.setCollected(next, series: series)
            RDHaptics.shared.playCollectResult(collected: next)
            showCollectHint(next ? "已加入本机首页「在追片单」" : "已移出「在追片单」")
        }
        collectBusy = false
    }

    private func showCollectHint(_ msg: String) {
        collectBanner = msg
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self.collectBanner == msg { self.collectBanner = nil }
        }
    }

    private func load(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        error = nil
        do {
            let detail = try await ManjuAPI.shared.album(seriesID: series.id)
            series = detail.series
            episodes = detail.episodes
            CatalogCache.shared.ingestAlbum(detail)
            FollowStore.shared.markSeenEpisodeCount(for: detail.series)
            await offline.reconcileWithDisk(checking: detail.episodes.map(\.vid))
            AppLog.write("DETAIL UI title=\(detail.series.title) episodes=\(detail.episodes.count)")
        } catch {
            self.error = error.localizedDescription
            AppLog.write("DETAIL UI error=\(error.localizedDescription)")
            if episodes.isEmpty, let vid = initial.firstVid {
                episodes = [Episode(vid: vid, index: initial.firstIndex, title: "第\(initial.firstIndex)集",
                                    cover: initial.cover, duration: 0, seriesID: initial.id)]
            }
        }
        loading = false
    }
}
