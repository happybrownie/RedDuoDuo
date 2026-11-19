import Foundation

/// 离线缓存单集元数据（独立持久化键，不触碰 HistoryStore）。
struct OfflineEpisodeRecord: Codable, Identifiable, Equatable {
    var id: String { vid }
    let seriesID: String
    var seriesTitle: String
    var seriesCover: String
    let vid: String
    let episodeIndex: Int
    var episodeTitle: String
    let cachedAt: Double
    var fileBytes: Int64
    var autoCleanable: Bool
}

enum OfflineEpisodeState: Equatable {
    case idle
    case queued
    case downloading(String)
    case cached
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .queued, .downloading: return true
        default: return false
        }
    }
}

struct OfflineSeriesGroup: Identifiable {
    var id: String { seriesID }
    let seriesID: String
    let title: String
    let cover: String
    let records: [OfflineEpisodeRecord]
    var totalBytes: Int64 { records.reduce(0) { $0 + max(0, $1.fileBytes) } }
}

/// A3：一键离线追剧包管理器（后续 10 集 / 全集一键存、看完自动清理）。
/// 仅调用现行 `ManjuAPI.playbackCandidates` 与 `StreamPreparer` 现成入口，不改备流内部口径。
@MainActor
final class OfflineCacheManager: ObservableObject {
    static let shared = OfflineCacheManager()
    static let storageKey = "redduoduo.offline.records.v1"

    @Published private(set) var recordsByVid: [String: OfflineEpisodeRecord] = [:]
    @Published private(set) var statesByVid: [String: OfflineEpisodeState] = [:]
    @Published private(set) var totalDiskBytes: Int64 = 0
    @Published private(set) var activeBatchTitle: String?
    @Published private(set) var batchDoneCount: Int = 0
    @Published private(set) var batchTotalCount: Int = 0

    /// 仅当详情页或下载管理页处于前景可见时，单集落盘才震动提示。
    var isOfflineUIVisible = false

    private var queue: [(series: Series, episode: Episode, autoCleanable: Bool)] = []
    private var workerTask: Task<Void, Never>?

    private init() {
        loadRecords()
        Task { await reconcileWithDisk() }
    }

    var isDownloadingBatch: Bool {
        workerTask != nil || !queue.isEmpty
    }

    var seriesGroups: [OfflineSeriesGroup] {
        let grouped = Dictionary(grouping: recordsByVid.values, by: \.seriesID)
        return grouped.map { sid, list in
            let sorted = list.sorted { $0.episodeIndex < $1.episodeIndex }
            let latest = sorted.last
            return OfflineSeriesGroup(
                seriesID: sid,
                title: latest?.seriesTitle ?? "剧目 \(sid)",
                cover: latest?.seriesCover ?? "",
                records: sorted
            )
        }
        .sorted { ($0.records.last?.cachedAt ?? 0) > ($1.records.last?.cachedAt ?? 0) }
    }

    func state(for vid: String) -> OfflineEpisodeState {
        if let active = statesByVid[vid] { return active }
        if recordsByVid[vid] != nil { return .cached }
        return .idle
    }

    func isCached(_ vid: String) -> Bool {
        if case .cached = state(for: vid) { return true }
        return recordsByVid[vid] != nil
    }

    func cachedCount(for seriesID: String, episodes: [Episode]) -> Int {
        episodes.filter { isCached($0.vid) }.count
    }

    func refreshDiskUsage() async {
        totalDiskBytes = await StreamPreparer.shared.totalDiskCacheBytes()
    }

    func reconcileWithDisk(checking vids: [String] = []) async {
        var checkSet = Set(recordsByVid.keys)
        checkSet.formUnion(vids)
        var changed = false

        for vid in checkSet where !vid.isEmpty {
            let existing = await StreamPreparer.shared.existingPlaintextURL(forVid: vid)
            if let url = existing {
                let bytes = Self.fileSize(at: url)
                if var rec = recordsByVid[vid] {
                    if rec.fileBytes != bytes {
                        rec.fileBytes = bytes
                        recordsByVid[vid] = rec
                        changed = true
                    }
                }
                statesByVid[vid] = .cached
            } else if recordsByVid[vid] != nil {
                recordsByVid.removeValue(forKey: vid)
                if case .cached = statesByVid[vid] {
                    statesByVid.removeValue(forKey: vid)
                }
                changed = true
            }
        }
        if changed { saveRecords() }
        totalDiskBytes = await StreamPreparer.shared.totalDiskCacheBytes()
    }

