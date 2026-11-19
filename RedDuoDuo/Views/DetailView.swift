import SwiftUI

/// 1.4.8 详情「整页浮层」：
/// 顶 40 圆钮 → 柔溶封面 + 毛玻璃名牌 → 白「继续看」+ 玻璃追剧/离线 → 3 行简介
/// → 选集横滑胶囊带（区间 1-30… / 当前白实心 / 已看灰 / 未看玻璃 / 缓存 5pt 点）→ 相似行。
/// 大屏左 44% Hero + 操作 + 简介，右 56% 浮板选集（6/行）+ 3 列相似；半折上下分屏。
struct DetailView: View {
    let initial: Series
    @EnvironmentObject private var history: WatchHistory
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var offline = OfflineCacheManager.shared
    @ObservedObject private var prefs = RDPlaybackPrefs.shared
    @ObservedObject private var catalog = CatalogCache.shared

    @Environment(\.dismiss) private var dismiss

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
    @State private var tint: RDAlbumTint?
    @State private var showOfflineSheet = false
    @State private var showEpisodeDrawer = false
    private let chromeReason = "detail-\(UUID().uuidString)"

    private let rangeSize = 30

    init(initial: Series) {
        self.initial = initial
        _series = State(initialValue: initial)
    }

    var body: some View {
        ZStack(alignment: .top) {
            RDAlbumAmbientBackground(tint: tint)
            RDAlbum.C.base.opacity(0.001).ignoresSafeArea()
            RDSafeAreaProbe(insets: $safeInsets)

            GeometryReader { fullGeo in
                let fullWidth = fullGeo.size.width
                let fullHeight = fullGeo.size.height
                let wide = RD.isWide(fullWidth)
                let horiz = RDLayoutInsets.horizontal(in: fullGeo)
                let leadingPad = max(horiz.leading, wide ? RDAlbum.Space.pageWide : RDAlbum.Space.pageSmall)
                let trailingPad = max(horiz.trailing, wide ? RDAlbum.Space.pageWide : RDAlbum.Space.pageSmall)
                let panes = DuoFoldLayout.physicalFoldPanes(in: fullGeo)

                ZStack(alignment: .top) {
                    if let panes {
                        if panes.isBookPosture {
                            wideLayout(
                                fullWidth: fullWidth,
                                leftWidth: max(1, panes.videoRect.width),
                                rightWidth: max(1, panes.panelRect.width),
                                leadingPad: 16,
                                trailingPad: 16,
                                topClearance: max(safeInsets.top + 60, 72)
                            )
                        } else {
                            foldLayout(
                                fullWidth: fullWidth,
                                topHeight: max(1, panes.videoRect.height),
                                bottomHeight: max(1, panes.panelRect.height),
                                leadingPad: leadingPad,
                                trailingPad: trailingPad,
                                topClearance: max(safeInsets.top + 56, 68)
                            )
                        }
                    } else if wide {
                        wideLayout(
                            fullWidth: fullWidth,
                            leftWidth: min(max(fullWidth * 0.44, 320), 560),
                            rightWidth: fullWidth - min(max(fullWidth * 0.44, 320), 560),
                            leadingPad: leadingPad,
                            trailingPad: trailingPad,
                            topClearance: max(safeInsets.top + 60, 72)
                        )
                    } else {
                        compactLayout(
                            fullWidth: fullWidth,
                            fullHeight: fullHeight,
                            leadingPad: leadingPad,
                            trailingPad: trailingPad
                        )
                    }

                    topButtons
                        .padding(.top, max(safeInsets.top + 8, 14))
                        .padding(.horizontal, max(leadingPad, 16))
                }
                .frame(width: fullWidth, height: fullHeight)
            }
            .ignoresSafeArea(edges: .top)
        }
        .rdScreen()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            RDAlbumChrome.shared.setBrowseChromeHidden(true, reason: chromeReason)
            isCollected = FollowStore.shared.isCollected(series.id)
            offline.isOfflineUIVisible = true
        }
        .onDisappear {
            RDAlbumChrome.shared.setBrowseChromeHidden(false, reason: chromeReason)
            offline.isOfflineUIVisible = false
        }
        .task {
            if episodes.isEmpty { await load() }
            if let url = currentCoverURL {
                tint = await RDAlbumTintStore.shared.tint(for: url)
            }
        }
        .onChange(of: series.cover) { _, _ in
            Task {
                if let url = currentCoverURL {
                    tint = await RDAlbumTintStore.shared.tint(for: url)
                }
            }
        }
        .fullScreenCover(item: $playing) { episode in
            let idx = episodes.firstIndex(where: { $0.vid == episode.vid }) ?? 0
            PlayerView(series: series, episodes: episodes, startIndex: idx)
        }
        .sheet(isPresented: $showOfflineSheet) {
            offlineSheet
                .presentationDetents([.height(380), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showEpisodeDrawer) {
            episodeDrawerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var currentCoverURL: String? {
        let url = series.cover.isEmpty ? initial.cover : series.cover
        return url.isEmpty ? nil : url
    }

    // MARK: - 顶 40 圆钮

    private var topButtons: some View {
        HStack(spacing: 10) {
            Button {
                RDHaptics.shared.playGlassTap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(RDAlbumRoundIconStyle(size: 40, mediaOverlay: true))
            .accessibilityLabel("返回")

            Spacer(minLength: 8)

            Menu {
                Button {
                    RDHaptics.shared.playSquareGlassTap()
                    Task { await load(force: true) }
                } label: {
                    Label("刷新剧集", systemImage: "arrow.clockwise")
                }
                Button {
                    Task { await toggleCollect() }
                } label: {
                    Label(isCollected ? "取消追剧" : "加入追剧", systemImage: isCollected ? "bookmark.slash" : "bookmark")
                }
                Button {
                    RDHaptics.shared.playGlassTap()
                    showOfflineSheet = true
                } label: {
                    Label("离线追剧包", systemImage: "arrow.down.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(RDAlbumRoundIconStyle(size: 40, mediaOverlay: true))
            .accessibilityLabel("更多")
        }
    }

    // MARK: - 小屏：单列

    private func compactLayout(
        fullWidth: CGFloat,
        fullHeight: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat
    ) -> some View {
        let coverWidth = max(1, fullWidth - 24)
        let coverHeight = min(min(coverWidth * 1.25, fullHeight * 0.48), 540)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                coverSection(width: coverWidth, height: coverHeight, wide: false)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                    infoBlock()
                    episodeSectionCompact()
                    relatedSectionCompact()
                }
                .padding(.horizontal, leadingPad)
                .padding(.top, RDAlbum.Space.lg)
            }
            .padding(.bottom, max(safeInsets.bottom + 40, 48))
        }
    }

    // MARK: - 半折：上封面 / 下信息

    private func foldLayout(
        fullWidth: CGFloat,
        topHeight: CGFloat,
        bottomHeight: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat,
        topClearance: CGFloat
    ) -> some View {
        let coverWidth = max(1, fullWidth - 24)
        let coverHeight = max(240, topHeight - topClearance - 10)
        return VStack(spacing: 0) {
            coverSection(width: coverWidth, height: min(coverHeight, coverWidth * 1.3), wide: false)
                .padding(.horizontal, 12)
                .padding(.top, topClearance)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                    infoBlock()
                    episodeSectionCompact()
                }
                .padding(.horizontal, leadingPad)
                .padding(.top, RDAlbum.Space.md)
                .padding(.bottom, 40)
            }
            .frame(height: max(1, bottomHeight))
        }
    }

    // MARK: - 大屏：左 44% / 右 56%

    private func wideLayout(
        fullWidth: CGFloat,
        leftWidth: CGFloat,
        rightWidth: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat,
        topClearance: CGFloat
    ) -> some View {
        let gap: CGFloat = 24
        let leftColumnWidth = max(1, leftWidth - 32)
        let coverHeight = min(max(leftColumnWidth * 1.12, 360), 560)
        return HStack(alignment: .top, spacing: gap) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                    coverSection(width: leftColumnWidth, height: coverHeight, wide: true)
                    infoBlock()
                }
                .padding(.top, topClearance)
                .padding(.bottom, max(safeInsets.bottom + 40, 48))
            }
            .frame(width: max(1, leftWidth - 16))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    episodeBoard(columns: 6)
                    relatedGrid(columns: 3)
                }
                .padding(.top, topClearance)
                .padding(.bottom, max(safeInsets.bottom + 40, 48))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
    }

    // MARK: - 柔溶封面 + 毛玻璃名牌

    private func coverSection(width: CGFloat, height: CGFloat, wide: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteCover(url: series.cover, thumbnailMaxPixel: 1200)
                .frame(width: width, height: height)
                .clipped()

            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.48), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.40),
                    .init(color: RDAlbum.C.base.opacity(0.46), location: 0.62),
                    .init(color: RDAlbum.C.base.opacity(0.90), location: 0.82),
                    .init(color: RDAlbum.C.base, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if !series.badge.isEmpty {
                        tagPill(series.badge, accent: true)
                    }
                    if series.isCompleted {
                        tagPill("已完结", accent: false)
                    } else if series.isJustUpdated {
                        tagPill("刚更新", accent: false)
                    }
                    if !series.score.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 8))
                            Text(series.score)
                        }
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.mediaPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.44), in: Capsule())
                    }
                }

                Text(series.title.isEmpty ? initial.title : series.title)
                    .accessibilityIdentifier("detail-title")
                    .font(RDAlbum.Font.hero(wide))
                    .foregroundStyle(RDAlbum.C.mediaPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: RDAlbum.C.heroTextShadow, radius: 8, y: 2)

                Text(detailMetaLine)
                    .font(RDAlbum.Font.wideSub)
                    .tracking(1.4)
                    .foregroundStyle(RDAlbum.C.mediaSecondary)
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(rdHex: 0x101116, opacity: 0.40))
                    )
                    .environment(\.colorScheme, .dark)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous))
        .shadow(color: RDAlbum.C.posterShadow, radius: 20, x: 0, y: 10)
    }

    private var detailMetaLine: String {
        var parts: [String] = ["漫剧", "共\(max(series.episodeCount, episodes.count))集"]
        if !series.tags.isEmpty {
            parts.append(contentsOf: series.tags.prefix(3))
        }
        if !series.seasonTag.isEmpty { parts.append(series.seasonTag) }
        parts.append("免费")
        return parts.joined(separator: " · ")
    }

    private func tagPill(_ text: String, accent: Bool) -> some View {
        HStack(spacing: 4) {
            if accent {
                Circle().fill(RDAlbum.C.accentDot).frame(width: 5, height: 5)
            }
            Text(text)
        }
        .font(RDAlbum.Font.plateSub)
        .foregroundStyle(RDAlbum.C.mediaPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.44), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
    }

    // MARK: - 信息块

    private func infoBlock() -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.md) {
            if let collectBanner {
                Text(collectBanner)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .rdAlbumGlass(Capsule(style: .continuous), kind: .secondary, shadow: false)
                    .transition(.opacity)
            }

            actionRow

            if let entry = history.entry(for: series.id) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RDAlbum.C.textSecondary)
                    Text("上次看到第 \(entry.lastIndex) 集\(entry.lastPosition >= 1.5 ? " · \(entry.positionText)" : "")")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .rdAlbumGlass(Capsule(style: .continuous), kind: .secondary, shadow: false)
                .accessibilityIdentifier("detail-last-watched")
            }

            if let error {
                Text(error)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.accentDot)
                    .lineLimit(3)
            }

            introSection
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                RDHaptics.shared.playResumeCardTap()
                if let entry = history.entry(for: series.id),
                   let ep = episodes.first(where: { $0.vid == entry.lastVid || $0.index == entry.lastIndex }) ?? episodes.first {
                    playing = ep
                } else if let first = episodes.first {
                    playing = first
                }
            } label: {
                Label(continueTitle, systemImage: "play.fill")
            }
            .buttonStyle(RDAlbumPrimaryPillStyle(height: 48, horizontalPadding: 16, fullWidth: true))
            .disabled(episodes.isEmpty)
            .accessibilityIdentifier("detail-continue-button")

            Button {
                Task { await toggleCollect() }
            } label: {
                Label(isCollected ? "已追" : "追剧", systemImage: isCollected ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(RDAlbumGlassPillStyle(height: 48, horizontalPadding: 14))
            .disabled(collectBusy)
            .accessibilityLabel(isCollected ? "取消追剧" : "加入追剧")

            Button {
                RDHaptics.shared.playGlassTap()
                showOfflineSheet = true
            } label: {
                Label("离线", systemImage: "arrow.down.circle")
            }
            .buttonStyle(RDAlbumGlassPillStyle(height: 48, horizontalPadding: 14))
        }
    }

    private var continueTitle: String {
        if let entry = history.entry(for: series.id) {
            return "继续看 第\(entry.lastIndex)集"
        }
        return episodes.isEmpty ? "加载中…" : "从第\(episodes.first?.index ?? 1)集开始"
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(series.intro.isEmpty ? "暂无简介" : series.intro)
                .font(RDAlbum.Font.body)
                .foregroundStyle(RDAlbum.C.textSecondary)
                .lineSpacing(5)
                .lineLimit(expandedIntro ? nil : 3)
                .onTapGesture {
                    let next = !expandedIntro
                    RDHaptics.shared.playIntroToggle(expanded: next)
                    withAnimation(RDAlbum.Motion.rearrange) { expandedIntro = next }
                }
            if !series.intro.isEmpty {
                Button {
                    let next = !expandedIntro
                    RDHaptics.shared.playIntroToggle(expanded: next)
                    withAnimation(RDAlbum.Motion.rearrange) { expandedIntro = next }
                } label: {
                    Text(expandedIntro ? "收起" : "展开全部")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.textPrimary.opacity(0.86))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 选集（小屏横滑胶囊带）

    private var rangeCount: Int { max(1, (episodes.count + rangeSize - 1) / rangeSize) }

    private var safeRange: Int { min(max(rangeIndex, 0), rangeCount - 1) }

    private var visibleEpisodes: [Episode] {
        let lo = safeRange * rangeSize
        let hi = min(lo + rangeSize, episodes.count)
        return lo < hi ? Array(episodes[lo..<hi]) : []
    }

    private func episodeSectionCompact() -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                RDAlbumSectionHeader(
                    title: "选集",
                    trailing: episodes.isEmpty ? nil : "\(episodes.count) 集",
                    showsChevron: false
                )
                Button("全部") {
                    RDHaptics.shared.playDrawerToggle(open: true)
                    showEpisodeDrawer = true
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 14))
            }

            if loading && episodes.isEmpty {
                RDDetailSkeletonView(columns: 6)
            } else if episodes.isEmpty {
                Text("选集为空，点右上更多刷新重试")
                    .font(RDAlbum.Font.body)
                    .foregroundStyle(RDAlbum.C.textSecondary)
            } else {
                if rangeCount > 1 {
                    rangeChips
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(visibleEpisodes) { ep in
                            episodeCapsule(ep, fillsWidth: false)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var rangeChips: some View {
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
                            .font(RDAlbum.Font.rounded(13, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(i == safeRange ? RDAlbum.C.inverse : RDAlbum.C.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background {
                                if i == safeRange {
                                    Capsule(style: .continuous).fill(Color.white)
                                } else {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.0001))
                                        .overlay(Capsule(style: .continuous).strokeBorder(RDAlbum.C.textSecondary.opacity(0.28), lineWidth: 0.6))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func episodeCapsule(_ ep: Episode, fillsWidth: Bool) -> some View {
        let currentIndex = history.entry(for: series.id)?.lastIndex
        let isCurrent = currentIndex == ep.index
        let watched = isWatched(ep)
        let state: RDAlbumEpisodeState = isCurrent ? .current : (watched ? .watched : .unwatched)
        return RDAlbumEpisodeCapsule(
            index: ep.index,
            state: state,
            cached: offline.isCached(ep.vid),
            fillsWidth: fillsWidth
        ) {
            RDHaptics.shared.playEpisodeCellTap(watched: watched)
            if showEpisodeDrawer {
                showEpisodeDrawer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    playing = ep
                }
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    playing = ep
                }
            }
        }
        .accessibilityIdentifier("episode-\(ep.index)")
        .contextMenu {
            if offline.isCached(ep.vid) {
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

    private func isWatched(_ ep: Episode) -> Bool {
        if let entry = history.entry(for: series.id), entry.lastIndex == ep.index { return true }
        return prefs.isEpisodeWatched(seriesID: series.id, episodeIndex: ep.index)
    }

    // MARK: - 大屏右浮板（6/行胶囊）

    private func episodeBoard(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                RDAlbumSectionHeader(
                    title: "选集",
                    trailing: episodes.isEmpty ? nil : "\(episodes.count) 集",
                    showsChevron: false
                )
                Button("全部") {
                    RDHaptics.shared.playDrawerToggle(open: true)
                    showEpisodeDrawer = true
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 32, horizontalPadding: 14))
            }

            if loading && episodes.isEmpty {
                RDDetailSkeletonView(columns: columns)
            } else if episodes.isEmpty {
                Text("选集为空，点右上更多刷新重试")
                    .font(RDAlbum.Font.body)
                    .foregroundStyle(RDAlbum.C.textSecondary)
            } else {
                if rangeCount > 1 { rangeChips }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                    spacing: 10
                ) {
                    ForEach(visibleEpisodes) { ep in
                        episodeCapsule(ep, fillsWidth: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous), kind: .drawer)
    }

    // MARK: - 相似行

    @ViewBuilder
    private func relatedSectionCompact() -> some View {
        let related = catalog.relatedSeries(for: series, limit: 8)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
                RDAlbumSectionHeader(title: "同款接档", trailing: "按题材匹配", showsChevron: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: RDAlbum.Space.cardGapSmall) {
                        ForEach(related) { item in
                            NavigationLink(value: item) {
                                RDAlbumPosterCard(series: item, width: RDAlbum.Poster.mediumSmall, plateHeight: RDAlbum.Poster.plateMedium)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func relatedGrid(columns: Int) -> some View {
        let related = catalog.relatedSeries(for: series, limit: 9)
        if !related.isEmpty {
            GeometryReader { geo in
                let spacing: CGFloat = 16
                let cardWidth = max(80, (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(related) { item in
                        NavigationLink(value: item) {
                            RDAlbumPosterCard(series: item, width: cardWidth, plateHeight: RDAlbum.Poster.plateMedium)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: gridHeight(columns: columns))
        }
    }

    private func gridHeight(columns: Int) -> CGFloat {
        // 右板宽度近似：以 3 列 × 16:12 卡高 + 行距估算，够 ScrollView 布局即可。
        let estimatedWidth = 380.0
        let cardWidth = max(80, (estimatedWidth - 16 * CGFloat(columns - 1)) / CGFloat(columns))
        let rows = ceil(Double(9) / Double(columns))
        return CGFloat(rows) * (cardWidth * 4 / 3 + 24)
    }

    // MARK: - 全部选集抽屉

    private var episodeDrawerSheet: some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.md) {
            HStack {
                Text("全部选集")
                    .font(RDAlbum.Font.rowTitle)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                Spacer()
                Button {
                    showEpisodeDrawer = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RDAlbumRoundIconStyle(size: 40))
            }
            .padding(.top, 8)

            if rangeCount > 1 { rangeChips }

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                    spacing: 10
                ) {
                    ForEach(episodes) { ep in
                        episodeCapsule(ep, fillsWidth: true)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 离线追剧包

    private var offlineSheet: some View {
        let cachedCount = offline.cachedCount(for: series.id, episodes: episodes)
        let currentIdx = resumeEpisodeArrayIndex
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("离线追剧包")
                        .font(RDAlbum.Font.rowTitle)
                        .foregroundStyle(RDAlbum.C.textPrimary)
                    Text("已存 \(cachedCount)/\(episodes.count) 集")
                        .font(RDAlbum.Font.wideSub)
                        .tracking(1.4)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                }
                Spacer()
                Button {
                    showOfflineSheet = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RDAlbumRoundIconStyle(size: 40))
            }

            if let batchTitle = offline.activeBatchTitle, offline.isDownloadingBatch {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(RDAlbum.C.textPrimary)
                    Text("正在下载：\(batchTitle)（\(offline.batchDoneCount)/\(offline.batchTotalCount)）")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button("暂停") {
                        RDHaptics.shared.playGlassTap()
                        offline.cancelPendingQueue()
                    }
                    .font(RDAlbum.Font.plateSub.weight(.semibold))
                    .foregroundStyle(RDAlbum.C.textPrimary)
                }
                .padding(10)
                .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous), kind: .secondary, shadow: false)
            }

            HStack(spacing: 10) {
                Button {
                    offline.cacheNext10(series: series, episodes: episodes, fromIndex: currentIdx)
                } label: {
                    Label("存后续 10 集", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 44, horizontalPadding: 14))

                Button {
                    offline.cacheAll(series: series, episodes: episodes)
                } label: {
                    Label("一键存全集", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(RDAlbumPrimaryPillStyle(height: 44, horizontalPadding: 16))
            }

            if cachedCount > 0 {
                Button {
                    offline.removeSeries(seriesID: series.id)
                } label: {
                    Text("清理本剧离线缓存")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.accentDot)
                }
                .buttonStyle(.plain)
            }

            Text(prefs.autoCleanWatchedOffline ? "已开启「看完自动清理」，播完后自动释放磁盘空间" : "当前保留已看完离线剧集（可在「我的」开启自动清理）")
                .font(RDAlbum.Font.plateSub)
                .foregroundStyle(RDAlbum.C.textTertiary)

            Spacer(minLength: 0)
        }
        .padding(22)
    }

    private var resumeEpisodeArrayIndex: Int {
        guard let entry = history.entry(for: series.id),
              let idx = episodes.firstIndex(where: { $0.vid == entry.lastVid || $0.index == entry.lastIndex }) else {
            return 0
        }
        return idx
    }

    // MARK: - 数据 / 追剧

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
