import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var history: WatchHistory
    @ObservedObject private var haptics = RDHaptics.shared
    @ObservedObject private var prefs = RDPlaybackPrefs.shared
    @ObservedObject private var offline = OfflineCacheManager.shared

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
                                VStack(alignment: .leading, spacing: RD.Space.xl) {
                                    Color.clear.frame(height: 0).id("profile-top-anchor")
                                    pageHeader

                                    if let notice = auth.sessionExpiredNotice {
                                        RDNotice(text: notice, actionTitle: "知道了") {
                                            RDHaptics.shared.playGlassTap()
                                            auth.clearExpiredNotice()
                                        }
                                    }

                                    if wide {
                                        HStack(alignment: .top, spacing: RD.Space.xl) {
                                            VStack(alignment: .leading, spacing: RD.Space.lg) {
                                                accountCard
                                                hapticDensityCard
                                                playbackSettingsCard
                                                deviceIdentityCard
                                            }
                                            .frame(width: min(contentWidth * 0.44, 410))

                                            VStack(alignment: .leading, spacing: RD.Space.lg) {
                                                offlinePackSection
                                                if auth.isLoggedIn {
                                                    loggedInCollections(wide: true)
                                                } else {
                                                    guestInfoCard
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: RD.Space.lg) {
                                            accountCard
                                            hapticDensityCard
                                            playbackSettingsCard
                                            offlinePackSection
                                            if auth.isLoggedIn {
                                                loggedInCollections(wide: false)
                                            } else {
                                                guestInfoCard
                                            }
                                            deviceIdentityCard
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
                                await reloadAccountData()
                                RDHaptics.shared.playPullRefreshComplete()
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .rdScrollToTop)) { note in
                                if let tab = note.object as? Int, tab == 4 {
                                    withAnimation(RD.Motion.snappy) {
                                        scrollProxy.scrollTo("profile-top-anchor", anchor: .top)
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
            .onChange(of: auth.sessionExpiredNotice) { _, notice in
                if notice != nil {
                    RDHaptics.shared.playSessionExpiredNotice()
                }
            }
            .task(id: auth.sessionVersion) {
                await reloadAccountData()
            }
        }
    }

    // MARK: - 顶栏与大标题

    private func topBar(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        let scrolled = scrollOffset > 28
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                RDGemPlayMark(size: 22)
                Text("我的")
                    .font(RD.Font.rowTitle)
                    .foregroundStyle(RD.Palette.textPrimary)
                    .rdTitleShadow()
            }
            .opacity(scrolled ? 1 : 0)

            Spacer(minLength: 8)

            if auth.isLoggedIn {
                Button {
                    RDHaptics.shared.playGlassTap()
                    Task { await reloadAccountData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .rdGlassCircle()
                }
                .buttonStyle(RDPosterButtonStyle())
                .accessibilityLabel("刷新账号数据")
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
                RDBadgePill(text: auth.isLoggedIn ? "红果会员态" : "游客模式", accent: auth.isLoggedIn)
                if auth.isLoggedIn {
                    Text("已绑定设备")
                        .font(RD.Font.caption.weight(.semibold))
                        .foregroundStyle(RD.Palette.textSecondary)
                }
            }
            Text("我的")
                .font(RD.Font.displayLarge)
                .foregroundStyle(RD.Palette.textPrimary)
                .rdTitleShadow()
                .accessibilityAddTraits(.isHeader)
            Text(auth.isLoggedIn ? "账号信息、云端续播与个人书架" : "登录红果账号以同步云端记录与书架收藏")
                .font(RD.Font.body)
                .foregroundStyle(RD.Palette.textSecondary)
        }
    }

    // MARK: - 账号宝石卡（未登录：醒目宝石风登录入口 / 已登录：账号资料 + 退出登录）

    @ViewBuilder
    private var accountCard: some View {
        if let user = auth.currentUser, let sess = auth.session {
            VStack(alignment: .leading, spacing: RD.Space.md) {
                HStack(spacing: 14) {
                    avatarView(url: user.avatarURL)
                        .overlay(
                            Circle()
                                .strokeBorder(RD.Gem.anchorBorderGradient, lineWidth: 1.1)
                        )
                        .shadow(color: RD.Palette.gemCore.opacity(0.42), radius: 7, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(RD.Font.title)
                            .foregroundStyle(RD.Palette.textPrimary)
                            .lineLimit(1)
                        if !user.userID.isEmpty {
                            Text("UID：\(user.userID)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(RD.Palette.textSecondary)
                        }
                        if !user.mobile.isEmpty {
                            Text("手机：\(user.mobile)")
                                .font(.caption)
                                .foregroundStyle(RD.Palette.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Divider().background(RD.Palette.hairline)

                HStack(alignment: .center, spacing: RD.Space.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(RD.Palette.pearl)
                                .frame(width: 7, height: 7)
                                .shadow(color: RD.Palette.pearl.opacity(0.65), radius: 4)
                            Text("会话状态：已登录")
                                .font(RD.Font.caption.weight(.bold))
                                .foregroundStyle(RD.Palette.textPrimary)
                        }
                        if let exp = sess.expiresAt {
                            Text("凭据有效期至 \(dateText(exp))")
                                .font(.caption2)
                                .foregroundStyle(RD.Palette.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("退出登录") {
                        RDHaptics.shared.playGlassTap()
                        showLogoutConfirm = true
                    }
                    .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 14, verticalPadding: 8))
                    .accessibilityIdentifier("profile-logout-button")
                }
            }
            .padding(RD.Space.lg)
            .rdGemCard(radius: RD.Radius.sheet, fill: RD.Palette.surface, glow: true)
        } else {
            VStack(alignment: .leading, spacing: RD.Space.md) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(RD.Palette.gemVoid)
                            .frame(width: 56, height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(RD.Gem.anchorBorderGradient, lineWidth: 1.0)
                            )
                            .shadow(color: RD.Palette.gemCore.opacity(0.36), radius: 8, y: 2)
                        RDGemPlayMark(size: 32)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        RDBadgePill(text: "红果通行证", accent: true)
                        Text("登录红果账号")
                            .font(RD.Font.title)
                            .foregroundStyle(RD.Palette.textPrimary)
                    }
                    Spacer(minLength: 0)
                }

                Text("登录后即可同步云端观看记录、我的书架收藏，并开启首页个性化推荐漫剧。")
                    .font(RD.Font.body)
                    .foregroundStyle(RD.Palette.textSecondary)
                    .lineSpacing(3)

                Button {
                    RDHaptics.shared.playLoginSheetOpen()
                    auth.showLoginSheet = true
                } label: {
                    Label("立即登录", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(RDGemPrimaryButtonStyle())
                .accessibilityIdentifier("profile-login-button")
            }
            .padding(RD.Space.lg)
            .rdGemCard(radius: RD.Radius.sheet, fill: RD.Palette.surface, glow: true)
        }
    }

    // MARK: - 已登录云端数据区

    @ViewBuilder
    private func loggedInCollections(wide: Bool) -> some View {
        if loadingCloud && cloudHistory.isEmpty && bookshelf.isEmpty {
            RDProfileSkeletonView()
        } else {
            cloudHistorySection
            bookshelfSection(wide: wide)
        }
    }

    private var cloudHistorySection: some View {
        VStack(alignment: .leading, spacing: RD.Space.md) {
            HStack {
                RDSectionHeader(
                    title: "云端观看记录",
                    trailing: cloudHistory.isEmpty ? nil : "\(cloudHistory.count) 部",
                    showsChevron: false,
                    accentMark: true
                )
                if loadingCloud {
                    ProgressView().controlSize(.small).tint(RD.Palette.gemBright)
                } else {
                    Button("同步") {
                        RDHaptics.shared.playGlassTap()
                        Task { await reloadAccountData() }
                    }
                    .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 11, verticalPadding: 5))
                }
            }

            if let cloudError, cloudHistory.isEmpty {
                RDEmptyStateView(
                    systemImage: "exclamationmark.icloud",
                    title: "云端记录同步失败",
                    subtitle: cloudError,
                    actionTitle: "重试"
                ) {
                    Task { await reloadAccountData() }
                }
            } else if cloudHistory.isEmpty {
                RDEmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "暂无云端观看记录",
                    subtitle: "在已登录状态下观看剧集，进度将自动同步到这里"
                )
            } else {
                VStack(spacing: RD.Space.sm) {
                    ForEach(cloudHistory.prefix(15)) { item in
                        NavigationLink(value: item.toSeries()) {
                            HStack(spacing: 12) {
                                RemoteCover(url: item.cover)
                                    .frame(width: 56, height: 82)
                                    .rdGemPosterChrome()

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title.isEmpty ? "剧目 \(item.seriesID)" : item.title)
                                        .font(RD.Font.headline)
                                        .foregroundStyle(RD.Palette.textPrimary)
                                        .lineLimit(1)
                                    Text("第 \(item.episodeIndex) 集 · \(HistoryEntry.formatTime(item.positionSeconds))")
                                        .font(RD.Font.caption.weight(.semibold))
                                        .foregroundStyle(RD.Palette.gemText)
                                    if item.updatedAt > 0 {
                                        Text(dateText(item.updatedAt))
                                            .font(.caption2)
                                            .foregroundStyle(RD.Palette.textTertiary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(RD.Palette.platinum.opacity(0.75))
                            }
                            .padding(RD.Space.md)
                            .rdGemCard()
                        }
                        .buttonStyle(RDPosterButtonStyle())
                    }
                }
            }
        }
    }

    private func bookshelfSection(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: RD.Space.md) {
            RDSectionHeader(
                title: "我的收藏（书架）",
                trailing: bookshelf.isEmpty ? nil : "\(bookshelf.count) 部",
                showsChevron: false,
                accentMark: true
            )

            if bookshelf.isEmpty {
                RDEmptyStateView(
                    systemImage: "bookmark",
                    title: "暂无云端收藏",
                    subtitle: "可在任意剧集详情页点击书签按钮加入收藏"
                )
            } else {
                let cols = Array(repeating: GridItem(.flexible(), spacing: RD.Space.md), count: wide ? 2 : 1)
                LazyVGrid(columns: cols, spacing: RD.Space.sm) {
                    ForEach(bookshelf) { item in
                        NavigationLink(value: item.toSeries()) {
                            HStack(spacing: 12) {
                                RemoteCover(url: item.cover)
                                    .frame(width: 56, height: 82)
                                    .rdGemPosterChrome()

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title.isEmpty ? "剧目 ID \(item.seriesID)" : item.title)
                                        .font(RD.Font.headline)
                                        .foregroundStyle(RD.Palette.textPrimary)
                                        .lineLimit(1)
                                    Text(item.episodeCount > 0 ? "共 \(item.episodeCount) 集" : "点击查看详情")
                                        .font(RD.Font.caption)
                                        .foregroundStyle(RD.Palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(RD.Palette.platinum.opacity(0.75))
                            }
                            .padding(RD.Space.md)
                            .rdGemCard()
                        }
                        .buttonStyle(RDPosterButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - 触感浓度、追剧偏好与离线追剧包管理

    private var hapticDensityCard: some View {
        VStack(alignment: .leading, spacing: RD.Space.md) {
            RDSectionHeader(title: "宝石触感浓度", trailing: haptics.density.title, showsChevron: false, accentMark: true)

            HStack(spacing: 8) {
                ForEach(RDHapticDensity.allCases) { mode in
                    let active = haptics.density == mode
                    Button {
                        haptics.density = mode
                        RDHaptics.shared.playDensitySample()
                    } label: {
                        Text(mode.title)
                            .font(RD.Font.caption.weight(.bold))
                            .foregroundStyle(active ? .white : RD.Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if active {
                                    RDGemFacetSurface(
                                        shape: RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous),
                                        shadowRadius: 6,
                                        borderWidth: 0.9
                                    )
                                } else {
                                    RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                                        .fill(RD.Palette.surfaceRaised)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                                                .strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.7)
                                        )
                                }
                            }
                    }
                    .buttonStyle(RDPosterButtonStyle())
                }
            }

            Text(haptics.density.subtitle)
                .font(.caption2)
                .foregroundStyle(RD.Palette.textTertiary)
        }
        .padding(RD.Space.lg)
        .rdGemCard()
    }

    private var playbackSettingsCard: some View {
        VStack(alignment: .leading, spacing: RD.Space.md) {
            RDSectionHeader(title: "追剧与播放偏好", showsChevron: false, accentMark: true)

            prefToggleRow(
                title: "上下滑跟手切集",
                subtitle: "播放视频区上下滑动过 1/3 屏切集，横竖屏均可用",
                binding: $prefs.verticalSwipeEnabled
            )
            Divider().background(RD.Palette.hairline)

            prefToggleRow(
                title: "播完自动连播下一集",
                subtitle: "提前备好后两集，集尾倒计时 3 秒丝滑切入",
                binding: $prefs.autoPlayNextEnabled
            )
            Divider().background(RD.Palette.hairline)

            prefToggleRow(
                title: "自动跳过片头片尾",
                subtitle: "起播自动跳过片头，接近片尾时自动进入下一集",
                binding: $prefs.skipIntroOutroEnabled
            )
            Divider().background(RD.Palette.hairline)

            prefToggleRow(
                title: "后台小窗与息屏听剧",
                subtitle: "切后台自动小窗，锁屏或音频模式下保持后台连播",
                binding: $prefs.backgroundAudioEnabled
            )
            Divider().background(RD.Palette.hairline)

            prefToggleRow(
                title: "离线剧集看完自动清理",
                subtitle: "开启后，已看完的离线缓存集在切走或退出时自动释放",
                binding: $prefs.autoCleanWatchedOffline
            )
        }
        .padding(RD.Space.lg)
        .rdGemCard()
    }

    private func prefToggleRow(title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { binding.wrappedValue },
            set: { next in
                binding.wrappedValue = next
                RDHaptics.shared.playChipSelect()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RD.Font.headline)
                    .foregroundStyle(RD.Palette.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(RD.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(RD.Palette.accent)
    }

    private var offlinePackSection: some View {
        let groups = offline.seriesGroups
        let totalSizeText = ByteCountFormatter.string(fromByteCount: offline.totalDiskBytes, countStyle: .file)

        return VStack(alignment: .leading, spacing: RD.Space.md) {
            HStack {
                RDSectionHeader(
                    title: "离线追剧包管理",
                    trailing: offline.totalDiskBytes > 0 ? totalSizeText : "0 MB",
                    showsChevron: false,
                    accentMark: true
                )
                if !groups.isEmpty || offline.totalDiskBytes > 0 {
                    Button("清空") {
                        RDHaptics.shared.playGlassTap()
                        showClearOfflineConfirm = true
                    }
                    .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 11, verticalPadding: 5))
                }
            }

            if let batchTitle = offline.activeBatchTitle, offline.isDownloadingBatch {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(RD.Palette.gemBright)
                    Text("正在缓存：\(batchTitle)（\(offline.batchDoneCount)/\(offline.batchTotalCount)）")
                        .font(.caption2)
                        .foregroundStyle(RD.Palette.gemAccentText)
                        .lineLimit(1)
                    Spacer()
                    Button("停止") {
                        RDHaptics.shared.playGlassTap()
                        offline.cancelPendingQueue()
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(RD.Palette.warning)
                }
                .padding(10)
                .rdGemCard(radius: RD.Radius.control, fill: RD.Palette.surfaceRaised)
            }

            if groups.isEmpty {
                RDEmptyStateView(
                    systemImage: "arrow.down.circle",
                    title: "暂无离线剧集",
                    subtitle: "在剧集详情页或播放器抽屉可一键缓存后续 10 集或全集，支持看完自动清理"
                )
            } else {
                VStack(spacing: RD.Space.sm) {
                    ForEach(groups) { group in
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
                        HStack(spacing: 12) {
                            NavigationLink(value: seriesObj) {
                                HStack(spacing: 12) {
                                    RemoteCover(url: group.cover)
                                        .frame(width: 52, height: 76)
                                        .rdGemPosterChrome()

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.title)
                                            .font(RD.Font.headline)
                                            .foregroundStyle(RD.Palette.textPrimary)
                                            .lineLimit(1)
                                        Text("已缓存 \(group.records.count) 集 · \(sizeText)")
                                            .font(RD.Font.caption.weight(.semibold))
                                            .foregroundStyle(RD.Palette.gemText)
                                        if let firstIdx = group.records.first?.episodeIndex,
                                           let lastIdx = group.records.last?.episodeIndex {
                                            Text(firstIdx == lastIdx ? "第 \(firstIdx) 集" : "第 \(firstIdx)–\(lastIdx) 集")
                                                .font(.caption2)
                                                .foregroundStyle(RD.Palette.textTertiary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RDPosterButtonStyle())

                            Button {
                                offline.removeSeries(seriesID: group.seriesID)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(RD.Palette.textTertiary)
                                    .frame(width: 30, height: 30)
                                    .background(RD.Palette.surfaceRaised, in: Circle())
                                    .overlay(Circle().strokeBorder(RD.Palette.hairline, lineWidth: 0.6))
                            }
                            .buttonStyle(RDPosterButtonStyle())
                            .accessibilityLabel("清理本剧离线缓存")
                        }
                        .padding(RD.Space.md)
                        .rdGemCard()
                    }
                }
            }
        }
    }

    // MARK: - 游客进度与设备信息

    private var guestInfoCard: some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            HStack(spacing: 8) {
                RDSectionHeader(title: "本机播放进度", trailing: "\(history.entries.count) 部", showsChevron: false, accentMark: true)
            }
            Text("当前已在本地记住 \(history.entries.count) 部漫剧的集数与秒级播放进度，重开剧集将自动续播。")
                .font(RD.Font.body)
                .foregroundStyle(RD.Palette.textSecondary)
                .lineSpacing(3)
        }
        .padding(RD.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rdGemCard()
    }

    private var deviceIdentityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.caption.bold())
                    .foregroundStyle(RD.Palette.platinum)
                Text("设备与版本信息")
                    .font(RD.Font.caption.weight(.bold))
                    .foregroundStyle(RD.Palette.textSecondary)
            }
            .padding(.bottom, 2)

            Text("版本：RedDuoDuo 1.4.6 (1)")
            Text("固定设备 ID：\(deviceID.isEmpty ? (auth.currentDeviceID.isEmpty ? "待首次请求注册" : auth.currentDeviceID) : deviceID)")
                .monospacedDigit()
            Text("Passport：security.snssdk.com · 业务：api5-normal-sinfonlinea.fqnovel.com")
        }
        .font(.caption2)
        .foregroundStyle(RD.Palette.textTertiary)
        .padding(RD.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rdGemCard()
    }

    // MARK: - 头像 & 刷新

    private func avatarView(url: String) -> some View {
        Group {
            if let u = URL(string: url), !url.isEmpty {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(RD.Palette.watchedCellFill)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(RD.Palette.gemAccentText)
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

    private func dateText(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}