    /// 缓存后续 10 集（从当前集的下一集起，若已是末集则包含当前集）。
    func cacheNext10(series: Series, episodes: [Episode], fromIndex currentIndex: Int) {
        guard !episodes.isEmpty else { return }
        let start = currentIndex < episodes.count - 1 ? currentIndex + 1 : currentIndex
        let end = min(start + 10, episodes.count)
        let slice = Array(episodes[start..<end])
        enqueue(series: series, episodes: slice, label: "\(series.title) · 后续 \(slice.count) 集")
    }

    /// 缓存全集。
    func cacheAll(series: Series, episodes: [Episode]) {
        guard !episodes.isEmpty else { return }
        enqueue(series: series, episodes: episodes, label: "\(series.title) · 全 \(episodes.count) 集")
    }

    /// 缓存单集。
    func cacheSingle(series: Series, episode: Episode) {
        enqueue(series: series, episodes: [episode], label: "\(series.title) · 第\(episode.index)集")
    }

    func cancelPendingQueue() {
        workerTask?.cancel()
        workerTask = nil
        for item in queue {
            if case .queued = statesByVid[item.episode.vid] {
                statesByVid.removeValue(forKey: item.episode.vid)
            }
        }
        queue.removeAll()
        activeBatchTitle = nil
        batchDoneCount = 0
        batchTotalCount = 0
    }

    /// 看完自动清理：若开启自动清理且该集属于离线追剧记录，则在切走/退出后清掉本集落盘。
    func autoCleanFinishedEpisodeIfEnabled(_ episode: Episode, seriesID: String) {
        guard RDPlaybackPrefs.shared.autoCleanWatchedOffline else { return }
        guard let rec = recordsByVid[episode.vid], rec.autoCleanable else { return }
        Task {
            let freed = await StreamPreparer.shared.removeCachedFiles(forVid: episode.vid)
            await MainActor.run {
                self.recordsByVid.removeValue(forKey: episode.vid)
                self.statesByVid.removeValue(forKey: episode.vid)
                self.saveRecords()
                AppLog.write("OFFLINE auto_clean series=\(seriesID) ep=\(episode.index) vid=\(episode.vid) freed=\(freed)B")
            }
            await self.refreshDiskUsage()
        }
    }

    func removeEpisode(vid: String) {
        Task {
            _ = await StreamPreparer.shared.removeCachedFiles(forVid: vid)
            await MainActor.run {
                self.recordsByVid.removeValue(forKey: vid)
                self.statesByVid.removeValue(forKey: vid)
                self.saveRecords()
                RDHaptics.shared.playDeleteSingleItem()
            }
            await self.refreshDiskUsage()
        }
    }

    func removeSeries(seriesID: String) {
        let vids = recordsByVid.values.filter { $0.seriesID == seriesID }.map(\.vid)
        Task {
            for vid in vids {
                _ = await StreamPreparer.shared.removeCachedFiles(forVid: vid)
            }
            await MainActor.run {
                for vid in vids {
                    self.recordsByVid.removeValue(forKey: vid)
                    self.statesByVid.removeValue(forKey: vid)
                }
                self.saveRecords()
                RDHaptics.shared.playDeleteSingleItem()
            }
            await self.refreshDiskUsage()
        }
    }

    func clearAllCache() {
        cancelPendingQueue()
        Task {
            let freed = await StreamPreparer.shared.clearAllDiskCache()
            await MainActor.run {
                self.recordsByVid.removeAll()
                self.statesByVid.removeAll()
                self.saveRecords()
                self.totalDiskBytes = 0
                RDHaptics.shared.playClearAllDestructive()
                AppLog.write("OFFLINE clear_all freed=\(freed)B")
            }
        }
    }

    // MARK: - 队列执行

    private func enqueue(series: Series, episodes: [Episode], label: String) {
        var added = 0
        for ep in episodes {
            if isCached(ep.vid) { continue }
            if case .queued = statesByVid[ep.vid] { continue }
            if case .downloading = statesByVid[ep.vid] { continue }
            queue.append((series: series, episode: ep, autoCleanable: true))
            statesByVid[ep.vid] = .queued
            added += 1
        }
        guard added > 0 else {
            RDHaptics.shared.playCacheSubmit(batch: false)
            return
        }
        RDHaptics.shared.playCacheSubmit(batch: added > 1)
        activeBatchTitle = label
        if workerTask == nil {
            batchDoneCount = 0
            batchTotalCount = added
            startWorker()
        } else {
            batchTotalCount += added
        }
    }

