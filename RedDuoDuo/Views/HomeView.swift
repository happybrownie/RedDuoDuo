import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var history: WatchHistory
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var catalog = CatalogCache.shared

    var onOpenGoldenHooks: (() -> Void)? = nil

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
    @State private var lastTopRankSnapBucket = -1
    @State private var lastTopRankOffset: CGFloat = 0
    @State private var lastTopRankSampleTime: TimeInterval = 0
    @State private var didBounceEdge = false
    @State private var didBounceTopRankEdge = false

    private struct ResumeTarget: Identifiable {
        let id = UUID()
        let series: Series
        let episodes: [Episode]
        let startIndex: Int
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                RD.Palette.background.ignoresSafeArea()
                RDSafeAreaProbe(insets: $safeInsets)

                GeometryReader { fullGeo in
                    let fullWidth = fullGeo.size.width
                    let wide = RD.isWide(fullWidth)
                    let horiz = RDLayoutInsets.horizontal(in: fullGeo)
                    let leadingPad = horiz.leading
                    let trailingPad = horiz.trailing
                    let contentWidth = max(1, fullWidth - leadingPad - trailingPad)
                    let topBarHeight = max(safeInsets.top + 52, 64)

                    ZStack(alignment: .top) {
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: RD.Space.xl) {
                                    Color.clear.frame(height: 0).id("home-top-anchor")

                                    if let notice = auth.sessionExpiredNotice {
                                        RDNotice(text: notice, actionTitle: "重新登录") {
                                            RDHaptics.shared.playGlassTap()
                                            auth.clearExpiredNotice()
                                            auth.showLoginSheet = true
                                        }
                                        .padding(.leading, leadingPad)
                                        .padding(.trailing, trailingPad)
                                        .padding(.top, topBarHeight + 8)
                                    }

                                    if loading && series.isEmpty {
                                        RDHomeSkeletonView(
                                            width: fullWidth,
                                            wide: wide,
                                            leadingPad: leadingPad,
                                            trailingPad: trailingPad
                                        )
                                        .padding(.top, topBarHeight + 8)
                                    } else if let error, series.isEmpty {
                                        errorView(error)
                                            .padding(.top, topBarHeight + 24)
                                    } else if series.isEmpty {
                                        emptyView
                                            .padding(.top, topBarHeight + 24)
                                    } else {
                                        // 响应式 Hero：大屏为网飞式内嵌圆角宽卡；小屏高度收紧、按宽度完整显示海报且标题区错开压暗
                                        let showcasePool = Array(series.prefix(5))
                                        let hero = showcasePool.isEmpty ? series[0] : showcasePool[heroIndexOffset % showcasePool.count]
                                        heroShowcaseSection(
                                            hero: hero,
                                            showcasePool: showcasePool,
                                            wide: wide,
                                            contentWidth: contentWidth,
                                            availableHeight: fullGeo.size.height,
                                            leadingPad: leadingPad,
                                            trailingPad: trailingPad,
                                            topInset: topBarHeight + 6
                                        )

                                        // A4: 首页置顶「在追片单」（剩 X 集未看 + 刚更新/已完结徽标）
                                        let queue = followStore.bingeQueue(history: history.entries, catalog: catalog.byID)
                                        if !queue.isEmpty {
                                            bingeQueueSection(queue, leadingPad: leadingPad, trailingPad: trailingPad)
                                        }

                                        // A11 & A9: 「帮我挑一部」随机开剧 + 「第一集黄金钩子」试看切片入口
                                        quickDiscoveryBar(wide: wide, leadingPad: leadingPad, trailingPad: trailingPad)

                                        if !topRank.isEmpty {
                                            topRankSection(leadingPad: leadingPad, trailingPad: trailingPad)
                                        }

                                        // A11: 按时长片单行（半小时刷完 / 全集完结）
                                        durationShelvesSection(leadingPad: leadingPad, trailingPad: trailingPad)

                                        // A10: 题材走廊（标签可点筛选）
                                        genreCorridorSection(leadingPad: leadingPad, trailingPad: trailingPad)

                                        discoveryContent(
                                            wide: wide,
                                            contentWidth: contentWidth,
                                            leadingPad: leadingPad,
                                            trailingPad: trailingPad
                                        )

                                        feedFooter(leadingPad: leadingPad, trailingPad: trailingPad)
                                    }
                                }
                                .frame(width: fullWidth, alignment: .leading)
                            }
                            .onScrollGeometryChange(for: CGFloat.self) { geo in
                                geo.contentOffset.y + geo.contentInsets.top
                            } action: { _, offset in
                                scrollOffset = offset
                                let crossed = offset > 28
                                if crossed && !wasScrolledPastTopBar {
                                    RDHaptics.shared.playStickyBarCrossed()
                                }
                                wasScrolledPastTopBar = crossed
                            }
                            .refreshable {
                                RDHaptics.shared.playPullRefreshTriggered()
                                await load(force: true)
                                RDHaptics.shared.playPullRefreshComplete()
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                if let tab = note.object as? Int, tab == 0 {
                                    withAnimation(RD.Motion.snappy) {
                                        scrollProxy.scrollTo("home-top-anchor", anchor: .top)
                                    }
                                }
                            }
                        }

                        topBar(wide: wide, leadingPad: leadingPad, trailingPad: trailingPad)
                    }
                    .frame(width: fullWidth)
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

    // MARK: 顶栏（安全区自适应 + 随滚动渐入磨砂黑底）

    private func topBar(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let scrolled = scrollOffset > 28
        return HStack(spacing: 8) {
            HStack(spacing: 9) {
                RDGemPlayMark(size: 28)
                Text("红果漫剧")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(RD.Palette.textPrimary)
                    .rdTitleShadow()
            }

            Spacer(minLength: 6)

            // A9: 试看切片入口
            Button {
                RDHaptics.shared.playGlassTap()
                if let onOpenGoldenHooks {
                    onOpenGoldenHooks()
                } else {
                    showHookModal = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RD.Palette.gemAccentText)
                    Text(wide ? "第一集试看" : "试看")
                        .font(RD.Font.caption.weight(.bold))
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .rdGlassCircleCapsule()
            }
            .buttonStyle(RDPosterButtonStyle())

            // A11: 帮我挑一部
            Button {
                Task { await pickRandomDramaAndPlay() }
            } label: {
                HStack(spacing: 4) {
                    if pickingRandom {
                        ProgressView().controlSize(.mini).tint(RD.Palette.textPrimary)
                    } else {
                        Image(systemName: "dice.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(RD.Palette.platinum)
                    }
                    Text(wide ? "帮我挑一部" : "挑剧")
                        .font(RD.Font.caption.weight(.bold))
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .rdGlassCircleCapsule()
            }
            .buttonStyle(RDPosterButtonStyle())
            .disabled(pickingRandom || series.isEmpty)

            Button {
                RDHaptics.shared.playPullRefreshTriggered()
                Task {
                    await load(force: true)
                    RDHaptics.shared.playPullRefreshComplete()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .rdGlassCircle()
            }
            .buttonStyle(RDPosterButtonStyle())
            .accessibilityLabel("刷新")
        }
        .padding(.top, max(safeInsets.top + 6, 12))
        .padding(.bottom, 10)
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
        .background {
            RDStickyTopBarBackground(scrolled: scrolled)
        }
        .animation(RD.Motion.fade, value: scrolled)
    }

    // MARK: Hero（大屏网飞式内嵌圆角卡 / 小屏收紧高度完整呈宽防重字）

    @ViewBuilder
    private func heroShowcaseSection(
        hero: Series,
        showcasePool: [Series],
        wide: Bool,
        contentWidth: CGFloat,
        availableHeight: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat,
        topInset: CGFloat
    ) -> some View {
        if wide {
            wideNetflixHeroCard(
                hero: hero,
                showcasePool: showcasePool,
                cardWidth: contentWidth,
                availableHeight: availableHeight
            )
            .padding(.top, topInset)
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        } else {
            compactHeroSection(
                hero: hero,
                showcasePool: showcasePool,
                cardWidth: contentWidth
            )
            .padding(.top, topInset)
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        }
    }

    private func wideNetflixHeroCard(
        hero: Series,
        showcasePool: [Series],
        cardWidth: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        let maxViewportCardH = max(290, min(450, availableHeight * 0.66))
        let cardHeight = min(max(cardWidth * 0.48, 300), maxViewportCardH)
        let cardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return ZStack(alignment: .bottomLeading) {
            RDHeroArtworkView(
                coverURL: hero.cover,
                landscapeURL: hero.landscapeCover,
                wide: true,
                width: cardWidth,
                artworkHeight: cardHeight
            )

            // 左侧标题护底 + 底部温和压暗，确保左下角文案与胶囊按钮高对比可读
            LinearGradient(
                stops: [
                    .init(color: Color(red: 14/255, green: 14/255, blue: 16/255).opacity(0.92), location: 0.0),
                    .init(color: Color(red: 14/255, green: 14/255, blue: 16/255).opacity(0.70), location: 0.36),
                    .init(color: Color(red: 14/255, green: 14/255, blue: 16/255).opacity(0.22), location: 0.56),
                    .init(color: .clear, location: 0.76)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.46),
                    .init(color: Color.black.opacity(0.45), location: 0.74),
                    .init(color: Color.black.opacity(0.84), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // 顶部卡片标识与换主推切换胶囊
            VStack {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        RDGemPlayMark(size: 18)
                        Text("今日主推")
                            .font(RD.Font.micro)
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))

                    Spacer()

                    if showcasePool.count > 1 {
                        Button {
                            RDHaptics.shared.playChipSelect()
                            withAnimation(RD.Motion.snappy) { heroIndexOffset += 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text("换主推 · \((heroIndexOffset % showcasePool.count) + 1)/\(showcasePool.count)")
                            }
                            .font(RD.Font.micro)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.48), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6))
                        }
                        .buttonStyle(RDPosterButtonStyle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()
            }

            // 网飞式左下锚定区：标题 / 元信息 / 简介(<=45%宽、<=3行) / 胶囊双按钮
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    RDBadgePill(text: hero.badge.isEmpty ? "漫剧精选" : hero.badge, accent: true)
                    if !hero.seasonTag.isEmpty {
                        RDBadgePill(text: hero.seasonTag, accent: false)
                    }
                    if !hero.score.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(RD.Palette.mediaSilver)
                            Text(hero.score)
                                .font(RD.Font.micro)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.62), in: Capsule())
                    }
                }

                Text(hero.title)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: cardWidth * 0.48, alignment: .leading)
                    .rdMediaShadow()

                Text(heroMetaLine(hero))
                    .font(RD.Font.caption.weight(.semibold))
                    .foregroundStyle(RD.Palette.mediaTextSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: cardWidth * 0.48, alignment: .leading)
                    .rdMediaShadow()

                if !hero.intro.isEmpty {
                    Text(hero.intro)
                        .font(RD.Font.body)
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: cardWidth * 0.45, alignment: .leading)
                }

                HStack(spacing: 12) {
                    NavigationLink(value: hero) {
                        Label("立即播放", systemImage: "play.fill")
                    }
                    .buttonStyle(RDGemPrimaryButtonStyle(minHeight: 42, capsule: true, haptics: true))
                    .accessibilityIdentifier("series-card-\(hero.id)")

                    NavigationLink(value: hero) {
                        Label("详情", systemImage: "info.circle")
                    }
                    .buttonStyle(RDGlassHeroButtonStyle(minHeight: 42, capsule: true, mediaOverlay: true))
                    .simultaneousGesture(TapGesture().onEnded {
                        RDHaptics.shared.playGlassHeroTap()
                    })
                }
                .padding(.top, 4)
            }
            .padding(.leading, 22)
            .padding(.bottom, 20)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(cardShape)
        .overlay(
            cardShape.strokeBorder(
                RD.Gem.posterBorderGradient,
                lineWidth: 0.75
            )
        )
        .shadow(color: RD.Palette.posterShadow, radius: 14, y: 6)
    }

    private func compactHeroSection(
        hero: Series,
        showcasePool: [Series],
        cardWidth: CGFloat
    ) -> some View {
        let artworkHeight = min(max(cardWidth * 0.88, 250), 315)
        let totalHeight = artworkHeight + 96

        return ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                RDHeroArtworkView(
                    coverURL: hero.cover,
                    landscapeURL: hero.landscapeCover,
                    wide: false,
                    width: cardWidth,
                    artworkHeight: artworkHeight
                )
                .overlay(alignment: .topTrailing) {
                    if showcasePool.count > 1 {
                        Button {
                            RDHaptics.shared.playChipSelect()
                            withAnimation(RD.Motion.snappy) { heroIndexOffset += 1 }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9, weight: .bold))
                                Text("换主推")
                            }
                            .font(RD.Font.micro)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.58), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6))
                        }
                        .buttonStyle(RDPosterButtonStyle())
                        .padding(10)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: cardWidth, height: totalHeight)

            // 强渐变压暗：彻底压暗/淡出海报底部自带标题区，让 UI 标题与主体错开、绝不两层字打架
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.24),
                    .init(color: RD.Palette.background.opacity(0.45), location: 0.44),
                    .init(color: RD.Palette.background.opacity(0.88), location: 0.60),
                    .init(color: RD.Palette.background, location: 0.74),
                    .init(color: RD.Palette.background, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    RDBadgePill(text: hero.badge.isEmpty ? "漫剧精选" : hero.badge, accent: true)
                    if !hero.seasonTag.isEmpty {
                        RDBadgePill(text: hero.seasonTag, accent: false)
                    }
                    if !hero.score.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(RD.Palette.mediaSilver)
                            Text(hero.score)
                                .font(RD.Font.micro)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.62), in: Capsule())
                    }
                }

                Text(hero.title)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(RD.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .rdTitleShadow()

                Text(heroMetaLine(hero))
                    .font(RD.Font.caption.weight(.semibold))
                    .foregroundStyle(RD.Palette.textSecondary)
                    .lineLimit(1)

                if !hero.intro.isEmpty {
                    Text(hero.intro)
                        .font(RD.Font.caption)
                        .foregroundStyle(RD.Palette.textSecondary.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 10) {
                    NavigationLink(value: hero) {
                        Label("立即播放", systemImage: "play.fill")
                    }
                    .buttonStyle(RDGemPrimaryButtonStyle(minHeight: 40, capsule: true, haptics: true))
                    .accessibilityIdentifier("series-card-\(hero.id)")

                    NavigationLink(value: hero) {
                        Label("详情", systemImage: "info.circle")
                    }
                    .buttonStyle(RDGlassHeroButtonStyle(minHeight: 40, capsule: true, mediaOverlay: false))
                    .simultaneousGesture(TapGesture().onEnded {
                        RDHaptics.shared.playGlassHeroTap()
                    })
                }
                .padding(.top, 3)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .frame(width: cardWidth, height: totalHeight)
    }

    private func heroMetaLine(_ hero: Series) -> String {
        var parts: [String] = []
        if !hero.tags.isEmpty {
            parts.append(contentsOf: hero.tags.prefix(3))
        } else {
            parts.append("漫剧")
        }
        parts.append("共\(hero.episodeCount)集")
        parts.append("免费观看")
        return parts.joined(separator: " · ")
    }

    // MARK: A4 首页置顶「在追片单」（剩 X 集未看 + 刚更新/已完结徽标）

    private func bingeQueueSection(_ items: [BingeQueueItem], leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            RDSectionHeader(
                title: "在追片单",
                trailing: "\(items.count) 部在追 · 点击直接续播",
                accentMark: true
            )
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: RD.Space.md) {
                    ForEach(items.prefix(15)) { item in
                        Button {
                            RDHaptics.shared.playResumeCardTap()
                            Task { await openBingeItem(item) }
                        } label: {
                            BingeQueueCard(item: item, isLoading: loadingResumeID == item.series.id)
                                .frame(width: 128)
                        }
                        .buttonStyle(RDPosterButtonStyle())
                        .accessibilityIdentifier("continue-card-\(item.series.id)")
                    }
                }
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x
            } action: { _, x in
                if x < -14 {
                    if !didBounceEdge {
                        didBounceEdge = true
                        RDHaptics.shared.playShelfEdgeBounce()
                    }
                } else {
                    didBounceEdge = false
                }
            }
        }
        .accessibilityIdentifier("continue-watching-section")
    }

    // MARK: A9 & A11 黄金试看 + 帮我挑一部

    private func quickDiscoveryBar(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let stack = Group {
            Button {
                Task { await pickRandomDramaAndPlay() }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RDGemFacetSurface(
                            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                            shadowRadius: 5,
                            borderWidth: 0.85
                        )
                        .frame(width: 42, height: 42)
                        if pickingRandom {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "dice.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("帮我挑一部")
                            .font(RD.Font.headline.weight(.bold))
                            .foregroundStyle(RD.Palette.textPrimary)
                        Text("随机盲盒开播第 1 集")
                            .font(.caption2)
                            .foregroundStyle(RD.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(RD.Palette.gemAccentText)
                }
                .padding(12)
                .rdGemCard(radius: RD.Radius.card, fill: RD.Palette.surface, glow: true)
            }
            .buttonStyle(RDPosterButtonStyle())
            .disabled(pickingRandom || series.isEmpty)

            Button {
                RDHaptics.shared.playGlassTap()
                if let onOpenGoldenHooks {
                    onOpenGoldenHooks()
                } else {
                    showHookModal = true
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(RD.Palette.surfaceRaised)
                            .frame(width: 42, height: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.8)
                            )
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(RD.Palette.gemCaustic)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("第一集黄金钩子")
                            .font(RD.Font.headline.weight(.bold))
                            .foregroundStyle(RD.Palette.textPrimary)
                        Text("上下滑连刷第 1 集试看流")
                            .font(.caption2)
                            .foregroundStyle(RD.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(RD.Palette.platinum.opacity(0.75))
                }
                .padding(12)
                .rdGemCard(radius: RD.Radius.card, fill: RD.Palette.surface, glow: false)
            }
            .buttonStyle(RDPosterButtonStyle())
        }

        return Group {
            if wide {
                HStack(spacing: RD.Space.md) { stack }
            } else {
                HStack(spacing: RD.Space.sm) { stack }
            }
        }
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
    }

    // MARK: Top 10 数字榜单

    private func topRankSection(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            RDSectionHeader(title: "漫剧热播 Top 10", trailing: "实时热度榜", accentMark: true)
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: RD.Space.md) {
                    ForEach(Array(topRank.prefix(10).enumerated()), id: \.element.id) { idx, item in
                        NavigationLink(value: item) {
                            TopRankCard(rank: idx + 1, series: item)
                        }
                        .buttonStyle(RDPosterButtonStyle())
                        .accessibilityIdentifier("rank-card-\(item.id)")
                    }
                }
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)
            }
            .onScrollGeometryChange(for: CGPoint.self) { geo in
                CGPoint(x: geo.contentOffset.x, y: max(0, geo.contentSize.width - geo.containerSize.width))
            } action: { _, pt in
                let x = pt.x
                let maxX = pt.y
                let now = CACurrentMediaTime()
                let dt = max(now - lastTopRankSampleTime, 0.016)
                let velocity = Double(x - lastTopRankOffset) / dt
                lastTopRankOffset = x
                lastTopRankSampleTime = now

                let bucket = Int(max(0, x) / 145)
                if bucket != lastTopRankSnapBucket {
                    lastTopRankSnapBucket = bucket
                    RDHaptics.shared.playTopRankSnap(velocity: velocity)
                }
                let pastEdge = x < -14 || (maxX > 20 && x > maxX + 14)
                if pastEdge {
                    if !didBounceTopRankEdge {
                        didBounceTopRankEdge = true
                        RDHaptics.shared.playShelfEdgeBounce()
                    }
                } else {
                    didBounceTopRankEdge = false
                }
            }
        }
    }

    // MARK: A11 按时长片单行（半小时刷完 / 全集完结）

    @ViewBuilder
    private func durationShelvesSection(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let allKnown = catalog.mergedSeries(primary: series + topRank)
        let halfHour = allKnown.filter { catalog.isHalfHourBinge($0) }
        let completed = allKnown.filter { $0.isCompleted }

        if !halfHour.isEmpty {
            VStack(alignment: .leading, spacing: RD.Space.sm) {
                RDSectionHeader(title: "半小时刷完", trailing: "短篇轻追 · \(halfHour.count) 部", accentMark: true)
                    .padding(.leading, leadingPad)
                    .padding(.trailing, trailingPad)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: RD.Space.md) {
                        ForEach(halfHour.prefix(14)) { item in
                            NavigationLink(value: item) {
                                DurationCuratedCard(series: item, hint: catalog.durationHintText(for: item) ?? "短篇速看")
                                    .frame(width: 122)
                            }
                            .buttonStyle(RDPosterButtonStyle())
                            .accessibilityIdentifier("series-card-\(item.id)")
                        }
                    }
                    .padding(.leading, leadingPad)
                    .padding(.trailing, trailingPad)
                }
            }
        }

        if !completed.isEmpty {
            VStack(alignment: .leading, spacing: RD.Space.sm) {
                RDSectionHeader(title: "全集完结 · 一次刷完", trailing: "已完结 \(completed.count) 部", accentMark: true)
                    .padding(.leading, leadingPad)
                    .padding(.trailing, trailingPad)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: RD.Space.md) {
                        ForEach(completed.prefix(14)) { item in
                            NavigationLink(value: item) {
                                DurationCuratedCard(series: item, hint: "已完结 · 全\(item.episodeCount)集")
                                    .frame(width: 122)
                            }
                            .buttonStyle(RDPosterButtonStyle())
                            .accessibilityIdentifier("series-card-\(item.id)")
                        }
                    }
                    .padding(.leading, leadingPad)
                    .padding(.trailing, trailingPad)
                }
            }
        }
    }

    // MARK: A10 题材走廊（标签可点筛选）

    @ViewBuilder
    private func genreCorridorSection(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let tags = catalog.sortedTags(from: series + topRank, limit: 16)
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: RD.Space.sm) {
                RDSectionHeader(
                    title: "题材走廊",
                    trailing: selectedTag.map { "筛选：\($0)" } ?? "点击标签筛选",
                    showsChevron: false,
                    accentMark: true
                )
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        genreChip(title: "全部", active: selectedTag == nil) {
                            RDHaptics.shared.playChipSelect()
                            withAnimation(RD.Motion.snappy) { selectedTag = nil }
                        }

                        ForEach(tags, id: \.self) { tag in
                            let active = selectedTag == tag
                            genreChip(title: tag, active: active) {
                                RDHaptics.shared.playChipSelect()
                                withAnimation(RD.Motion.snappy) {
                                    selectedTag = active ? nil : tag
                                }
                                if !active && hasMore {
                                    Task { await triggerLoadMore(fromScrollBottom: false) }
                                }
                            }
                        }
                    }
                    .padding(.leading, leadingPad)
                    .padding(.trailing, trailingPad)
                }
            }
        }
    }

    private func genreChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RD.Font.caption.weight(.bold))
                .foregroundStyle(active ? .white : RD.Palette.textPrimary.opacity(0.86))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    if active {
                        RDGemFacetSurface(shape: Capsule(style: .continuous), shadowRadius: 4, borderWidth: 0.8)
                    } else {
                        Capsule()
                            .fill(RD.Palette.surfaceRaised)
                            .overlay(Capsule().strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.7))
                    }
                }
        }
        .buttonStyle(RDPosterButtonStyle())
    }

    // MARK: 推荐内容

    @ViewBuilder
    private func discoveryContent(
        wide: Bool,
        contentWidth: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat
    ) -> some View {
        if let activeTag = selectedTag {
            let pool = catalog.mergedSeries(primary: series + topRank)
            let filtered = pool.filter { $0.tags.contains(activeTag) }
            infinitePosterGrid(
                title: "题材筛选 · \(activeTag)",
                items: filtered,
                wide: wide,
                contentWidth: contentWidth,
                leadingPad: leadingPad,
                trailingPad: trailingPad
            )
        } else {
            let rest = Array(series.dropFirst())
            if rest.isEmpty {
                EmptyView()
            } else if !wide && rest.count > 6 {
                let featured = Array(rest.prefix(6))
                let gridItems = Array(rest.dropFirst(6))
                VStack(alignment: .leading, spacing: RD.Space.xl) {
                    horizontalShelf(
                        title: "热门推荐",
                        trailing: "猜你喜欢",
                        items: featured,
                        leadingPad: leadingPad,
                        trailingPad: trailingPad
                    )
                    infinitePosterGrid(
                        title: "无限探索",
                        items: gridItems,
                        wide: false,
                        contentWidth: contentWidth,
                        leadingPad: leadingPad,
                        trailingPad: trailingPad
                    )
                }
            } else {
                infinitePosterGrid(
                    title: wide ? "全部漫剧 · 无限探索" : "热门推荐",
                    items: rest,
                    wide: wide,
                    contentWidth: contentWidth,
                    leadingPad: leadingPad,
                    trailingPad: trailingPad
                )
            }
        }
    }

    private func horizontalShelf(
        title: String,
        trailing: String?,
        items: [Series],
        leadingPad: CGFloat,
        trailingPad: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            RDSectionHeader(title: title, trailing: trailing, accentMark: true)
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: RD.Space.md) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            SeriesCard(series: item, compact: true)
                                .frame(width: 122)
                        }
                        .buttonStyle(RDPosterButtonStyle())
                        .accessibilityIdentifier("series-card-\(item.id)")
                        .onAppear {
                            Task { await loadMoreIfNeeded(for: item) }
                        }
                    }
                }
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)
            }
        }
    }

    private func infinitePosterGrid(
        title: String,
        items: [Series],
        wide: Bool,
        contentWidth: CGFloat,
        leadingPad: CGFloat,
        trailingPad: CGFloat
    ) -> some View {
        let cols = RD.gridColumns(
            contentWidth: contentWidth,
            minCardWidth: wide ? 132 : 104,
            spacing: RD.Space.md
        )
        return VStack(alignment: .leading, spacing: RD.Space.md) {
            RDSectionHeader(title: title, trailing: "共 \(items.count) 部", accentMark: true)

            if items.isEmpty {
                RDEmptyStateView(
                    systemImage: "tag.slash",
                    title: "暂无该题材漫剧",
                    subtitle: "可以切换其他题材标签或点击全部恢复浏览",
                    actionTitle: "查看全部"
                ) {
                    RDHaptics.shared.playChipSelect()
                    selectedTag = nil
                }
            } else {
                LazyVGrid(columns: cols, alignment: .leading, spacing: RD.Space.lg) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            SeriesCard(series: item)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(RDPosterButtonStyle())
                        .accessibilityIdentifier("series-card-\(item.id)")
                        .onAppear {
                            Task { await loadMoreIfNeeded(for: item) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 宽屏或短列表底部预取哨兵
            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task { await triggerLoadMore(fromScrollBottom: true) }
                }
        }
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func feedFooter(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(spacing: RD.Space.sm) {
            if loadingMore {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(RD.Palette.accent)
                    Text("正在发现更多漫剧…")
                        .font(RD.Font.caption)
                        .foregroundStyle(RD.Palette.textSecondary)
                }
                .padding(.vertical, RD.Space.md)
            } else if !hasMore && !series.isEmpty {
                Text("已展示全部 \(series.count) 部推荐漫剧 · 红果 bookmall\(auth.isLoggedIn ? "（个性推荐）" : "")")
                    .font(RD.Font.micro)
                    .foregroundStyle(RD.Palette.textTertiary)
                    .padding(.vertical, RD.Space.md)
                    .onAppear {
                        if !didFireFeedEndHaptic {
                            didFireFeedEndHaptic = true
                            RDHaptics.shared.playFeedEndReached()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
        .padding(.bottom, RD.Space.xl)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: RD.Space.lg) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(RD.Palette.accent)
            Text(message)
                .font(RD.Font.caption)
                .foregroundStyle(RD.Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                RDHaptics.shared.playRetryTap()
                Task { await load(force: true) }
            }
            .buttonStyle(RDPrimaryButtonStyle())
            .frame(width: 140)
        }
        .padding(RD.Space.xl)
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var emptyView: some View {
        Text("暂无漫剧")
            .font(RD.Font.body)
            .foregroundStyle(RD.Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 360)
    }

    // MARK: 数据拉取、随机挑剧与无限分页

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
            withAnimation(RD.Motion.fade) {
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
            let allSeen = series.map(\.id)
            updatedCursor.seenIDs = allSeen
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
                let fallbackSeries = item.series
                let fallbackEp = Episode(vid: entry.lastVid, index: entry.lastIndex,
                                         title: "第\(entry.lastIndex)集", cover: entry.cover,
                                         duration: Int(entry.lastDuration), seriesID: entry.seriesID)
                resumeTarget = ResumeTarget(series: fallbackSeries, episodes: [fallbackEp], startIndex: 0)
            } else if let vid = item.series.firstVid {
                let fallbackEp = Episode(vid: vid, index: item.series.firstIndex,
                                         title: "第\(item.series.firstIndex)集", cover: item.series.cover,
                                         duration: item.series.estimatedEpisodeDuration, seriesID: item.series.id)
                resumeTarget = ResumeTarget(series: item.series, episodes: [fallbackEp], startIndex: 0)
            }
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

// MARK: - 卡片组件

private struct TopRankCard: View {
    let rank: Int
    let series: Series

    var body: some View {
        let plaqueShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let isTop3 = rank <= 3

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(width: 112, height: 168)
                    .overlay { RemoteCover(url: series.cover) }
                    .overlay(alignment: .topTrailing) {
                        if !series.score.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 7.5))
                                    .foregroundStyle(RD.Palette.mediaSilver)
                                Text(series.score)
                            }
                            .font(RD.Font.micro)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(6)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if !series.badge.isEmpty {
                            RDBadgePill(text: series.badge)
                                .padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: RD.Radius.poster, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: RD.Radius.poster, style: .continuous)
                            .strokeBorder(isTop3 ? RD.Gem.anchorBorderGradient : RD.Gem.posterBorderGradient, lineWidth: isTop3 ? 0.9 : 0.7)
                    }
                    .shadow(color: isTop3 ? RD.Palette.gemGlow : .clear, radius: 6, y: 2)
                    .shadow(color: RD.Palette.posterShadow, radius: 6, y: 3)
                    .padding(.leading, rank >= 10 ? 34 : 26)

                RDRankNumberView(rank: rank)
                    .offset(x: 2, y: 8)
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .background {
                plaqueShape
                    .fill(RD.Palette.surface.opacity(0.92))
                    .overlay {
                        if isTop3 {
                            plaqueShape
                                .fill(
                                    RadialGradient(
                                        colors: [RD.Palette.anchorCardGlowTop, .clear],
                                        center: .bottomLeading,
                                        startRadius: 4,
                                        endRadius: 110
                                    )
                                )
                        }
                    }
                    .overlay {
                        plaqueShape.strokeBorder(
                            isTop3 ? RD.Gem.anchorBorderGradient : RD.Gem.cardBorderGradient,
                            lineWidth: isTop3 ? 0.85 : 0.65
                        )
                    }
            }

            Text(series.title)
                .font(RD.Font.headline)
                .foregroundStyle(RD.Palette.textPrimary)
                .lineLimit(1)
                .padding(.leading, rank >= 10 ? 34 : 26)
                .frame(width: rank >= 10 ? 150 : 142, alignment: .leading)
        }
    }
}

private struct BingeQueueCard: View {
    let item: BingeQueueItem
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteCover(url: item.series.cover) }
                .overlay {
                    ZStack {
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        Color.black.opacity(isLoading ? 0.45 : 0)
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            ZStack {
                                RDGemFacetSurface(shape: Circle(), shadowRadius: 5, borderWidth: 0.9)
                                    .frame(width: 40, height: 40)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(x: 1)
                            }
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let badge = item.statusBadge {
                        RDStatusBadgePill(text: badge, kind: badge == "已完结" ? .completed : .updated)
                            .padding(6)
                    } else if item.isCollected {
                        RDBadgePill(text: "在追", accent: true)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Text(item.remainingEpisodes > 0 ? "剩\(item.remainingEpisodes)集" : "追平")
                        .font(RD.Font.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
                .overlay(alignment: .bottom) {
                    if item.progressFraction > 0 {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.24))
                                Rectangle().fill(RD.Gem.progressGradient).frame(width: g.size.width * item.progressFraction)
                            }
                        }
                        .frame(height: 3.5)
                    }
                }
                .rdGemPosterChrome()

            Text(item.series.title)
                .font(RD.Font.headline)
                .foregroundStyle(RD.Palette.textPrimary)
                .lineLimit(1)

            if item.hasResumeHistory {
                Text("第\(item.currentEpisodeIndex)集 · 剩\(item.remainingEpisodes)集未看")
                    .font(RD.Font.caption)
                    .foregroundStyle(RD.Palette.gemText)
                    .lineLimit(1)
            } else {
                Text("待看 · 剩\(item.remainingEpisodes)集未看")
                    .font(RD.Font.caption)
                    .foregroundStyle(RD.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct DurationCuratedCard: View {
    let series: Series
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteCover(url: series.cover) }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if series.isCompleted {
                        RDStatusBadgePill(text: "已完结", kind: .completed)
                            .padding(6)
                    } else if !series.badge.isEmpty {
                        RDBadgePill(text: series.badge)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(hint)
                        .font(RD.Font.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
                .rdGemPosterChrome()

            Text(series.title)
                .font(RD.Font.headline)
                .foregroundStyle(RD.Palette.textPrimary)
                .lineLimit(1)
        }
    }
}

struct SeriesCard: View {
    let series: Series
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteCover(url: series.cover) }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if series.isCompleted {
                        RDStatusBadgePill(text: "已完结", kind: .completed)
                            .padding(6)
                    } else if !series.badge.isEmpty {
                        RDBadgePill(text: series.badge)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !series.score.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(RD.Palette.mediaSilver)
                            Text(series.score)
                        }
                        .font(RD.Font.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("全\(series.episodeCount)集")
                        .font(RD.Font.micro)
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
                .rdGemPosterChrome()

            Text(series.title)
                .font(RD.Font.headline)
                .foregroundStyle(RD.Palette.textPrimary)
                .lineLimit(compact ? 1 : 2)
                .multilineTextAlignment(.leading)

            if !compact {
                Text(subtitleText)
                    .font(RD.Font.caption)
                    .foregroundStyle(RD.Palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var subtitleText: String {
        if !series.heatText.isEmpty { return series.heatText }
        if !series.tags.isEmpty { return series.tags.prefix(2).joined(separator: " · ") }
        return series.intro.isEmpty ? "红果漫剧" : series.intro
    }
}
