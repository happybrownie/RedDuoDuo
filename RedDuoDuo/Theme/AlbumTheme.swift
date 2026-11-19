import SwiftUI
import UIKit

// RedDuoDuo 1.4.8 「B 浮层画册」
// 沿网飞骨架（大 Hero + 横滑海报行 + 详情 + 播放），以焦点海报取色的低饱和漫反射光晕替代死黑底；
// 海报 3:4 大圆角无描边 + 毛玻璃名牌 + 纯黑软影；全站按钮/选集/搜索/底栏/播控皆胶囊/丸。
// 明暗：页面背景、毛玻璃、名牌等使用自适应 token；播放页/试看流等媒体舞台继续恒深色。

// MARK: - 自适应色工具

private func rdAlbumAdaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}

private func rdAlbumAdaptiveUI(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    }
}

extension UIColor {
    convenience init(rdHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(rdHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private func rdClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(v, lo), hi)
}

// MARK: - 设计 token

enum RDAlbum {
    // 2. 色彩
    enum C {
        /// 景深基底：深色 #0C0C0F / 浅色干净雾白，均由海报余光托底。
        static let base = rdAlbumAdaptive(
            light: UIColor(rdHex: 0xF4F5F9),
            dark: UIColor(rdHex: 0x0C0C0F)
        )
        static let baseDeep = rdAlbumAdaptive(
            light: UIColor(rdHex: 0xEBEDF4),
            dark: UIColor(rdHex: 0x09090B)
        )
        /// 无图/加载/空页兜底峰值。
        static let fallbackPeak = rdAlbumAdaptive(
            light: UIColor(rdHex: 0xDFE3EF),
            dark: UIColor(rdHex: 0x2B3042)
        )
        static let fallbackDeep = rdAlbumAdaptive(
            light: UIColor(rdHex: 0xE8EBF4),
            dark: UIColor(rdHex: 0x1C202E)
        )

        // 2.2 文字与功能色（浅色下提深保证 ≥4.5:1）
        static let textPrimary = rdAlbumAdaptive(
            light: UIColor(rdHex: 0x111114),
            dark: UIColor(rdHex: 0xF5F5F7)
        )
        static let textSecondary = rdAlbumAdaptive(
            light: UIColor(rdHex: 0x585B66),
            dark: UIColor(rdHex: 0xB8B9C2)
        )
        static let textTertiary = rdAlbumAdaptive(
            light: UIColor(rdHex: 0x6B6D77),
            dark: UIColor(rdHex: 0x7D7F8A)
        )
        static let disabled = rdAlbumAdaptive(
            light: UIColor(rdHex: 0xA9ABB4),
            dark: UIColor(rdHex: 0x4A4C55)
        )
        /// 反色（白胶囊上的字）。固定，白胶囊恒白。
        static let inverse = Color(rdHex: 0x0E0E11)
        /// 压在媒体（海报/视频）上的固定亮字，与页面明暗无关。
        static let mediaPrimary = Color(rdHex: 0xF5F5F7)
        static let mediaSecondary = Color(rdHex: 0xB8B9C2)
        static let mediaTertiary = Color(rdHex: 0x7D7F8A)
        /// 彩点：更新 6pt / 删除警示。
        static let accentDot = Color(rdHex: 0xFF5E6C)

        static let progressPlayed = Color.white
        static let progressBuffer = Color.white.opacity(0.42)
        static let progressTrack = Color.white.opacity(0.20)

        // 纯黑软影（禁彩影）
        static let posterShadow = Color.black.opacity(0.32)
        static let posterShadowLift = Color.black.opacity(0.48)
        static let barShadow = Color.black.opacity(0.42)
        static let controlShadow = Color.black.opacity(0.50)
        static let heroTextShadow = Color.black.opacity(0.28)

        // 海报名牌恒为媒体上的深色玻璃
        static let plateFill = Color(rdHex: 0x101116, opacity: 0.44)

        // 媒体上的弱白/白描边
        static let mediaHairline = Color.white.opacity(0.18)
        static let mediaHairlineSoft = Color.white.opacity(0.12)
    }

    // 3. 排印（SF Pro Rounded + PingFang，禁 .black/.heavy）
    enum Font {
        static func rounded(_ size: CGFloat, _ weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        /// 主片名 30/36（大屏 34/40）
        static func hero(_ wide: Bool) -> SwiftUI.Font { rounded(wide ? 34 : 30, .bold) }
        /// 页标题 28/34
        static let pageTitle = rounded(28, .bold)
        /// 行标题 20/26
        static let rowTitle = rounded(20, .semibold)
        /// 宽副标 13/18 Medium tracking +1.8（中文 +1.4）
        static let wideSub = rounded(13, .medium)
        /// 正文 15/23 Regular
        static let body = rounded(15, .regular)
        /// 胶囊字 15/18 Semibold
        static let pill = rounded(15, .semibold)
        /// 名牌名 13/17 Semibold
        static let plateName = rounded(13, .semibold)
        /// 名牌副 11/14 Medium
        static let plateSub = rounded(11, .medium)
        /// 集号 14/16 Semibold
        static let episode = rounded(14, .semibold)
        /// 时间码 12/14 Medium
        static let timecode = rounded(12, .medium)
        static let navLabel = rounded(10, .semibold)
    }

