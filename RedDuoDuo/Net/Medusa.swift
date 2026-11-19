// Copyright (c) 2026 iDuanJu contributors (https://github.com/my-name-is-alan/iDuanJu)
// License: GPL-3.0 (iDuanJu project); see LICENSE / THIRD_PARTY_NOTICES.md.
// Source: iDuanJu STV/Providers/Hongguo/Medusa.swift.
// Modified for RedDuoDuo: reduced to the SM3 hash used by
// HGPlayerSign. The unused X-Medusa minting path and white-box transform tables (which
// required a non-distributed medusa_tables.bin resource) were removed as dead code.
import Foundation

/// SM3 哈希（GB/T 32905-2016），供 HGPlayerSign 签名使用。
enum Medusa {
    // MARK: SM3
    private static let sm3IV: [UInt32] = [0x7380166F, 0x4914B2B9, 0x172442D7, 0xDA8A0600, 0xA96F30BC, 0x163138AA, 0xE38DEE4D, 0xB0FB0E4E]
    @inline(__always) private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { let n = n & 31; return n == 0 ? x : (x << n) | (x >> (32 - n)) }
    private static func p0(_ x: UInt32) -> UInt32 { x ^ rotl(x, 9) ^ rotl(x, 17) }
    private static func p1(_ x: UInt32) -> UInt32 { x ^ rotl(x, 15) ^ rotl(x, 23) }

    static func sm3(_ data: [UInt8]) -> [UInt8] {
        var v = sm3IV
        var buf = data + [0x80]
        while buf.count % 64 != 56 { buf.append(0) }
        let bitLen = UInt64(data.count) * 8
        for i in (0..<8).reversed() { buf.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xff)) }
        var off = 0
        while off < buf.count {
            var w = [UInt32](repeating: 0, count: 68)
            for i in 0..<16 {
                let o = off + i * 4
                w[i] = UInt32(buf[o]) << 24 | UInt32(buf[o + 1]) << 16 | UInt32(buf[o + 2]) << 8 | UInt32(buf[o + 3])
            }
            for j in 16..<68 { w[j] = p1(w[j - 16] ^ w[j - 9] ^ rotl(w[j - 3], 15)) ^ rotl(w[j - 13], 7) ^ w[j - 6] }
            var w1 = [UInt32](repeating: 0, count: 64)
            for j in 0..<64 { w1[j] = w[j] ^ w[j + 4] }
            var a = v[0], b = v[1], c = v[2], d = v[3], e = v[4], f = v[5], g = v[6], h = v[7]
            for j in 0..<64 {
                let tj: UInt32 = j < 16 ? 0x79CC4519 : 0x7A879D8A
                let ss1 = rotl(rotl(a, 12) &+ e &+ rotl(tj, UInt32(j)), 7)
                let ss2 = ss1 ^ rotl(a, 12)
                let ff = j < 16 ? (a ^ b ^ c) : ((a & b) | (a & c) | (b & c))
                let gg = j < 16 ? (e ^ f ^ g) : ((e & f) | (~e & g))
                let tt1 = ff &+ d &+ ss2 &+ w1[j]
                let tt2 = gg &+ h &+ ss1 &+ w[j]
                d = c; c = rotl(b, 9); b = a; a = tt1
                h = g; g = rotl(f, 19); f = e; e = p0(tt2)
            }
            v = [v[0] ^ a, v[1] ^ b, v[2] ^ c, v[3] ^ d, v[4] ^ e, v[5] ^ f, v[6] ^ g, v[7] ^ h]
            off += 64
        }
        return v.flatMap { Bytes.u32BE($0) }
    }
}