    private func startWorker() {
        workerTask = Task { [weak self] in
            guard let self else { return }
            var hadFailure = false

            while !Task.isCancelled {
                let nextItem: (series: Series, episode: Episode, autoCleanable: Bool)? = await MainActor.run {
                    self.queue.isEmpty ? nil : self.queue.removeFirst()
                }
                guard let item = nextItem else { break }

                let ok = await self.downloadSingle(series: item.series, episode: item.episode, autoCleanable: item.autoCleanable)
                if !ok { hadFailure = true }

                await MainActor.run {
                    self.batchDoneCount += 1
                }
            }

            await MainActor.run {
                self.workerTask = nil
                if !Task.isCancelled, self.isOfflineUIVisible {
                    if hadFailure {
                        RDHaptics.shared.playCacheError()
                    } else if self.batchTotalCount > 1 {
                        RDHaptics.shared.playCacheSeriesDone()
                    }
                }
                self.activeBatchTitle = nil
                self.batchDoneCount = 0
                self.batchTotalCount = 0
            }
            await self.refreshDiskUsage()
        }
    }

    private func downloadSingle(series: Series, episode: Episode, autoCleanable: Bool) async -> Bool {
        if let existing = await StreamPreparer.shared.existingPlaintextURL(forVid: episode.vid) {
            let bytes = Self.fileSize(at: existing)
            recordSuccess(series: series, episode: episode, bytes: bytes, autoCleanable: autoCleanable)
            return true
        }

        statesByVid[episode.vid] = .downloading("获取取流中…")
        do {
            let candidates = try await ManjuAPI.shared.playbackCandidates(vid: episode.vid, seriesID: series.id)
            guard !candidates.isEmpty else {
                statesByVid[episode.vid] = .failed("无可用片源")
                return false
            }

            var lastError: Error?
            for info in candidates.prefix(3) {
                if Task.isCancelled { return false }
                do {
                    let localURL: URL
                    if info.isEncrypted {
                        statesByVid[episode.vid] = .downloading("准备 \(info.definition)…")
                        localURL = try await StreamPreparer.shared.prepare(info) { [weak self] msg in
                            Task { @MainActor [weak self] in
                                self?.statesByVid[episode.vid] = .downloading(msg)
                            }
                        }
                    } else {
                        guard let u = URL(string: info.url) else { continue }
                        localURL = u
                    }
                    let bytes = localURL.isFileURL ? Self.fileSize(at: localURL) : Int64(info.fileSize)
                    recordSuccess(series: series, episode: episode, bytes: bytes, autoCleanable: autoCleanable)
                    if isOfflineUIVisible {
                        RDHaptics.shared.playCacheEpisodeDone()
                    }
                    AppLog.write("OFFLINE cached series=\(series.id) ep=\(episode.index) vid=\(episode.vid) bytes=\(bytes)")
                    return true
                } catch {
                    lastError = error
                }
            }
            let reason = lastError?.localizedDescription ?? "缓存失败"
            statesByVid[episode.vid] = .failed(reason)
            if isOfflineUIVisible {
                RDHaptics.shared.playCacheError()
            }
            AppLog.write("OFFLINE failed series=\(series.id) ep=\(episode.index) err=\(reason)")
            return false
        } catch {
            statesByVid[episode.vid] = .failed(error.localizedDescription)
            if isOfflineUIVisible {
                RDHaptics.shared.playCacheError()
            }
            return false
        }
    }

    private func recordSuccess(series: Series, episode: Episode, bytes: Int64, autoCleanable: Bool) {
        recordsByVid[episode.vid] = OfflineEpisodeRecord(
            seriesID: series.id,
            seriesTitle: series.title,
            seriesCover: series.cover,
            vid: episode.vid,
            episodeIndex: episode.index,
            episodeTitle: episode.title,
            cachedAt: Date().timeIntervalSince1970,
            fileBytes: bytes,
            autoCleanable: autoCleanable
        )
        statesByVid[episode.vid] = .cached
        saveRecords()
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: OfflineEpisodeRecord].self, from: data) else { return }
        recordsByVid = decoded
        for vid in decoded.keys {
            statesByVid[vid] = .cached
        }
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(recordsByVid) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