    // 4. 圆角（Continuous）
    enum Radius {
        static let poster: CGFloat = 18
        static let thumb: CGFloat = 14
        static let hero: CGFloat = 24
        static let board: CGFloat = 28
        static let sheet: CGFloat = 28
        static let capsule: CGFloat = 999
    }

    // 4. 间距
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
        static let pageSmall: CGFloat = 20
        static let pageWide: CGFloat = 32
        static let rowGap: CGFloat = 36
        static let rowGapFeatured: CGFloat = 40
        static let headerToRow: CGFloat = 14
        static let cardGapSmall: CGFloat = 14
        static let cardGapWide: CGFloat = 16
        static let foldClearance: CGFloat = 12
    }

    // 4. 3:4 尺寸
    enum Poster {
        static func height(_ width: CGFloat) -> CGFloat { width * 4 / 3 }
        static let largeSmall: CGFloat = 160
        static let largeWide: CGFloat = 188
        static let mediumSmall: CGFloat = 132
        static let plateLarge: CGFloat = 52
        static let plateMedium: CGFloat = 46
        static let thumbContinue = CGSize(width: 54, height: 72)
        static let thumbHistory = CGSize(width: 64, height: 85)
    }

    // 5. 悬浮导航丸
    enum Nav {
        static let height: CGFloat = 58
        static let bottomGap: CGFloat = 12
        static let wideLimit: CGFloat = 420
        static let selectedHeight: CGFloat = 44
    }

    // 6. 动效
    enum Motion {
        static let glow = Animation.easeInOut(duration: 0.65)
        static let pillPress = Animation.spring(response: 0.12, dampingFraction: 1.0)
        static let pillRelease = Animation.spring(response: 0.22, dampingFraction: 0.72)
        static let drawer = Animation.spring(response: 0.38, dampingFraction: 0.84)
        static let posterLift = Animation.spring(response: 0.30, dampingFraction: 0.78)
        static let heroParallax = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let rearrange = Animation.easeInOut(duration: 0.35)
    }

    // 2.3 玻璃
    enum GlassKind: Equatable {
        case secondary   // 24 模糊 / #FFF@14%(secondary) / #FFF@20%
        case nav         // 32 / #181920@62% / #FFF@16%
        case player      // 32 / #14151B@68% / #FFF@18%
        case plate       // 18 / #101116@44% / 无
        case drawer      // 40 / #15161D@78% / #FFF@12%
        case toast       // 24 / #14151B@78% / #FFF@14%
    }
}

// MARK: - 海报取色（2.1）

/// 从海报提取的景深光晕色：保 H，钳 S'∈[0.14,0.30]、L'∈[0.10,0.18]（深色峰值）。
struct RDAlbumTint: Equatable {
    let hue: Double        // 0...1
    let saturation: Double // 0...1
    let lightness: Double  // 0...1
    let key: String
    let isFallback: Bool

    static let fallback = RDAlbumTint(
        hue: 0.625, saturation: 0.22, lightness: 0.17, key: "fallback", isFallback: true
    )

    var darkPeakColor: Color { Self.color(h: hue, s: saturation, l: lightness) }

    /// 浅色外观下同一色相转为极浅雾色峰值（自适应 token 优先，避免深色光晕压脏白底）。
    var lightPeakColor: Color {
        Self.color(h: hue, s: rdClamp(saturation * 0.42, 0.05, 0.13), l: 0.88)
    }

    /// 深色峰值叠色；浅色更轻。
    func peak(isLight: Bool) -> Color {
        isLight ? lightPeakColor : darkPeakColor
    }

    static func color(h: Double, s: Double, l: Double) -> Color {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r: Double = 0, g: Double = 0, b: Double = 0
        switch hp {
        case 0..<1: r = c; g = x; b = 0
        case 1..<2: r = x; g = c; b = 0
        case 2..<3: r = 0; g = c; b = x
        case 3..<4: r = 0; g = x; b = c
        case 4..<5: r = x; g = 0; b = c
        default:    r = c; g = 0; b = x
        }
        let m = l - c / 2
        return Color(.sRGB, red: rdClamp(r + m, 0, 1), green: rdClamp(g + m, 0, 1), blue: rdClamp(b + m, 0, 1), opacity: 1)
    }

