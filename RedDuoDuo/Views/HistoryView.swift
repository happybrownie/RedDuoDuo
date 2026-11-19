import SwiftUI

/// 1.4.8 历史「浮层画册」：
/// 标题 + 编辑丸 → 16:9 续看卡（24 圆角 + 毛玻璃名牌 + 进度 + 40 白播钮）
/// → 今 / 周 / 早分组（64×85 缩略 + 进度）。小屏单列；大屏左 40% 卡 + 右 60% 双列；半折上卡下列表。
struct HistoryView: View {
    @EnvironmentObject private var history: WatchHistory

    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var scrollOffset: CGFloat = 0
    @State private var wasScrolledPastTopBar = false
    @State private var showClearConfirm = false
    @State private var refreshing = false
    @State private var editing = false
    @State private var tint: RDAlbumTint?

    var body: some View {
        NavigationStack {
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
                    let contentWidth = max(1, fullWidth - leadingPad - trailingPad)
                    let topClearance = max(safeInsets.top + 56, 68)
                    let panes = DuoFoldLayout.physicalFoldPanes(in: fullGeo)

                    ZStack(alignment: .top) {
                        if let panes {
                            if panes.isBookPosture {
                                HStack(alignment: .top, spacing: 0) {
                                    ScrollView(showsIndicators: false) {
                                        VStack(alignment: .leading, spacing: 20) {
                                            pageHeader(wide: true)
                                            featuredContent(width: max(1, panes.videoRect.width - 32), wide: true)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, topClearance)
                                        .padding(.bottom, 40)
                                    }
                                    .frame(width: panes.videoRect.width)

                                    ScrollView(showsIndicators: false) {
                                        listContent(
                                            wide: true,
                                            leadingPad: 16,
                                            trailingPad: 16,
                                            columns: 1
                                        )
                                        .padding(.top, topClearance)
                                        .padding(.bottom, 92)
                                    }
                                    .frame(width: panes.panelRect.width)
                                }
                            } else {
                                VStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        pageHeader(wide: false)
                                        featuredContent(
                                            width: max(1, panes.videoRect.width - 40),
                                            wide: false
                                        )
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.top, topClearance)

                                    ScrollView(showsIndicators: false) {
                                        listContent(
                                            wide: false,
                                            leadingPad: 20,
                                            trailingPad: 20,
                                            columns: 1
                                        )
                                        .padding(.top, 16)
                                        .padding(.bottom, 40)
                                    }
                                    .frame(height: max(1, panes.panelRect.height))
                                }
                            }
                        } else if wide {
                            ScrollViewReader { scrollProxy in
                                ScrollView(showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                                        Color.clear.frame(height: 0).id("history-top-anchor")
                                        pageHeader(wide: true)

                                        if history.entries.isEmpty {
                                            emptyBoard
                                        } else {
                                            let featuredWidth = max(1, contentWidth * 0.40)
                                            HStack(alignment: .top, spacing: 28) {
                                                VStack(alignment: .leading, spacing: 20) {
                                                    if let latest = history.entries.first {
                                                        RDAlbumSectionHeader(title: "最近在看", trailing: dateText(latest.updatedAt), showsChevron: false)
                                                        NavigationLink(value: series(from: latest)) {
                                                            RDAlbumContinueCard(entry: latest, height: featuredWidth * 9 / 16)
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                                .frame(width: featuredWidth)

                                                VStack(alignment: .leading, spacing: 20) {
                                                    let rest = Array(history.entries.dropFirst())
                                                    if rest.isEmpty {
                                                        Text("暂无更多观看记录")
                                                            .font(RDAlbum.Font.body)
                                                            .foregroundStyle(RDAlbum.C.textSecondary)
                                                            .padding(.top, 8)
                                                    } else {
                                                        historyGroups(rest, columns: 2, leadingPad: 0)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                            }
                                        }
                                    }
                                    .padding(.top, topClearance)
                                    .padding(.horizontal, leadingPad)
                                    .padding(.bottom, 96)
                                    .frame(width: fullWidth, alignment: .leading)
                                }
                                .onScrollGeometryChange(for: CGFloat.self) { geo in
                                    geo.contentOffset.y + geo.contentInsets.top
                                } action: { _, offset in
                                    handleScrollOffset(offset)
                                }
                                .refreshable { await refresh() }
                                .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                    if let tab = note.object as? Int, tab == 3 {
                                        withAnimation(RDAlbum.Motion.rearrange) {
                                            scrollProxy.scrollTo("history-top-anchor", anchor: .top)
                                        }
                                    }
                                }
                            }
                        } else {
                            ScrollViewReader { scrollProxy in
                                ScrollView(showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                                        Color.clear.frame(height: 0).id("history-top-anchor")
                                        pageHeader(wide: false)

                                        if refreshing && history.entries.isEmpty {
                                            RDHistorySkeletonView(wide: false)
                                        } else if history.entries.isEmpty {
                                            emptyBoard
                                        } else {
                                            if let latest = history.entries.first {
                                                featuredContent(width: contentWidth, wide: false)
                                                    .padding(.top, 4)
                                            }
                                            let rest = Array(history.entries.dropFirst())
                                            if !rest.isEmpty {
                                                listContent(
                                                    wide: false,
                                                    leadingPad: leadingPad,
                                                    trailingPad: trailingPad,
                                                    columns: 1
                                                )
                                            }
                                        }
                                    }
                                    .padding(.top, topClearance)
                                    .padding(.horizontal, leadingPad)
                                    .padding(.bottom, 96)
                                    .frame(width: fullWidth, alignment: .leading)
                                }
                                .onScrollGeometryChange(for: CGFloat.self) { geo in
                                    geo.contentOffset.y + geo.contentInsets.top
                                } action: { _, offset in
                                    handleScrollOffset(offset)
                                }
                                .refreshable { await refresh() }
                                .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                    if let tab = note.object as? Int, tab == 3 {
                                        withAnimation(RDAlbum.Motion.rearrange) {
                                            scrollProxy.scrollTo("history-top-anchor", anchor: .top)
                                        }
                                    }
                                }
                            }
                        }

                        topBar(leadingPad: leadingPad, trailingPad: trailingPad)
                    }
                    .frame(width: fullWidth, height: fullHeight)
                }
                .ignoresSafeArea(edges: .top)
            }
            .rdScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Series.self) { item in
                DetailView(initial: item)
            }
            .alert("清空观看记录", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空全部", role: .destructive) {
                    RDHaptics.shared.playClearAllDestructive()
                    withAnimation(RDAlbum.Motion.rearrange) {
                        history.clear()
                    }
                }
            } message: {
                Text("将清空本机保存的 \(history.entries.count) 部观看进度，此操作不可撤销。")
            }
            .task(id: history.entries.first?.cover ?? "") {
                let cover = history.entries.first?.cover ?? ""
                guard !cover.isEmpty else { tint = nil; return }
                tint = await RDAlbumTintStore.shared.tint(for: cover)
            }
        }
    }

    // MARK: - 顶栏 / 页头

    private func topBar(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let scrolled = scrollOffset > 28
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                RDGemPlayMark(size: 22)
                Text("观看记录")
                    .font(RDAlbum.Font.rounded(19, .bold))
                    .foregroundStyle(RDAlbum.C.textPrimary)
            }
            .opacity(scrolled ? 1 : 0)

            Spacer(minLength: 8)

            if !history.entries.isEmpty {
                Button {
                    RDHaptics.shared.playGlassTap()
                    showClearConfirm = true
                } label: {
                    Text("清空")
                        .font(RDAlbum.Font.plateSub.weight(.semibold))
                        .foregroundStyle(RDAlbum.C.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .rdAlbumGlass(Capsule(style: .continuous), kind: .secondary, shadow: false)
                }
                .buttonStyle(.plain)
            }
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

    private func pageHeader(wide: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("观看记录")
                    .font(RDAlbum.Font.pageTitle)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(history.entries.isEmpty ? "自动保存集数与秒级进度" : "已记住 \(history.entries.count) 部 · 点开接着看")
                    .font(RDAlbum.Font.wideSub)
                    .tracking(1.8)
                    .foregroundStyle(RDAlbum.C.textSecondary)
            }
            Spacer(minLength: 12)
            if !history.entries.isEmpty {
                Button(editing ? "完成" : "编辑") {
                    RDHaptics.shared.playChipSelect()
                    withAnimation(RDAlbum.Motion.rearrange) { editing.toggle() }
                }
                .buttonStyle(RDAlbumGlassPillStyle(height: 34, horizontalPadding: 18))
            }
        }
    }

    // MARK: - 16:9 续看卡

    private func featuredContent(width: CGFloat, wide: Bool) -> some View {
        Group {
            if let latest = history.entries.first {
                VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
                    RDAlbumSectionHeader(title: "最近在看", trailing: dateText(latest.updatedAt), showsChevron: false)
                    NavigationLink(value: series(from: latest)) {
                        RDAlbumContinueCard(entry: latest, height: max(180, width * 9 / 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 分组列表

    private struct HistoryGroup: Identifiable {
        let id: String
        let title: String
        let entries: [HistoryEntry]
    }

    private func groups(_ entries: [HistoryEntry]) -> [HistoryGroup] {
        var today: [HistoryEntry] = []
        var week: [HistoryEntry] = []
        var earlier: [HistoryEntry] = []
        let now = Date()
        let cal = Calendar.current
        for entry in entries {
            let date = Date(timeIntervalSince1970: entry.updatedAt)
            if cal.isDateInToday(date) {
                today.append(entry)
            } else if let days = cal.dateComponents([.day], from: date, to: now).day, days < 7 {
                week.append(entry)
            } else {
                earlier.append(entry)
            }
        }
        var out: [HistoryGroup] = []
        if !today.isEmpty { out.append(HistoryGroup(id: "today", title: "今天", entries: today)) }
        if !week.isEmpty { out.append(HistoryGroup(id: "week", title: "本周", entries: week)) }
        if !earlier.isEmpty { out.append(HistoryGroup(id: "earlier", title: "更早", entries: earlier)) }
        return out
    }

    private func historyGroups(_ entries: [HistoryEntry], columns: Int, leadingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
            ForEach(groups(entries)) { group in
                VStack(alignment: .leading, spacing: RDAlbum.Space.sm) {
                    RDAlbumSectionHeader(title: group.title, trailing: "\(group.entries.count) 部", showsChevron: false)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns),
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(group.entries) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listContent(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat, columns: Int) -> some View {
        let rest = Array(history.entries.dropFirst())
        if rest.isEmpty {
            if history.entries.isEmpty {
                emptyBoard
            } else {
                Text("暂无更多观看记录")
                    .font(RDAlbum.Font.body)
                    .foregroundStyle(RDAlbum.C.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            historyGroups(rest, columns: columns, leadingPad: leadingPad)
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: series(from: entry)) {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottom) {
                        RemoteCover(url: entry.cover, thumbnailMaxPixel: 300)
                            .frame(width: RDAlbum.Poster.thumbHistory.width, height: RDAlbum.Poster.thumbHistory.height)
                            .clipped()
                        RDAlbumProgressBar(fraction: entry.progressFraction, trackHeight: 2, showsBuffer: false)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 3)
                    }
                    .frame(width: RDAlbum.Poster.thumbHistory.width, height: RDAlbum.Poster.thumbHistory.height)
                    .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous))
                    .shadow(color: RDAlbum.C.posterShadow, radius: 10, x: 0, y: 5)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title)
                            .font(RDAlbum.Font.plateName)
                            .foregroundStyle(RDAlbum.C.textPrimary)
                            .lineLimit(1)
                        Text("第 \(entry.lastIndex) 集\(entry.lastPosition >= 1.5 ? " · \(entry.positionText)" : "") · 共\(entry.episodeCount)集")
                            .font(RDAlbum.Font.plateSub)
                            .foregroundStyle(RDAlbum.C.textSecondary)
                            .lineLimit(1)
                        Text(dateText(entry.updatedAt))
                            .font(RDAlbum.Font.plateSub)
                            .foregroundStyle(RDAlbum.C.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editing {
                Button {
                    RDHaptics.shared.playDeleteSingleItem()
                    withAnimation(RDAlbum.Motion.rearrange) { history.remove(entry) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RDAlbum.C.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(rdAlbumAdaptiveGlassFill(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除观看记录")
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .padding(12)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: false)
        .contextMenu {
            Button(role: .destructive) {
                RDHaptics.shared.playDeleteSingleItem()
                withAnimation(RDAlbum.Motion.rearrange) { history.remove(entry) }
            } label: {
                Label("删除该记录", systemImage: "trash")
            }
        }
    }

    private var emptyBoard: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(RDAlbum.C.textTertiary)
            Text("还没有观看记录")
                .font(RDAlbum.Font.rowTitle)
                .foregroundStyle(RDAlbum.C.textPrimary)
            Text("看一集漫剧后，会自动记住当前集数与秒级播放进度")
                .font(RDAlbum.Font.body)
                .foregroundStyle(RDAlbum.C.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background {
            RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous)
                .fill(rdAlbumAdaptiveGlassFill())
        }
        .padding(.top, 8)
    }

    private func handleScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
        let crossed = offset > 28
        if crossed && !wasScrolledPastTopBar {
            RDHaptics.shared.playStickyBarCrossed()
        }
        wasScrolledPastTopBar = crossed
    }

    private func refresh() async {
        RDHaptics.shared.playPullRefreshTriggered()
        refreshing = true
        try? await Task.sleep(nanoseconds: 250_000_000)
        refreshing = false
        RDHaptics.shared.playPullRefreshComplete()
    }

    private func series(from entry: HistoryEntry) -> Series {
        Series(id: entry.seriesID, title: entry.title, cover: entry.cover, intro: entry.intro,
               episodeCount: entry.episodeCount, firstVid: entry.lastVid, firstIndex: entry.lastIndex,
               updatedAt: entry.updatedAt)
    }

    private func dateText(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}

private func rdAlbumAdaptiveGlassFill() -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.white.withAlphaComponent(0.60)
    })
}
