import Foundation

@MainActor
final class WatchHistory: ObservableObject {
    static let shared = WatchHistory()
    private let key = "redduoduo.watch.history.v1"

    @Published private(set) var entries: [HistoryEntry] = []

    private init() { load() }

    func entry(for seriesID: String) -> HistoryEntry? {
        entries.first { $0.seriesID == seriesID }
    }

    func record(series: Series, episode: Episode, position: Double = 0, duration: Double = 0, log: Bool = true) {
        let existing = entry(for: series.id)
        let safePos = position.isFinite ? max(0, position) : 0
        let safeDur = duration.isFinite ? max(0, duration) : (existing?.lastIndex == episode.index ? (existing?.lastDuration ?? 0) : 0)
        let record = HistoryEntry(seriesID: series.id,
                                  title: series.title.isEmpty ? (existing?.title ?? series.title) : series.title,
                                  cover: series.cover.isEmpty ? (existing?.cover ?? series.cover) : series.cover,
                                  intro: series.intro.isEmpty ? (existing?.intro ?? series.intro) : series.intro,
                                  episodeCount: max(series.episodeCount, existing?.episodeCount ?? 0),
                                  lastIndex: episode.index,
                                  lastVid: episode.vid,
                                  lastPosition: safePos,
                                  lastDuration: safeDur,
                                  updatedAt: Date().timeIntervalSince1970)
        if let at = entries.firstIndex(where: { $0.seriesID == series.id }) {
            entries[at] = record
        } else {
            entries.insert(record, at: 0)
        }
        entries.sort { $0.updatedAt > $1.updatedAt }
        if entries.count > 100 { entries = Array(entries.prefix(100)) }
        save()
        if log {
            AppLog.write("HISTORY record series=\(series.id) title=\(record.title) ep=\(episode.index) pos=\(String(format: "%.1f", safePos))s/\(String(format: "%.1f", safeDur))s vid=\(episode.vid)")
        }
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.seriesID == entry.seriesID }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