    /// 32×32 sRGB 缩样；剔 L<0.08 / L>0.92 / S<0.10；有效 <15% 用兜底；
    /// 12 色相桶，权 W=S×(1-|L-0.5|)，取最高桶均值；保 H 钳 S/L。
    static func extract(from image: UIImage, cacheKey: String) -> RDAlbumTint? {
        guard let cg = image.cgImage else { return nil }
        let side = 32
        var data = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drawn: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var bucketWeight = [Double](repeating: 0, count: 12)
        var bucketH = [Double](repeating: 0, count: 12)
        var bucketS = [Double](repeating: 0, count: 12)
        var bucketL = [Double](repeating: 0, count: 12)
        var valid = 0

        for i in 0..<(side * side) {
            let o = i * 4
            let r = Double(data[o]) / 255
            let g = Double(data[o + 1]) / 255
            let b = Double(data[o + 2]) / 255
            let maxV = max(r, max(g, b))
            let minV = min(r, min(g, b))
            let l = (maxV + minV) / 2
            let d = maxV - minV
            let s: Double = d <= 0.0001 ? 0 : d / max(0.0001, 1 - abs(2 * l - 1))
            guard l >= 0.08, l <= 0.92, s >= 0.10 else { continue }
            var h: Double = 0
            if d > 0.0001 {
                if maxV == r {
                    h = ((g - b) / d).truncatingRemainder(dividingBy: 6) / 6
                } else if maxV == g {
                    h = ((b - r) / d + 2) / 6
                } else {
                    h = ((r - g) / d + 4) / 6
                }
                if h < 0 { h += 1 }
            }
            let bucket = min(11, max(0, Int(h * 12)))
            let w = s * (1 - abs(l - 0.5))
            bucketWeight[bucket] += w
            bucketH[bucket] += h * w
            bucketS[bucket] += s * w
            bucketL[bucket] += l * w
            valid += 1
        }

        guard valid >= Int(Double(side * side) * 0.15) else { return nil }
        guard let best = bucketWeight.indices.max(by: { bucketWeight[$0] < bucketWeight[$1] }),
              bucketWeight[best] > 0.0001 else { return nil }
        let w = bucketWeight[best]
        let h = bucketH[best] / w
        let s = bucketS[best] / w
        let l = bucketL[best] / w
        let sPrime = rdClamp(s * 0.55, 0.14, 0.30)
        let lPrime = rdClamp(l * 0.42, 0.10, 0.18)
        return RDAlbumTint(
            hue: h, saturation: sPrime, lightness: lPrime,
            key: "\(cacheKey)#\(Int(h * 1000))-\(Int(sPrime * 1000))-\(Int(lPrime * 1000))",
            isFallback: false
        )
    }
}

/// 取色缓存：同一 URL 只算一次（32×32 缩样，主线程耗时可忽略）。
@MainActor
final class RDAlbumTintStore {
    static let shared = RDAlbumTintStore()
    private var cache: [String: RDAlbumTint] = [:]
    private var failed: Set<String> = []

    func tint(for urlString: String) async -> RDAlbumTint? {
        guard !urlString.isEmpty else { return nil }
        if let hit = cache[urlString] { return hit }
        guard !failed.contains(urlString), let url = URL(string: urlString) else { return nil }
        guard let img = await ImageCache.shared.loadThumb(url, maxPixel: 64) else {
            failed.insert(urlString)
            return nil
        }
        guard let tint = RDAlbumTint.extract(from: img, cacheKey: urlString) else {
            failed.insert(urlString)
            return nil
        }
        cache[urlString] = tint
        return tint
    }
}

// MARK: - 景深光晕背景

private struct RDAlbumNoise: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = RDSeededGenerator(seed: 0x9E3779B9)
            for _ in 0..<720 {
                let x = CGFloat.random(in: 0...max(size.width, 1), using: &rng)
                let y = CGFloat.random(in: 0...max(size.height, 1), using: &rng)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(0.55))
                )
            }
        }
        .blendMode(.overlay)
        .opacity(0.035)
        .allowsHitTesting(false)
    }
}

private struct RDSeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
}

