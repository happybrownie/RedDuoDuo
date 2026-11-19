import SwiftUI

/// A9：「第一集黄金钩子」上下滑试看切片流。
/// 复用现行双引擎播放器（RDPlayerController + RDPlayerSurface）与备流口径（ManjuAPI + StreamPreparer），
/// 每次只切各部剧的第 1 集快速试看，支持抖音式跟手上下滑（过 1/3 屏切剧、不到弹回）、追剧收藏与一键看全集。
struct GoldenHookFeedView: View {
    var isActive: Bool = true
    var onClose: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var catalog = CatalogCache.shared
    @ObservedObject private var followStore = FollowStore.shared

    @StateObject private var controller = RDPlayerController()
    @AppStorage(RDVideoFit.preferenceKey) private var fillScreen = RDVideoFit.defaultFillScreen

    @State private var feed: [Series] = []
    @State private var hookIndex: Int = 0
    @State private var feedCursor: HomeFeedCursor?
    @State private var albumsBySeriesID: [String: AlbumDetail] = [:]

    @State private var loading = true
    @State private var error: String?
    @State private var activeLoadID = UUID()
    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var didFirePremiereHaptic = false

    @State private var dragOffsetY: CGFloat = 0
    @State private var swipeThresholdCrossed = false
    @State private var didFireBoundaryHaptic = false
    @State private var pinchScale: CGFloat = RDVideoFit.releasedScale
    @State private var pinchCrossedMode: Bool?
    @State private var centerFlashIcon: String?
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?

    @State private var fullPlayerTarget: FullPlayerTarget?
    @State private var detailTarget: Series?
    @State private var preloadTask: Task<Void, Never>?
    @State private var reloadToken = 0

    private struct FullPlayerTarget: Identifiable {
        let id = UUID()
        let series: Series
        let episodes: [Episode]
        let startIndex: Int
    }

