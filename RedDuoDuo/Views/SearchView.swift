import SwiftUI

/// 1.4.8 搜索「浮层画册」：
/// 46 高胶囊搜索栏（聚焦出取消）→ 最近胶囊 → 两列热搜（1–3 白 / 4–10 灰）→ 3:4 海报网。
/// 小屏 2 列（距 14，键入隐底栏）；大屏搜索/空闲区居中限 560，结果 5 列（距 16）。
struct SearchView: View {
    @ObservedObject private var searchHistory = SearchHistoryStore.shared
    @ObservedObject private var chrome = RDAlbumChrome.shared

    @State private var query = ""
    @State private var results: [Series] = []
    @State private var suggestions: [SearchSuggestion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var searched = false
    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var scrollOffset: CGFloat = 0
    @State private var wasScrolledPastTopBar = false
    @State private var tint: RDAlbumTint?
    @FocusState private var searchFocused: Bool

    private let hotWords = [
        "灵葫仙缘", "御狐", "凡修逆仙", "末世第一粮仓", "开局签到荒古圣体",
        "龙王殿", "神医下山", "都市最强狂兵", "重生都市修仙", "镇国战神"
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                RDAlbumAmbientBackground(tint: tint)
                RDAlbum.C.base.opacity(0.001).ignoresSafeArea()
                RDSafeAreaProbe(insets: $safeInsets)

                GeometryReader { fullGeo in
                    let fullWidth = fullGeo.size.width
                    let wide = RD.isWide(fullWidth)
                    let horiz = RDLayoutInsets.horizontal(in: fullGeo)
                    let leadingPad = max(horiz.leading, wide ? RDAlbum.Space.pageWide : RDAlbum.Space.pageSmall)
                    let trailingPad = max(horiz.trailing, wide ? RDAlbum.Space.pageWide : RDAlbum.Space.pageSmall)
                    let contentWidth = max(1, fullWidth - leadingPad - trailingPad)
                    let topClearance = max(safeInsets.top + 56, 68)

                    ZStack(alignment: .top) {
                        ScrollViewReader { scrollProxy in
                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                                    Color.clear.frame(height: 0).id("search-top-anchor")

                                    pageHeader(wide: wide, leadingPad: leadingPad, trailingPad: trailingPad)

                                    searchBar(wide: wide, contentWidth: contentWidth)
                                        .padding(.horizontal, leadingPad)

                                    if searchFocused || query.trimmingCharacters(in: .whitespaces).isEmpty {
                                        idleContent(
                                            wide: wide,
                                            contentWidth: contentWidth,
                                            leadingPad: leadingPad,
                                            trailingPad: trailingPad
                                        )
                                    } else {
                                        resultContent(
                                            wide: wide,
                                            contentWidth: contentWidth,
                                            leadingPad: leadingPad,
                                            trailingPad: trailingPad
                                        )
                                    }
                                }
                                .padding(.top, topClearance)
                                .padding(.bottom, 96)
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
                            .scrollDismissesKeyboard(.interactively)
                            .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                if let tab = note.object as? Int, tab == 2 {
                                    withAnimation(RDAlbum.Motion.rearrange) {
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
                chrome.setBrowseChromeHidden(focused, reason: "searchTyping")
            }
            .onDisappear {
                if searchFocused { chrome.setBrowseChromeHidden(false, reason: "searchTyping") }
            }
            .task(id: results.first?.cover ?? "") {
                let cover = results.first?.cover ?? ""
                guard !cover.isEmpty else { tint = nil; return }
                tint = await RDAlbumTintStore.shared.tint(for: cover)
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
                    .font(RDAlbum.Font.rounded(19, .bold))
                    .foregroundStyle(RDAlbum.C.textPrimary)
            }
            .opacity(scrolled ? 1 : 0)

            Spacer(minLength: 8)
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

    private func pageHeader(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("搜索")
                .font(RDAlbum.Font.pageTitle)
                .foregroundStyle(RDAlbum.C.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("全站片库检索 · 关键词联想")
                .font(RDAlbum.Font.wideSub)
                .tracking(1.8)
                .foregroundStyle(RDAlbum.C.textSecondary)
        }
        .frame(maxWidth: wide ? 560 : .infinity, alignment: .leading)
        .padding(.horizontal, leadingPad)
    }

    // MARK: - 46 高胶囊搜索栏

    private func searchBar(wide: Bool, contentWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(searchFocused ? RDAlbum.C.textPrimary : RDAlbum.C.textTertiary)

                TextField("搜剧名 / 关键词", text: $query)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(RDAlbum.Font.body)
                    .foregroundStyle(RDAlbum.C.textPrimary)
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
                            .foregroundStyle(RDAlbum.C.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .rdAlbumGlass(Capsule(style: .continuous), kind: .nav, shadow: searchFocused)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(searchFocused ? RDAlbum.C.textPrimary.opacity(0.22) : .clear, lineWidth: 0.8)
            }
            .animation(RDAlbum.Motion.glow, value: searchFocused)

            if searchFocused {
                Button("取消") {
                    RDHaptics.shared.playSearchClear()
                    searchFocused = false
                    chrome.setBrowseChromeHidden(false, reason: "searchTyping")
                }
                .font(RDAlbum.Font.pill)
                .foregroundStyle(RDAlbum.C.textPrimary)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(maxWidth: wide ? 560 : .infinity)
        .frame(maxWidth: .infinity, alignment: wide ? .center : .leading)
        .animation(RDAlbum.Motion.rearrange, value: searchFocused)
    }

    // MARK: - 空闲内容：最近 + 两列热搜

    @ViewBuilder
    private func idleContent(wide: Bool, contentWidth: CGFloat, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
            if !searchHistory.queries.isEmpty {
                recentChips(leadingPad: leadingPad, trailingPad: trailingPad)
            }
            hotSearchBoard(wide: wide, leadingPad: leadingPad, trailingPad: trailingPad)

            if !suggestions.isEmpty {
                suggestionBoard(leadingPad: leadingPad, trailingPad: trailingPad)
            }
        }
        .frame(maxWidth: wide ? 560 : .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func recentChips(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.sm) {
            HStack {
                RDAlbumSectionHeader(title: "最近搜过", showsChevron: false)
                Button("清空") {
                    RDHaptics.shared.playSearchClear()
                    withAnimation(RDAlbum.Motion.rearrange) { searchHistory.clear() }
                }
                .font(RDAlbum.Font.plateSub.weight(.semibold))
                .foregroundStyle(RDAlbum.C.textTertiary)
            }
            .padding(.horizontal, leadingPad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(searchHistory.queries, id: \.self) { word in
                        HStack(spacing: 6) {
                            Button {
                                RDHaptics.shared.playChipSelect()
                                query = word
                                searchFocused = false
                                chrome.setBrowseChromeHidden(false, reason: "searchTyping")
                                runSearch()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(RDAlbum.C.textSecondary)
                                    Text(word)
                                        .font(RDAlbum.Font.rounded(13, .semibold))
                                        .foregroundStyle(RDAlbum.C.textPrimary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                RDHaptics.shared.playSearchClear()
                                withAnimation(RDAlbum.Motion.rearrange) { searchHistory.remove(word) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(RDAlbum.C.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .rdAlbumGlass(Capsule(style: .continuous), kind: .secondary, shadow: false)
                    }
                }
                .padding(.horizontal, leadingPad)
                .padding(.vertical, 2)
            }
        }
    }

    private func hotSearchBoard(wide: Bool, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.sm) {
            RDAlbumSectionHeader(title: "热门搜索", trailing: "实时", showsChevron: false)
                .padding(.horizontal, leadingPad)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12, alignment: .leading),
                    GridItem(.flexible(), spacing: 12, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(Array(hotWords.enumerated()), id: \.offset) { idx, word in
                    let rank = idx + 1
                    let top = rank <= 3
                    Button {
                        RDHaptics.shared.playChipSelect()
                        query = word
                        searchFocused = false
                        chrome.setBrowseChromeHidden(false, reason: "searchTyping")
                        runSearch()
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(rank)")
                                .font(RDAlbum.Font.rounded(14, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(top ? RDAlbum.C.textPrimary : RDAlbum.C.textTertiary)
                                .frame(width: 18, alignment: .trailing)
                            Text(word)
                                .font(RDAlbum.Font.rounded(14, top ? .semibold : .regular))
                                .foregroundStyle(top ? RDAlbum.C.textPrimary : RDAlbum.C.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if top {
                                Circle()
                                    .fill(RDAlbum.C.accentDot)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 38)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: false)
            .padding(.horizontal, leadingPad)
        }
    }

    private func suggestionBoard(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RDAlbumSectionHeader(title: "搜索联想", trailing: "\(suggestions.count) 条", showsChevron: false)
                .padding(.horizontal, leadingPad)

            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, s in
                    if let series = seriesFromSuggestion(s) {
                        NavigationLink(value: series) {
                            HStack(spacing: 12) {
                                RDGemPlayMark(size: 20)
                                Text(s.text)
                                    .font(RDAlbum.Font.plateName)
                                    .foregroundStyle(RDAlbum.C.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(RDAlbum.C.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < suggestions.count - 1 {
                            Divider().background(RDAlbum.C.textTertiary.opacity(0.18)).padding(.leading, 48)
                        }
                    }
                }
            }
            .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: false)
            .padding(.horizontal, leadingPad)
        }
    }

    // MARK: - 结果内容

    @ViewBuilder
    private func resultContent(wide: Bool, contentWidth: CGFloat, leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        if loading {
            VStack(alignment: .leading, spacing: RDAlbum.Space.md) {
                RDAlbumSectionHeader(title: "正在检索", showsChevron: false)
                    .padding(.horizontal, leadingPad)
                RDSearchSkeletonView(contentWidth: contentWidth)
                    .padding(.horizontal, leadingPad)
            }
        } else if let error, results.isEmpty && suggestions.isEmpty {
            emptyBoard(
                icon: "wifi.exclamationmark",
                title: "搜索暂时失败",
                subtitle: error,
                action: ("重试", {
                    RDHaptics.shared.playRetryTap()
                    runSearch()
                }),
                leadingPad: leadingPad
            )
        } else if !results.isEmpty {
            let spacing: CGFloat = wide ? 16 : 14
            let columns = wide ? 5 : 2
            let available = wide ? contentWidth : contentWidth
            let cardWidth = max(80, (available - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            VStack(alignment: .leading, spacing: RDAlbum.Space.md) {
                RDAlbumSectionHeader(title: "搜索结果", trailing: "共 \(results.count) 部", showsChevron: false)
                    .padding(.horizontal, leadingPad)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns),
                    alignment: .leading,
                    spacing: wide ? 24 : 22
                ) {
                    ForEach(results) { item in
                        NavigationLink(value: item) {
                            RDAlbumPosterCard(
                                series: item,
                                width: cardWidth,
                                plateHeight: RDAlbum.Poster.plateMedium,
                                badge: item.isJustUpdated ? "更新" : (item.isCompleted ? "完结" : nil)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, leadingPad)
            }
        } else if !suggestions.isEmpty {
            suggestionBoard(leadingPad: leadingPad, trailingPad: trailingPad)
        } else if searched {
            emptyBoard(
                icon: "questionmark.folder",
                title: "没有找到相关漫剧",
                subtitle: "换个剧名或关键词试试，也可以点击上方热门搜索",
                action: nil,
                leadingPad: leadingPad
            )
        } else {
            emptyBoard(
                icon: "text.magnifyingglass",
                title: "输入剧名开始探索",
                subtitle: "支持剧名、题材与热搜关键词直达详情",
                action: nil,
                leadingPad: leadingPad
            )
        }
    }

    private func emptyBoard(
        icon: String,
        title: String,
        subtitle: String,
        action: (String, () -> Void)?,
        leadingPad: CGFloat
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(RDAlbum.C.textTertiary)
            Text(title)
                .font(RDAlbum.Font.rowTitle)
                .foregroundStyle(RDAlbum.C.textPrimary)
            Text(subtitle)
                .font(RDAlbum.Font.body)
                .foregroundStyle(RDAlbum.C.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(RDAlbumGlassPillStyle(height: 40, horizontalPadding: 22))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .background {
            RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous)
                .fill(rdAlbumAdaptiveGlassFill())
        }
        .padding(.horizontal, leadingPad)
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
        searchFocused = false
        chrome.setBrowseChromeHidden(false, reason: "searchTyping")
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

private func rdAlbumAdaptiveGlassFill() -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.white.withAlphaComponent(0.62)
    })
}