/// 双径向晕 + 48 模糊 + 2% 噪点防色带；切色 0.65s easeInOut（ΔE<6 跳过由 key 等值天然处理）。
struct RDAlbumAmbientBackground: View {
    var tint: RDAlbumTint?
    var intensity: Double = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let isLight = colorScheme == .light
            let peak = (tint ?? .fallback).peak(isLight: isLight)
            let deep = tint?.isFallback ?? true
            ZStack {
                LinearGradient(
                    colors: [
                        isLight ? RDAlbum.C.base : RDAlbum.C.baseDeep,
                        RDAlbum.C.base
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ZStack {
                    RadialGradient(
                        stops: [
                            .init(color: peak.opacity(isLight ? 0.92 : 0.98), location: 0),
                            .init(color: peak.opacity(isLight ? 0.55 : 0.62), location: 0.56),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: 0.50, y: 0.14),
                        startRadius: 0,
                        endRadius: max(geo.size.width, geo.size.height) * (deep ? 0.78 : 0.85)
                    )

                    RadialGradient(
                        stops: [
                            .init(color: peak.opacity(isLight ? 0.50 : 0.72), location: 0),
                            .init(color: peak.opacity(isLight ? 0.22 : 0.30), location: 0.22),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: 0.82, y: 0.46),
                        startRadius: 0,
                        endRadius: max(geo.size.width, geo.size.height) * 0.65
                    )
                }
                .blur(radius: 48)
                .scaleEffect(1.12)
                .opacity(intensity)

                RDAlbumNoise()
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(RDAlbum.Motion.glow, value: tint?.key)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 毛玻璃

extension RDAlbum.GlassKind {
    var fill: Color {
        switch self {
        case .secondary:
            return rdAlbumAdaptive(light: UIColor(rdHex: 0xFFFFFF, alpha: 0.62), dark: UIColor(rdHex: 0xFFFFFF, alpha: 0.14))
        case .nav:
            return rdAlbumAdaptive(light: UIColor(rdHex: 0xFFFFFF, alpha: 0.78), dark: UIColor(rdHex: 0x181920, alpha: 0.62))
        case .player:
            return UIColor(rdHex: 0x14151B, alpha: 0.68).asColor
        case .plate:
            return RDAlbum.C.plateFill
        case .drawer:
            return rdAlbumAdaptive(light: UIColor(rdHex: 0xFFFFFF, alpha: 0.88), dark: UIColor(rdHex: 0x15161D, alpha: 0.78))
        case .toast:
            return UIColor(rdHex: 0x14151B, alpha: 0.78).asColor
        }
    }

    var stroke: Color {
        switch self {
        case .secondary: return rdAlbumAdaptive(light: UIColor.black.withAlphaComponent(0.10), dark: UIColor.white.withAlphaComponent(0.20))
        case .nav: return rdAlbumAdaptive(light: UIColor.black.withAlphaComponent(0.08), dark: UIColor.white.withAlphaComponent(0.16))
        case .player: return Color.white.opacity(0.18)
        case .plate: return .clear
        case .drawer: return rdAlbumAdaptive(light: UIColor.black.withAlphaComponent(0.08), dark: UIColor.white.withAlphaComponent(0.12))
        case .toast: return Color.white.opacity(0.14)
        }
    }

    var forceDark: Bool {
        self == .player || self == .toast || self == .plate
    }

    var material: Material {
        switch self {
        case .plate: return .ultraThinMaterial
        case .secondary, .toast: return .ultraThinMaterial
        case .nav, .player: return .thinMaterial
        case .drawer: return .regularMaterial
        }
    }
}

private extension UIColor {
    var asColor: Color { Color(uiColor: self) }
}

private struct RDAlbumGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let kind: RDAlbum.GlassKind
    let shadow: Bool
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(kind.material)
                    shape.fill(kind.fill)
                    if kind != .plate {
                        shape.strokeBorder(kind.stroke, lineWidth: 0.6)
                    }
                }
                .environment(\.colorScheme, kind.forceDark ? .dark : colorScheme)
                .allowsHitTesting(false)
            }
            .shadow(color: shadow && kind != .plate ? Color.black.opacity(0.34) : .clear, radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func rdAlbumGlass<S: InsettableShape>(
        _ shape: S,
        kind: RDAlbum.GlassKind = .secondary,
        shadow: Bool = true,
        shadowRadius: CGFloat = 20,
        shadowY: CGFloat = 10
    ) -> some View {
        modifier(RDAlbumGlassModifier(shape: shape, kind: kind, shadow: shadow, shadowRadius: shadowRadius, shadowY: shadowY))
    }

    func rdAlbumCapsuleGlass(kind: RDAlbum.GlassKind = .secondary, shadow: Bool = false) -> some View {
        rdAlbumGlass(Capsule(style: .continuous), kind: kind, shadow: shadow)
    }
}

// MARK: - 胶囊按钮

/// 主白胶囊（播放/继续看）。白底恒白 + 反色字，压深色软影；不用于页面正文。
struct RDAlbumPrimaryPillStyle: ButtonStyle {
    var height: CGFloat = 46
    var horizontalPadding: CGFloat = 22
    var fullWidth: Bool = false
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RDAlbum.Font.pill)
            .foregroundStyle(RDAlbum.C.inverse)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5))
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.22 : 0.34), radius: configuration.isPressed ? 10 : 20, x: 0, y: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(configuration.isPressed ? RDAlbum.Motion.pillPress : RDAlbum.Motion.pillRelease, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard haptic else { return }
                if pressed { RDHaptics.shared.playGemButtonPressDown() } else { RDHaptics.shared.playGemButtonRelease() }
            }
    }
}

