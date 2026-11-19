import Foundation

enum StreamPrepareError: LocalizedError {
    case noKey
    case badURL(String)
    case http(Int)
    case emptyFile
    case decryptFailed(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "加密流缺少内容密钥"
        case .badURL(let s): return "播放地址无效：\(s)"
        case .http(let c): return "下载失败 HTTP \(c)"
        case .emptyFile: return "下载到的文件为空"
        case .decryptFailed(let s): return "解密失败：\(s)"
        }
    }
}

/// 取流后的本地化：下载 CENC 加密 MP4 → CommonCrypto AES-128-CTR 解成明文文件 → 交给 VLC 播本地文件。
/// 明文流直接返回原 URL，不落盘。
actor StreamPreparer {
    static let shared = StreamPreparer()

    private let fm = FileManager.default
    private let ua = "Dalvik/2.1.0 (Linux; U; Android 13; Pixel 5 Build/TQ3A.230805.001) Kylin/7.2.7.32"
    private let session: URLSession
    private var inflight: [String: Task<URL, Error>] = [:]

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    private var cacheDir: URL {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("RedDuoDuoStreams", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    func prepare(_ info: StreamInfo, progress: @escaping (String) -> Void) async throws -> URL {
        guard info.isEncrypted else {
            guard let url = URL(string: info.url) else { throw StreamPrepareError.badURL(info.url) }
            return url
        }
        guard let key = info.keyHex, !key.isEmpty else { throw StreamPrepareError.noKey }

        // 1.4.4 修复口径：同一集各档共用同一内容密钥，把 definition 与 codec 纳入缓存文件名防止高低档撞名；
        // 校验逻辑保持不变，仍只判 size > 100_000。
        let defPart = safe(info.definition.isEmpty ? "unknown" : info.definition)
        let codecPart = safe(info.codec.isEmpty ? "unknown" : info.codec)
        let cacheKey = "\(safe(info.vid))-\(defPart)-\(codecPart)-\(key.prefix(8))"
        let dest = cacheDir.appendingPathComponent("\(cacheKey).mp4")
        if let attrs = try? fm.attributesOfItem(atPath: dest.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > 100_000 {
            // 1.2 (2) 已验证口径：只判文件是否像完整的解密 MP4，不比对 info.fileSize。
            AppLog.write("PREPARE cache hit vid=\(info.vid) def=\(info.definition) codec=\(info.codec) bytes=\(size.intValue) path=\(dest.lastPathComponent)")
            progress("已命中本地解密缓存，起播")
            return dest
        }
        if let running = inflight[cacheKey] {
            return try await running.value
        }

        let task = Task<URL, Error> {
            try await self.downloadAndDecrypt(info, key: key, dest: dest, progress: progress)
        }
        inflight[cacheKey] = task
        defer { inflight[cacheKey] = nil }
        return try await task.value
    }

    private func downloadAndDecrypt(_ info: StreamInfo, key: String, dest: URL,
                                    progress: @escaping (String) -> Void) async throws -> URL {
        var candidates: [String] = [info.url]
        if let backup = info.backupURL, !backup.isEmpty, backup != info.url { candidates.append(backup) }
        var lastError: Error = StreamPrepareError.emptyFile

        for (i, address) in candidates.enumerated() {
            guard let url = URL(string: address), url.host != nil else {
                lastError = StreamPrepareError.badURL(address)
                continue
            }
            do {
                AppLog.write("PREPARE download start vid=\(info.vid) def=\(info.definition) codec=\(info.codec) host=\(url.host ?? "?") try=\(i + 1) size=\(info.fileSize)")
                progress("正在下载加密流（\(info.definition)）…")
                var req = URLRequest(url: url)
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
                // 红果 CDN 对带 Referer 的请求直接 403（openresty Forbid_code 020200）；不要加。
                let (tmp, response) = try await session.download(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let tmpSize = (try? fm.attributesOfItem(atPath: tmp.path))
                    .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
                AppLog.write("PREPARE download HTTP status=\(status) bytes=\(tmpSize) host=\(url.host ?? "?")")
                guard status == 200 || status == 206 else {
                    try? fm.removeItem(at: tmp)
                    throw StreamPrepareError.http(status)
                }
                guard tmpSize > 0 else {
                    try? fm.removeItem(at: tmp)
                    throw StreamPrepareError.emptyFile
                }
                progress("下载完成 \(tmpSize / 1024 / 1024)MB，正在本地解密…")
                var bytes = [UInt8](try Data(contentsOf: tmp))
                try? fm.removeItem(at: tmp)
                let did = try CENCDecryptor.decrypt(&bytes, keyHex: key)
                guard did else { throw StreamPrepareError.decryptFailed("文件没有 CENC 加密标记") }
                try Data(bytes).write(to: dest, options: .atomic)
                AppLog.write("PREPARE decrypted vid=\(info.vid) def=\(info.definition) codec=\(info.codec) bytes=\(bytes.count) key=\(key.prefix(8)) dest=\(dest.lastPathComponent)")
                progress("解密完成，起播")
                return dest
            } catch {
                lastError = error
                AppLog.write("PREPARE try=\(i + 1) failed host=\(url.host ?? "?") error=\(error.localizedDescription)")
            }
        }
        throw lastError
    }

    private func pruneStaleCaches(forVid vid: String, keeping dest: URL) {
        let prefix = "\(safe(vid))-"
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.path != dest.path {
            try? fm.removeItem(at: file)
        }
    }

    private func safe(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    // MARK: - 1.4 离线追剧包 & 缓存占用统计/清理接口（沿用同一 RedDuoDuoStreams 解密落盘目录）

    func existingPlaintextURL(forVid vid: String) -> URL? {
        let prefix = "\(safe(vid))-"
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        var best: (url: URL, size: Int)?
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "mp4" {
            let size = (try? fm.attributesOfItem(atPath: file.path))
                .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
            if size > 100_000, best == nil || size > best!.size {
                best = (file, size)
            }
        }
        return best?.url
    }

    func removeCachedFiles(forVid vid: String) -> Int64 {
        let prefix = "\(safe(vid))-"
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return 0 }
        var freed: Int64 = 0
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            let size = (try? fm.attributesOfItem(atPath: file.path))
                .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? 0
            if (try? fm.removeItem(at: file)) != nil {
                freed += size
            }
        }
        return freed
    }

    func totalDiskCacheBytes() -> Int64 {
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let v = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = v.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func clearAllDiskCache() -> Int64 {
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return 0 }
        var freed: Int64 = 0
        for file in files {
            let size = (try? fm.attributesOfItem(atPath: file.path))
                .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? 0
            if (try? fm.removeItem(at: file)) != nil {
                freed += size
            }
        }
        return freed
    }
}
