import SwiftUI

struct SearchView: View {
    @ObservedObject private var searchHistory = SearchHistoryStore.shared

    @State private var query = ""
    @State private var results: [Series] = []
    @State private var suggestions: [SearchSuggestion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var searched = false
    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var scrollOffset: CGFloat = 0
    @State private var wasScrolledPastTopBar = false
    @FocusState private var searchFocused: Bool

    private let quick = ["灵葫仙缘", "御狐", "凡修逆仙", "末世第一粮仓"]

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
                    let contentWidth = max(1, fullWidth - leadingPad - trailingPad)
                    let topClearance = max(safeInsets.top + 56, 68)

                    ZStack(alignment: .top) {
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: RD.Space.lg) {
                                    Color.clear.frame(height: 0).id("search-top-anchor")

                                    pageHeader
                                        .padding(.leading, leadingPad)
                                        .padding(.trailing, trailingPad)

                                    searchBar
                                        .padding(.leading, leadingPad)
                                        .padding(.trailing, trailingPad)

                                    // A12: 个人搜索胶囊（最近搜过）
                                    if !searchHistory.queries.isEmpty {
                                        recentSearchChips(leadingPad: leadingPad, trailingPad: trailingPad)
                                    }

                                    quickChips(leadingPad: leadingPad, trailingPad: trailingPad)

                                    content(wide: wide, contentWidth: contentWidth, leadingPad: leadingPad, trailingPad: trailingPad)
                                }
                                .padding(.top, topClearance)
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
                            .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                if let tab = note.object as? Int, tab == 2 {
                                    withAnimation(RD.Motion.snappy) {
                                        scrollProxy.scrollTo("search-top-anchor", anchor: .top)
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
            .onChange(of: searchFocused) { _, focused in
                if focused {
                    RDHaptics.shared.playSearchFocus()
                }
            }
        }
    }

    // MARK: - 顶栏与大标题

    private func topBar(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let scrolled = scrollOffset > 28
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                RDGemPlayMark(size: 22)
                Text("搜索")
                    .font(RD.Font.rowTitle)
                    .foregroundStyle(.white)
                    .rdMediaShadow()
            }
            .opacity(scrolled ? 1 : 0)

            Spacer(minLength: 8)
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
            RDBadgePill(text: "发现漫剧", accent: true)
            Text("搜索")
                .font(RD.Font.displayLarge)
                .foregroundStyle(.white)
                .rdMediaShadow()
                .accessibilityAddTraits(.isHeader)
            Text("全站片库检索与关键词联想")
                .font(RD.Font.body)
                .foregroundStyle(RD.Palette.textSecondary)
        }
    }

    // MARK: - 宝石搜索框、最近搜过胶囊 & 热门关键词

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(searchFocused ? RD.Palette.gemRim : RD.Palette.textSecondary)

            TextField("搜剧名 / 关键词", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .submitLabel(.search)
                .onSubmit { runSearch() }

            if !query.isEmpty {
                Button {
                    RDHaptics.shared.playSearchClear()
                    query = ""
                    results = []
                    suggestions = []
                    searched = false
                    error = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            Button("搜索") {
                searchFocused = false
                runSearch()
            }
            .buttonStyle(RDGemPillButtonStyle(horizontalPadding: 16, verticalPadding: 8))
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || loading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .rdGemCard(radius: RD.Radius.card, fill: RD.Palette.surfaceRaised, glow: searchFocused)
        .animation(RD.Motion.fade, value: searchFocused)
    }

    private func recentSearchChips(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            HStack {
                RDSectionHeader(title: "最近搜过", showsChevron: false, accentMark: true)
                Button {
                    RDHaptics.shared.playSearchClear()
                    withAnimation(RD.Motion.snappy) {
                        searchHistory.clear()
                    }
                } label: {
                    Text("清空")
                        .font(RD.Font.caption.weight(.bold))
                        .foregroundStyle(RD.Palette.textTertiary)
                }
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(searchHistory.queries, id: \.self) { word in
                        let selected = query.trimmingCharacters(in: .whitespacesAndNewlines) == word
                        HStack(spacing: 6) {
                            Button {
                                RDHaptics.shared.playChipSelect()
                                query = word
                                searchFocused = false
                                runSearch()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(selected ? .white : RD.Palette.gemRim.opacity(0.8))
                                    Text(word)
                                        .font(RD.Font.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                RDHaptics.shared.playSearchClear()
                                withAnimation(RD.Motion.snappy) {
                                    searchHistory.remove(word)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? .white : .white.opacity(0.88))
                                .background {
                                    if selected {
                                        RDGemFacetSurface(shape: Capsule(style: .continuous), shadowRadius: 4, borderWidth: 0.8)
                                    } else {
                                        Capsule()
                                            .fill(RD.Palette.surfaceRaised)
                                            .overlay(Capsule().strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.7))
                                    }
                                }
                    }
                }
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)
            }
        }
    }

    private func quickChips(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            RDSectionHeader(title: "热门搜索", showsChevron: false, accentMark: true)
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quick, id: \.self) { word in
                        let selected = query.trimmingCharacters(in: .whitespacesAndNewlines) == word
                        Button(word) {
                            RDHaptics.shared.playChipSelect()
                            query = word
                            searchFocused = false
                            runSearch()
                        }
                        .font(RD.Font.caption.weight(.semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? .white : .white.opacity(0.86))
                        .background {
                            if selected {
                                RDGemFacetSurface(shape: Capsule(style: .continuous), shadowRadius: 4, borderWidth: 0.8)
                            } else {
                                Capsule()
                                    .fill(RD.Palette.surfaceRaised)
                                    .overlay(Capsule().strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.7))
                            }
                        }
                        .buttonStyle(RDPosterButtonStyle())
                    }
                }
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)
            }
        }
    }

    // MARK: - 搜索内容区

    @ViewBuilder
    private func content(wide: Bool, contentWidth: CGFloat, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        if loading {
            VStack(alignment: .leading, spacing: RD.Space.md) {
                RDSectionHeader(title: "正在检索", showsChevron: false, accentMark: true)
                RDSearchSkeletonView(contentWidth: contentWidth)
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        } else if let error, results.isEmpty && suggestions.isEmpty {
            RDEmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "搜索暂时失败",
                subtitle: error,
                actionTitle: "重试"
            ) {
                RDHaptics.shared.playRetryTap()
                runSearch()
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        } else if !results.isEmpty {
            let cols = RD.gridColumns(
                contentWidth: contentWidth,
                minCardWidth: wide ? 132 : 108,
                spacing: RD.Space.md
            )
            VStack(alignment: .leading, spacing: RD.Space.md) {
                RDSectionHeader(title: "搜索结果", trailing: "共 \(results.count) 部", showsChevron: false, accentMark: true)
                LazyVGrid(columns: cols, alignment: .leading, spacing: RD.Space.lg) {
                    ForEach(results) { item in
                        NavigationLink(value: item) {
                            SeriesCard(series: item)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(RDPosterButtonStyle())
                    }
                }
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        } else if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RDSectionHeader(title: "搜索联想", trailing: "\(suggestions.count) 条", showsChevron: false, accentMark: true)
                Text("搜索 tab 接口当前返回空包，已用官方 cue 联想兜底，点条目进入详情。")
                    .font(.caption2)
                    .foregroundStyle(RD.Palette.textTertiary)
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, s in
                        if let series = seriesFromSuggestion(s) {
                            NavigationLink(value: series) {
                                HStack(spacing: 12) {
                                    RDGemPlayMark(size: 20)
                                    Text(s.text)
                                        .font(RD.Font.headline)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(RD.Palette.platinum.opacity(0.75))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RDPosterButtonStyle())
                            if idx < suggestions.count - 1 {
                                Divider().background(RD.Palette.hairline).padding(.leading, 48)
                            }
                        }
                    }
                }
                .rdGemCard(radius: RD.Radius.card, fill: RD.Palette.surface)
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        } else if searched {
            RDEmptyStateView(
                systemImage: "questionmark.folder",
                title: "没有找到相关漫剧",
                subtitle: "换个剧名或关键词试试，也可以点击上方热门搜索"
            )
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        } else {
            RDEmptyStateView(
                systemImage: "text.magnifyingglass",
                title: "输入剧名开始探索",
                subtitle: "支持剧名、题材与热搜关键词直达详情（aid=8704）"
            )
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
        }
    }

    private func seriesFromSuggestion(_ s: SearchSuggestion) -> Series? {
        guard !s.bookID.isEmpty else { return nil }
        return Series(id: s.bookID, title: s.text, cover: "", intro: "",
                      episodeCount: 0, firstVid: nil, firstIndex: 1,
                      updatedAt: Date().timeIntervalSince1970)
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading else { return }
        SearchHistoryStore.shared.add(q)
        loading = true
        error = nil
        searched = true
        results = []
        suggestions = []
        Task {
            do {
                let out = try await ManjuAPI.shared.search(query: q)
                results = out.series
                suggestions = out.suggestions
                CatalogCache.shared.ingest(out.series)
                let hasAny = !out.series.isEmpty || !out.suggestions.isEmpty
                RDHaptics.shared.playSearchOutcome(hasAny ? .success : .empty)
                AppLog.write("SEARCH UI query=\(q) results=\(out.series.count) suggestions=\(out.suggestions.count)")
            } catch {
                self.error = error.localizedDescription
                RDHaptics.shared.playSearchOutcome(.error)
                AppLog.write("SEARCH UI error=\(error.localizedDescription)")
            }
            loading = false
        }
    }
}