/// 次级玻璃胶囊。
struct RDAlbumGlassPillStyle: ButtonStyle {
    var height: CGFloat = 46
    var horizontalPadding: CGFloat = 18
    var fullWidth: Bool = false
    var mediaOverlay: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RDAlbum.Font.pill)
            .foregroundStyle(mediaOverlay ? RDAlbum.C.mediaPrimary : RDAlbum.C.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background {
                let shape = Capsule(style: .continuous)
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(mediaOverlay
                               ? Color(rdHex: 0x101116, opacity: 0.46)
                               : rdAlbumAdaptive(light: UIColor.white.withAlphaComponent(0.58), dark: UIColor.white.withAlphaComponent(0.14)))
                    shape.strokeBorder(mediaOverlay ? Color.white.opacity(0.20) : rdAlbumAdaptive(light: UIColor.black.withAlphaComponent(0.09), dark: UIColor.white.withAlphaComponent(0.20)), lineWidth: 0.6)
                }
                .environment(\.colorScheme, mediaOverlay ? .dark : colorScheme)
            }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.18 : 0.30), radius: configuration.isPressed ? 8 : 18, x: 0, y: configuration.isPressed ? 4 : 9)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed ? RDAlbum.Motion.pillPress : RDAlbum.Motion.pillRelease, value: configuration.isPressed)
    }
}

/// 40 圆钮（详情返回/更多）。
struct RDAlbumRoundIconStyle: ButtonStyle {
    var size: CGFloat = 40
    var mediaOverlay: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(mediaOverlay ? RDAlbum.C.mediaPrimary : RDAlbum.C.textPrimary)
            .frame(width: size, height: size)
            .background {
                let shape = Circle()
                ZStack {
                    if mediaOverlay {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Color(rdHex: 0x101116, opacity: 0.44))
                        shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    } else {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(rdAlbumAdaptive(light: UIColor.white.withAlphaComponent(0.66), dark: UIColor.white.withAlphaComponent(0.14)))
                        shape.strokeBorder(rdAlbumAdaptive(light: UIColor.black.withAlphaComponent(0.09), dark: UIColor.white.withAlphaComponent(0.18)), lineWidth: 0.6)
                    }
                }
                .environment(\.colorScheme, mediaOverlay ? .dark : colorScheme)
            }
            .shadow(color: Color.black.opacity(0.26), radius: 14, x: 0, y: 7)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(RDAlbum.Motion.pillPress, value: configuration.isPressed)
    }
}

/// 36 顶栏圆钮（挑剧/刷新）。
struct RDAlbumTopIconStyle: ButtonStyle {
    var size: CGFloat = 36
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(RDAlbum.C.textPrimary)
            .frame(width: size, height: size)
            .background {
                let shape = Circle()
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(rdAlbumAdaptive(light: UIColor.white.withAlphaComponent(0.66), dark: UIColor.white.withAlphaComponent(0.12)))
                    shape.strokeBorder(rdAlbumAdaptive(light: UIColor.black.withAlphaComponent(0.08), dark: UIColor.white.withAlphaComponent(0.16)), lineWidth: 0.6)
                }
            }
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(RDAlbum.Motion.pillPress, value: configuration.isPressed)
    }
}

// MARK: - 排印 & 区块标题

