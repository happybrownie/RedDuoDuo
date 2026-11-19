import Foundation

// MARK: - 基础模型

struct Series: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var cover: String
    var intro: String
    var episodeCount: Int
    var firstVid: String?
    var firstIndex: Int
    var updatedAt: Double
    var score: String = ""
    var badge: String = ""
    var heatText: String = ""
    var tags: [String] = []
    var seasonTag: String = ""
    var isCompleted: Bool = false
    var isJustUpdated: Bool = false
    var estimatedEpisodeDuration: Int = 0
    var landscapeCover: String = ""

    enum CodingKeys: String, CodingKey {
        case id, title, cover, intro, episodeCount, firstVid, firstIndex, updatedAt
        case score, badge, heatText, tags, seasonTag
        case isCompleted, isJustUpdated, estimatedEpisodeDuration, landscapeCover
    }

    init(id: String, title: String, cover: String, intro: String, episodeCount: Int,
         firstVid: String?, firstIndex: Int, updatedAt: Double,
         score: String = "", badge: String = "", heatText: String = "",
         tags: [String] = [], seasonTag: String = "",
         isCompleted: Bool = false, isJustUpdated: Bool = false, estimatedEpisodeDuration: Int = 0,
         landscapeCover: String = "") {
        self.id = id
        self.title = title
        self.cover = cover
        self.intro = intro
        self.episodeCount = episodeCount
        self.firstVid = firstVid
        self.firstIndex = firstIndex
        self.updatedAt = updatedAt
        self.score = score
        self.badge = badge
        self.heatText = heatText
        self.tags = tags
        self.seasonTag = seasonTag
        self.isCompleted = isCompleted
        self.isJustUpdated = isJustUpdated
        self.estimatedEpisodeDuration = estimatedEpisodeDuration
        self.landscapeCover = landscapeCover
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        cover = try c.decode(String.self, forKey: .cover)
        intro = try c.decode(String.self, forKey: .intro)
        episodeCount = try c.decode(Int.self, forKey: .episodeCount)
        firstVid = try c.decodeIfPresent(String.self, forKey: .firstVid)
        firstIndex = try c.decode(Int.self, forKey: .firstIndex)
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
        score = try c.decodeIfPresent(String.self, forKey: .score) ?? ""
        badge = try c.decodeIfPresent(String.self, forKey: .badge) ?? ""
        heatText = try c.decodeIfPresent(String.self, forKey: .heatText) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        seasonTag = try c.decodeIfPresent(String.self, forKey: .seasonTag) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        isJustUpdated = try c.decodeIfPresent(Bool.self, forKey: .isJustUpdated) ?? false
        estimatedEpisodeDuration = try c.decodeIfPresent(Int.self, forKey: .estimatedEpisodeDuration) ?? 0
        landscapeCover = try c.decodeIfPresent(String.self, forKey: .landscapeCover) ?? ""
    }

    var parsedScoreValue: Double {
        let filtered = score.filter { $0.isNumber || $0 == "." }
        return Double(filtered) ?? 0
    }

    var totalEstimatedSeconds: Int {
        guard episodeCount > 0, estimatedEpisodeDuration > 0 else { return 0 }
        return episodeCount * estimatedEpisodeDuration
    }
}

struct HomeFeedCursor: Equatable {
    var cellID: String
    var planID: String
    var sessionID: String
    var offset: Int
    var hasMore: Bool
    var seenIDs: [String]
}

struct HomeFeedPage {
    let items: [Series]
    let cursor: HomeFeedCursor
}

struct Episode: Identifiable, Hashable {
    var id: String { vid }
    let vid: String
    let index: Int
    let title: String
    let cover: String
    let duration: Int
    let seriesID: String
}

struct AlbumDetail {
    var series: Series
    var episodes: [Episode]
}

struct SearchSuggestion: Identifiable, Hashable {
    var id: String { bookID.isEmpty ? text : bookID }
    let text: String
    let bookID: String
    let searchSourceID: String
}

struct StreamInfo {
    let url: String
    let domain: String
    let vid: String
    let seriesID: String
    let identity: String
    /// 加密流的内容密钥（32 位 hex）；明文流为 nil。
    let keyHex: String?
    let backupURL: String?
    let codec: String
    let definition: String
    let fileSize: Int
    let isEncrypted: Bool
}