    private var currentSeries: Series? {
        guard feed.indices.contains(hookIndex) else { return nil }
        return feed[hookIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RDSafeAreaProbe(insets: $safeInsets)

            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let h = max(1, geo.size.height)
                let topPad = max(safeInsets.top + 8, 16)
                let bottomPad = max(safeInsets.bottom + 14, 24)
                let leadingPad = max(safeInsets.leading, 16)
                let trailingPad = max(safeInsets.trailing, 16)

                ZStack {
                    if feed.isEmpty && loading {
                        VStack(spacing: 14) {
                            ProgressView().tint(RD.Palette.accent).scaleEffect(1.2)
                            Text("正在准备第一集黄金试看流…")
                                .font(RD.Font.body)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    } else if feed.isEmpty, let error {
                        RDEmptyStateView(
                            systemImage: "flame.fill",
                            title: "试看流加载失败",
                            subtitle: error,
                            actionTitle: "重试"
                        ) {
                            Task { await bootstrapFeed(force: true) }
                        }
                        .padding(24)
                    } else {
                        // 相邻预演卡（上/下滑跟手露出）
                        if dragOffsetY < -1, let next = feed[safe: hookIndex + 1] {
                            hookPreviewCard(next, label: "下一部试看", crossed: swipeThresholdCrossed)
                                .frame(width: w, height: h)
                                .offset(y: h + dragOffsetY)
                                .allowsHitTesting(false)
                        } else if dragOffsetY > 1, let prev = feed[safe: hookIndex - 1] {
                            hookPreviewCard(prev, label: "上一部试看", crossed: swipeThresholdCrossed)
                                .frame(width: w, height: h)
                                .offset(y: -h + dragOffsetY)
                                .allowsHitTesting(false)
                        }

                        // 常驻视频表面
                        RDPlayerSurface(controller: controller, fillScreen: fillScreen, videoSize: controller.videoSize)
                            .frame(width: w, height: h)
                            .scaleEffect(pinchScale)
                            .offset(y: dragOffsetY)
                            .clipped()
                            .allowsHitTesting(false)

                        // 如果仍在缓冲第1集首帧，先显示柔和封面底避免干黑
                        if loading, let cur = currentSeries {
                            RemoteCover(url: cur.cover, thumbnailMaxPixel: 800)
                                .frame(width: w, height: h)
                                .opacity(0.45)
                                .blur(radius: 6)
                                .offset(y: dragOffsetY)
                                .allowsHitTesting(false)
                        }

                        // 手势层：单击暂停/继续、双击收藏追剧、上下滑切剧
                        RDPlayerGestureOverlay(
                            allowPlaybackGestures: !loading && error == nil,
                            allowVerticalSwipe: !feed.isEmpty,
                            onSingleTap: {
                                guard !loading, error == nil else { return }
                                controller.playPause()
                                RDHaptics.shared.playDoubleTapToggle(nowPlaying: controller.isPlaying)
                                flashCenterIcon(controller.isPlaying ? "play.fill" : "pause.fill")
                            },
                            onDoubleTap: {
                                if let cur = currentSeries {
                                    Task { await collectCurrent(cur, forceTrue: true) }
                                }
                            },
                            onLongPress: { boosting in
                                guard !loading, error == nil else { return }
                                controller.setRate(boosting ? 2.0 : 1.0)
                                if boosting {
                                    RDHaptics.shared.playSpeedBoostEngage()
                                } else {
                                    RDHaptics.shared.playSpeedBoostRelease()
                                }
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
                                pinchCrossedMode = nil
                                if let committed = RDVideoFit.pinchCommit(magnitude: scale) {
                                    fillScreen = committed
                                    RDHaptics.shared.playPinchCommit(fillScreen: committed)
                                } else {
                                    RDHaptics.shared.playPinchDeadzoneCancel()
                                }
                                withAnimation(RD.Motion.snappy) {
                                    pinchScale = RDVideoFit.releasedScale
                                }
                            },
                            onPinchCancelled: {
                                pinchCrossedMode = nil
                                RDHaptics.shared.playPinchDeadzoneCancel()
                                withAnimation(RD.Motion.snappy) {
                                    pinchScale = RDVideoFit.releasedScale
                                }
                            },
                            onVerticalPanChanged: { ty, vy in
                                handlePanChanged(ty: ty, vy: vy, height: h)
                            },
                            onVerticalPanEnded: { ty, vy in
                                handlePanEnded(ty: ty, vy: vy, height: h)
                            },
                            onVerticalPanCancelled: {
                                handlePanCancelled()
                            }
                        )
                        .frame(width: w, height: h)

                        // 上下渐隐保护
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: topPad + 56)
                            Spacer()
                            LinearGradient(colors: [.clear, .black.opacity(0.84)], startPoint: .top, endPoint: .bottom)
                                .frame(height: bottomPad + 180)
                        }
                        .allowsHitTesting(false)

                        // 顶栏
                        VStack {
                            HStack(spacing: 10) {
                                if let onClose {
                                    Button {
                                        RDHaptics.shared.playGlassTap()
                                        onClose()
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.headline.bold())
                                            .frame(width: 36, height: 36)
                                            .rdGlassCircle()
                                    }
                                }

                                RDBadgePill(text: "第一集黄金钩子", accent: true)
                                Text("\(hookIndex + 1)/\(feed.count)")
                                    .font(RD.Font.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.white.opacity(0.86))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .rdGlassCircleCapsule()

                                Spacer()

                                Button {
                                    RDHaptics.shared.playSurprisePick()
                                    Task { await shuffleOrFetchMore() }
                                } label: {
                                    Label("换一批", systemImage: "shuffle")
                                        .font(RD.Font.caption.weight(.bold))
                                        .padding(.horizontal, 11)
                                        .frame(height: 34)
                                        .rdGlassCircleCapsule()
                                }
                            }
                            .padding(.top, topPad)
                            .padding(.leading, leadingPad)
                            .padding(.trailing, trailingPad)

                            Spacer()
                        }

                        // 右侧动作栏 + 底部剧目信息
                        if let cur = currentSeries {
                            VStack(spacing: 0) {
                                Spacer()
                                HStack(alignment: .bottom, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            RDBadgePill(text: "第 1 集试看", accent: true)
                                            if !cur.score.isEmpty {
                                                Text(cur.score)
                                                    .font(RD.Font.micro)
                                                    .foregroundStyle(RD.Palette.platinum)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                                            }
                                            Text("全\(cur.episodeCount)集")
                                                .font(RD.Font.micro)
                                                .foregroundStyle(.white.opacity(0.9))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                                        }

                                        Text(cur.title)
                                            .font(RD.Font.title)
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                            .rdMediaShadow()

                                        if !cur.tags.isEmpty {
                                            Text(cur.tags.prefix(3).joined(separator: " · "))
                                                .font(RD.Font.caption.weight(.semibold))
                                                .foregroundStyle(RD.Palette.gemRim)
                                                .lineLimit(1)
                                        }

                                        if !cur.intro.isEmpty {
                                            Text(cur.intro)
                                                .font(RD.Font.caption)
                                                .foregroundStyle(.white.opacity(0.84))
                                                .lineLimit(2)
                                        }

                                        // 试看进度细条
                                        let dur = max(controller.duration, 1)
                                        let frac = min(max(controller.time / dur, 0), 1)
                                        GeometryReader { pg in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.white.opacity(0.24))
                                                Capsule().fill(RD.Gem.progressGradient)
                                                    .frame(width: max(4, pg.size.width * frac))
                                            }
                                        }
                                        .frame(height: 3)
                                        .padding(.top, 4)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    // 右侧竖向宝石交互轨
                                    VStack(spacing: 14) {
                                        let collected = followStore.isCollected(cur.id)
                                        Button {
                                            Task { await collectCurrent(cur, forceTrue: false) }
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: collected ? "bookmark.fill" : "bookmark")
                                                    .font(.system(size: 20, weight: .bold))
                                                    .foregroundStyle(collected ? RD.Palette.gemBright : .white)
                                                    .frame(width: 44, height: 44)
                                                    .rdGlassCircle()
                                                Text(collected ? "已追" : "追剧")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }

                                        Button {
                                            RDHaptics.shared.playGlassHeroTap()
                                            detailTarget = cur
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: "info.circle")
                                                    .font(.system(size: 20, weight: .bold))
                                                    .frame(width: 44, height: 44)
                                                    .rdGlassCircle()
                                                Text("详情")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }

                                        Button {
                                            RDHaptics.shared.playGemButtonRelease()
                                            Task { await openFullSeries(cur) }
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .frame(width: 46, height: 46)
                                                    .background {
                                                        RDGemFacetSurface(shape: Circle(), shadowRadius: 8)
                                                    }
                                                Text("看全集")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, leadingPad)
                                .padding(.trailing, trailingPad)
                                .padding(.bottom, bottomPad)
                            }
                        }

                        if loading && !feed.isEmpty {
                            VStack {
                                ProgressView().tint(RD.Palette.accent)
                                Text("正在准备第 1 集…")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .padding(16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .environment(\.colorScheme, .dark)
                            .allowsHitTesting(false)
                        }

                        if let error, !feed.isEmpty {
                            VStack(spacing: 10) {
                                Text("本剧第 1 集暂无法起播")
                                    .font(RD.Font.headline)
                                    .foregroundStyle(.white)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(RD.Palette.textSecondary)
                                    .lineLimit(2)
                                HStack(spacing: 10) {
                                    Button("重试") {
                                        RDHaptics.shared.playRetryTap()
                                        reloadToken += 1
                                    }
                                    .buttonStyle(RDGemSecondaryButtonStyle(capsule: true))
                                    if hookIndex < feed.count - 1 {
                                        Button("下一部") {
                                            switchHook(delta: 1)
                                        }
                                        .buttonStyle(RDGemPillButtonStyle())
                                    }
                                }
                            }
                            .padding(16)
                            .rdGemCard(radius: 14, fill: RD.Palette.surface.opacity(0.92))
                            .padding(24)
                        }

                        if let centerFlashIcon {
                            Image(systemName: centerFlashIcon)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(20)
                                .background(.black.opacity(0.55), in: Circle())
                                .allowsHitTesting(false)
                        }

                        if let toastText {
                            VStack {
                                Spacer()
                                Text(toastText)
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.black.opacity(0.78), in: Capsule())
                                    .overlay(Capsule().strokeBorder(RD.Palette.gemBorder, lineWidth: 0.8))
                                    .padding(.bottom, bottomPad + 140)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }
                .frame(width: w, height: h)
            }
            .ignoresSafeArea(edges: onClose != nil ? .all : [.top, .horizontal])
        }
        .task {
            if feed.isEmpty {
                await bootstrapFeed(force: false)
            }
        }
        .task(id: "\(isActive)-\(hookIndex)-\(reloadToken)") {
            guard isActive, !feed.isEmpty else {
                activeLoadID = UUID()
                preloadTask?.cancel()
                controller.stop()
                return
            }
            await playCurrentHook()
        }
        .onChange(of: controller.time) { _, t in
            if !didFirePremiereHaptic, t > 0.5, controller.isPlaying || controller.hasVideoOut {
                didFirePremiereHaptic = true
                RDHaptics.shared.playSignaturePremiere()
            }
        }
        .onChange(of: controller.stateText) { _, state in
            if state == "ended", isActive, !loading, error == nil, hookIndex < feed.count - 1 {
                switchHook(delta: 1)
            }
        }
        .onDisappear {
            preloadTask?.cancel()
            activeLoadID = UUID()
            controller.stop()
        }
        .fullScreenCover(item: $fullPlayerTarget) { target in
            PlayerView(series: target.series, episodes: target.episodes, startIndex: target.startIndex)
        }
        .sheet(item: $detailTarget) { item in
            NavigationStack {
                DetailView(initial: item)
            }
        }
    }

    private func hookPreviewCard(_ item: Series, label: String, crossed: Bool) -> some View {
        ZStack {
            RD.Palette.background
            RemoteCover(url: item.cover, thumbnailMaxPixel: 800)
                .opacity(0.40)
                .blur(radius: 12)
            VStack(spacing: 12) {
                RemoteCover(url: item.cover, thumbnailMaxPixel: 600)
                    .frame(width: 124, height: 180)
                    .rdGemPosterChrome()
                RDBadgePill(text: label, accent: crossed)
                Text(item.title)
                    .font(RD.Font.title)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(crossed ? "松手开看第 1 集" : "继续滑动切换")
                    .font(RD.Font.caption.weight(.bold))
                    .foregroundStyle(crossed ? RD.Palette.gemRim : RD.Palette.textSecondary)
            }
            .padding(24)
        }
    }

    // MARK: - 手势控制（1/3 屏阈值）

    private func handlePanChanged(ty: CGFloat, vy: CGFloat, height: CGFloat) {
        let movingUp = ty < 0
        let hasTarget = movingUp ? (hookIndex < feed.count - 1) : (hookIndex > 0)
        if !hasTarget {
            dragOffsetY = ty * 0.22
            if abs(ty) > 48 && !didFireBoundaryHaptic {
                didFireBoundaryHaptic = true
                RDHaptics.shared.playSwipeBoundaryWall()
                showToast(hookIndex == 0 ? "已是第一部试看" : "已到试看切片末尾")
            }
            return
        }
        dragOffsetY = ty
        let threshold = max(height / 3.0, 90)
        RDHaptics.shared.updateSwipeDragField(progress: min(abs(ty) / threshold, 1.0), velocityY: vy)
        let crossed = abs(ty) >= threshold
        if crossed != swipeThresholdCrossed {
            swipeThresholdCrossed = crossed
            if crossed { RDHaptics.shared.playSwipeThresholdCrossed() }
        }
    }

    private func handlePanEnded(ty: CGFloat, vy: CGFloat, height: CGFloat) {
        let threshold = max(height / 3.0, 90)
        let isNext = dragOffsetY < 0
        let hasTarget = isNext ? (hookIndex < feed.count - 1) : (hookIndex > 0)
        let commit = hasTarget && abs(dragOffsetY) >= threshold

        swipeThresholdCrossed = false
        didFireBoundaryHaptic = false

        if commit {
            RDHaptics.shared.playEpisodeSwitch(next: isNext)
            withAnimation(.easeOut(duration: 0.16)) {
                dragOffsetY = isNext ? -height : height
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 140_000_000)
                dragOffsetY = 0
                switchHook(delta: isNext ? 1 : -1)
            }
        } else {
            if hasTarget {
                RDHaptics.shared.playSwipeBounceBack()
            } else {
                RDHaptics.shared.stopDynamicField()
            }
            withAnimation(RD.Motion.snappy) { dragOffsetY = 0 }
        }
    }

    private func handlePanCancelled() {
        swipeThresholdCrossed = false
        didFireBoundaryHaptic = false
        RDHaptics.shared.playSwipeBounceBack()
        withAnimation(RD.Motion.snappy) { dragOffsetY = 0 }
    }

    private func switchHook(delta: Int) {
        let next = hookIndex + delta
        guard feed.indices.contains(next) else { return }
        hookIndex = next
        if next >= feed.count - 3 {
            Task { await loadMoreFeedSilently() }
        }
    }

    // MARK: - 数据与第一集起播

    private func bootstrapFeed(force: Bool) async {
        loading = true
        error = nil
        if !force {
            let cached = Array(catalog.byID.values).shuffled()
            if !cached.isEmpty {
                feed = cached
                hookIndex = 0
                return
            }
        }
        do {
            let page = try await ManjuAPI.shared.homeFeedFirstPage()
            CatalogCache.shared.ingest(page.items)
            feedCursor = page.cursor
            feed = page.items.shuffled()
            hookIndex = 0
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }

    private func loadMoreFeedSilently() async {
        guard let cursor = feedCursor, cursor.hasMore else { return }
        if let next = try? await ManjuAPI.shared.homeFeedNextPage(cursor: cursor) {
            CatalogCache.shared.ingest(next.items)
            feedCursor = next.cursor
            let seen = Set(feed.map(\.id))
            let additions = next.items.filter { !seen.contains($0.id) }
            feed.append(contentsOf: additions)
        }
    }

    private func shuffleOrFetchMore() async {
        if let cursor = feedCursor, cursor.hasMore,
           let next = try? await ManjuAPI.shared.homeFeedNextPage(cursor: cursor), !next.items.isEmpty {
            CatalogCache.shared.ingest(next.items)
            feedCursor = next.cursor
            let seen = Set(feed.map(\.id))
            let additions = next.items.filter { !seen.contains($0.id) }
            if !additions.isEmpty {
                feed.insert(contentsOf: additions.shuffled(), at: min(hookIndex + 1, feed.count))
                hookIndex = min(hookIndex + 1, feed.count - 1)
                showToast("已刷新黄金钩子切片")
                return
            }
        }
        if feed.count > 1 {
            feed.shuffle()
            hookIndex = 0
            reloadToken += 1
            showToast("已重排试看切片流")
        } else {
            await bootstrapFeed(force: true)
        }
    }

    private func resolveFirstEpisode(for item: Series) async throws -> (Series, Episode) {
        if let cached = albumsBySeriesID[item.id], let first = cached.episodes.first {
            return (cached.series, first)
        }
        if let vid = item.firstVid, !vid.isEmpty {
            let ep = Episode(vid: vid, index: item.firstIndex, title: "第\(item.firstIndex)集",
                             cover: item.cover, duration: item.estimatedEpisodeDuration, seriesID: item.id)
            return (item, ep)
        }
        let detail = try await ManjuAPI.shared.album(seriesID: item.id)
        CatalogCache.shared.ingestAlbum(detail)
        albumsBySeriesID[item.id] = detail
        guard let first = detail.episodes.first else {
            throw ManjuError.emptyResponse("该剧暂无剧集")
        }
        return (detail.series, first)
    }

    private func playCurrentHook() async {
        guard let item = currentSeries else { return }
        let loadID = UUID()
        activeLoadID = loadID
        controller.stop()
        loading = true
        error = nil
        didFirePremiereHaptic = false

        func isStale() -> Bool { Task.isCancelled || activeLoadID != loadID || !isActive }

        do {
            let (resolvedSeries, ep) = try await resolveFirstEpisode(for: item)
            if isStale() { return }
            if feed.indices.contains(hookIndex), feed[hookIndex].id == resolvedSeries.id {
                feed[hookIndex] = resolvedSeries
            }

            let candidates = try await ManjuAPI.shared.playbackCandidates(vid: ep.vid, seriesID: resolvedSeries.id)
            if isStale() { return }
            guard !candidates.isEmpty else { throw ManjuError.noMainURL("暂无可用试看流") }

            for info in candidates.prefix(4) {
                if isStale() { return }
                let local: URL
                do {
                    if info.isEncrypted {
                        local = try await StreamPreparer.shared.prepare(info) { _ in }
                    } else if let u = URL(string: info.url) {
                        local = u
                    } else {
                        continue
                    }
                } catch {
                    continue
                }
                if isStale() { return }

                for engine in RDPlaybackEngine.allCases {
                    if isStale() { return }
                    controller.load(url: local, startAt: 0, engine: engine)
                    if await waitHookStart(engine: engine, loadID: loadID) {
                        if isStale() { return }
                        loading = false
                        scheduleNextHookPreload(after: hookIndex)
                        return
                    }
                    if isStale() {
                        if activeLoadID == loadID { controller.stop() }
                        return
                    }
                    controller.stop()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            if !isStale() {
                throw ManjuError.noMainURL("第一集试看流起播失败")
            }
        } catch is CancellationError {
            // 切换切片时静默取消
        } catch {
            if !isStale() {
                self.error = error.localizedDescription
                loading = false
                RDHaptics.shared.playPlaybackError()
            }
        }
    }

    private func waitHookStart(engine: RDPlaybackEngine, loadID: UUID) async -> Bool {
        let deadline = Date().addingTimeInterval(8.0)
        var stoppedSince: Date?

        while Date() < deadline {
            if Task.isCancelled || activeLoadID != loadID || !isActive { return false }
            switch engine {
            case .avPlayer:
                if controller.av.isItemFailed || controller.av.stateText == "error" { return false }
                if controller.stateText == "ended" {
                    return controller.av.hasTimelineAdvanced || controller.time >= 1.0
                }
                if controller.av.isItemReady && (controller.av.hasVideoOut || controller.av.hasTimelineAdvanced) { return true }
            case .vlc:
                if controller.vlc.hasVideoOut && controller.time > 0.05 { return true }
                if controller.time > 1.0 { return true }
                if controller.stateText == "error" { return false }
                if controller.stateText == "ended" {
                    return controller.time >= 1.0
                }
                if controller.stateText == "stopped" {
                    if let stoppedSince, Date().timeIntervalSince(stoppedSince) > 1.2 { return false }
                    if stoppedSince == nil { stoppedSince = Date() }
                } else {
                    stoppedSince = nil
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    private func scheduleNextHookPreload(after idx: Int) {
        preloadTask?.cancel()
        let nextTargets = [idx + 1, idx + 2].compactMap { feed[safe: $0] }
        guard !nextTargets.isEmpty else { return }
        preloadTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            for item in nextTargets {
                if Task.isCancelled { return }
                guard let (s, ep) = try? await resolveFirstEpisode(for: item) else { continue }
                guard await StreamPreparer.shared.existingPlaintextURL(forVid: ep.vid) == nil else { continue }
                if let info = try? await ManjuAPI.shared.playbackCandidates(vid: ep.vid, seriesID: s.id).first,
                   info.isEncrypted {
                    _ = try? await StreamPreparer.shared.prepare(info) { _ in }
                }
            }
        }
    }

    private func collectCurrent(_ item: Series, forceTrue: Bool) async {
        let currentState = followStore.isCollected(item.id)
        let target = forceTrue ? true : !currentState
        RDHaptics.shared.playCollectPreTap()
        if auth.isLoggedIn {
            do {
                try await ManjuAPI.shared.collectSeries(seriesID: item.id, collect: target)
                followStore.setCollected(target, series: item)
                RDHaptics.shared.playCollectResult(collected: target)
                showToast(target ? "已加入在追片单" : "已移出在追片单")
            } catch {
                RDHaptics.shared.playCollectRollback()
                showToast("收藏同步失败，请稍后再试")
            }
        } else {
            followStore.setCollected(target, series: item)
            RDHaptics.shared.playCollectResult(collected: target)
            showToast(target ? "已加入本机在追片单" : "已移出在追片单")
        }
    }

    private func openFullSeries(_ item: Series) async {
        controller.stop()
        if let album = albumsBySeriesID[item.id] {
            fullPlayerTarget = FullPlayerTarget(series: album.series, episodes: album.episodes, startIndex: 0)
            return
        }
        do {
            let detail = try await ManjuAPI.shared.album(seriesID: item.id)
            CatalogCache.shared.ingestAlbum(detail)
            albumsBySeriesID[item.id] = detail
            fullPlayerTarget = FullPlayerTarget(series: detail.series, episodes: detail.episodes, startIndex: 0)
        } catch {
            if let vid = item.firstVid {
                let ep = Episode(vid: vid, index: item.firstIndex, title: "第\(item.firstIndex)集",
                                 cover: item.cover, duration: item.estimatedEpisodeDuration, seriesID: item.id)
                fullPlayerTarget = FullPlayerTarget(series: item, episodes: [ep], startIndex: 0)
            } else {
                detailTarget = item
            }
        }
    }

    private func flashCenterIcon(_ icon: String) {
        centerFlashIcon = icon
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if self.centerFlashIcon == icon {
                self.centerFlashIcon = nil
            }
        }
    }

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        toastText = msg
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled && self.toastText == msg {
                self.toastText = nil
            }
        }
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