struct RDAlbumSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var showsChevron: Bool = true
    var wideSubtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(RDAlbum.Font.rowTitle)
                .foregroundStyle(RDAlbum.C.textPrimary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RDAlbum.C.textTertiary)
            }
            Spacer(minLength: 8)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(RDAlbum.Font.wideSub)
                    .tracking(1.4)
                    .foregroundStyle(RDAlbum.C.textSecondary)
                    .lineLimit(1)
            } else if let wideSubtitle, !wideSubtitle.isEmpty {
                Text(wideSubtitle)
                    .font(RDAlbum.Font.wideSub)
                    .tracking(1.4)
                    .foregroundStyle(RDAlbum.C.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 宽副标（元信息）13 / tracking 1.8。
struct RDAlbumWideSub: View {
    let text: String
    var color: Color = RDAlbum.C.textSecondary
    var body: some View {
        Text(text)
            .font(RDAlbum.Font.wideSub)
            .tracking(1.4)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - 海报名牌

struct RDAlbumNameplate: View {
    let name: String
    var sub: String? = nil
    var height: CGFloat = RDAlbum.Poster.plateLarge
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 0)
            if let hint {
                Text(hint)
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.mediaPrimary.opacity(0.92))
                    .lineLimit(1)
                Text(name)
                    .font(RDAlbum.Font.plateName)
                    .foregroundStyle(RDAlbum.C.mediaPrimary)
                    .lineLimit(1)
            } else {
                Text(name)
                    .font(RDAlbum.Font.plateName)
                    .foregroundStyle(RDAlbum.C.mediaPrimary)
                    .lineLimit(1)
                if let sub, !sub.isEmpty {
                    Text(sub)
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.mediaSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .bottomLeading)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(RDAlbum.C.plateFill)
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.16)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .environment(\.colorScheme, .dark)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 12 / max(height, 1)),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 3:4 无框软影海报卡

struct RDAlbumPosterCard: View {
    let series: Series
    var width: CGFloat
    var plateHeight: CGFloat = RDAlbum.Poster.plateLarge
    var sub: String? = nil
    var badge: String? = nil
    var showsScore: Bool = false

    @State private var previewing = false
    @State private var previewZoom: CGFloat = 1.0
    @State private var previewTask: Task<Void, Never>?
    @State private var pressTask: Task<Void, Never>?

    private var height: CGFloat { RDAlbum.Poster.height(width) }

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteCover(url: series.cover, thumbnailMaxPixel: 600)
                .frame(width: width, height: height)
                .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.22)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            RDAlbumNameplate(
                name: series.title,
                sub: sub ?? subLine,
                height: plateHeight,
                hint: previewing ? "静音预览 · 8s" : nil
            )
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topLeading) {
            if let badge, !badge.isEmpty {
                HStack(spacing: 4) {
                    if series.isJustUpdated {
                        Circle().fill(RDAlbum.C.accentDot).frame(width: 6, height: 6)
                    }
                    Text(badge)
                        .font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.mediaPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.44), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsScore, !series.score.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.system(size: 8))
                        .foregroundStyle(RDAlbum.C.mediaPrimary.opacity(0.9))
                    Text(series.score).font(RDAlbum.Font.plateSub)
                        .foregroundStyle(RDAlbum.C.mediaPrimary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.44), in: Capsule())
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.poster, style: .continuous))
        .overlay {
            if previewing {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(RDAlbum.C.mediaPrimary)
                        .padding(10)
                        .background(Color.black.opacity(0.46), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                }
                .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.poster, style: .continuous))
                .transition(.opacity)
            }
        }
        .scaleEffect(previewing ? 1.07 * previewZoom : 1)
        .rotation3DEffect(.degrees(previewing ? 6 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .shadow(color: previewing ? RDAlbum.C.posterShadowLift : RDAlbum.C.posterShadow, radius: previewing ? 32 : 20, x: 0, y: previewing ? 18 : 10)
        .contentShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.poster, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.38, maximumDistance: 24, perform: {
            beginPreview()
        }, onPressingChanged: { pressing in
            if !pressing { scheduleEndPreview() }
        })
        .onDisappear {
            previewTask?.cancel()
            pressTask?.cancel()
            previewing = false
            previewZoom = 1
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(series.title)，\(series.episodeCount)集")
    }

    private var subLine: String {
        if series.isCompleted { return "已完结 · 全\(series.episodeCount)集" }
        if !series.badge.isEmpty { return series.badge }
        if !series.tags.isEmpty { return series.tags.prefix(2).joined(separator: " · ") }
        return "全\(series.episodeCount)集"
    }

    private func beginPreview() {
        guard !previewing else { return }
        RDHaptics.shared.playResumeCardTap()
        withAnimation(RDAlbum.Motion.posterLift) {
            previewing = true
            previewZoom = 1.0
        }
        withAnimation(.easeOut(duration: 8)) { previewZoom = 1.08 }
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            endPreview()
        }
    }

    private func scheduleEndPreview() {
        pressTask?.cancel()
        pressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, previewing else { return }
            endPreview()
        }
    }

    private func endPreview() {
        previewTask?.cancel()
        withAnimation(RDAlbum.Motion.pillRelease) {
            previewing = false
            previewZoom = 1.0
        }
    }
}

// MARK: - 悬浮导航丸（5 项 / 58 高 / 距底 12 / 选中 44 丸）

@MainActor
final class RDAlbumChrome: ObservableObject {
    static let shared = RDAlbumChrome()
    /// 详情浮层 / 搜索键入时隐藏浏览底栏（多来源按 reason 叠加，避免互相覆盖）。
    @Published private(set) var hidesBrowseChrome = false
    private var reasons: Set<String> = []

    func setBrowseChromeHidden(_ hidden: Bool, reason: String) {
        if hidden {
            reasons.insert(reason)
        } else {
            reasons.remove(reason)
        }
        let next = !reasons.isEmpty
        if next != hidesBrowseChrome {
            hidesBrowseChrome = next
        }
    }
}

struct RDAlbumFloatingNav: View {
    @Binding var selection: Int
    var onSelect: (Int) -> Void

