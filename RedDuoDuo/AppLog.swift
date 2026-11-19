import Foundation

/// 落盘诊断日志（Documents/redduoduo.log）。
/// - 脱敏口径：所有调用点只记录状态码、字节数、Cookie 名、存在性标志等元数据；
///   不记录原始响应体、任何 token/cookie 值、手机号、账号 uid/昵称（见 ManjuAPI / AuthStore）。
/// - 大小上限 512 KB：超限即清空重建，避免无限增长。
enum AppLog {
    private static let lock = NSLock()
    private static let maxFileBytes: UInt64 = 512 * 1024
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("redduoduo.log")
    }

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        print("RDD \(line)", terminator: "")
        guard let data = line.data(using: .utf8) else { return }
        // 超过上限直接清空重建（诊断日志不做历史保留）。
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? NSNumber, size.uint64Value > maxFileBytes {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}