struct HistoryEntry: Codable, Identifiable {
    var id: String { seriesID }
    let seriesID: String
    var title: String
    var cover: String
    var intro: String
    var episodeCount: Int
    var lastIndex: Int
    var lastVid: String
    var lastPosition: Double
    var lastDuration: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case seriesID, title, cover, intro, episodeCount, lastIndex, lastVid, lastPosition, lastDuration, updatedAt
    }

    init(seriesID: String, title: String, cover: String, intro: String, episodeCount: Int,
         lastIndex: Int, lastVid: String, lastPosition: Double = 0, lastDuration: Double = 0, updatedAt: Double) {
        self.seriesID = seriesID
        self.title = title
        self.cover = cover
        self.intro = intro
        self.episodeCount = episodeCount
        self.lastIndex = lastIndex
        self.lastVid = lastVid
        self.lastPosition = lastPosition
        self.lastDuration = lastDuration
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = try c.decode(String.self, forKey: .seriesID)
        title = try c.decode(String.self, forKey: .title)
        cover = try c.decode(String.self, forKey: .cover)
        intro = try c.decode(String.self, forKey: .intro)
        episodeCount = try c.decode(Int.self, forKey: .episodeCount)
        lastIndex = try c.decode(Int.self, forKey: .lastIndex)
        lastVid = try c.decode(String.self, forKey: .lastVid)
        lastPosition = try c.decodeIfPresent(Double.self, forKey: .lastPosition) ?? 0
        lastDuration = try c.decodeIfPresent(Double.self, forKey: .lastDuration) ?? 0
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
    }

    var progressFraction: Double {
        guard lastDuration > 1, lastPosition > 0 else { return 0 }
        return min(max(lastPosition / lastDuration, 0), 1)
    }

    var positionText: String {
        Self.formatTime(lastPosition)
    }

    var durationText: String {
        Self.formatTime(lastDuration)
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - 账号与登录模型

struct PassportUser: Codable, Equatable {
    var userID: String
    var name: String
    var mobile: String
    var avatarURL: String

    var displayName: String {
        if !name.isEmpty { return name }
        if !mobile.isEmpty { return mobile }
        return userID.isEmpty ? "红果用户" : "用户 \(userID)"
    }
}

struct MfaContext: Codable, Equatable {
    var retryTag: String
    var smsCodeKey: String
    var encryptUid: String
    var logId: String
    var verifyReason: String
    var verifyScene: String
    var copywritingKey: String
    var diversionTag: String
    var channelMobile: String
    var smsContent: String
    var tips: String
    var mfaToken: String
}

struct SendCodeResult {
    let message: String
    let mobileTicket: String
    let retryTime: Int
    let csrfToken: String
    let rawResponse: String
}

enum LoginOutcome {
    case success(AuthSession)
    case mfa(MfaContext)
}

enum UpsmsPollResult {
    case waiting
    case registered(newMfaToken: String)
}

struct AuthSession: Codable, Equatable {
    var user: PassportUser
    var cookies: [String: String]
    var xTTToken: String
    var loggedInAt: Double
    var expiresAt: Double?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date().timeIntervalSince1970 >= expiresAt
    }

    var hasSessionCookie: Bool {
        !(cookies["sessionid"] ?? "").isEmpty || !(cookies["sid_tt"] ?? "").isEmpty
    }

    var shortXTTToken: String {
        xTTToken.isEmpty ? "" : String(xTTToken.prefix(56))
    }

    func cookieHeader(identity: Identity?) -> String {
        var merged = [String: String]()
        if let id = identity {
            if !id.ttreq.isEmpty { merged["ttreq"] = id.ttreq }
            if !id.iid.isEmpty { merged["install_id"] = id.iid }
        }
        for (k, v) in cookies where !v.isEmpty {
            merged[k] = v
        }
        return merged.keys.sorted().map { "\($0)=\(merged[$0]!)" }.joined(separator: "; ")
    }
}

struct CloudHistoryItem: Identifiable, Hashable {
    var id: String { seriesID }
    let seriesID: String
    let title: String
    let cover: String
    let episodeIndex: Int
    let vid: String
    let positionSeconds: Double
    let durationSeconds: Double
    let episodeCount: Int
    let updatedAt: Double

    func toSeries() -> Series {
        Series(id: seriesID, title: title.isEmpty ? "剧目 \(seriesID)" : title, cover: cover,
               intro: "", episodeCount: max(episodeCount, 1),
               firstVid: vid.isEmpty ? nil : vid, firstIndex: max(episodeIndex, 1),
               updatedAt: updatedAt)
    }
}

