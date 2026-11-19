import SwiftUI

/// 1.4.8 首页「浮层画册」：
/// 透明顶栏 → 3:4 大圆角无框 Hero（毛玻璃名牌 + 双胶囊 + 5 页点，8s 轮播 + 下拉视差）
/// → 继续观看 → L/M 错落海报行与题材胶囊 → 无限探索。
/// 网飞骨架保留：大 Hero + 横滑行 + 详情 + 播放；大屏 62/38 双幅首屏、M 行一排 5 张；半折上下分屏零跨痕。
struct HomeView: View {
    @EnvironmentObject private var history: WatchHistory
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var catalog = CatalogCache.shared

    var onOpenGoldenHooks: (() -> Void)? = nil

    @State private var path = NavigationPath()
    @State private var series: [Series] = []
    @State private var topRank: [Series] = []
    @State private var feedCursor: HomeFeedCursor?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var hasMore = true
    @State private var consecutiveEmptyPages = 0
    @State private var loadGeneration = 0
    @State private var error: String?
    @State private var didLoad = false
    @State private var loadingResumeID: String?
    @State private var pickingRandom = false
    @State private var lastRandomPickedID: String?
    @State private var resumeTarget: ResumeTarget?
    @State private var showHookModal = false
    @State private var selectedTag: String? = nil
    @State private var heroIndexOffset: Int = 0
    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var scrollOffset: CGFloat = 0
    @State private var wasScrolledPastTopBar = false
    @State private var didFireFeedEndHaptic = false
    @State private var heroTint: RDAlbumTint?

    private struct ResumeTarget: Identifiable {
        let id = UUID()
        let series: Series
        let episodes: [Episode]
        let startIndex: Int
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                RDAlbumAmbientBackground(tint: heroTint)
                    .scaleEffect(1 + CGFloat(min(Double(max(0, -scrollOffset)) / 2800.0, 0.12)))
                    .brightness(min(Double(max(0, -scrollOffset)) / 280.0, 1.0) * 0.08)
                RDAlbum.C.base.opacity(0.001).ignoresSafeArea()
                RDSafeAreaProbe(insets: $safeInsets)

