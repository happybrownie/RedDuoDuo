// Copyright (c) 2026 iDuanJu contributors (https://github.com/my-name-is-alan/iDuanJu)
// License: GPL-3.0 (iDuanJu project); see LICENSE / THIRD_PARTY_NOTICES.md.
// Source: iDuanJu STV/Providers/Hongguo/HGSign.swift — spade section, excerpted line-by-line.
// Modified for RedDuoDuo: kept only the functions needed for key unwrapping.
// Attribution note: this file is GPL-3.0 iDuanJu code; the Apache-2.0 NOTICE covers
// only the current*.go transforms, not spade.
import Foundation

/// CENC 内容密钥解封：红果 `video_model.video_list[].encrypt_info.spade_a` → 32 hex 内容密钥。
/// 只保留取密钥所需函数，纯本地计算，不访问网络。
enum SpadeKey {
    private static func popcount(_ x: Int) -> Int { x.nonzeroBitCount }

    private static func transformNonmagic(_ a: [UInt8], _ mode: Int) -> [UInt8] {
        var w11: UInt8 = 0x55, w12: UInt8 = 0xfa
        var out = [UInt8]()
        for (i, c) in a.enumerated() {
            let x: UInt8
            if i % 2 == 0 { x = w12; w12 = c } else { x = w11; w11 = c }
            let pc = popcount(i)
            let delta = mode != 0 ? pc + 0x15 : -0x15 - pc
            out.append(UInt8(truncatingIfNeeded: (Int(x ^ c) + delta) & 0xff))
        }
        return out
    }

    private static func transformMagic(_ a: [UInt8], _ mode: Int) -> [UInt8] {
        func swap(_ b: [UInt8]) -> [UInt8] {
            var b = b; var i = 0
            while i + 1 < b.count { b.swapAt(i, i + 1); i += 2 }
            return b
        }
        let s = swap(a)
        var w12: UInt8 = 0x55, w13: UInt8 = 0xfa
        var out = [UInt8]()
        for (i, c) in s.enumerated() {
            let x: UInt8, y: UInt8
            if i % 2 == 0 { x = w13; y = w12; w13 = c } else { x = w12; y = w13; w12 = c }
            let pc = popcount(i)
            let delta = mode != 0 ? pc + 0x15 : -0x15 - pc
            out.append(UInt8(truncatingIfNeeded: (Int(x ^ c) - Int(y) + delta) & 0xff))
        }
        return swap(out)
    }

    private static func hexval(_ ch: UInt8) -> Int {
        if ch >= 0x30 && ch <= 0x39 { return Int(ch) - 0x30 }
        if ch >= 0x61 && ch <= 0x66 { return Int(ch) - 0x57 }
        return -1
    }

    static func unwrap(_ spade: [UInt8], mode: Int = 0) -> String? {
        let ln = spade.count
        guard ln >= 4 else { return nil }
        let v = Int(spade[0] ^ spade[1] ^ spade[2])
        let hdr = v - 0x30
        guard hdr >= 1 else { return nil }
        let w22 = ln - v + 0x2f
        guard w22 >= 1, 1 + w22 <= ln else { return nil }
        let a = Array(spade[1..<1 + w22])
        let si = ln - hdr - 2
        guard si >= 0, si + 1 < ln, ln - hdr >= 0 else { return nil }
        let seed = spade[si] ^ spade[si + 1]
        let buf = (0..<hdr).map { seed ^ spade[ln - hdr + $0] }
        let magic = buf.count >= 6 && ["app_v2", "web_v2"].contains(String(decoding: buf[0..<6], as: UTF8.self))
        let a2 = magic ? transformMagic(a, mode) : transformNonmagic(a, mode)
        guard !a2.isEmpty else { return nil }
        let hv = hexval(a2[0])
        guard hv >= 0 else { return nil }
        let remaining = w22 - hv
        guard remaining >= 2, remaining <= a2.count else { return nil }
        return String(decoding: a2[1..<remaining], as: UTF8.self)
    }

    /// 输入 `encrypt_info.spade_a`，返回 32 位小写 hex；失败返回 nil。
    static func contentKey(envelope: String) -> String? {
        let t = envelope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var cands: [[UInt8]] = []
        var b64 = t.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        if let d = Data(base64Encoded: b64) { cands.append(Array(d)) }
        if let h = hexBytes(t) { cands.append(h) }
        for raw in cands {
            if let k = unwrap(raw), let kb = hexBytes(k), kb.count == 16 { return k.lowercased() }
        }
        return nil
    }

    static func base64Data(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    static func hexBytes(_ s: String) -> [UInt8]? {
        let chars = Array(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard chars.count % 2 == 0, !chars.isEmpty else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let h = UInt8(String(decoding: chars[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
            out.append(h); i += 2
        }
        return out
    }
}