struct BookshelfItem: Identifiable, Hashable {
    var id: String { seriesID }
    let seriesID: String
    let title: String
    let cover: String
    let episodeCount: Int
    let collectTime: Double

    func toSeries() -> Series {
        Series(id: seriesID, title: title.isEmpty ? "收藏剧目 \(seriesID)" : title, cover: cover,
               intro: "", episodeCount: max(episodeCount, 1), firstVid: nil, firstIndex: 1,
               updatedAt: collectTime)
    }
}

// MARK: - 宽松 JSON 读取

enum JSONValue {
    static func string(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
}

// MARK: - 响应解析（首页 / 专辑 / 播放）

enum SeriesParser {
    static let defaultTab36CellID = "7597343008509411390"
    static let defaultTab36PlanID = "7597343072904560702"

    static func parseList(from any: Any) -> [Series] {
        var out: [Series] = []
        var seen = Set<String>()
        func append(_ s: Series) {
            guard !s.id.isEmpty, !s.title.isEmpty, !seen.contains(s.id) else { return }
            seen.insert(s.id)
            out.append(s)
        }
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                // 首页：video_detail 是剧目卡片
                if let vd = dict["video_detail"] as? [String: Any],
                   let sid = JSONValue.string(vd["series_id_str"]) ?? JSONValue.string(vd["series_id"]) ?? JSONValue.string(dict["series_id"]),
                   let title = JSONValue.string(vd["series_title"]) {
                    append(makeSeries(id: sid, dict: vd, wrapper: dict, fallbackTitle: title))
                }
                // 专辑：video_data 直接带 series_title + video_list
                if let sid = JSONValue.string(dict["series_id_str"]) ?? JSONValue.string(dict["series_id"]),
                   let title = JSONValue.string(dict["series_title"]),
                   dict["video_list"] is [Any] {
                    append(makeSeries(id: sid, dict: dict, wrapper: dict, fallbackTitle: title))
                }
                for value in dict.values { walk(value) }
            } else if let arr = node as? [Any] {
                for value in arr { walk(value) }
            }
        }
        walk(any)
        return out
    }

    static func parseHomeTab(_ json: [String: Any], preferredTabType: String = "36") -> HomeFeedPage {
        let data = json["data"] as? [String: Any] ?? [:]
        let tabs = data["tab_item"] as? [[String: Any]] ?? []
        let targetTab = tabs.first { JSONValue.string($0["tab_type"]) == preferredTabType }
            ?? tabs.first { !($0["cell_data"] as? [[String: Any]] ?? []).isEmpty }
            ?? tabs.first

        let planID = JSONValue.string(targetTab?["bookstore_id"]) ?? defaultTab36PlanID
        let sessionID = JSONValue.string(targetTab?["session_id"]) ?? ""
        let cells = targetTab?["cell_data"] as? [[String: Any]] ?? []

        var chosenCellID = ""
        var items: [Series] = []
        var seen = Set<String>()

        for cell in cells {
            var cellItems: [Series] = []
            var rawWrappers: [[String: Any]] = []
            if let direct = cell["video_data"] as? [[String: Any]] {
                rawWrappers.append(contentsOf: direct)
            }
            if let nested = cell["cell_data"] as? [[String: Any]] {
                for sc in nested {
                    if let vds = sc["video_data"] as? [[String: Any]] {
                        rawWrappers.append(contentsOf: vds)
                    }
                }
            }
            for wrapper in rawWrappers {
                if let item = parseFeedWrapper(wrapper), !seen.contains(item.id) {
                    seen.insert(item.id)
                    cellItems.append(item)
                }
            }
            if !cellItems.isEmpty {
                if chosenCellID.isEmpty {
                    chosenCellID = JSONValue.string(cell["cell_id_str"])
                        ?? JSONValue.string(cell["cell_id"])
                        ?? ""
                }
                items.append(contentsOf: cellItems)
            }
        }

        if items.isEmpty {
            items = parseList(from: json)
            seen = Set(items.map(\.id))
        }
        if chosenCellID.isEmpty {
            if let first = cells.first {
                chosenCellID = JSONValue.string(first["cell_id_str"]) ?? JSONValue.string(first["cell_id"]) ?? defaultTab36CellID
            } else {
                chosenCellID = defaultTab36CellID
            }
        }

        let cursor = HomeFeedCursor(
            cellID: chosenCellID,
            planID: planID,
            sessionID: sessionID,
            offset: 0,
            hasMore: !sessionID.isEmpty,
            seenIDs: items.map(\.id)
        )
        return HomeFeedPage(items: items, cursor: cursor)
    }

    static func parseHomeChange(_ json: [String: Any], currentCursor: HomeFeedCursor) -> HomeFeedPage {
        let data = json["data"] as? [String: Any] ?? [:]
        let cellView = data["cell_view"] as? [String: Any] ?? [:]
        let cells = cellView["cell_data"] as? [[String: Any]] ?? []

        var seen = Set(currentCursor.seenIDs)
        var newItems: [Series] = []

        func collectFromCell(_ cell: [String: Any]) {
            if let direct = cell["video_data"] as? [[String: Any]] {
                for wrapper in direct {
                    if let item = parseFeedWrapper(wrapper), !seen.contains(item.id) {
                        seen.insert(item.id)
                        newItems.append(item)
                    }
                }
            }
            if let nested = cell["cell_data"] as? [[String: Any]] {
                for sub in nested { collectFromCell(sub) }
            }
        }
        for cell in cells { collectFromCell(cell) }

        let nextSession = JSONValue.string(data["session_id"]) ?? currentCursor.sessionID
        let nextOffset = JSONValue.int(data["next_offset"]) ?? (currentCursor.offset + newItems.count)
        let rawHasMore = JSONValue.bool(data["has_more"]) ?? false
        var allSeen = currentCursor.seenIDs
        allSeen.append(contentsOf: newItems.map(\.id))

        let nextCursor = HomeFeedCursor(
            cellID: currentCursor.cellID,
            planID: currentCursor.planID,
            sessionID: nextSession,
            offset: nextOffset,
            hasMore: rawHasMore && !newItems.isEmpty,
            seenIDs: allSeen
        )
        return HomeFeedPage(items: newItems, cursor: nextCursor)
    }

    static func parseRankList(_ json: [String: Any]) -> [Series] {
        let data = json["data"] as? [String: Any] ?? [:]
        let cellView = data["cell_view"] as? [String: Any] ?? [:]
        let cells = cellView["cell_data"] as? [[String: Any]] ?? []
        var out: [Series] = []
        var seen = Set<String>()

        func collect(_ cell: [String: Any]) {
            if let vds = cell["video_data"] as? [[String: Any]] {
                for raw in vds {
                    if let vd = raw["video_detail"] as? [String: Any],
                       let item = parseFeedWrapper(raw), !seen.contains(item.id) {
                        seen.insert(item.id)
                        out.append(item)
                        _ = vd
                    } else if let sid = JSONValue.string(raw["series_id_str"]) ?? JSONValue.string(raw["series_id"]),
                              let title = JSONValue.string(raw["title"]) ?? JSONValue.string(raw["series_title"]),
                              !seen.contains(sid) {
                        seen.insert(sid)
                        out.append(makeSeries(id: sid, dict: raw, wrapper: raw, fallbackTitle: title))
                    }
                }
            }
            if let nested = cell["cell_data"] as? [[String: Any]] {
                for sub in nested { collect(sub) }
            }
        }
        for cell in cells { collect(cell) }
        return out
    }

    private static func parseFeedWrapper(_ wrapper: [String: Any]) -> Series? {
        guard let vd = wrapper["video_detail"] as? [String: Any],
              let sid = JSONValue.string(vd["series_id_str"])
                ?? JSONValue.string(vd["series_id"])
                ?? JSONValue.string(wrapper["series_id"]),
              let title = JSONValue.string(vd["series_title"]) ?? JSONValue.string(wrapper["title"]) else {
            return nil
        }
        return makeSeries(id: sid, dict: vd, wrapper: wrapper, fallbackTitle: title)
    }

    private static func makeSeries(id: String, dict: [String: Any], wrapper: [String: Any] = [:], fallbackTitle: String) -> Series {
        let videos = dict["video_list"] as? [[String: Any]] ?? []
        let first = videos.first
        let cover = JSONValue.string(dict["series_cover"])
            ?? JSONValue.string(dict["series_cover_uri"])
            ?? JSONValue.string(first?["cover"])
            ?? JSONValue.string(first?["episode_cover"])
            ?? JSONValue.string(dict["cover"])
            ?? JSONValue.string(wrapper["cover"])
            ?? ""
        let landscapeCover = JSONValue.string(dict["horizontal_cover"])
            ?? JSONValue.string(dict["landscape_cover"])
            ?? JSONValue.string(dict["wide_cover"])
            ?? JSONValue.string(dict["cover_horizontal"])
            ?? JSONValue.string(dict["banner_url"])
            ?? JSONValue.string(wrapper["horizontal_cover"])
            ?? JSONValue.string(wrapper["banner_url"])
            ?? ""
        var count = JSONValue.int(dict["episode_cnt"]) ?? JSONValue.int(dict["episode_count"]) ?? videos.count
        if count <= 0 { count = max(videos.count, 1) }
        let intro = JSONValue.string(dict["series_intro"])
            ?? JSONValue.string(dict["video_desc"])
            ?? JSONValue.string(dict["intro"])
            ?? ""
        let firstIndex = JSONValue.int(first?["vid_index"]) ?? 1
        let firstVid = JSONValue.string(first?["vid"])
            ?? JSONValue.string(wrapper["vid"])
            ?? JSONValue.string(dict["first_vid"])
            ?? JSONValue.string(dict["vid"])

        let secInfos = (dict["secondary_infos"] as? [[String: Any]])
            ?? (dict["secondary_info_list"] as? [[String: Any]])
            ?? []
        let subTitleList = dict["sub_title_list"] as? [[String: Any]] ?? []

        // 评分：优先 secondary_infos[data_type=4]，其次扁平 score 字段
        var score = ""
        for info in secInfos {
            if JSONValue.int(info["data_type"]) == 4, let c = JSONValue.string(info["content"]) {
                score = c
                break
            }
        }
        if score.isEmpty, let rawScore = JSONValue.string(dict["score"]), !rawScore.isEmpty, rawScore != "0" {
            score = rawScore.hasSuffix("分") ? rawScore : "\(rawScore)分"
        }

        // 角标：tag_info.text（「爆剧」「新剧」等）
        let tagInfo = (dict["tag_info"] as? [String: Any]) ?? (wrapper["tag_info"] as? [String: Any])
        let badge = (JSONValue.bool(tagInfo?["enable"]) == false) ? "" : (JSONValue.string(tagInfo?["text"]) ?? "")

        // 季徽：secondary_infos 缺省或 data_type=0 / sub_title_list data_type=0
        var seasonTag = ""
        for info in secInfos {
            let dt = JSONValue.int(info["data_type"])
            if (dt == nil || dt == 0), let c = JSONValue.string(info["content"]), c.contains("季") {
                seasonTag = c
                break
            }
        }
        if seasonTag.isEmpty {
            for info in subTitleList {
                if JSONValue.int(info["data_type"]) == 0, let c = JSONValue.string(info["content"]) {
                    seasonTag = c
                    break
                }
            }
        }

        // 热度：rec_tags[data_type=1] / rec_text_item.RecommendText / secondary_info_list[data_type=1]
        let recTags = (wrapper["rec_tags"] as? [[String: Any]]) ?? (dict["rec_tags"] as? [[String: Any]]) ?? []
        var heatParts = recTags.compactMap { t -> String? in
            guard JSONValue.int(t["data_type"]) == 1 else { return nil }
            return JSONValue.string(t["content"])
        }
        if heatParts.isEmpty, let recItem = dict["rec_text_item"] as? [String: Any],
           let txt = JSONValue.string(recItem["RecommendText"]) {
            heatParts.append(txt)
        }
        if heatParts.isEmpty {
            for info in secInfos where JSONValue.int(info["data_type"]) == 1 {
                if let c = JSONValue.string(info["content"]) { heatParts.append(c) }
            }
        }
        let heatText = heatParts.joined(separator: " · ")

        // 题材标签：category_schema JSON 串或 secondary_infos[data_type=3]
        var tags = parseCategoryTags(dict["category_schema"])
        if tags.isEmpty {
            for info in secInfos where JSONValue.int(info["data_type"]) == 3 {
                if let c = JSONValue.string(info["content"]), !tags.contains(c) {
                    tags.append(c)
                }
            }
        }
        if tags.isEmpty, let subTitle = JSONValue.string(dict["sub_title"]) {
            let parts = subTitle.split(separator: "·").map { String($0).trimmingCharacters(in: .whitespaces) }
            if let firstTag = parts.first, !firstTag.isEmpty, !firstTag.contains("集") {
                tags.append(firstTag)
            }
        }

        // 完结 / 刚更新状态与单集时长提示（严格基于真实字段文本或明确布尔标记，不猜造）
        var statusCandidates: [String] = [badge, heatText]
        if let st = JSONValue.string(dict["sub_title"]) { statusCandidates.append(st) }
        if let st = JSONValue.string(dict["status_text"]) { statusCandidates.append(st) }
        for info in secInfos {
            if let c = JSONValue.string(info["content"]) { statusCandidates.append(c) }
        }
        for info in subTitleList {
            if let c = JSONValue.string(info["content"]) { statusCandidates.append(c) }
        }
        let statusBlob = statusCandidates.joined(separator: " ")
        let explicitFinished = JSONValue.bool(dict["is_finished"]) ?? JSONValue.bool(dict["finished"]) ?? false
        let isCompleted = explicitFinished
            || statusBlob.contains("已完结")
            || statusBlob.contains("完结")
        let isJustUpdated = !isCompleted && (
            statusBlob.contains("刚更新")
            || statusBlob.contains("刚刚更新")
            || statusBlob.contains("今日更新")
            || badge.contains("新剧")
            || badge.contains("更新")
        )
        let firstEpDur = JSONValue.int(first?["duration"]) ?? JSONValue.int(dict["duration"]) ?? 0

        return Series(id: id,
                      title: JSONValue.string(dict["series_title"]) ?? JSONValue.string(dict["title"]) ?? fallbackTitle,
                      cover: cover,
                      intro: intro,
                      episodeCount: count,
                      firstVid: firstVid,
                      firstIndex: max(firstIndex, 1),
                      updatedAt: Date().timeIntervalSince1970,
                      score: score,
                      badge: badge,
                      heatText: heatText,
                      tags: Array(tags.prefix(4)),
                      seasonTag: seasonTag,
                      isCompleted: isCompleted,
                      isJustUpdated: isJustUpdated,
                      estimatedEpisodeDuration: max(0, firstEpDur),
                      landscapeCover: landscapeCover)
    }

    private static func parseCategoryTags(_ value: Any?) -> [String] {
        var list: [[String: Any]] = []
        if let arr = value as? [[String: Any]] {
            list = arr
        } else if let str = value as? String, let data = str.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            list = parsed
        }
        var out: [String] = []
        for item in list {
            if let name = JSONValue.string(item["name"]), !out.contains(name) {
                out.append(name)
            }
        }
        return out
    }

    static func parseAlbum(_ json: [String: Any], fallback: Series) -> AlbumDetail? {
        guard let data = json["data"] as? [String: Any] else { return nil }
        let album = data["album_data"] as? [String: Any] ?? [:]
        let sid = JSONValue.string(album["album_id_str"])
            ?? JSONValue.string(album["album_id"])
            ?? fallback.id

        var videoData: [String: Any]?
        if let map = data["video_detail_data"] as? [String: Any] {
            if let item = map[sid] as? [String: Any] {
                videoData = item["video_data"] as? [String: Any] ?? item
            } else if let first = map.values.first as? [String: Any] {
                videoData = first["video_data"] as? [String: Any] ?? first
            }
        }
        let videos = (videoData?["video_list"] as? [[String: Any]]) ?? []
        var episodes: [Episode] = []
        for (offset, v) in videos.enumerated() {
            guard let vid = JSONValue.string(v["vid"]) else { continue }
            let idx = JSONValue.int(v["vid_index"]) ?? (offset + 1)
            episodes.append(Episode(vid: vid,
                                    index: idx,
                                    title: JSONValue.string(v["title"]) ?? "第\(idx)集",
                                    cover: JSONValue.string(v["episode_cover"]) ?? JSONValue.string(v["cover"]) ?? "",
                                    duration: JSONValue.int(v["duration"]) ?? 0,
                                    seriesID: sid))
        }
        if episodes.isEmpty {
            // 首页兜底：拿到过前几集
            if let vid = fallback.firstVid {
                episodes = [Episode(vid: vid, index: fallback.firstIndex, title: "第\(fallback.firstIndex)集",
                                    cover: fallback.cover, duration: 0, seriesID: fallback.id)]
            } else {
                return nil
            }
        }
        episodes.sort { $0.index < $1.index }
        let title = JSONValue.string(album["title"]) ?? JSONValue.string(videoData?["series_title"]) ?? fallback.title
        let intro = JSONValue.string(album["intro"]) ?? JSONValue.string(videoData?["series_intro"]) ?? fallback.intro
        let cover = JSONValue.string(album["cover"])
            ?? JSONValue.string(videoData?["series_cover"])
            ?? episodes.first?.cover
            ?? fallback.cover
        let landscapeCover = JSONValue.string(album["horizontal_cover"])
            ?? JSONValue.string(videoData?["horizontal_cover"])
            ?? JSONValue.string(album["landscape_cover"])
            ?? JSONValue.string(videoData?["landscape_cover"])
            ?? fallback.landscapeCover
        let count = JSONValue.int(videoData?["episode_cnt"]) ?? episodes.count
        let parsedTags = parseCategoryTags(videoData?["category_schema"])
        let durValues = episodes.map(\.duration).filter { $0 > 0 }
        let avgDuration = durValues.isEmpty ? fallback.estimatedEpisodeDuration : (durValues.reduce(0, +) / durValues.count)
        let albumSub = JSONValue.string(album["sub_title"]) ?? JSONValue.string(videoData?["sub_title"]) ?? ""
        let explicitFinished = JSONValue.bool(album["is_finished"]) ?? JSONValue.bool(videoData?["is_finished"]) ?? false
        let albumCompleted = fallback.isCompleted || explicitFinished || albumSub.contains("完结")
        let series = Series(id: sid, title: title, cover: cover, intro: intro,
                            episodeCount: max(count, episodes.count),
                            firstVid: episodes.first?.vid,
                            firstIndex: episodes.first?.index ?? 1,
                            updatedAt: fallback.updatedAt,
                            score: fallback.score,
                            badge: fallback.badge,
                            heatText: fallback.heatText,
                            tags: parsedTags.isEmpty ? fallback.tags : Array(parsedTags.prefix(4)),
                            seasonTag: fallback.seasonTag,
                            isCompleted: albumCompleted,
                            isJustUpdated: fallback.isJustUpdated,
                            estimatedEpisodeDuration: max(0, avgDuration),
                            landscapeCover: landscapeCover)
        return AlbumDetail(series: series, episodes: episodes)
    }

    /// 递归找播放地址：兼容 video_model 字符串、video_list、顶层 main_url
    static func firstMainURL(in any: Any) -> String? {
        if let s = any as? String {
            if s.hasPrefix("http"), s.contains(".mp4") || s.contains("video/tos") { return s }
            if s.hasPrefix("{") || s.hasPrefix("["),
               let data = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return firstMainURL(in: obj)
            }
            return nil
        }
        if let dict = any as? [String: Any] {
            if let url = dict["main_url"] as? String, url.hasPrefix("http") { return url }
            if let url = dict["backup_url"] as? String, url.hasPrefix("http") { return url }
            for value in dict.values {
                if let found = firstMainURL(in: value) { return found }
            }
        }
        if let arr = any as? [Any] {
            for value in arr {
                if let found = firstMainURL(in: value) { return found }
            }
        }
        return nil
    }

    static func firstVid(in any: Any) -> String? {
        if let dict = any as? [String: Any] {
            for key in ["vid", "video_id"] {
                if let v = JSONValue.string(dict[key]), !v.isEmpty { return v }
            }
            for value in dict.values {
                if let v = firstVid(in: value) { return v }
            }
        }
        if let arr = any as? [Any] {
            for value in arr {
                if let v = firstVid(in: value) { return v }
            }
        }
        return nil
    }

    static func parseSuggestions(_ json: [String: Any]) -> [SearchSuggestion] {
        let data = json["data"] as? [String: Any]
        let list = json["data_v1"] as? [[String: Any]]
            ?? data?["data_v1"] as? [[String: Any]]
            ?? data?["data"] as? [[String: Any]]
            ?? []
        var out: [SearchSuggestion] = []
        var seen = Set<String>()
        for item in list {
            guard let text = JSONValue.string(item["text"]), !text.isEmpty else { continue }
            let bookID = JSONValue.string(item["book_id"]) ?? ""
            let ssid = JSONValue.string(item["search_source_id"]) ?? ""
            let key = bookID + "|" + text
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(SearchSuggestion(text: text, bookID: bookID, searchSourceID: ssid))
        }
        return out
    }
}