                GeometryReader { fullGeo in
                    let fullWidth = fullGeo.size.width
                    let wide = RD.isWide(fullWidth)
                    let horiz = RDLayoutInsets.horizontal(in: fullGeo)
                    let leadingPad = max(horiz.leading, wide ? RDAlbum.Space.pageWide : RDAlbum.Space.pageSmall)
                    let trailingPad = max(horiz.trailing, wide ? RDAlbum.Space.pageWide : RDAlbum.Space.pageSmall)
                    let contentWidth = max(1, fullWidth - leadingPad - trailingPad)
                    let topBarHeight = max(safeInsets.top + 50, 62)
                    let panes = DuoFoldLayout.physicalFoldPanes(in: fullGeo)

                    ZStack(alignment: .top) {
                        contentLayer(
                            fullWidth: fullWidth,
                            fullHeight: fullGeo.size.height,
                            wide: wide,
                            contentWidth: contentWidth,
                            leadingPad: leadingPad,
                            trailingPad: trailingPad,
                            topBarHeight: topBarHeight,
                            panes: panes
                        )

                        topBar(wide: wide, leadingPad: leadingPad, trailingPad: trailingPad)
                            .frame(
                                width: (panes?.isBookPosture == true) ? panes?.videoRect.width : fullWidth,
                                alignment: .leading
                            )
                    }
                    .frame(width: fullWidth, height: fullGeo.size.height)
                }
                .ignoresSafeArea(edges: .top)
            }
            .rdScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Series.self) { item in
                DetailView(initial: item)
            }
            .sheet(isPresented: $auth.showLoginSheet) {
                LoginView()
                    .environmentObject(auth)
            }
            .fullScreenCover(item: $resumeTarget) { target in
                PlayerView(series: target.series, episodes: target.episodes, startIndex: target.startIndex)
            }
            .fullScreenCover(isPresented: $showHookModal) {
                GoldenHookFeedView(isActive: true) {
                    showHookModal = false
                }
                .environmentObject(auth)
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                await load(force: false)
            }
            .task(id: heroCoverURL) {
                guard !heroCoverURL.isEmpty else { heroTint = nil; return }
                heroTint = await RDAlbumTintStore.shared.tint(for: heroCoverURL)
            }
            .task(id: heroRotationKey) {
                guard series.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(RDAlbum.Motion.glow) {
                        heroIndexOffset = (heroIndexOffset + 1) % max(min(series.count, 5), 1)
                    }
                }
            }
            .onChange(of: auth.sessionVersion) { _, _ in
                Task { await load(force: true) }
            }
            .onChange(of: auth.sessionExpiredNotice) { _, notice in
                if notice != nil {
                    RDHaptics.shared.playSessionExpiredNotice()
                }
            }
        }
    }

    // MARK: - 当前 Hero

    private var showcasePool: [Series] { Array(series.prefix(5)) }

    private var currentHero: Series? {
        guard !series.isEmpty else { return nil }
        let pool = showcasePool
        guard !pool.isEmpty else { return series.first }
        return pool[heroIndexOffset % pool.count]
    }

    private var heroCoverURL: String {
        currentHero?.cover ?? ""
    }

    private var heroRotationKey: String {
        series.prefix(5).map(\.id).joined(separator: "|")
    }

    // MARK: - 内容分层

    @ViewBuilder
    private func contentLayer(
        fullWidth: CGFloat,
        fullHeight: CGFloat,
        wide: Bool,
        contentWidth: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat,
        topBarHeight: CGFloat,
        panes: DuoFoldLayout.SplitPanes?
    ) -> some View {
        if let panes {
            if panes.isBookPosture {
                HStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        heroBlock(
                            width: max(1, panes.videoRect.width - 24),
                            height: min(max(panes.videoRect.height * 0.72, 320), 520),
                            wide: false,
                            showsDots: false
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, topBarHeight + 8)
                        .padding(.bottom, 12)
                    }
                    .frame(width: panes.videoRect.width)

                    ScrollView(showsIndicators: false) {
                        shelvesContent(
                            wide: true,
                            contentWidth: max(1, panes.panelRect.width - 32),
                            leadingPad: 16,
                            trailingPad: 16,
                            includeContinueHeader: true
                        )
                        .padding(.top, topBarHeight + 8)
                        .padding(.bottom, 92)
                    }
                    .frame(width: panes.panelRect.width)
                }
            } else {
                VStack(spacing: 0) {
                    heroBlock(
                        width: max(1, fullWidth - 24),
                        height: min(max(panes.videoRect.height - topBarHeight - 20, 260), 500),
                        wide: false,
                        showsDots: true
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, topBarHeight + 4)

                    ScrollView(showsIndicators: false) {
                        shelvesContent(
                            wide: false,
                            contentWidth: max(1, fullWidth - 40),
                            leadingPad: RDAlbum.Space.pageSmall,
                            trailingPad: RDAlbum.Space.pageSmall,
                            includeContinueHeader: true
                        )
                        .padding(.top, RDAlbum.Space.xl)
                        .padding(.bottom, 92)
                    }
                    .frame(height: max(1, panes.panelRect.height))
                }
            }
        } else if wide {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("home-top-anchor")

                        if let notice = auth.sessionExpiredNotice {
                            RDNotice(text: notice, actionTitle: "重新登录") {
                                RDHaptics.shared.playGlassTap()
                                auth.clearExpiredNotice()
                                auth.showLoginSheet = true
                            }
                            .padding(.horizontal, leadingPad)
                            .padding(.top, topBarHeight + 8)
                        }

                        if loading && series.isEmpty {
                            RDHomeSkeletonView(
                                width: fullWidth, wide: true,
                                leadingPad: leadingPad, trailingPad: trailingPad
                            )
                            .padding(.top, topBarHeight + 8)
                        } else if let error, series.isEmpty {
                            errorView(error).padding(.top, topBarHeight + 40)
                        } else if series.isEmpty {
                            emptyView.padding(.top, topBarHeight + 40)
                        } else {
                            wideFirstScreen(
                                contentWidth: contentWidth,
                                leadingPad: leadingPad,
                                trailingPad: trailingPad,
                                topInset: topBarHeight + 10
                            )

                            shelvesContent(
                                wide: true,
                                contentWidth: contentWidth,
                                leadingPad: leadingPad,
                                trailingPad: trailingPad,
                                includeContinueHeader: false
                            )
                            .padding(.top, RDAlbum.Space.rowGap)

                            feedFooter(leadingPad: leadingPad, trailingPad: trailingPad)
                                .padding(.top, RDAlbum.Space.xl)
                        }
                    }
                    .frame(width: fullWidth, alignment: .leading)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, offset in
                    handleScrollOffset(offset)
                }
                .refreshable {
                    RDHaptics.shared.playPullRefreshTriggered()
                    await load(force: true)
                    RDHaptics.shared.playPullRefreshComplete()
                }
                .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                    if let tab = note.object as? Int, tab == 0 {
                        withAnimation(RDAlbum.Motion.rearrange) {
                            scrollProxy.scrollTo("home-top-anchor", anchor: .top)
                        }
                    }
                }
            }
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("home-top-anchor")

                        if let notice = auth.sessionExpiredNotice {
                            RDNotice(text: notice, actionTitle: "重新登录") {
                                RDHaptics.shared.playGlassTap()
                                auth.clearExpiredNotice()
                                auth.showLoginSheet = true
                            }
                            .padding(.horizontal, leadingPad)
                            .padding(.top, topBarHeight + 8)
                        }

                        if loading && series.isEmpty {
                            RDHomeSkeletonView(
                                width: fullWidth, wide: false,
                                leadingPad: leadingPad, trailingPad: trailingPad
                            )
                            .padding(.top, topBarHeight + 8)
                        } else if let error, series.isEmpty {
                            errorView(error).padding(.top, topBarHeight + 40)
                        } else if series.isEmpty {
                            emptyView.padding(.top, topBarHeight + 40)
                        } else {
                            heroBlock(
                                width: max(1, fullWidth - 24),
                                height: min(min((fullWidth - 24) * 4 / 3, fullHeight * 0.60), 500),
                                wide: false,
                                showsDots: true
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, topBarHeight + 6)

                            shelvesContent(
                                wide: false,
                                contentWidth: contentWidth,
                                leadingPad: leadingPad,
                                trailingPad: trailingPad,
                                includeContinueHeader: true
                            )
                            .padding(.top, RDAlbum.Space.xl)

                            feedFooter(leadingPad: leadingPad, trailingPad: trailingPad)
                                .padding(.top, RDAlbum.Space.xxl)
                        }
                    }
                    .frame(width: fullWidth, alignment: .leading)
                    .padding(.bottom, 86)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, offset in
                    handleScrollOffset(offset)
                }
                .refreshable {
                    RDHaptics.shared.playPullRefreshTriggered()
                    await load(force: true)
                    RDHaptics.shared.playPullRefreshComplete()
                }
                .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                    if let tab = note.object as? Int, tab == 0 {
                        withAnimation(RDAlbum.Motion.rearrange) {
                            scrollProxy.scrollTo("home-top-anchor", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func handleScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
        let crossed = offset > 28
        if crossed && !wasScrolledPastTopBar {
            RDHaptics.shared.playStickyBarCrossed()
        }
        wasScrolledPastTopBar = crossed
    }

    // MARK: - 顶栏（24 标 + 副标 + 36 挑剧钮）

    private func topBar(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let scrolled = scrollOffset > 28
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                RDGemPlayMark(size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("红果漫剧")
                        .font(RDAlbum.Font.rounded(19, .bold))
                        .foregroundStyle(RDAlbum.C.textPrimary)
                    Text("光照进故事里")
                        .font(RDAlbum.Font.rounded(11, .medium))
                        .tracking(1.4)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                }
            }

            Spacer(minLength: 6)

            Button {
                RDHaptics.shared.playGlassTap()
                if let onOpenGoldenHooks {
                    onOpenGoldenHooks()
                } else {
                    showHookModal = true
                }
            } label: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(RDAlbum.C.textPrimary)
            }
            .buttonStyle(RDAlbumTopIconStyle())
            .accessibilityLabel("第一集试看")

            Button {
                Task { await pickRandomDramaAndPlay() }
            } label: {
                if pickingRandom {
                    ProgressView().controlSize(.mini).tint(RDAlbum.C.textPrimary)
                } else {
                    Image(systemName: "dice.fill")
                }
            }
            .buttonStyle(RDAlbumTopIconStyle())
            .disabled(pickingRandom || series.isEmpty)
            .accessibilityLabel(wide ? "帮我挑一部" : "挑剧")

            Button {
                RDHaptics.shared.playPullRefreshTriggered()
                Task {
                    await load(force: true)
                    RDHaptics.shared.playPullRefreshComplete()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(RDAlbumTopIconStyle())
            .accessibilityLabel("刷新")
        }
        .padding(.top, max(safeInsets.top + 6, 12))
        .padding(.bottom, 8)
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
        .background {
            RDStickyTopBarBackground(scrolled: scrolled)
        }
        .animation(RD.Motion.fade, value: scrolled)
    }

    // MARK: - Hero（3:4 大圆角无框海报 + 毛玻璃名牌 + 软影）

    @ViewBuilder
    private func heroBlock(width: CGFloat, height: CGFloat, wide: Bool, showsDots: Bool) -> some View {
        if let hero = currentHero {
            let pool = showcasePool
            let pull = max(0, -scrollOffset)
            let imageScale = 1 + min(pull / 280, 0.22)
            let contentShift = pull * 0.65
            ZStack(alignment: .bottom) {
                RemoteCover(url: hero.cover, thumbnailMaxPixel: 1200)
                    .frame(width: width, height: height)
                    .scaleEffect(imageScale)
                    .offset(y: pull * 0.35)
                    .overlay {
                        RDAlbumTintPlaceholderTint(intensity: min(pull / 280, 0.22))
                    }

                // 顶 120 暗渐，保护状态栏与顶栏
                VStack {
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.55), location: 0),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)

                // 底部柔溶进景深光晕底
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.34),
                        .init(color: RDAlbum.C.base.opacity(0.28), location: 0.56),
                        .init(color: RDAlbum.C.base.opacity(0.72), location: 0.76),
                        .init(color: RDAlbum.C.base.opacity(0.96), location: 0.92),
                        .init(color: RDAlbum.C.base, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 12) {
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(hero.title)
                            .font(RDAlbum.Font.hero(wide))
                            .foregroundStyle(RDAlbum.C.mediaPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: RDAlbum.C.heroTextShadow, radius: 8, y: 2)
                        Text(heroMetaLine(hero))
                            .font(RDAlbum.Font.wideSub)
                            .tracking(1.4)
                            .foregroundStyle(RDAlbum.C.mediaSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(rdHex: 0x101116, opacity: 0.40))
                            )
                            .environment(\.colorScheme, .dark)
                    }

                    HStack(spacing: 12) {
                        Button {
                            RDHaptics.shared.playGlassHeroTap()
                            path.append(hero)
                        } label: {
                            Label("播放", systemImage: "play.fill")
                        }
                        .buttonStyle(RDAlbumPrimaryPillStyle(height: 46))
                        .accessibilityIdentifier("series-card-\(hero.id)")

                        Button {
                            RDHaptics.shared.playGlassHeroTap()
                            path.append(hero)
                        } label: {
                            Label("详情", systemImage: "info.circle")
                        }
                        .buttonStyle(RDAlbumGlassPillStyle(height: 46, mediaOverlay: true))

                        Spacer(minLength: 0)
                    }

                    if showsDots, pool.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(Array(pool.enumerated()), id: \.offset) { idx, _ in
                                let active = (heroIndexOffset % pool.count) == idx
                                Capsule(style: .continuous)
                                    .fill(active ? RDAlbum.C.mediaPrimary : RDAlbum.C.mediaPrimary.opacity(0.34))
                                    .frame(width: active ? 18 : 6, height: 6)
                                    .onTapGesture {
                                        RDHaptics.shared.playChipSelect()
                                        withAnimation(RDAlbum.Motion.glow) { heroIndexOffset = idx }
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
                .offset(y: contentShift)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous))
            .shadow(color: RDAlbum.C.posterShadow, radius: 20, x: 0, y: 10)
        }
    }

    private func heroMetaLine(_ hero: Series) -> String {
        var parts: [String] = []
        if !hero.tags.isEmpty {
            parts.append(contentsOf: hero.tags.prefix(3))
        } else {
            parts.append("漫剧")
        }
        parts.append("共\(hero.episodeCount)集")
        if !hero.seasonTag.isEmpty { parts.append(hero.seasonTag) }
        parts.append("免费观看")
        return parts.joined(separator: " · ")
    }

    // MARK: - 大屏双幅首屏（Hero 左 62% + 继续观看右 38%）

    private func wideFirstScreen(
        contentWidth: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat,
        topInset: CGFloat
    ) -> some View {
        let gap: CGFloat = 20
        let heroWidth = (contentWidth - gap) * 0.62
        let sideWidth = (contentWidth - gap) * 0.38
        return HStack(alignment: .top, spacing: gap) {
            heroBlock(width: heroWidth, height: 460, wide: true, showsDots: true)
            continuePanel(width: sideWidth, height: 460)
        }
        .padding(.horizontal, leadingPad)
        .padding(.top, topInset)
    }

    // MARK: - 继续观看（大屏右 38% 浮板 / 小屏横滑）

    @ViewBuilder
    private func continuePanel(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("继续观看")
                    .font(RDAlbum.Font.rowTitle)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                Spacer(minLength: 6)
                Text(history.entries.isEmpty ? "暂无进度" : "\(history.entries.count) 部")
                    .font(RDAlbum.Font.wideSub)
                    .tracking(1.4)
                    .foregroundStyle(RDAlbum.C.textSecondary)
            }

            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(RDAlbum.C.textTertiary)
                    Text("看一集后这里会记住进度")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(history.entries.prefix(4)) { entry in
                        continuePanelRow(entry)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(width: width, height: height, alignment: .topLeading)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous), kind: .drawer)
        .accessibilityIdentifier("continue-watching-section")
    }

    private func continuePanelRow(_ entry: HistoryEntry) -> some View {
        Button {
            RDHaptics.shared.playResumeCardTap()
            Task { await openHistoryEntry(entry) }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottom) {
                    RemoteCover(url: entry.cover, thumbnailMaxPixel: 200)
                        .frame(width: 54, height: 72)
                        .clipped()
                    RDAlbumProgressBar(fraction: entry.progressFraction, trackHeight: 2, showsBuffer: false)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                }
                .frame(width: 54, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(RDAlbum.Font.plateName)
                        .foregroundStyle(RDAlbum.C.textPrimary)
                        .lineLimit(1)
                    Text("第\(entry.lastIndex)集 · 剩\(max(entry.episodeCount - entry.lastIndex, 0))集")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                        .lineLimit(1)
                    RDAlbumProgressBar(fraction: entry.progressFraction, trackHeight: 2, showsBuffer: false)
                }

                Spacer(minLength: 0)

                if loadingResumeID == entry.seriesID {
                    ProgressView().controlSize(.mini).tint(RDAlbum.C.textPrimary)
                        .frame(width: 34, height: 34)
                } else {
                    RDAlbumPlayCircle(size: 34)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("continue-card-\(entry.seriesID)")
    }

    private func continueRow(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
            RDAlbumSectionHeader(
                title: "继续观看",
                trailing: history.entries.isEmpty ? "暂无进度" : "\(history.entries.count) 部",
                showsChevron: false
            )
            .padding(.horizontal, leadingPad)

            if history.entries.isEmpty {
                Text("看一集后这里会记住集数与秒级进度")
                    .font(RDAlbum.Font.body)
                    .foregroundStyle(RDAlbum.C.textSecondary)
                    .padding(.horizontal, leadingPad)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: RDAlbum.Space.cardGapSmall) {
                        ForEach(history.entries.prefix(10)) { entry in
                            Button {
                                RDHaptics.shared.playResumeCardTap()
                                Task { await openHistoryEntry(entry) }
                            } label: {
                                RDAlbumContinueTile(entry: entry, width: 250)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("continue-card-\(entry.seriesID)")
                        }
                    }
                    .padding(.horizontal, leadingPad)
                    .padding(.vertical, 4)
                }
            }
        }
        .accessibilityIdentifier("continue-watching-section")
    }

    // MARK: - 货架内容（L/M 错落）

    @ViewBuilder
    private func shelvesContent(
        wide: Bool,
        contentWidth: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat,
        includeContinueHeader: Bool
    ) -> some View {
        let largeWidth = wide ? RDAlbum.Poster.largeWide : RDAlbum.Poster.largeSmall
        let mediumWidth = wide
            ? max(130, (contentWidth - 128) / 5)
            : RDAlbum.Poster.mediumSmall
        let queue = followStore.bingeQueue(history: history.entries, catalog: catalog.byID)
        let allKnown = catalog.mergedSeries(primary: series + topRank)
        let halfHour = allKnown.filter { catalog.isHalfHourBinge($0) }
        let completed = allKnown.filter { $0.isCompleted }

        VStack(alignment: .leading, spacing: RDAlbum.Space.rowGap) {
            if !wide && includeContinueHeader {
                continueRow(leadingPad: leadingPad, trailingPad: trailingPad)
            }

            if !queue.isEmpty {
                VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
                    RDAlbumSectionHeader(
                        title: "在追片单",
                        trailing: "剩 \(queue.reduce(0) { $0 + $1.remainingEpisodes }) 集",
                        showsChevron: false
                    )
                    .padding(.horizontal, leadingPad)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: wide ? RDAlbum.Space.cardGapWide : RDAlbum.Space.cardGapSmall) {
                            ForEach(Array(queue.prefix(15).enumerated()), id: \.element.id) { _, item in
                                Button {
                                    RDHaptics.shared.playResumeCardTap()
                                    Task { await openBingeItem(item) }
                                } label: {
                                    RDAlbumPosterCard(
                                        series: item.series,
                                        width: largeWidth,
                                        plateHeight: RDAlbum.Poster.plateLarge,
                                        sub: item.remainingEpisodes > 0 ? "剩\(item.remainingEpisodes)集" : "追平",
                                        badge: item.statusBadge
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("continue-card-\(item.series.id)")
                            }
                        }
                        .padding(.leading, leadingPad)
                        .padding(.trailing, trailingPad)
                        .padding(.vertical, 6)
                    }
                }
            }

            if !topRank.isEmpty {
                staggeredRow(
                    title: "漫剧热播 Top 10",
                    trailing: "实时热度榜",
                    items: Array(topRank.prefix(10)),
                    cardWidth: mediumWidth,
                    plateHeight: RDAlbum.Poster.plateMedium,
                    spacing: wide ? RDAlbum.Space.cardGapWide : RDAlbum.Space.cardGapSmall,
                    leadingPad: leadingPad,
                    trailingPad: trailingPad,
                    inset: 24,
                    subtitle: { item in
                        if let rank = topRank.firstIndex(where: { $0.id == item.id }) {
                            return "TOP \(rank + 1)"
                        }
                        return nil
                    },
                    showScore: true
                )
            }

            quickDiscoveryBar(
                wide: wide,
                leadingPad: leadingPad,
                trailingPad: trailingPad
            )

            if !halfHour.isEmpty {
                staggeredRow(
                    title: "半小时刷完",
                    trailing: "短篇轻追 · \(halfHour.count) 部",
                    items: Array(halfHour.prefix(14)),
                    cardWidth: largeWidth,
                    plateHeight: RDAlbum.Poster.plateLarge,
                    spacing: wide ? RDAlbum.Space.cardGapWide : RDAlbum.Space.cardGapSmall,
                    leadingPad: leadingPad,
                    trailingPad: trailingPad,
                    inset: 0,
                    subtitle: { item in catalog.durationHintText(for: item) }
                )
            }

            if !completed.isEmpty {
                staggeredRow(
                    title: "全集完结",
                    trailing: "一次刷完 · \(completed.count) 部",
                    items: Array(completed.prefix(14)),
                    cardWidth: mediumWidth,
                    plateHeight: RDAlbum.Poster.plateMedium,
                    spacing: wide ? RDAlbum.Space.cardGapWide : RDAlbum.Space.cardGapSmall,
                    leadingPad: leadingPad,
                    trailingPad: trailingPad,
                    inset: 24,
                    subtitle: { item in "全\(item.episodeCount)集" }
                )
            }

            genreCorridor(
                wide: wide,
                leadingPad: leadingPad,
                trailingPad: trailingPad
            )

            discoveryGrid(
                wide: wide,
                contentWidth: contentWidth,
                leadingPad: leadingPad,
                trailingPad: trailingPad
            )
        }
    }

    private func staggeredRow(
        title: String,
        trailing: String?,
        items: [Series],
        cardWidth: CGFloat,
        plateHeight: CGFloat,
        spacing: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat,
        inset: CGFloat,
        subtitle: ((Series) -> String?)? = nil,
        showScore: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
            RDAlbumSectionHeader(title: title, trailing: trailing, showsChevron: false)
                .padding(.horizontal, leadingPad)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        Button {
                            RDHaptics.shared.playResumeCardTap()
                            path.append(item)
                        } label: {
                            RDAlbumPosterCard(
                                series: item,
                                width: cardWidth,
                                plateHeight: plateHeight,
                                sub: subtitle?(item) ?? nil,
                                badge: item.isJustUpdated ? "更新" : (item.isCompleted ? "完结" : nil),
                                showsScore: showScore
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("series-card-\(item.id)")
                    }
                }
                .padding(.leading, leadingPad + inset)
                .padding(.trailing, trailingPad)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - 挑剧 / 试看快捷条

    private func quickDiscoveryBar(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        HStack(spacing: RDAlbum.Space.cardGapSmall) {
            Button {
                Task { await pickRandomDramaAndPlay() }
            } label: {
                quickDiscoveryCard(
                    icon: "dice.fill",
                    title: "帮我挑一部",
                    subtitle: "随机盲盒开播第 1 集",
                    busy: pickingRandom,
                    media: false
                )
            }
            .buttonStyle(.plain)
            .disabled(pickingRandom || series.isEmpty)

            Button {
                RDHaptics.shared.playGlassTap()
                if let onOpenGoldenHooks {
                    onOpenGoldenHooks()
                } else {
                    showHookModal = true
                }
            } label: {
                quickDiscoveryCard(
                    icon: "flame.fill",
                    title: "第一集黄金钩子",
                    subtitle: "上下滑连刷试看流",
                    busy: false,
                    media: true
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, leadingPad)
    }

    private func quickDiscoveryCard(icon: String, title: String, subtitle: String, busy: Bool, media: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(media ? RDAlbum.C.accentDot.opacity(0.16) : Color.white.opacity(0.14))
                    .frame(width: 38, height: 38)
                if busy {
                    ProgressView().controlSize(.small).tint(RDAlbum.C.textPrimary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(media ? RDAlbum.C.accentDot : RDAlbum.C.textPrimary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RDAlbum.Font.plateName)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: false)
    }

    // MARK: - 题材胶囊

    @ViewBuilder
    private func genreCorridor(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let tags = catalog.sortedTags(from: series + topRank, limit: 16)
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
                RDAlbumSectionHeader(
                    title: "题材走廊",
                    trailing: selectedTag.map { "筛选：\($0)" } ?? "点击标签筛选",
                    showsChevron: false
                )
                .padding(.horizontal, leadingPad)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        genreChipCapsule(title: "全部", active: selectedTag == nil) {
                            RDHaptics.shared.playChipSelect()
                            withAnimation(RDAlbum.Motion.rearrange) { selectedTag = nil }
                        }
                        ForEach(tags, id: \.self) { tag in
                            let active = selectedTag == tag
                            genreChipCapsule(title: tag, active: active) {
                                RDHaptics.shared.playChipSelect()
                                withAnimation(RDAlbum.Motion.rearrange) {
                                    selectedTag = active ? nil : tag
                                }
                                if !active && hasMore {
                                    Task { await triggerLoadMore(fromScrollBottom: false) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, leadingPad)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func genreChipCapsule(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RDAlbum.Font.rounded(13, .semibold))
                .foregroundStyle(active ? RDAlbum.C.inverse : RDAlbum.C.textPrimary.opacity(0.88))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    if active {
                        Capsule(style: .continuous).fill(Color.white)
                            .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
                    } else {
                        Capsule(style: .continuous)
                            .fill(rdAlbumAdaptiveGlassFill())
                            .overlay(Capsule(style: .continuous).strokeBorder(rdAlbumAdaptiveGlassStroke(), lineWidth: 0.6))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func rdAlbumAdaptiveGlassFill() -> Color {
        Color(uiColor: rdAlbumAdaptiveUI(light: UIColor.white.withAlphaComponent(0.62), dark: UIColor.white.withAlphaComponent(0.12)))
    }

    private func rdAlbumAdaptiveGlassStroke() -> Color {
        Color(uiColor: rdAlbumAdaptiveUI(light: UIColor.black.withAlphaComponent(0.07), dark: UIColor.white.withAlphaComponent(0.16)))
    }

    // MARK: - 无限探索网格

    @ViewBuilder
    private func discoveryGrid(wide: Bool, contentWidth: CGFloat, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let activeTag = selectedTag
        let items: [Series] = activeTag.map { tag in
            catalog.mergedSeries(primary: series + topRank).filter { $0.tags.contains(tag) }
        } ?? Array(series.dropFirst())
        let title: String = activeTag.map { "题材筛选 · \($0)" }
            ?? (wide ? "全部漫剧 · 无限探索" : "无限探索")

        let spacing: CGFloat = wide ? RDAlbum.Space.cardGapWide : RDAlbum.Space.cardGapSmall
        let cols = RD.gridColumns(
            contentWidth: contentWidth,
            minCardWidth: wide ? 140 : 104,
            spacing: spacing
        )
        let count = max(cols.count, 1)
        let cardWidth = max(80, (contentWidth - spacing * CGFloat(count - 1)) / CGFloat(count))

        VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
            RDAlbumSectionHeader(title: title, trailing: "共 \(items.count) 部", showsChevron: false)
                .padding(.horizontal, leadingPad)

            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(RDAlbum.C.textTertiary)
                    Text("暂无该题材漫剧")
                        .font(RDAlbum.Font.body)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                    Button("查看全部") {
                        RDHaptics.shared.playChipSelect()
                        withAnimation(RDAlbum.Motion.rearrange) { selectedTag = nil }
                    }
                    .buttonStyle(RDAlbumGlassPillStyle(height: 38, horizontalPadding: 18))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count),
                    alignment: .leading,
                    spacing: wide ? 24 : 22
                ) {
                    ForEach(items) { item in
                        Button {
                            RDHaptics.shared.playResumeCardTap()
                            path.append(item)
                        } label: {
                            RDAlbumPosterCard(
                                series: item,
                                width: cardWidth,
                                plateHeight: RDAlbum.Poster.plateMedium,
                                badge: item.isJustUpdated ? "更新" : (item.isCompleted ? "完结" : nil)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("series-card-\(item.id)")
                        .onAppear {
                            Task { await loadMoreIfNeeded(for: item) }
                        }
                    }
                }
                .padding(.horizontal, leadingPad)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task { await triggerLoadMore(fromScrollBottom: true) }
                }
        }
    }

    @ViewBuilder
    private func feedFooter(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(spacing: 8) {
            if loadingMore {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(RDAlbum.C.textPrimary)
                    Text("正在发现更多漫剧…")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                }
                .padding(.vertical, 12)
            } else if !hasMore && !series.isEmpty {
                Text("已展示全部 \(series.count) 部推荐漫剧")
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.textTertiary)
                    .padding(.vertical, 12)
                    .onAppear {
                        if !didFireFeedEndHaptic {
                            didFireFeedEndHaptic = true
                            RDHaptics.shared.playFeedEndReached()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, leadingPad)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(RDAlbum.C.textSecondary)
            Text(message)
                .font(RDAlbum.Font.body)
                .foregroundStyle(RDAlbum.C.textSecondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                RDHaptics.shared.playRetryTap()
                Task { await load(force: true) }
            }
            .buttonStyle(RDAlbumPrimaryPillStyle(height: 42, horizontalPadding: 28))
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.horizontal, 20)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(RDAlbum.C.textTertiary)
            Text("暂无漫剧")
                .font(RDAlbum.Font.body)
                .foregroundStyle(RDAlbum.C.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - 数据拉取、随机挑剧与无限分页（1.4.7 原逻辑保留）

    private func load(force: Bool) async {
        if !force && loading { return }
        loadGeneration += 1
        let gen = loadGeneration

        loading = true
        loadingMore = false
        hasMore = true
        consecutiveEmptyPages = 0
        didFireFeedEndHaptic = false
        error = nil
        if force {
            series = []
            topRank = []
            feedCursor = nil
        }

        do {
            async let feedTask = ManjuAPI.shared.homeFeedFirstPage()
            async let rankTask = ManjuAPI.shared.homeTopRank()
            let (page, rank) = try await (feedTask, rankTask)
            guard gen == loadGeneration else { return }
            let dedupFeed = deduplicateSeries(page.items)
            let dedupRank = deduplicateSeries(rank)
            CatalogCache.shared.ingest(dedupFeed)
            CatalogCache.shared.ingest(dedupRank)
            withAnimation(RDAlbum.Motion.glow) {
                series = dedupFeed
                topRank = dedupRank
            }
            feedCursor = page.cursor
            hasMore = page.cursor.hasMore

            if auth.isLoggedIn, let uid = auth.session?.user.userID {
                Task {
                    if let shelf = try? await ManjuAPI.shared.fetchBookshelf(uid: uid) {
                        FollowStore.shared.syncBookshelf(shelf)
                    }
                }
            }
            AppLog.write("HOME UI updated count=\(series.count) rank=\(topRank.count) hasMore=\(hasMore)")
        } catch {
            guard gen == loadGeneration else { return }
            self.error = error.localizedDescription
            AppLog.write("HOME UI error=\(error.localizedDescription)")
        }
        if gen == loadGeneration {
            loading = false
        }
    }

    private func loadMoreIfNeeded(for item: Series) async {
        guard !loading, !loadingMore, hasMore else { return }
        guard let idx = series.firstIndex(where: { $0.id == item.id }) else { return }
        guard idx >= max(0, series.count - 6) else { return }
        await triggerLoadMore(fromScrollBottom: true)
    }

    private func triggerLoadMore(fromScrollBottom: Bool) async {
        guard !loading, !loadingMore, hasMore, let cursor = feedCursor else { return }
        guard cursor.hasMore else {
            hasMore = false
            return
        }
        let gen = loadGeneration
        loadingMore = true
        if fromScrollBottom {
            RDHaptics.shared.playPaginationFetch()
        }
        defer {
            if gen == loadGeneration {
                loadingMore = false
            }
        }

        do {
            let next = try await ManjuAPI.shared.homeFeedNextPage(cursor: cursor)
            guard gen == loadGeneration else { return }

            CatalogCache.shared.ingest(next.items)
            let existingIDs = Set(series.map(\.id))
            let uniqueNew = next.items.filter { !existingIDs.contains($0.id) }
            if !uniqueNew.isEmpty {
                series.append(contentsOf: uniqueNew)
                consecutiveEmptyPages = 0
            } else {
                consecutiveEmptyPages += 1
            }

            var updatedCursor = next.cursor
            updatedCursor.seenIDs = series.map(\.id)
            feedCursor = updatedCursor

            if !next.cursor.hasMore || consecutiveEmptyPages >= 2 {
                hasMore = false
            }
            AppLog.write("HOME UI loadMore added=\(uniqueNew.count) total=\(series.count) hasMore=\(hasMore)")
        } catch {
            guard gen == loadGeneration else { return }
            hasMore = false
            AppLog.write("HOME UI loadMore stopped silently error=\(error.localizedDescription)")
        }
    }

    private func deduplicateSeries(_ list: [Series]) -> [Series] {
        var seen = Set<String>()
        var out: [Series] = []
        for item in list where !item.id.isEmpty && !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
        }
        return out
    }

    private func openBingeItem(_ item: BingeQueueItem) async {
        guard loadingResumeID == nil else { return }
        loadingResumeID = item.series.id
        let entry = item.resumeEntry
        AppLog.write("HOME binge tap series=\(item.series.id) ep=\(item.currentEpisodeIndex) remaining=\(item.remainingEpisodes)")
        do {
            let detail = try await ManjuAPI.shared.album(seriesID: item.series.id)
            CatalogCache.shared.ingestAlbum(detail)
            FollowStore.shared.markSeenEpisodeCount(for: detail.series)
            let startIdx: Int
            if let entry {
                startIdx = detail.episodes.firstIndex(where: { $0.vid == entry.lastVid || $0.index == entry.lastIndex }) ?? 0
            } else {
                startIdx = 0
            }
            resumeTarget = ResumeTarget(series: detail.series, episodes: detail.episodes, startIndex: startIdx)
        } catch {
            if let entry {
                let fallbackEp = Episode(vid: entry.lastVid, index: entry.lastIndex,
                                         title: "第\(entry.lastIndex)集", cover: entry.cover,
                                         duration: Int(entry.lastDuration), seriesID: entry.seriesID)
                resumeTarget = ResumeTarget(series: item.series, episodes: [fallbackEp], startIndex: 0)
            } else if let vid = item.series.firstVid {
                let fallbackEp = Episode(vid: vid, index: item.series.firstIndex,
                                         title: "第\(item.series.firstIndex)集", cover: item.series.cover,
                                         duration: item.series.estimatedEpisodeDuration, seriesID: item.series.id)
                resumeTarget = ResumeTarget(series: item.series, episodes: [fallbackEp], startIndex: 0)
            }
        }
        loadingResumeID = nil
    }

    private func openHistoryEntry(_ entry: HistoryEntry) async {
        guard loadingResumeID == nil else { return }
        loadingResumeID = entry.seriesID
        do {
            let detail = try await ManjuAPI.shared.album(seriesID: entry.seriesID)
            CatalogCache.shared.ingestAlbum(detail)
            let startIdx = detail.episodes.firstIndex(where: { $0.vid == entry.lastVid || $0.index == entry.lastIndex }) ?? 0
            resumeTarget = ResumeTarget(series: detail.series, episodes: detail.episodes, startIndex: startIdx)
        } catch {
            let fallbackSeries = Series(
                id: entry.seriesID, title: entry.title, cover: entry.cover, intro: entry.intro,
                episodeCount: entry.episodeCount, firstVid: entry.lastVid, firstIndex: entry.lastIndex,
                updatedAt: entry.updatedAt
            )
            let fallbackEp = Episode(vid: entry.lastVid, index: entry.lastIndex,
                                     title: "第\(entry.lastIndex)集", cover: entry.cover,
                                     duration: Int(entry.lastDuration), seriesID: entry.seriesID)
            resumeTarget = ResumeTarget(series: fallbackSeries, episodes: [fallbackEp], startIndex: 0)
        }
        loadingResumeID = nil
    }

    private func pickRandomDramaAndPlay() async {
        guard !pickingRandom else { return }
        let pool = catalog.mergedSeries(primary: series + topRank)
        let watchedIDs = Set(history.entries.map(\.seriesID))
        let unwatched = pool.filter { !watchedIDs.contains($0.id) && $0.id != lastRandomPickedID }
        let candidates = unwatched.isEmpty ? pool.filter { $0.id != lastRandomPickedID } : unwatched
        guard let picked = (candidates.isEmpty ? pool : candidates).randomElement() else { return }

        pickingRandom = true
        lastRandomPickedID = picked.id
        RDHaptics.shared.playSurprisePick()
        AppLog.write("HOME surprise_pick series=\(picked.id) title=\(picked.title)")

        do {
            let detail = try await ManjuAPI.shared.album(seriesID: picked.id)
            CatalogCache.shared.ingestAlbum(detail)
            resumeTarget = ResumeTarget(series: detail.series, episodes: detail.episodes, startIndex: 0)
        } catch {
            if let vid = picked.firstVid {
                let ep = Episode(vid: vid, index: picked.firstIndex, title: "第\(picked.firstIndex)集",
                                 cover: picked.cover, duration: picked.estimatedEpisodeDuration, seriesID: picked.id)
                resumeTarget = ResumeTarget(series: picked, episodes: [ep], startIndex: 0)
            }
        }
        pickingRandom = false
    }
}

/// 下拉视差时给 Hero 叠一层极轻的亮部提升（1.12× 亮 +8% 的近似实现）。
private struct RDAlbumTintPlaceholderTint: View {
    let intensity: Double
    var body: some View {
        Color.white.opacity(0.08 * min(max(intensity / 0.22, 0), 1))
            .blendMode(.softLight)
            .allowsHitTesting(false)
    }
}

// 供 AlbumTheme 在视图内使用的自适应玻璃色（不引入额外依赖）。
private func rdAlbumAdaptiveUI(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    }
}
