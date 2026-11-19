import Foundation

/// 1.4 播放与手势偏好存储（全部采用独立新键，绝不触碰 1.3 既有存储键）。
@MainActor
final class RDPlaybackPrefs: ObservableObject {
    static let shared = RDPlaybackPrefs()

    static let verticalSwipeKey = "redduoduo.player.vertical_swipe_enabled.v1"
    static let skipIntroOutroKey = "redduoduo.player.skip_intro_outro.v1"
    static let autoPlayNextKey = "redduoduo.player.autoplay_next.v1"
    static let backgroundAudioKey = "redduoduo.player.background_audio.v1"
    static let autoCleanOfflineKey = "redduoduo.player.autoclean_offline.v1"
    static let seriesRatesKey = "redduoduo.player.series_rates.v1"
    static let watchedEpisodesKey = "redduoduo.player.watched_episodes.v1"

    static let supportedRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    @Published var verticalSwipeEnabled: Bool {
        didSet { UserDefaults.standard.set(verticalSwipeEnabled, forKey: Self.verticalSwipeKey) }
    }

    @Published var skipIntroOutroEnabled: Bool {
        didSet { UserDefaults.standard.set(skipIntroOutroEnabled, forKey: Self.skipIntroOutroKey) }
    }

    @Published var autoPlayNextEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPlayNextEnabled, forKey: Self.autoPlayNextKey) }
    }

    @Published var backgroundAudioEnabled: Bool {
        didSet { UserDefaults.standard.set(backgroundAudioEnabled, forKey: Self.backgroundAudioKey) }
    }

    @Published var autoCleanWatchedOffline: Bool {
        didSet { UserDefaults.standard.set(autoCleanWatchedOffline, forKey: Self.autoCleanOfflineKey) }
    }

    @Published private(set) var seriesRates: [String: Float] = [:]
    @Published private(set) var watchedEpisodes: [String: [Int]] = [:]

    private init() {
        let ud = UserDefaults.standard
        verticalSwipeEnabled = ud.object(forKey: Self.verticalSwipeKey) as? Bool ?? true
        skipIntroOutroEnabled = ud.object(forKey: Self.skipIntroOutroKey) as? Bool ?? false
        autoPlayNextEnabled = ud.object(forKey: Self.autoPlayNextKey) as? Bool ?? true
        backgroundAudioEnabled = ud.object(forKey: Self.backgroundAudioKey) as? Bool ?? true
        autoCleanWatchedOffline = ud.object(forKey: Self.autoCleanOfflineKey) as? Bool ?? true

        if let data = ud.data(forKey: Self.seriesRatesKey),
           let decoded = try? JSONDecoder().decode([String: Float].self, from: data) {
            seriesRates = decoded
        }
        if let data = ud.data(forKey: Self.watchedEpisodesKey),
           let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            watchedEpisodes = decoded
        }
    }

    func rate(for seriesID: String) -> Float {
        guard let raw = seriesRates[seriesID], Self.supportedRates.contains(raw) else {
            return 1.0
        }
        return raw
    }

    func setRate(_ rate: Float, for seriesID: String) {
        let nearest = Self.supportedRates.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 1.0
        seriesRates[seriesID] = nearest
        if let data = try? JSONEncoder().encode(seriesRates) {
            UserDefaults.standard.set(data, forKey: Self.seriesRatesKey)
        }
    }

    static func rateLabel(_ rate: Float) -> String {
        if abs(rate - 0.75) < 0.01 { return "0.75x" }
        if abs(rate - 1.25) < 0.01 { return "1.25x" }
        if abs(rate - 1.5) < 0.01 { return "1.5x" }
        if abs(rate - 2.0) < 0.01 { return "2.0x" }
        return "1.0x"
    }

    func markEpisodeWatched(seriesID: String, episodeIndex: Int) {
        var list = watchedEpisodes[seriesID] ?? []
        if !list.contains(episodeIndex) {
            list.append(episodeIndex)
            if list.count > 1000 { list = Array(list.suffix(1000)) }
            watchedEpisodes[seriesID] = list
            if let data = try? JSONEncoder().encode(watchedEpisodes) {
                UserDefaults.standard.set(data, forKey: Self.watchedEpisodesKey)
            }
        }
    }

    func isEpisodeWatched(seriesID: String, episodeIndex: Int) -> Bool {
        watchedEpisodes[seriesID]?.contains(episodeIndex) ?? false
    }

    /// 保守片头跳过点位（按单集时长比例，不编造官方时间标记；低于 45s 的短片不跳过）。
    static func introSkipTarget(duration: Double) -> Double? {
        guard duration.isFinite, duration >= 45.0 else { return nil }
        return min(max(duration * 0.06, 5.0), 18.0)
    }

    /// 保守片尾跳过起点（按单集时长比例，不编造官方时间标记；低于 45s 的短片不跳过）。
    static func outroSkipStart(duration: Double) -> Double? {
        guard duration.isFinite, duration >= 45.0 else { return nil }
        let tail = min(max(duration * 0.07, 6.0), 20.0)
        return max(0, duration - tail)
    }
}

