import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: WatchHistory

    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var scrollOffset: CGFloat = 0
    @State private var wasScrolledPastTopBar = false
    @State private var showClearConfirm = false
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                RD.Palette.background.ignoresSafeArea()
                RDAmbientTopGlow()
                RDSafeAreaProbe(insets: $safeInsets)

                GeometryReader { fullGeo in
                    let fullWidth = fullGeo.size.width
                    let wide = RD.isWide(fullWidth)
                    let horiz = RDLayoutInsets.horizontal(in: fullGeo)
                    let leadingPad = horiz.leading
                    let trailingPad = horiz.trailing
                    let topClearance = max(safeInsets.top + 56, 68)

                    ZStack(alignment: .top) {
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: RD.Space.xl) {
                                    Color.clear.frame(height: 0).id("history-top-anchor")
                                    pageHeader

                                    if refreshing && history.entries.isEmpty {
                                        RDHistorySkeletonView(wide: wide)
                                    } else if history.entries.isEmpty {
                                        RDEmptyStateView(
                                            systemImage: "clock.arrow.circlepath",
                                            title: "还没有观看记录",
                                            subtitle: "看一集漫剧后，会自动记住当前集数与秒级播放进度"
                                        )
                                        .padding(.top, RD.Space.sm)
                                    } else {
                                        if let latest = history.entries.first {
                                            featuredSection(latest, wide: wide)
                                        }

                                        let rest = Array(history.entries.dropFirst())
                                        if !rest.isEmpty {
                                            historyGridSection(rest, wide: wide)
                                        }
                                    }
                                }
                                .padding(.top, topClearance)
                                .padding(.leading, leadingPad)
                                .padding(.trailing, trailingPad)
                                .padding(.bottom, RD.Space.xl)
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
                                refreshing = true
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                refreshing = false
                                RDHaptics.shared.playPullRefreshComplete()
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                if let tab = note.object as? Int, tab == 3 {
                                    withAnimation(RD.Motion.snappy) {
                                        scrollProxy.scrollTo("history-top-anchor", anchor: .top)
                                    }
                                }
                            }
                        }

                        topBar(leadingPad: leadingPad, trailingPad: trailingPad)
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
            .alert("清空观看记录", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空全部", role: .destructive) {
                    RDHaptics.shared.playClearAllDestructive()
                    withAnimation(RD.Motion.snappy) {
                        history.clear()
                    }
                }
            } message: {
                Text("将清空本机保存的 \(history.entries.count) 部观看进度，此操作不可撤销。")
            }
        }
    }

    // MARK: - 顶栏与大标题

    private func topBar(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let scrolled = scrollOffset > 28
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                RDGemPlayMark(size: 22)
                Text("观看记录")
                    .font(RD.Font.rowTitle)
                    .foregroundStyle(.white)
                    .rdMediaShadow()
            }
            .opacity(scrolled ? 1 : 0)

            Spacer(minLength: 8)

            if !history.entries.isEmpty {
                Button("清空") {
                    RDHaptics.shared.playGlassTap()
                    showClearConfirm = true
                }
                .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 14, verticalPadding: 7))
            }
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

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: RD.Space.xs) {
            HStack(spacing: 8) {
                RDBadgePill(text: "续播足迹", accent: true)
                if !history.entries.isEmpty {
                    Text("已记住 \(history.entries.count) 部")
                        .font(RD.Font.caption.weight(.semibold))
                        .foregroundStyle(RD.Palette.textSecondary)
                }
            }
            Text("观看记录")
                .font(RD.Font.displayLarge)
                .foregroundStyle(.white)
                .rdMediaShadow()
                .accessibilityAddTraits(.isHeader)
            Text("自动保存集数与秒级进度，点开即可接着看")
                .font(RD.Font.body)
                .foregroundStyle(RD.Palette.textSecondary)
        }
    }

    // MARK: - 最近在看（宝石精选卡）

    private func featuredSection(_ entry: HistoryEntry, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            RDSectionHeader(title: "最近在看", trailing: dateText(entry.updatedAt), showsChevron: false, accentMark: true)

            NavigationLink(value: series(from: entry)) {
                HStack(spacing: RD.Space.md) {
                    ZStack(alignment: .bottom) {
                        RemoteCover(url: entry.cover)
                            .frame(width: wide ? 104 : 88, height: wide ? 156 : 132)
                        LinearGradient(colors: [.clear, .black.opacity(0.60)], startPoint: .center, endPoint: .bottom)
                        if entry.progressFraction > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.white.opacity(0.24))
                                    Rectangle().fill(RD.Gem.progressGradient).frame(width: g.size.width * entry.progressFraction)
                                }
                            }
                            .frame(height: 3.5)
                        }
                    }
                    .frame(width: wide ? 104 : 88, height: wide ? 156 : 132)
                    .overlay {
                        ZStack {
                            RDGemFacetSurface(shape: Circle(), shadowRadius: 5, borderWidth: 0.85)
                                .frame(width: 34, height: 34)
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                    }
                    .rdGemPosterChrome()

                    VStack(alignment: .leading, spacing: 8) {
                        RDBadgePill(text: "上次观看", accent: true)

                        Text(entry.title)
                            .font(RD.Font.title)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("看到第 \(entry.lastIndex) 集\(entry.lastPosition >= 1.5 ? " · \(entry.positionText)" : "") · 共\(entry.episodeCount)集")
                            .font(RD.Font.caption.weight(.semibold))
                            .foregroundStyle(RD.Palette.gemText)
                            .lineLimit(1)

                        if entry.progressFraction > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.14))
                                    Capsule()
                                        .fill(RD.Gem.progressGradient)
                                        .frame(width: max(6, g.size.width * entry.progressFraction))
                                }
                            }
                            .frame(height: 4)
                        }

                        HStack(spacing: 6) {
                            Text("查看剧集详情")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(RD.Font.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background {
                            RDGemFacetSurface(shape: Capsule(style: .continuous), shadowRadius: 4, borderWidth: 0.8)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(RD.Space.md)
                .rdGemCard(radius: RD.Radius.sheet, fill: RD.Palette.surface, glow: true)
            }
            .buttonStyle(RDPosterButtonStyle())
            .contextMenu {
                Button(role: .destructive) {
                    RDHaptics.shared.playDeleteSingleItem()
                    withAnimation(RD.Motion.snappy) { history.remove(entry) }
                } label: {
                    Label("删除该记录", systemImage: "trash")
                }
                .onAppear { RDHaptics.shared.playContextMenuPop() }
            }
        }
    }

    // MARK: - 历史列表 / 网格

    private func historyGridSection(_ entries: [HistoryEntry], wide: Bool) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: RD.Space.md), count: wide ? 2 : 1)
        return VStack(alignment: .leading, spacing: RD.Space.md) {
            RDSectionHeader(title: "全部历史", trailing: "共 \(entries.count) 部", showsChevron: false, accentMark: true)

            LazyVGrid(columns: cols, spacing: RD.Space.md) {
                ForEach(entries) { entry in
                    historyRowCard(entry)
                }
            }
        }
    }

    private func historyRowCard(_ entry: HistoryEntry) -> some View {
        HStack(spacing: RD.Space.sm) {
            NavigationLink(value: series(from: entry)) {
                HStack(spacing: 14) {
                    ZStack(alignment: .bottom) {
                        RemoteCover(url: entry.cover)
                            .frame(width: 68, height: 98)
                        LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
                        if entry.progressFraction > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.white.opacity(0.24))
                                    Rectangle().fill(RD.Gem.progressGradient).frame(width: g.size.width * entry.progressFraction)
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                    .frame(width: 68, height: 98)
                    .rdGemPosterChrome()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title)
                            .font(RD.Font.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("看到第 \(entry.lastIndex) 集\(entry.lastPosition >= 1.5 ? " · \(entry.positionText)" : "") · 共\(entry.episodeCount)集")
                            .font(RD.Font.caption.weight(.semibold))
                            .foregroundStyle(RD.Palette.gemText)
                            .lineLimit(1)

                        Text(dateText(entry.updatedAt))
                            .font(.caption2)
                            .foregroundStyle(RD.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RDPosterButtonStyle())

            Button {
                RDHaptics.shared.playDeleteSingleItem()
                withAnimation(RD.Motion.snappy) {
                    history.remove(entry)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RD.Palette.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(RD.Palette.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(RD.Palette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(RDPosterButtonStyle())
            .accessibilityLabel("删除观看记录")
        }
        .padding(RD.Space.md)
        .rdGemCard()
        .contextMenu {
            Button(role: .destructive) {
                RDHaptics.shared.playDeleteSingleItem()
                withAnimation(RD.Motion.snappy) { history.remove(entry) }
            } label: {
                Label("删除该记录", systemImage: "trash")
            }
            .onAppear { RDHaptics.shared.playContextMenuPop() }
        }
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
