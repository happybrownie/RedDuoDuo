import SwiftUI

/// 1.4.8 我的「浮层画册」：
/// 无框账号头（64 头像 + 22 昵称 + 宽副标 / 访客 44 白登录丸）→ 书架 / 离线横滑
/// → 玻璃设置板（24 圆角、54 行：外观 / 触感 / 播放 / 缓存 / 关于）。
/// 小屏单栏；大屏左 36% 账号设置 + 右 64% 书架 3–4 列；半折上账号书架、下设置板。
struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var history: WatchHistory
    @ObservedObject private var haptics = RDHaptics.shared
    @ObservedObject private var prefs = RDPlaybackPrefs.shared
    @ObservedObject private var offline = OfflineCacheManager.shared
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system

    @State private var cloudHistory: [CloudHistoryItem] = []
    @State private var bookshelf: [BookshelfItem] = []
    @State private var loadingCloud = false
    @State private var cloudError: String?
    @State private var showLogoutConfirm = false
    @State private var showClearOfflineConfirm = false
    @State private var deviceID = ""
    @State private var safeInsets = RDScreenMetrics.keyWindowSafeAreaInsets
    @State private var scrollOffset: CGFloat = 0
    @State private var wasScrolledPastTopBar = false
    @State private var showAdvanced = false
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
                                        VStack(alignment: .leading, spacing: 24) {
                                            pageHeader(wide: true)
                                            accountHeader
                                            settingsBoard
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, topClearance)
                                        .padding(.bottom, 40)
                                    }
                                    .frame(width: panes.videoRect.width)

                                    ScrollView(showsIndicators: false) {
                                        VStack(alignment: .leading, spacing: 24) {
                                            bookshelfSection(columns: 3, horizontal: false)
                                            offlineSection(horizontal: false)
                                            cloudHistorySection
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, topClearance)
                                        .padding(.bottom, 92)
                                    }
                                    .frame(width: panes.panelRect.width)
                                }
                            } else {
                                VStack(spacing: 0) {
                                    ScrollView(showsIndicators: false) {
                                        VStack(alignment: .leading, spacing: 24) {
                                            pageHeader(wide: false)
                                            accountHeader
                                            bookshelfSection(columns: 2, horizontal: true)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.top, topClearance)
                                        .padding(.bottom, 16)
                                    }
                                    .frame(height: max(1, panes.videoRect.height - topClearance + 20))

                                    ScrollView(showsIndicators: false) {
                                        VStack(alignment: .leading, spacing: 24) {
                                            settingsBoard
                                            offlineSection(horizontal: true)
                                            cloudHistorySection
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.top, 16)
                                        .padding(.bottom, 92)
                                    }
                                    .frame(height: max(1, panes.panelRect.height))
                                }
                            }
                        } else if wide {
                            ScrollViewReader { scrollProxy in
                                ScrollView(showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                                        Color.clear.frame(height: 0).id("profile-top-anchor")
                                        pageHeader(wide: true)

                                        HStack(alignment: .top, spacing: 28) {
                                            VStack(alignment: .leading, spacing: 24) {
                                                accountHeader
                                                settingsBoard
                                            }
                                            .frame(width: max(1, contentWidth * 0.36))

                                            VStack(alignment: .leading, spacing: 24) {
                                                bookshelfSection(columns: 4, horizontal: false)
                                                offlineSection(horizontal: false)
                                                cloudHistorySection
                                            }
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                                .refreshable { await refreshAll() }
                                .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                    if let tab = note.object as? Int, tab == 4 {
                                        withAnimation(RDAlbum.Motion.rearrange) {
                                            scrollProxy.scrollTo("profile-top-anchor", anchor: .top)
                                        }
                                    }
                                }
                            }
                        } else {
                            ScrollViewReader { scrollProxy in
                                ScrollView(showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: RDAlbum.Space.xl) {
                                        Color.clear.frame(height: 0).id("profile-top-anchor")
                                        pageHeader(wide: false)
                                        accountHeader
                                        bookshelfSection(columns: 2, horizontal: true)
                                        offlineSection(horizontal: true)
                                        settingsBoard
                                        cloudHistorySection
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
                                .refreshable { await refreshAll() }
                                .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                    if let tab = note.object as? Int, tab == 4 {
                                        withAnimation(RDAlbum.Motion.rearrange) {
                                            scrollProxy.scrollTo("profile-top-anchor", anchor: .top)
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
            .sheet(isPresented: $auth.showLoginSheet) {
                LoginView()
                    .environmentObject(auth)
            }
            .alert("退出登录", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出登录", role: .destructive) {
                    RDHaptics.shared.playLogoutConfirm()
                    auth.logout()
                    cloudHistory = []
                    bookshelf = []
                }
            } message: {
                Text("退出后将切回游客模式，本地观看记录和当前设备身份会保留。")
            }
            .alert("清空全部离线缓存", isPresented: $showClearOfflineConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空全部", role: .destructive) {
                    offline.clearAllCache()
                }
            } message: {
                Text("将删除所有已下载解密的离线剧集（共 \(offline.recordsByVid.count) 集），释放本地存储空间。")
            }
            .onAppear {
                offline.isOfflineUIVisible = true
                Task { await offline.reconcileWithDisk() }
            }
            .onDisappear {
                offline.isOfflineUIVisible = false
            }
            .task(id: auth.sessionVersion) {
                await reloadAccountData()
            }
            .task(id: tintKey) {
                guard !tintKey.isEmpty else { tint = nil; return }
                tint = await RDAlbumTintStore.shared.tint(for: tintKey)
            }
        }
    }

    private var tintKey: String {
        if let cover = bookshelf.first?.cover, !cover.isEmpty { return cover }
        return history.entries.first?.cover ?? ""
    }

    // MARK: - 顶栏 / 页头

    private func topBar(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let scrolled = scrollOffset > 28
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                RDGemPlayMark(size: 22)
                Text("我的")
                    .font(RDAlbum.Font.rounded(19, .bold))
                    .foregroundStyle(RDAlbum.C.textPrimary)
            }
            .opacity(scrolled ? 1 : 0)

            Spacer(minLength: 8)

            if auth.isLoggedIn {
                Button {
                    RDHaptics.shared.playGlassTap()
                    Task { await reloadAccountData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RDAlbum.C.textPrimary)
                        .frame(width: 32, height: 32)
                        .rdAlbumGlass(Circle(), kind: .secondary, shadow: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新账号数据")
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
        VStack(alignment: .leading, spacing: 6) {
            Text("我的")
                .font(RDAlbum.Font.pageTitle)
                .foregroundStyle(RDAlbum.C.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(auth.isLoggedIn ? "云端续播 · 个人书架 · 播放偏好" : "登录以同步云端记录与书架")
                .font(RDAlbum.Font.wideSub)
                .tracking(1.8)
                .foregroundStyle(RDAlbum.C.textSecondary)
        }
    }

    // MARK: - 无框账号头

    @ViewBuilder
    private var accountHeader: some View {
        if let user = auth.currentUser, let sess = auth.session {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    avatarView(url: user.avatarURL)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(RDAlbum.Font.rounded(22, .semibold))
                            .foregroundStyle(RDAlbum.C.textPrimary)
                            .lineLimit(1)
                        Text(authMetaLine(uid: user.userID, exp: sess.expiresAt))
                            .font(RDAlbum.Font.wideSub)
                            .tracking(1.6)
                            .foregroundStyle(RDAlbum.C.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)

                HStack(spacing: 10) {
                    Button {
                        RDHaptics.shared.playGlassTap()
                        showLogoutConfirm = true
                    } label: {
                        Text("退出登录")
                    }
                    .buttonStyle(RDAlbumGlassPillStyle(height: 36, horizontalPadding: 18))
                    .accessibilityIdentifier("profile-logout-button")

                    Button {
                        RDHaptics.shared.playGlassTap()
                        Task { await reloadAccountData() }
                    } label: {
                        Label("同步云端", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(RDAlbumGlassPillStyle(height: 36, horizontalPadding: 16))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(rdAlbumAdaptiveGlassFill())
                            .frame(width: 64, height: 64)
                        RDGemPlayMark(size: 34)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("游客模式")
                            .font(RDAlbum.Font.rounded(22, .semibold))
                            .foregroundStyle(RDAlbum.C.textPrimary)
                        Text("已在本机记住 \(history.entries.count) 部进度")
                            .font(RDAlbum.Font.wideSub)
                            .tracking(1.6)
                            .foregroundStyle(RDAlbum.C.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        RDHaptics.shared.playLoginSheetOpen()
                        auth.showLoginSheet = true
                    } label: {
                        Label("登录", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(RDAlbumPrimaryPillStyle(height: 44, horizontalPadding: 18))
                    .accessibilityIdentifier("profile-login-button")
                }
                Text("登录后同步云端观看记录与书架收藏，并开启首页个性化推荐。")
                    .font(RDAlbum.Font.body)
                    .foregroundStyle(RDAlbum.C.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func authMetaLine(uid: String, exp: Double?) -> String {
        var parts: [String] = []
        if !uid.isEmpty { parts.append("UID \(uid)") }
        parts.append("会话有效")
        if let exp, exp > 0 { parts.append("至 \(dateText(exp))") }
        return parts.joined(separator: " · ")
    }

    private static var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var appBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    // MARK: - 书架

    @ViewBuilder
    private func bookshelfSection(columns: Int, horizontal: Bool) -> some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
            HStack(alignment: .firstTextBaseline) {
                RDAlbumSectionHeader(
                    title: "我的书架",
                    trailing: bookshelf.isEmpty ? nil : "\(bookshelf.count) 部",
                    showsChevron: false
                )
                if loadingCloud {
                    ProgressView().controlSize(.mini).tint(RDAlbum.C.textPrimary)
                }
            }

            if bookshelf.isEmpty {
                inlineEmpty(
                    icon: "bookmark",
                    title: auth.isLoggedIn ? "书架还是空的" : "登录后显示云端书架",
                    subtitle: "在详情页点击「追剧」即可加入书架"
                )
            } else if horizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: RDAlbum.Space.cardGapSmall) {
                        ForEach(bookshelf) { item in
                            NavigationLink(value: item.toSeries()) {
                                RDAlbumPosterCard(
                                    series: item.toSeries(),
                                    width: RDAlbum.Poster.mediumSmall,
                                    plateHeight: RDAlbum.Poster.plateMedium
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                GeometryReader { geo in
                    let spacing: CGFloat = 14
                    let cardWidth = max(80, (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns),
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(bookshelf) { item in
                            NavigationLink(value: item.toSeries()) {
                                RDAlbumPosterCard(
                                    series: item.toSeries(),
                                    width: cardWidth,
                                    plateHeight: RDAlbum.Poster.plateMedium
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: shelfGridHeight(columns: columns, count: bookshelf.count))
            }
        }
    }

    private func shelfGridHeight(columns: Int, count: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(count) / Double(max(columns, 1)))))
        let cardWidth: CGFloat = 150
        return CGFloat(rows) * (cardWidth * 4 / 3 + 46 + 22) + 8
    }

    // MARK: - 离线横滑

    @ViewBuilder
    private func offlineSection(horizontal: Bool) -> some View {
        let groups = offline.seriesGroups
        VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
            HStack(alignment: .firstTextBaseline) {
                RDAlbumSectionHeader(
                    title: "离线追剧包",
                    trailing: groups.isEmpty ? "0 MB" : ByteCountFormatter.string(fromByteCount: offline.totalDiskBytes, countStyle: .file),
                    showsChevron: false
                )
                if !groups.isEmpty {
                    Button("清空") {
                        RDHaptics.shared.playGlassTap()
                        showClearOfflineConfirm = true
                    }
                    .font(RDAlbum.Font.plateSub.weight(.semibold))
                    .foregroundStyle(RDAlbum.C.textSecondary)
                }
            }

            if let batchTitle = offline.activeBatchTitle, offline.isDownloadingBatch {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(RDAlbum.C.textPrimary)
                    Text("正在缓存：\(batchTitle)（\(offline.batchDoneCount)/\(offline.batchTotalCount)）")
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button("停止") {
                        RDHaptics.shared.playGlassTap()
                        offline.cancelPendingQueue()
                    }
                    .font(RDAlbum.Font.plateSub.weight(.semibold))
                    .foregroundStyle(RDAlbum.C.textPrimary)
                }
                .padding(10)
                .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous), kind: .secondary, shadow: false)
            }

            if groups.isEmpty {
                inlineEmpty(
                    icon: "arrow.down.circle",
                    title: "暂无离线剧集",
                    subtitle: "在详情页或播放器抽屉可一键缓存，看完自动清理"
                )
            } else if horizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RDAlbum.Space.cardGapSmall) {
                        ForEach(groups) { group in
                            offlineTile(group, width: 250)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 1),
                    spacing: 12
                ) {
                    ForEach(groups) { group in
                        offlineTile(group, width: nil)
                    }
                }
            }
        }
    }

    private func offlineTile(_ group: OfflineSeriesGroup, width: CGFloat?) -> some View {
        let sizeText = ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file)
        let seriesObj = Series(
            id: group.seriesID,
            title: group.title,
            cover: group.cover,
            intro: "",
            episodeCount: max(group.records.last?.episodeIndex ?? 1, group.records.count),
            firstVid: group.records.first?.vid,
            firstIndex: group.records.first?.episodeIndex ?? 1,
            updatedAt: group.records.last?.cachedAt ?? 0
        )
        return HStack(spacing: 12) {
            NavigationLink(value: seriesObj) {
                HStack(spacing: 12) {
                    RemoteCover(url: group.cover, thumbnailMaxPixel: 220)
                        .frame(width: 52, height: 76)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(RDAlbum.Font.plateName)
                            .foregroundStyle(RDAlbum.C.textPrimary)
                            .lineLimit(1)
                        Text("已缓存 \(group.records.count) 集 · \(sizeText)")
                            .font(RDAlbum.Font.plateSub)
                            .foregroundStyle(RDAlbum.C.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                offline.removeSeries(seriesID: group.seriesID)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RDAlbum.C.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(rdAlbumAdaptiveGlassFill(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清理本剧离线缓存")
        }
        .padding(12)
        .frame(width: width)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: false)
    }

    // MARK: - 玻璃设置板（24 圆角 / 54 行）

    private var settingsBoard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsRow(title: "外观", subtitle: "浅色 / 深色 / 跟随系统") {
                appearanceSegments
            }
            rowDivider

            settingsRow(title: "触感浓度", subtitle: haptics.density.subtitle) {
                densitySegments
            }
            rowDivider

            toggleRow("上下滑跟手切集", subtitle: "播放视频区上下滑动过 1/3 屏切集", binding: $prefs.verticalSwipeEnabled)
            rowDivider
            toggleRow("播完自动连播下一集", subtitle: "提前备好后两集，集尾 3 秒切换", binding: $prefs.autoPlayNextEnabled)
            rowDivider
            toggleRow("自动跳过片头片尾", subtitle: "起播跳片头，接近片尾进入下一集", binding: $prefs.skipIntroOutroEnabled)
            rowDivider
            toggleRow("后台小窗与息屏听剧", subtitle: "切后台小窗，锁屏保持后台连播", binding: $prefs.backgroundAudioEnabled)
            rowDivider
            toggleRow("离线剧集看完自动清理", subtitle: "已看完的缓存集自动释放空间", binding: $prefs.autoCleanWatchedOffline)
            rowDivider

            settingsRow(
                title: "离线缓存",
                subtitle: offline.seriesGroups.isEmpty ? "暂无离线剧集" : "\(offline.seriesGroups.count) 部 · \(ByteCountFormatter.string(fromByteCount: offline.totalDiskBytes, countStyle: .file))"
            ) {
                if !offline.seriesGroups.isEmpty {
                    Button("清理") {
                        RDHaptics.shared.playGlassTap()
                        showClearOfflineConfirm = true
                    }
                    .font(RDAlbum.Font.plateSub.weight(.semibold))
                    .foregroundStyle(RDAlbum.C.textSecondary)
                }
            }
            rowDivider

            Button {
                RDHaptics.shared.playChipSelect()
                withAnimation(RDAlbum.Motion.rearrange) { showAdvanced.toggle() }
            } label: {
                settingsRow(
                    title: "关于",
                    subtitle: "RedDuoDuo \(Self.appShortVersion) (\(Self.appBuildVersion))"
                ) {
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RDAlbum.C.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 5) {
                    Text("固定设备 ID：\(deviceID.isEmpty ? (auth.currentDeviceID.isEmpty ? "待首次请求注册" : auth.currentDeviceID) : deviceID)")
                        .monospacedDigit()
                    Text("外观：\(appearanceMode.title) · 触感：\(haptics.density.title)")
                }
                .font(RDAlbum.Font.plateSub)
                .foregroundStyle(RDAlbum.C.textTertiary)
                .padding(.top, 10)
                .transition(.opacity)
            }

            if let cloudError, !cloudError.isEmpty {
                Text(cloudError)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.accentDot)
                    .lineLimit(2)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.board, style: .continuous), kind: .drawer)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(rdAlbumAdaptiveGlassStroke())
            .frame(height: 0.5)
    }

    private func settingsRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RDAlbum.Font.plateName)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                Text(subtitle)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 54)
        .padding(.vertical, 2)
    }

    private func toggleRow(_ title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RDAlbum.Font.plateName)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                Text(subtitle)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { binding.wrappedValue },
                set: { next in
                    binding.wrappedValue = next
                    RDHaptics.shared.playChipSelect()
                }
            ))
            .labelsHidden()
            .tint(RD.Palette.accent)
        }
        .frame(minHeight: 54)
        .padding(.vertical, 2)
    }

    private var appearanceSegments: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceMode.allCases) { mode in
                let active = appearanceMode == mode
                Button {
                    RDHaptics.shared.playChipSelect()
                    appearanceMode = mode
                } label: {
                    Text(mode.title)
                        .font(RDAlbum.Font.rounded(11, .semibold))
                        .foregroundStyle(active ? RDAlbum.C.inverse : RDAlbum.C.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background {
                            if active {
                                Capsule(style: .continuous).fill(Color.white)
                            } else {
                                Capsule(style: .continuous).fill(Color.white.opacity(0.0001))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(rdAlbumAdaptiveGlassFill()))
    }

    private var densitySegments: some View {
        HStack(spacing: 4) {
            ForEach(RDHapticDensity.allCases) { mode in
                let active = haptics.density == mode
                Button {
                    haptics.density = mode
                    RDHaptics.shared.playDensitySample()
                } label: {
                    Text(mode.title)
                        .font(RDAlbum.Font.rounded(11, .semibold))
                        .foregroundStyle(active ? RDAlbum.C.inverse : RDAlbum.C.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background {
                            if active {
                                Capsule(style: .continuous).fill(Color.white)
                            } else {
                                Capsule(style: .continuous).fill(Color.white.opacity(0.0001))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(rdAlbumAdaptiveGlassFill()))
    }

    // MARK: - 云端观看记录

    @ViewBuilder
    private var cloudHistorySection: some View {
        if auth.isLoggedIn {
            VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
                HStack(alignment: .firstTextBaseline) {
                    RDAlbumSectionHeader(
                        title: "云端观看记录",
                        trailing: cloudHistory.isEmpty ? nil : "\(cloudHistory.count) 部",
                        showsChevron: false
                    )
                    if loadingCloud {
                        ProgressView().controlSize(.mini).tint(RDAlbum.C.textPrimary)
                    } else {
                        Button("同步") {
                            RDHaptics.shared.playGlassTap()
                            Task { await reloadAccountData() }
                        }
                        .font(RDAlbum.Font.plateSub.weight(.semibold))
                        .foregroundStyle(RDAlbum.C.textSecondary)
                    }
                }

                if cloudHistory.isEmpty {
                    inlineEmpty(
                        icon: "clock.arrow.circlepath",
                        title: "暂无云端记录",
                        subtitle: "登录状态下观看剧集，进度会自动同步"
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(cloudHistory.prefix(8)) { item in
                            NavigationLink(value: item.toSeries()) {
                                HStack(spacing: 12) {
                                    RemoteCover(url: item.cover, thumbnailMaxPixel: 220)
                                        .frame(width: 52, height: 76)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title.isEmpty ? "剧目 \(item.seriesID)" : item.title)
                                            .font(RDAlbum.Font.plateName)
                                            .foregroundStyle(RDAlbum.C.textPrimary)
                                            .lineLimit(1)
                                        Text("第 \(item.episodeIndex) 集 · \(HistoryEntry.formatTime(item.positionSeconds))")
                                            .font(RDAlbum.Font.plateSub)
                                            .foregroundStyle(RDAlbum.C.textSecondary)
                                        if item.updatedAt > 0 {
                                            Text(dateText(item.updatedAt))
                                                .font(RDAlbum.Font.plateSub)
                                                .foregroundStyle(RDAlbum.C.textTertiary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(RDAlbum.C.textTertiary)
                                }
                                .padding(12)
                                .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func inlineEmpty(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(RDAlbum.C.textTertiary)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RDAlbum.Font.plateName)
                    .foregroundStyle(RDAlbum.C.textSecondary)
                Text(subtitle)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: false)
    }

    // MARK: - 数据

    private func handleScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
        let crossed = offset > 28
        if crossed && !wasScrolledPastTopBar {
            RDHaptics.shared.playStickyBarCrossed()
        }
        wasScrolledPastTopBar = crossed
    }

    private func refreshAll() async {
        RDHaptics.shared.playPullRefreshTriggered()
        await reloadAccountData()
        RDHaptics.shared.playPullRefreshComplete()
    }

    private func avatarView(url: String) -> some View {
        Group {
            if let u = URL(string: url), !url.isEmpty {
                CachedAsyncImage(url: u) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(rdAlbumAdaptiveGlassFill())
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(RDAlbum.C.textTertiary)
        }
    }

    private func reloadAccountData() async {
        if let id = await ManjuAPI.shared.currentIdentity() {
            deviceID = id.deviceID
        }
        guard auth.isLoggedIn, let uid = auth.session?.user.userID else { return }
        loadingCloud = true
        cloudError = nil
        await auth.refreshUserInfo()
        do {
            async let h = ManjuAPI.shared.fetchCloudHistory()
            async let b = ManjuAPI.shared.fetchBookshelf(uid: uid)
            cloudHistory = try await h
            if let loadedShelf = try? await b {
                bookshelf = loadedShelf
                FollowStore.shared.syncBookshelf(loadedShelf)
            } else {
                bookshelf = []
            }
        } catch let err as ManjuError {
            if case .sessionExpired(let reason) = err {
                auth.handleRemoteSessionInvalidated(reason: reason)
            } else {
                cloudError = err.localizedDescription
            }
        } catch {
            cloudError = error.localizedDescription
        }
        loadingCloud = false
    }

    private func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    private func dateText(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
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

private func rdAlbumAdaptiveGlassStroke() -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.07)
    })
}