// MARK: - 个人搜索胶囊存储

@MainActor
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()
    static let storageKey = "redduoduo.search.recent_queries.v1"

    @Published private(set) var queries: [String] = []

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.storageKey) {
            queries = saved
        }
    }

    func add(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        queries.removeAll { $0 == q }
        queries.insert(q, at: 0)
        if queries.count > 12 {
            queries = Array(queries.prefix(12))
        }
        save()
    }

    func remove(_ q: String) {
        queries.removeAll { $0 == q }
        save()
    }

    func clear() {
        queries = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(queries, forKey: Self.storageKey)
    }
}

// MARK: - 在追片单 & 收藏跟踪

struct FollowedSeriesRecord: Codable, Identifiable {
    var id: String { seriesID }
    let seriesID: String
    var title: String
    var cover: String
    var intro: String
    var episodeCount: Int
    var lastSeenEpisodeCount: Int
    var isCompleted: Bool
    var isJustUpdated: Bool
    var isCollected: Bool
    var updatedAt: Double
}

// 备用数据结构：未接入播放链。不合成 `Hashable`
// （其成员 `HistoryEntry` 未实现 `Hashable`）。
struct BingeQueueItem: Identifiable {
    var id: String { series.id }
    let series: Series
    let currentEpisodeIndex: Int
    let totalEpisodes: Int
    let remainingEpisodes: Int
    let progressFraction: Double
    let isCollected: Bool
    let statusBadge: String?
    let hasResumeHistory: Bool
    let resumeEntry: HistoryEntry?
}