    private let items: [(title: String, icon: String)] = [
        ("首页", "house.fill"),
        ("试看", "flame.fill"),
        ("搜索", "magnifyingglass"),
        ("观看", "clock.arrow.circlepath"),
        ("我的", "person.fill")
    ]

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 600
            let navWidth = wide ? min(RDAlbum.Nav.wideLimit, geo.size.width - 32) : geo.size.width - 32
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let active = idx == selection
                    Button {
                        onSelect(idx)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(height: 20)
                            Text(item.title)
                                .font(RDAlbum.Font.navLabel)
                                .tracking(0.2)
                        }
                        .foregroundStyle(active ? RDAlbum.C.textPrimary : RDAlbum.C.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: RDAlbum.Nav.selectedHeight)
                        .background {
                            if active {
                                Capsule(style: .continuous)
                                    .fill(rdAlbumAdaptive(light: UIColor.black.withAlphaComponent(0.07), dark: UIColor.white.withAlphaComponent(0.16)))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(.horizontal, 7)
            .frame(width: navWidth, height: RDAlbum.Nav.height)
            .rdAlbumGlass(Capsule(style: .continuous), kind: .nav, shadow: true, shadowRadius: 24, shadowY: 10)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .frame(height: RDAlbum.Nav.height)
        .padding(.bottom, RDAlbum.Nav.bottomGap)
    }
}

// MARK: - 选集胶囊

enum RDAlbumEpisodeState {
    case current
    case watched
    case unwatched
}

struct RDAlbumEpisodeCapsule: View {
    let index: Int
    let state: RDAlbumEpisodeState
    var cached: Bool = false
    var fillsWidth: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Text("\(index)")
                    .font(RDAlbum.Font.episode)
                    .monospacedDigit()
                    .foregroundStyle(textColor)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .frame(minWidth: 56)
                    .padding(.horizontal, fillsWidth ? 6 : 14)
                    .frame(height: 38)
                    .background {
                        Capsule(style: .continuous)
                            .fill(fillColor)
                            .overlay(Capsule(style: .continuous).strokeBorder(strokeColor, lineWidth: 0.6))
                    }
                if cached {
                    Circle()
                        .fill(RDAlbum.C.mediaPrimary.opacity(state == .unwatched ? 0.55 : 0.9))
                        .frame(width: 5, height: 5)
                        .padding(.trailing, 9)
                        .padding(.bottom, 6)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第\(index)集")
    }

    private var isLight: Bool { colorScheme == .light }

    private var fillColor: Color {
        switch state {
        case .current:
            return isLight ? Color(rdHex: 0x111114) : Color.white
        case .watched:
            return isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06)
        case .unwatched:
            return isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.12)
        }
    }

    private var textColor: Color {
        switch state {
        case .current: return isLight ? Color.white : RDAlbum.C.inverse
        case .watched: return RDAlbum.C.textTertiary
        case .unwatched: return RDAlbum.C.textPrimary
        }
    }

    private var strokeColor: Color {
        switch state {
        case .current: return .clear
        case .watched: return isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06)
        case .unwatched: return isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.10)
        }
    }
}

// MARK: - 通用横滑海报行（L/M 错落）

struct RDAlbumPosterRow: View {
    let title: String
    var trailing: String? = nil
    var showsChevron: Bool = true
    let items: [Series]
    var cardWidth: CGFloat = RDAlbum.Poster.largeSmall
    var plateHeight: CGFloat = RDAlbum.Poster.plateLarge
    var spacing: CGFloat = RDAlbum.Space.cardGapSmall
    var leadingInset: CGFloat = 0
    var subtitle: ((Series) -> String?)? = nil
    var showScore: Bool = false
    var onSelect: (Series) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RDAlbum.Space.headerToRow) {
            RDAlbumSectionHeader(title: title, trailing: trailing, showsChevron: showsChevron)
                .padding(.horizontal, RDAlbum.Space.pageSmall)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        Button {
                            RDHaptics.shared.playResumeCardTap()
                            onSelect(item)
                        } label: {
                            RDAlbumPosterCard(
                                series: item,
                                width: cardWidth,
                                plateHeight: plateHeight,
                                sub: subtitle?(item) ?? nil,
                                badge: item.isJustUpdated ? "更新" : (item.isCompleted ? "完结" : nil),
                                showsScore: showScore
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("series-card-\(item.id)")
                    }
                }
                .padding(.leading, RDAlbum.Space.pageSmall + leadingInset)
                .padding(.trailing, RDAlbum.Space.pageSmall)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - 进度条（3pt 轨 + 6/14 白点）

struct RDAlbumProgressBar: View {
    var fraction: Double
    var trackHeight: CGFloat = 3
    var showsBuffer: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(RDAlbum.C.progressTrack)
                    .frame(height: trackHeight)
                if showsBuffer {
                    Capsule().fill(RDAlbum.C.progressBuffer)
                        .frame(width: geo.size.width * min(max(fraction, 0), 1) * 0.92, height: trackHeight)
                }
                Capsule().fill(RDAlbum.C.progressPlayed)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1), height: trackHeight)
            }
            .frame(height: trackHeight)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: max(trackHeight, 4))
    }
}

