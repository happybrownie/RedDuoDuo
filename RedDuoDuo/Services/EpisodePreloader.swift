import Foundation

/// A1：下集提前预备调度器。
/// 仅调用现行 `ManjuAPI.playbackCandidates` 与 `StreamPreparer.prepare` 现成入口，
/// 不修改备流命名/校验/清理口径，也不在静默预取期间触发震动（保持沉浸式体验）。
@MainActor
final class EpisodePreloader: ObservableObject {
    static let shared = EpisodePreloader()

    @Published private(set) var preparedVids: Set<String> = []
    @Published private(set) var activePreloadingVid: String?

    private var preloadTask: Task<Void, Never>?
    private var activeGeneration = UUID()

    private init() {}

    func isPrepared(_ vid: String) -> Bool {
        preparedVids.contains(vid)
    }

    func refreshDiskStatus(for vids: [String]) async {
        var found: Set<String> = []
        for vid in vids where !vid.isEmpty {
            if await StreamPreparer.shared.existingPlaintextURL(forVid: vid) != nil {
                found.insert(vid)
            }
        }
        if !found.isEmpty {
            preparedVids.formUnion(found)
        }
    }

    /// 在当前集起播稳定后，提前顺序预备后续最多两集（`index + 1`、`index + 2`）。
    func scheduleUpcoming(seriesID: String, episodes: [Episode], currentIndex: Int) {
        cancel()
        let nextIndices = [currentIndex + 1, currentIndex + 2].filter { episodes.indices.contains($0) }
        guard !nextIndices.isEmpty else { return }

        let gen = UUID()
        activeGeneration = gen
        let upcoming = nextIndices.map { episodes[$0] }

        preloadTask = Task { [weak self] in
            // 留出 0.6s 缓冲，让当前集首帧与系统解码彻底平稳后再开始后台备流
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            for ep in upcoming {
                guard !Task.isCancelled else { return }
                let stillValid = await MainActor.run { self?.activeGeneration == gen }
                guard stillValid else { return }

                if await StreamPreparer.shared.existingPlaintextURL(forVid: ep.vid) != nil {
                    await MainActor.run {
                        guard let self, self.activeGeneration == gen else { return }
                        self.preparedVids.insert(ep.vid)
                    }
                    continue
                }

                await MainActor.run {
                    guard let self, self.activeGeneration == gen else { return }
                    self.activePreloadingVid = ep.vid
                }

                do {
                    let candidates = try await ManjuAPI.shared.playbackCandidates(vid: ep.vid, seriesID: seriesID)
                    guard !Task.isCancelled else { break }
                    var didPrepare = false
                    for info in candidates.prefix(2) {
                        guard !Task.isCancelled else { break }
                        do {
                            if info.isEncrypted {
                                _ = try await StreamPreparer.shared.prepare(info) { _ in }
                            }
                            didPrepare = true
                            break
                        } catch {
                            continue
                        }
                    }
                    if didPrepare {
                        await MainActor.run {
                            guard let self, self.activeGeneration == gen else { return }
                            self.preparedVids.insert(ep.vid)
                            AppLog.write("PRELOAD ready series=\(seriesID) ep=\(ep.index) vid=\(ep.vid)")
                        }
                    }
                } catch {
                    AppLog.write("PRELOAD skip series=\(seriesID) ep=\(ep.index) err=\(error.localizedDescription)")
                }

                await MainActor.run {
                    if self?.activePreloadingVid == ep.vid {
                        self?.activePreloadingVid = nil
                    }
                }
            }

            await MainActor.run {
                if self?.activeGeneration == gen {
                    self?.activePreloadingVid = nil
                }
            }
        }
    }

    func cancel() {
        preloadTask?.cancel()
        preloadTask = nil
        activeGeneration = UUID()
        activePreloadingVid = nil
    }
}