@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()
    static let storageKey = "redduoduo.follow.series.v1"

    @Published private(set) var records: [String: FollowedSeriesRecord] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: FollowedSeriesRecord].self, from: data) {
            records = decoded
        }
    }

    func isCollected(_ seriesID: String) -> Bool {
        records[seriesID]?.isCollected ?? false
    }

    func setCollected(_ collected: Bool, series: Series) {
        let now = Date().timeIntervalSince1970
        if var existing = records[series.id] {
            existing.isCollected = collected
            existing.title = series.title.isEmpty ? existing.title : series.title
            existing.cover = series.cover.isEmpty ? existing.cover : series.cover
            existing.intro = series.intro.isEmpty ? existing.intro : series.intro
            if series.episodeCount > existing.episodeCount {
                existing.isJustUpdated = !series.isCompleted
                existing.episodeCount = series.episodeCount
            }
            existing.isCompleted = series.isCompleted || existing.isCompleted
            existing.updatedAt = now
            if collected {
                records[series.id] = existing
            } else {
                records.removeValue(forKey: series.id)
            }
        } else if collected {
            records[series.id] = FollowedSeriesRecord(
                seriesID: series.id,
                title: series.title,
                cover: series.cover,
                intro: series.intro,
                episodeCount: series.episodeCount,
                lastSeenEpisodeCount: series.episodeCount,
                isCompleted: series.isCompleted,
                isJustUpdated: series.isJustUpdated,
                isCollected: true,
                updatedAt: now
            )
        }
        save()
    }

    func syncBookshelf(_ items: [BookshelfItem]) {
        let now = Date().timeIntervalSince1970
        let remoteIDs = Set(items.map(\.seriesID))
        for key in Array(records.keys) where !remoteIDs.contains(key) {
            records.removeValue(forKey: key)
        }
        for item in items {
            if var existing = records[item.seriesID] {
                if item.episodeCount > existing.lastSeenEpisodeCount && existing.lastSeenEpisodeCount > 0 {
                    existing.isJustUpdated = true
                }
                existing.episodeCount = max(item.episodeCount, existing.episodeCount)
                existing.title = item.title.isEmpty ? existing.title : item.title
                existing.cover = item.cover.isEmpty ? existing.cover : item.cover
                existing.isCollected = true
                records[item.seriesID] = existing
            } else {
                records[item.seriesID] = FollowedSeriesRecord(
                    seriesID: item.seriesID,
                    title: item.title,
                    cover: item.cover,
                    intro: "",
                    episodeCount: max(item.episodeCount, 1),
                    lastSeenEpisodeCount: max(item.episodeCount, 1),
                    isCompleted: false,
                    isJustUpdated: false,
                    isCollected: true,
                    updatedAt: item.collectTime > 0 ? item.collectTime : now
                )
            }
        }
        save()
    }

    func observeLatestSeries(_ list: [Series]) {
        var changed = false
        for s in list {
            guard var rec = records[s.id] else { continue }
            if s.episodeCount > rec.lastSeenEpisodeCount && rec.lastSeenEpisodeCount > 0 {
                rec.isJustUpdated = !s.isCompleted
            }
            if s.isJustUpdated && !s.isCompleted {
                rec.isJustUpdated = true
            }
            if s.isCompleted {
                rec.isCompleted = true
                rec.isJustUpdated = false
            }
            rec.episodeCount = max(rec.episodeCount, s.episodeCount)
            if !s.title.isEmpty { rec.title = s.title }
            if !s.cover.isEmpty { rec.cover = s.cover }
            if !s.intro.isEmpty { rec.intro = s.intro }
            records[s.id] = rec
            changed = true
        }
        if changed { save() }
    }

    func markSeenEpisodeCount(for series: Series) {
        guard var rec = records[series.id] else { return }
        rec.lastSeenEpisodeCount = max(rec.lastSeenEpisodeCount, series.episodeCount)
        rec.isJustUpdated = false
        records[series.id] = rec
        save()
    }

    /// 汇总首页置顶「在追片单」：融合已收藏剧集与本地观看中剧集，计算「还剩 X 集」「刚更新/已完结」。
    func bingeQueue(history: [HistoryEntry], catalog: [String: Series]) -> [BingeQueueItem] {
        var combinedIDs: [String] = []
        var seen = Set<String>()

        let sortedHistory = history.sorted { $0.updatedAt > $1.updatedAt }
        for h in sortedHistory where !seen.contains(h.seriesID) {
            seen.addOrInsert(h.seriesID)
            combinedIDs.append(h.seriesID)
        }
        let sortedFollowed = records.values.sorted { $0.updatedAt > $1.updatedAt }
        for f in sortedFollowed where !seen.contains(f.seriesID) {
            seen.addOrInsert(f.seriesID)
            combinedIDs.append(f.seriesID)
        }

        return combinedIDs.compactMap { sid in
            let entry = sortedHistory.first { $0.seriesID == sid }
            let follow = records[sid]
            let cat = catalog[sid]

            let title = cat?.title ?? entry?.title ?? follow?.title ?? ""
            guard !title.isEmpty else { return nil }
            let cover = cat?.cover ?? entry?.cover ?? follow?.cover ?? ""
            let intro = cat?.intro ?? entry?.intro ?? follow?.intro ?? ""
            let total = max(cat?.episodeCount ?? 0, max(entry?.episodeCount ?? 0, follow?.episodeCount ?? 1))
            let currentIdx = entry?.lastIndex ?? 0
            let remaining = max(0, total - currentIdx)

            let completed = (cat?.isCompleted ?? false) || (follow?.isCompleted ?? false)
            let updated = !completed && ((cat?.isJustUpdated ?? false) || (follow?.isJustUpdated ?? false))
            let statusBadge: String? = completed ? "已完结" : (updated ? "刚更新" : nil)

            let baseSeries = cat ?? Series(
                id: sid,
                title: title,
                cover: cover,
                intro: intro,
                episodeCount: total,
                firstVid: entry?.lastVid,
                firstIndex: max(currentIdx, 1),
                updatedAt: entry?.updatedAt ?? follow?.updatedAt ?? 0,
                isCompleted: completed,
                isJustUpdated: updated
            )

            return BingeQueueItem(
                series: baseSeries,
                currentEpisodeIndex: currentIdx,
                totalEpisodes: total,
                remainingEpisodes: remaining,
                progressFraction: entry?.progressFraction ?? 0,
                isCollected: follow?.isCollected ?? false,
                statusBadge: statusBadge,
                hasResumeHistory: entry != nil,
                resumeEntry: entry
            )
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

private extension Set where Element == String {
    mutating func addOrInsert(_ value: String) {
        insert(value)
    }
}

// MARK: - 内存目录缓存（用于同款接档推荐与精确总时长）

@MainActor
final class CatalogCache: ObservableObject {
    static let shared = CatalogCache()

    @Published private(set) var byID: [String: Series] = [:]
    @Published private(set) var totalDurationByID: [String: Int] = [:]

    private init() {}

    func ingest(_ items: [Series]) {
        for item in items where !item.id.isEmpty {
            if let existing = byID[item.id] {
                var merged = item
                if merged.tags.isEmpty { merged.tags = existing.tags }
                if merged.score.isEmpty { merged.score = existing.score }
                if merged.estimatedEpisodeDuration <= 0 { merged.estimatedEpisodeDuration = existing.estimatedEpisodeDuration }
                merged.isCompleted = merged.isCompleted || existing.isCompleted
                byID[item.id] = merged
            } else {
                byID[item.id] = item
            }
        }
        FollowStore.shared.observeLatestSeries(items)
    }

    func ingestAlbum(_ detail: AlbumDetail) {
        ingest([detail.series])
        let total = detail.episodes.reduce(0) { $0 + max(0, $1.duration) }
        if total > 0 {
            totalDurationByID[detail.series.id] = total
        }
    }

    /// 精确或按片源已知单集时长估算是否可在 30 分钟内刷完（1800s）。
    func isHalfHourBinge(_ series: Series) -> Bool {
        if let exact = totalDurationByID[series.id], exact > 0 {
            return exact <= 1800
        }
        let estimated = series.totalEstimatedSeconds
        if estimated > 0 {
            return estimated <= 1800
        }
        // 当首页接口未下发单集时长时，红果漫剧常规约 2~3 分钟/集，保守以 ≤ 15 集作短篇筛选
        return series.episodeCount > 0 && series.episodeCount <= 15
    }

    func durationHintText(for series: Series) -> String? {
        if let exact = totalDurationByID[series.id], exact > 0 {
            let mins = max(1, (exact + 59) / 60)
            return "约 \(mins) 分钟"
        }
        let estimated = series.totalEstimatedSeconds
        if estimated > 0 {
            let mins = max(1, (estimated + 59) / 60)
            return "约 \(mins) 分钟"
        }
        return series.episodeCount > 0 ? "短篇 \(series.episodeCount) 集" : nil
    }

    /// 大结局「同款接档」推荐：按题材标签重合度 + 评分排序。
    func relatedSeries(for target: Series, limit: Int = 8) -> [Series] {
        let targetTags = Set(target.tags)
        let candidates = byID.values.filter { $0.id != target.id }
        let sorted = candidates.sorted { lhs, rhs in
            let lOverlap = Set(lhs.tags).intersection(targetTags).count
            let rOverlap = Set(rhs.tags).intersection(targetTags).count
            if lOverlap != rOverlap { return lOverlap > rOverlap }
            return lhs.parsedScoreValue > rhs.parsedScoreValue
        }
        return Array(sorted.prefix(limit))
    }

    /// 题材走廊：汇总目录内全部题材标签（按出现频次降序）。
    func sortedTags(from extra: [Series] = [], limit: Int = 18) -> [String] {
        var counts: [String: Int] = [:]
        var all = Array(byID.values)
        all.append(contentsOf: extra)
        var seenSeries = Set<String>()
        for s in all where !seenSeries.contains(s.id) {
            seenSeries.insert(s.id)
            for tag in s.tags where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
        .prefix(limit)
        .map(\.key)
    }

    /// 按关键词或题材筛选已知剧目（合并首页与已缓存目录）。
    func mergedSeries(primary: [Series]) -> [Series] {
        var out = primary
        var seen = Set(primary.map(\.id))
        for item in byID.values where !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
        }
        return out
    }
}