// MARK: - 白色播放圆钮

struct RDAlbumPlayCircle: View {
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.34), radius: 14, y: 7)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(RDAlbum.C.inverse)
                .offset(x: size * 0.02)
        }
    }
}

// MARK: - 续看卡（16:9 / 24 圆角 / 海报名牌 / 进度 / 40 白播钮）

struct RDAlbumContinueCard: View {
    let entry: HistoryEntry
    var height: CGFloat = 168
    var showsBadge: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteCover(url: entry.cover, thumbnailMaxPixel: 800)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.50)],
                startPoint: .center,
                endPoint: .bottom
            )

            RDAlbumNameplate(
                name: entry.title,
                sub: "第\(entry.lastIndex)集 · \(entry.progressFraction > 0 ? entry.positionText + " / " : "")共\(entry.episodeCount)集",
                height: 56
            )

            if entry.progressFraction > 0 {
                VStack {
                    Spacer()
                    RDAlbumProgressBar(fraction: entry.progressFraction, trackHeight: 3)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 3)
            }

            if showsBadge {
                VStack {
                    HStack {
                        Spacer()
                        RDAlbumPlayCircle(size: 40)
                            .padding(12)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous))
        .shadow(color: RDAlbum.C.posterShadow, radius: 20, x: 0, y: 10)
    }
}

// MARK: - 小型续看条目（54×72 缩略 + 进度 + 34 白播钮）

struct RDAlbumContinueTile: View {
    let entry: HistoryEntry
    var width: CGFloat = 230

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                RemoteCover(url: entry.cover, thumbnailMaxPixel: 200)
                    .frame(width: RDAlbum.Poster.thumbContinue.width, height: RDAlbum.Poster.thumbContinue.height)
                    .clipped()
                if entry.progressFraction > 0 {
                    RDAlbumProgressBar(fraction: entry.progressFraction, trackHeight: 2, showsBuffer: false)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                }
            }
            .frame(width: RDAlbum.Poster.thumbContinue.width, height: RDAlbum.Poster.thumbContinue.height)
            .clipShape(RoundedRectangle(cornerRadius: RDAlbum.Radius.thumb, style: .continuous))
            .shadow(color: RDAlbum.C.posterShadow, radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(RDAlbum.Font.plateName)
                    .foregroundStyle(RDAlbum.C.textPrimary)
                    .lineLimit(1)
                Text("第\(entry.lastIndex)集 · 剩\(max(entry.episodeCount - entry.lastIndex, 0))集")
                    .font(RDAlbum.Font.plateSub)
                    .foregroundStyle(RDAlbum.C.textSecondary)
                    .lineLimit(1)
                RDAlbumProgressBar(fraction: entry.progressFraction, trackHeight: 2, showsBuffer: false)
                    .frame(width: 88)
            }
            Spacer(minLength: 0)
            RDAlbumPlayCircle(size: 34)
        }
        .padding(10)
        .frame(width: width)
        .rdAlbumGlass(RoundedRectangle(cornerRadius: RDAlbum.Radius.hero, style: .continuous), kind: .secondary, shadow: true, shadowRadius: 16, shadowY: 8)
    }
}

// MARK: - 播放页底部单药丸（3pt 轨 / 拖 6+14 白点）

struct RDAlbumScrubber: View {
    let time: Double
    let duration: Double
    var onEditingChanged: (Bool) -> Void
    var onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = dragFraction ?? (duration > 0 ? min(max(time / duration, 0), 1) : 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(RDAlbum.C.progressTrack)
                    .frame(height: 3)
                Capsule()
                    .fill(RDAlbum.C.progressPlayed)
                    .frame(width: width * fraction, height: 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, y: 1)
                    .overlay(Circle().fill(Color.white).frame(width: 6, height: 6).opacity(0.0))
                    .offset(x: min(max(width * fraction - 7, 0), width - 14))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragFraction == nil {
                            onEditingChanged(true)
                        }
                        let f = min(max(value.location.x / width, 0), 1)
                        dragFraction = f
                        onSeek(f * max(duration, 1))
                    }
                    .onEnded { _ in
                        dragFraction = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 22)
        .accessibilityIdentifier("player-slider")
    }
}

// MARK: - 提示丸（2s）

struct RDAlbumToast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(RDAlbum.Font.timecode.weight(.semibold))
            .foregroundStyle(RDAlbum.C.mediaPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .rdAlbumGlass(Capsule(style: .continuous), kind: .toast, shadow: true, shadowRadius: 16, shadowY: 8)
            .environment(\.colorScheme, .dark)
    }
}
