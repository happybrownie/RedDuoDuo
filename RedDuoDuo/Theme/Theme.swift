// Copyright (c) 2026 DouDuo contributors (https://github.com/81199000/DouDuo)
// License: MIT — see Licenses/DouDuo-MIT.txt.
// Derived from DouDuo's theme/color system (DDColor and friends), heavily rewritten.
// Modified for RedDuoDuo: Faceted Ruby design language, RD palette/typography/
// components, glassEffect and iOS 27.1 reservedRegions layout hooks.
import SwiftUI

// RedDuoDuo 1.4.2 统一主题：黑曜石暗色玻璃底（#141414）+ 珠宝切面深红宝石（Faceted Ruby）组件语言。
// 质感唯一锚点 = AppIcon-1024.png：深红通透、斜角切面高光、克制内发光、边缘一线亮、阴影收敛；次要元素退回干净暗色玻璃。

enum RD {
    // MARK: 颜色
    enum Palette {
        static let background = Color(red: 18/255, green: 18/255, blue: 20/255)       // #121214 黑曜石底
        static let surface = Color(red: 27/255, green: 27/255, blue: 30/255)          // #1B1B1E 烟熏黑玻璃
        static let surfaceRaised = Color(red: 36/255, green: 36/255, blue: 40/255)    // #242428
        static let surfaceElevated = Color(red: 48/255, green: 48/255, blue: 53/255)  // #303035
        static let accent = Color(red: 196/255, green: 12/255, blue: 24/255)          // #C40C18 深石榴主红
        static let accentGlow = Color(red: 168/255, green: 10/255, blue: 22/255).opacity(0.24)
        static let textPrimary = Color.white
        static let textSecondary = Color(white: 0.74)
        static let textTertiary = Color(white: 0.50)
        static let hairline = Color.white.opacity(0.09)
        static let highlight = Color.white.opacity(0.18)
        static let warning = Color(red: 230/255, green: 152/255, blue: 72/255)        // 收敛琥珀警示
        static let success = Color(red: 186/255, green: 214/255, blue: 202/255)       // 克制银翠状态点（禁高饱和艳绿）
        static let platinum = Color(red: 220/255, green: 224/255, blue: 232/255)      // 珠宝铂银（替代刺眼黄，禁红金混搭）
        static let pearl = Color(red: 204/255, green: 212/255, blue: 222/255)         // 冷月珍珠银（离线/完成徽标点）
        static let gold = platinum                                                    // 兼容旧符号，全站收归铂银冷辉

        // Faceted Ruby 宝石色阶（严格采样自 AppIcon-1024 深红宝石播放键）
        static let gemVoid = Color(red: 34/255, green: 2/255, blue: 6/255)            // #220206 最深暗影切面
        static let gemAbyss = Color(red: 64/255, green: 3/255, blue: 10/255)          // #40030A 暗石榴深底
        static let gemDeep = Color(red: 112/255, green: 6/255, blue: 16/255)          // #700610 深红酒体量感
        static let gemCore = Color(red: 168/255, green: 10/255, blue: 22/255)         // #A80A16 鸽血红宝石本体
        static let gemBright = Color(red: 224/255, green: 24/255, blue: 36/255)       // #E01824 迎光切面红
        static let gemCaustic = Color(red: 255/255, green: 84/255, blue: 76/255)      // #FF544C 内部折射焦散光
        static let gemRim = Color(red: 255/255, green: 186/255, blue: 180/255)        // #FFBAB4 边缘折射亮丝
        static let gemFilament = Color(red: 255/255, green: 242/255, blue: 236/255)   // #FFF2EC 刀锋白粉亮边
        static let gemText = Color(red: 238/255, green: 146/255, blue: 150/255)       // #EE9296 克制玫瑰银辅字
        static let gemBorder = Color(red: 255/255, green: 138/255, blue: 132/255).opacity(0.36)
        static let gemBorderSoft = Color(red: 196/255, green: 12/255, blue: 24/255).opacity(0.24)
        static let gemGlow = Color(red: 168/255, green: 10/255, blue: 22/255).opacity(0.42)
    }

    // MARK: 宝石渐变与公共笔刷
    enum Gem {
        /// 深红通透本体渐变（70% 深石榴底 + 迎光切面红，拒绝塑料大红平涂）。
        static let fillGradient = LinearGradient(
            stops: [
                .init(color: Palette.gemBright, location: 0.0),
                .init(color: Palette.gemCore, location: 0.36),
                .init(color: Palette.gemDeep, location: 0.74),
                .init(color: Palette.gemAbyss, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 顶部/左上斜切面玻璃反光（配合几何切面裁切使用）。
        static let topGlossGradient = LinearGradient(
            stops: [
                .init(color: Palette.gemFilament.opacity(0.34), location: 0),
                .init(color: Palette.gemRim.opacity(0.12), location: 0.42),
                .init(color: .clear, location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 边缘一线亮（非对称：左上锐亮白粉锋芒 → 中段宝石红 → 暗面收敛 → 右下微回光）。
        static let innerRimGradient = LinearGradient(
            stops: [
                .init(color: Palette.gemFilament.opacity(0.92), location: 0.0),
                .init(color: Palette.gemRim.opacity(0.58), location: 0.22),
                .init(color: Palette.gemCore.opacity(0.22), location: 0.52),
                .init(color: Palette.gemAbyss.opacity(0.30), location: 0.78),
                .init(color: Palette.gemCaustic.opacity(0.48), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 暗色玻璃海报框边缘（次要容器退回克制冷银玻璃棱边，零糊红框）。
        static let posterBorderGradient = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.24), location: 0.0),
                .init(color: Color.white.opacity(0.09), location: 0.45),
                .init(color: Color.white.opacity(0.05), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 主锚点宝石卡片边线（克制一线亮红宝石棱）。
        static let anchorBorderGradient = LinearGradient(
            stops: [
                .init(color: Palette.gemFilament.opacity(0.62), location: 0.0),
                .init(color: Palette.gemRim.opacity(0.34), location: 0.25),
                .init(color: Palette.gemCore.opacity(0.20), location: 0.65),
                .init(color: Palette.gemCaustic.opacity(0.28), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 普通卡片干净暗色玻璃细描边。
        static let cardBorderGradient = LinearGradient(
            colors: [
                Color.white.opacity(0.14),
                Color.white.opacity(0.07),
                Palette.hairline
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let progressGradient = LinearGradient(
            stops: [
                .init(color: Palette.gemDeep, location: 0.0),
                .init(color: Palette.gemBright, location: 0.85),
                .init(color: Palette.gemRim, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: 字阶（拉大 Hero / 行标题 / 正文层级）
    enum Font {
        static let displayLarge = SwiftUI.Font.system(size: 34, weight: .black)
        static let display = SwiftUI.Font.system(size: 28, weight: .heavy)
        static let title = SwiftUI.Font.system(size: 22, weight: .bold)
        static let rowTitle = SwiftUI.Font.system(size: 19, weight: .bold)
        static let headline = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 14, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 12, weight: .medium)
        static let micro = SwiftUI.Font.system(size: 10, weight: .bold)
        static let rankNumber = SwiftUI.Font.system(size: 74, weight: .black, design: .rounded)
    }

    // MARK: 圆角
    enum Radius {
        static let poster: CGFloat = 7
        static let control: CGFloat = 9
        static let card: CGFloat = 12
        static let sheet: CGFloat = 18
    }

    // MARK: 间距
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let gutter: CGFloat = 16
    }

    // MARK: 动效节奏（对齐 DouDuo / Netflix 轻快回弹）
    enum Motion {
        static let press = Animation.spring(response: 0.24, dampingFraction: 0.78)
        static let snappy = Animation.snappy(duration: 0.22)
        static let fade = Animation.easeInOut(duration: 0.22)
    }

    // MARK: 折叠屏断点 & 响应式列数
    /// 展开（内屏）与合上（外屏）的宽度分界。只看容器宽度，折叠/展开时同一棵视图树原地重排。
    static let wideBreakpoint: CGFloat = 600
    static func isWide(_ width: CGFloat) -> Bool { width >= wideBreakpoint }

    /// 按可用容器宽度铺满列数（不留居中窄列）。
    static func gridColumns(contentWidth: CGFloat, minCardWidth: CGFloat = 116, spacing: CGFloat = Space.md) -> [GridItem] {
        let safeW = max(contentWidth, minCardWidth)
        let count = max(3, Int((safeW + spacing) / (minCardWidth + spacing)))
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
}

extension Color {
    static let rdBackground = RD.Palette.background
    static let rdSurface = RD.Palette.surface
    static let rdAccent = RD.Palette.accent
}

// MARK: - 安全区测量（让背景/视频满屏出血，同时保护前景标题与控件不被刘海/圆角裁切）

enum RDScreenMetrics {
    @MainActor static var keyWindowSafeAreaInsets: EdgeInsets {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return EdgeInsets()
        }
        let i = window.safeAreaInsets
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }
}

/// 放在不忽略安全区的背景探针中读取真实系统安全区（用于折叠/展开/横竖屏切态时实时同步）。
struct RDSafeAreaProbe: View {
    @Binding var insets: EdgeInsets

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { update(geo.safeAreaInsets) }
                .onChange(of: geo.safeAreaInsets) { _, new in update(new) }
        }
        .allowsHitTesting(false)
    }

    private func update(_ new: EdgeInsets) {
        if abs(insets.top - new.top) > 0.5 ||
            abs(insets.bottom - new.bottom) > 0.5 ||
            abs(insets.leading - new.leading) > 0.5 ||
            abs(insets.trailing - new.trailing) > 0.5 {
            insets = new
        }
    }
}

/// 在不忽略水平安全区的内容容器内，叠加 iOS 27.1+ `reservedRegions(kind: .occlusion)`（例如右侧悬浮状态/标签栏）避让宽度，防止任何内容钻到底下。
enum RDLayoutInsets {
    static func horizontal(in geo: GeometryProxy, gutter: CGFloat = RD.Space.gutter) -> (leading: CGFloat, trailing: CGFloat) {
        var leadingOcc: CGFloat = 0
        var trailingOcc: CGFloat = 0
        if #available(iOS 27.1, *) {
            let bounds = CGRect(origin: .zero, size: geo.size)
            if bounds.width > 120, bounds.height > 120 {
                for region in geo.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed) where region.isActive {
                    let f = region.frame.standardized
                    guard f.width > 1, f.height > 1, f.intersects(bounds), f.width < bounds.width * 0.42 else { continue }
                    if f.midX > bounds.width * 0.62 {
                        trailingOcc = max(trailingOcc, bounds.maxX - f.minX)
                    } else if f.midX < bounds.width * 0.38 {
                        leadingOcc = max(leadingOcc, f.maxX - bounds.minX)
                    }
                }
            }
        }
        return (
            leading: gutter + min(leadingOcc, 120),
            trailing: gutter + min(trailingOcc, 120)
        )
    }
}

// MARK: - 多层次 Netflix Scrim

/// 单向渐隐遮罩。
struct RDScrim: View {
    var top = false
    var strength: Double = 1
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: RD.Palette.background.opacity(0), location: 0),
                .init(color: RD.Palette.background.opacity(0.55 * strength), location: 0.55),
                .init(color: RD.Palette.background.opacity(strength), location: 1)
            ],
            startPoint: top ? .bottom : .top, endPoint: top ? .top : .bottom)
        .allowsHitTesting(false)
    }
}

/// Netflix 式 Hero 多层遮罩：顶部导航保护晕 + 宽屏左侧文字保护晕 + 多段式底部与背景融接。
struct RDHeroScrim: View {
    var wide: Bool = false

    var body: some View {
        ZStack {
            // 1. 顶部暗化，保证顶栏图标与状态栏可读
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.68), location: 0),
                        .init(color: .black.opacity(0.22), location: 0.55),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                Spacer(minLength: 0)
            }

            // 2. 宽屏时左半侧径向/横向暗化，突出左排大标题
            if wide {
                LinearGradient(
                    stops: [
                        .init(color: RD.Palette.background.opacity(0.88), location: 0),
                        .init(color: RD.Palette.background.opacity(0.52), location: 0.38),
                        .init(color: RD.Palette.background.opacity(0.10), location: 0.68),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            // 3. 底部多段平滑渐隐融入 #141414 纯黑底，消除硬切缝
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.18),
                    .init(color: RD.Palette.background.opacity(0.24), location: 0.45),
                    .init(color: RD.Palette.background.opacity(0.66), location: 0.70),
                    .init(color: RD.Palette.background.opacity(0.94), location: 0.88),
                    .init(color: RD.Palette.background, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 宝石播放标（与 AppIcon-1024 深红宝石播放键同款矢量）

/// 仅外轮廓或内镂空的圆角播放三角形路径。
struct RDGemPlayTrianglePath: Shape {
    var cutout: Bool = false

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let p1: CGPoint
        let p2: CGPoint
        let p3: CGPoint
        let r: CGFloat
        if cutout {
            p1 = CGPoint(x: w * 0.295, y: h * 0.325)
            p2 = CGPoint(x: w * 0.625, y: h * 0.500)
            p3 = CGPoint(x: w * 0.295, y: h * 0.675)
            r = min(w, h) * 0.055
        } else {
            p1 = CGPoint(x: w * 0.140, y: h * 0.080)
            p2 = CGPoint(x: w * 0.920, y: h * 0.500)
            p3 = CGPoint(x: w * 0.140, y: h * 0.920)
            r = min(w, h) * 0.165
        }
        return Self.roundedTriangle(p1: p1, p2: p2, p3: p3, radius: r)
    }

    static func roundedTriangle(p1: CGPoint, p2: CGPoint, p3: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let mid12 = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
        path.move(to: mid12)
        path.addArc(tangent1End: p2, tangent2End: p3, radius: radius)
        path.addArc(tangent1End: p3, tangent2End: p1, radius: radius)
        path.addArc(tangent1End: p1, tangent2End: p2, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// 带中心镂空的宝石播放键外环（eoFill），保留高光与内发光轮廓。
struct RDGemPlayRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = RDGemPlayTrianglePath(cutout: false).path(in: rect)
        path.addPath(RDGemPlayTrianglePath(cutout: true).path(in: rect))
        return path
    }
}

/// 左上角切面多边形路径（营造真实宝石斜角切削反光）。
private struct RDGemTopFacetPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width * 0.64, y: 0))
        p.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// 右下深度暗切面路径（与左上高光切面形成珠宝体块反差）。
private struct RDGemBottomFacetPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.56, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.28))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// 统一珠宝级红宝石多层次表面（深红通透体 + 内部焦散微光 + 几何斜角切面 + 内发光 + 边缘一线亮 + 收敛投影）。
struct RDGemFacetSurface<S: InsettableShape>: View {
    let shape: S
    var pressed: Bool = false
    var shadowRadius: CGFloat = 7
    var borderWidth: CGFloat = 0.9

    var body: some View {
        ZStack {
            // 1. 深石榴通透本体
            shape.fill(RD.Gem.fillGradient)

            // 2. 右下内部焦散微光（模拟光线穿过宝石内部折出）
            shape.fill(
                RadialGradient(
                    colors: [
                        RD.Palette.gemCaustic.opacity(0.42),
                        RD.Palette.gemCore.opacity(0.14),
                        .clear
                    ],
                    center: UnitPoint(x: 0.74, y: 0.72),
                    startRadius: 2,
                    endRadius: 96
                )
            )

            // 3. 左上斜角高光切面 & 右下深暗压面（真实切面对比，替代平庸顶部白条）
            RDGemTopFacetPath()
                .fill(RD.Gem.topGlossGradient)
                .clipShape(shape)

            RDGemBottomFacetPath()
                .fill(
                    LinearGradient(
                        colors: [.clear, RD.Palette.gemVoid.opacity(0.46)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(shape)

            // 4. 克制内发光（严格裁剪在轮廓内，绝不外糊）
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            RD.Palette.gemCaustic.opacity(0.70),
                            RD.Palette.gemCore.opacity(0.25),
                            RD.Palette.gemBright.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.0
                )
                .blur(radius: 1.5)
                .clipShape(shape)

            // 5. 边缘一线亮（0.9pt 锐利白粉晶体高光边）
            shape
                .strokeBorder(RD.Gem.innerRimGradient, lineWidth: borderWidth)
        }
        .shadow(color: RD.Palette.gemCore.opacity(pressed ? 0.25 : 0.40), radius: pressed ? 4 : shadowRadius, x: 0, y: pressed ? 1 : 2)
        .shadow(color: .black.opacity(0.60), radius: 4, x: 0, y: 2)
    }
}

/// 与 App 图标（AppIcon-1024.png）同款的深红宝石播放标：深红通透体、弯曲高光切面、内外刀锋亮边、收敛投影。
struct RDGemPlayMark: View {
    var size: CGFloat = 26

    var body: some View {
        let rimWidth = max(0.85, size * 0.036)
        let innerWidth = max(0.70, size * 0.030)
        RDGemPlayRingShape()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: RD.Palette.gemBright, location: 0.0),
                        .init(color: RD.Palette.gemCore, location: 0.34),
                        .init(color: RD.Palette.gemDeep, location: 0.70),
                        .init(color: RD.Palette.gemVoid, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: FillStyle(eoFill: true)
            )
            .frame(width: size, height: size)
            .overlay {
                // 内部核心火彩（右尖与下弧内部折射）
                RadialGradient(
                    colors: [RD.Palette.gemCaustic.opacity(0.55), RD.Palette.gemCore.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.72, y: 0.52),
                    startRadius: size * 0.04,
                    endRadius: size * 0.45
                )
                .mask(RDGemPlayRingShape().fill(style: FillStyle(eoFill: true)))
            }
            .overlay {
                // 左上弧形切面高光（对标 AppIcon-1024 左上角晶莹曲面反射）
                RDGemTopFacetPath()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: RD.Palette.gemFilament.opacity(0.76), location: 0),
                                .init(color: RD.Palette.gemRim.opacity(0.24), location: 0.45),
                                .init(color: .clear, location: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .mask(RDGemPlayRingShape().fill(style: FillStyle(eoFill: true)))
            }
            .overlay {
                // 右下深石榴暗切面（拉开体块深度）
                RDGemBottomFacetPath()
                    .fill(RD.Palette.gemVoid.opacity(0.52))
                    .mask(RDGemPlayRingShape().fill(style: FillStyle(eoFill: true)))
            }
            .overlay {
                // 外缘「边缘一线亮」（左上与右尖锐亮，暗边收敛）
                RDGemPlayTrianglePath(cutout: false)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: RD.Palette.gemFilament.opacity(0.95), location: 0.0),
                                .init(color: RD.Palette.gemRim.opacity(0.72), location: 0.24),
                                .init(color: RD.Palette.gemCore.opacity(0.28), location: 0.56),
                                .init(color: RD.Palette.gemCaustic.opacity(0.68), location: 0.90),
                                .init(color: RD.Palette.gemFilament.opacity(0.82), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: rimWidth
                    )
            }
            .overlay {
                // 内镂空三角形炽热折射亮边
                RDGemPlayTrianglePath(cutout: true)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: RD.Palette.gemCaustic.opacity(0.88), location: 0.0),
                                .init(color: RD.Palette.gemFilament.opacity(0.92), location: 0.45),
                                .init(color: RD.Palette.gemRim.opacity(0.70), location: 1.0)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        lineWidth: innerWidth
                    )
            }
            .shadow(color: RD.Palette.gemCore.opacity(0.50), radius: max(3, size * 0.16), x: 0, y: max(1, size * 0.05))
            .shadow(color: .black.opacity(0.68), radius: max(2, size * 0.10), x: 0, y: max(1, size * 0.04))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - 宝石按钮样式与按压反馈

private struct RDGemButtonSurface<S: InsettableShape>: View {
    let shape: S
    let isPressed: Bool
    var filled: Bool = true
    var haptics: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if filled {
                RDGemFacetSurface(shape: shape, pressed: isPressed, shadowRadius: 7, borderWidth: 0.9)
            } else {
                ZStack {
                    shape.fill(RD.Palette.surfaceRaised)
                    shape.strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.42), radius: 5, x: 0, y: 3)
            }
        }
        .opacity(isEnabled ? (isPressed ? 0.90 : 1.0) : 0.45)
        .allowsHitTesting(false)
        .onChange(of: isPressed) { _, pressed in
            guard haptics, isEnabled else { return }
            if pressed {
                RDHaptics.shared.prepareLightweight()
                RDHaptics.shared.playGemButtonPressDown()
            } else {
                RDHaptics.shared.playGemButtonRelease()
            }
        }
    }
}

/// 宝石主按钮（深红宝石渐变 + 顶部高光 + 内发光 + 红色辉光阴影）。
struct RDGemPrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 44
    var cornerRadius: CGFloat = RD.Radius.control
    var capsule: Bool = false
    var haptics: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = capsule ? 999 : cornerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(RD.Font.headline.weight(.bold))
            .foregroundStyle(.white)
            .rdMediaShadow()
            .frame(maxWidth: capsule ? nil : .infinity, minHeight: minHeight)
            .padding(.horizontal, capsule ? 20 : 0)
            .background { RDGemButtonSurface(shape: shape, isPressed: configuration.isPressed, filled: true, haptics: haptics) }
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(RD.Motion.press, value: configuration.isPressed)
    }
}

/// 宝石胶囊主按钮（用于搜索提交、轻量主动作胶囊）。
struct RDGemPillButtonStyle: ButtonStyle {
    var expanded: Bool = false
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(RD.Font.caption.weight(.bold))
            .foregroundStyle(.white)
            .rdMediaShadow()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: expanded ? .infinity : nil)
            .background { RDGemButtonSurface(shape: shape, isPressed: configuration.isPressed, filled: true) }
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .animation(RD.Motion.press, value: configuration.isPressed)
    }
}

/// 次级暗色玻璃按钮（干净烟熏玻璃 + 极细冷银棱边）。
struct RDGemSecondaryButtonStyle: ButtonStyle {
    var capsule: Bool = true
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = capsule ? 999 : RD.Radius.control
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(RD.Font.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial.opacity(0.68))
                    shape.fill(Color(red: 24/255, green: 24/255, blue: 28/255).opacity(0.55))
                    shape.strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.75)
                }
                .environment(\.colorScheme, .dark)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(RD.Motion.press, value: configuration.isPressed)
    }
}

struct RDPrimaryButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
        configuration.label
            .font(RD.Font.headline.weight(filled ? .bold : .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background { RDGemButtonSurface(shape: shape, isPressed: configuration.isPressed, filled: filled) }
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(RD.Motion.press, value: configuration.isPressed)
    }
}

/// Netflix Hero 主播放按钮（1.3 默认主样式，等价于宝石主按钮，保留符号兼容）。
struct RDWhiteHeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RDGemPrimaryButtonStyle().makeBody(configuration: configuration)
    }
}

/// Hero 玻璃次按钮（如「详情」——干净烟熏半透玻璃 + 顶部冷银细棱）。
struct RDGlassHeroButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 44
    var capsule: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = capsule ? 999 : RD.Radius.control
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(RD.Font.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: capsule ? nil : .infinity, minHeight: minHeight)
            .padding(.horizontal, capsule ? 18 : 0)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial.opacity(0.70))
                    shape.fill(Color(red: 22/255, green: 22/255, blue: 26/255).opacity(0.52))
                    shape.strokeBorder(RD.Gem.posterBorderGradient, lineWidth: 0.75)
                }
                .environment(\.colorScheme, .dark)
            }
            .shadow(color: .black.opacity(0.38), radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(RD.Motion.press, value: configuration.isPressed)
    }
}

struct RDIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(RD.Palette.textPrimary)
            .frame(width: 44, height: 44)
            .background(RD.Palette.surfaceRaised, in: shape)
            .overlay(
                shape.strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.7)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(RD.Motion.press, value: configuration.isPressed)
    }
}

/// 卡片通用按压反馈（海报 / Top10 / 继续观看 / 搜索 / 观看记录）。
struct RDPosterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(RD.Motion.press, value: configuration.isPressed)
    }
}

// MARK: - 宝石卡片与海报容器修饰器

struct RDCard: ViewModifier {
    var radius: CGFloat = RD.Radius.card
    var fill: Color = RD.Palette.surface
    var border = true
    var glow = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(fill)
                    if glow {
                        // 仅在关键锚点卡使用收敛深石榴内透与斜角反光
                        shape.fill(
                            RadialGradient(
                                colors: [RD.Palette.gemDeep.opacity(0.34), RD.Palette.gemAbyss.opacity(0.12), .clear],
                                center: .topLeading,
                                startRadius: 6,
                                endRadius: 230
                            )
                        )
                        RDGemTopFacetPath()
                            .fill(
                                LinearGradient(
                                    colors: [RD.Palette.gemFilament.opacity(0.08), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(shape)
                    } else {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [.white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 18)
                            Spacer(minLength: 0)
                        }
                        .clipShape(shape)
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay {
                if border {
                    shape
                        .strokeBorder(glow ? RD.Gem.anchorBorderGradient : RD.Gem.cardBorderGradient, lineWidth: glow ? 0.85 : 0.65)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: glow ? RD.Palette.gemCore.opacity(0.20) : .black.opacity(0.30), radius: glow ? 8 : 5, x: 0, y: 3)
    }
}

struct RDGemPosterChrome: ViewModifier {
    var radius: CGFloat = RD.Radius.poster

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(shape)
            // 次要海报框退回干净暗色玻璃棱边，零模糊红圈，让宝石徽标与主按钮成为视觉焦点
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .strokeBorder(RD.Gem.posterBorderGradient, lineWidth: 0.65)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.50), radius: 6, x: 0, y: 3)
    }
}

extension View {
    func rdCard(radius: CGFloat = RD.Radius.card, fill: Color = RD.Palette.surface, border: Bool = true) -> some View {
        modifier(RDCard(radius: radius, fill: fill, border: border, glow: false))
    }

    func rdGemCard(radius: CGFloat = RD.Radius.card, fill: Color = RD.Palette.surface, glow: Bool = false) -> some View {
        modifier(RDCard(radius: radius, fill: fill, border: true, glow: glow))
    }

    /// 宝石海报容器修饰器：玻璃高光棱边 + 半透明亮红描边 + 红色辉光，封面图片本身零重绘零滤镜。
    func rdGemPosterChrome(radius: CGFloat = RD.Radius.poster) -> some View {
        modifier(RDGemPosterChrome(radius: radius))
    }

    /// 海报卡片细腻阴影与边缘高光（1.3 统一收口到宝石海报容器）。
    func rdPosterChrome(radius: CGFloat = RD.Radius.poster) -> some View {
        rdGemPosterChrome(radius: radius)
    }

    /// 全屏纯黑底（#141414）。
    func rdScreen() -> some View {
        background(RD.Palette.background.ignoresSafeArea())
    }

    /// 借 DouDuo 的 themeShadow：叠在媒体上的文字投影。
    func rdMediaShadow() -> some View { shadow(color: .black.opacity(0.55), radius: 4, y: 1.5) }

    /// 借 DouDuo 的 ddMediaGlassCircle：iOS 26 液态玻璃圆底（系统级播放器 HUD 保持原样）。
    func rdGlassCircle() -> some View {
        foregroundStyle(.white).glassEffect(.regular.interactive(), in: .circle).environment(\.colorScheme, .dark)
    }

    /// 借 DouDuo 的 ddMediaGlassCapsule：iOS 26 液态玻璃胶囊（系统级播放器 HUD 保持原样）。
    func rdGlassCircleCapsule() -> some View {
        foregroundStyle(.white).glassEffect(.regular.interactive(), in: .capsule).environment(\.colorScheme, .dark)
    }
}

// MARK: - 区块标题（Netflix 式「标题 ›」+ 宝石红条点缀）

struct RDSectionHeader: View {
    let title: String
    var trailing: String?
    var showsChevron = true
    var accentMark = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if accentMark {
                let barShape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                RDGemFacetSurface(shape: barShape, shadowRadius: 3, borderWidth: 0.65)
                    .frame(width: 3.5, height: 17)
                    .offset(y: 2)
            }
            Text(title)
                .font(RD.Font.rowTitle)
                .foregroundStyle(RD.Palette.textPrimary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentMark ? RD.Palette.platinum.opacity(0.80) : RD.Palette.textSecondary)
            }
            Spacer(minLength: 8)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(RD.Font.caption)
                    .foregroundStyle(RD.Palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 宝石角标与 Top 10 排行大数字

struct RDBadgePill: View {
    let text: String
    var accent = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(text)
            .font(RD.Font.micro)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background {
                if accent {
                    RDGemFacetSurface(shape: shape, shadowRadius: 3, borderWidth: 0.75)
                } else {
                    ZStack {
                        shape.fill(Color.black.opacity(0.76))
                        shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 0.6)
                    }
                }
            }
    }
}

/// 状态徽标：统一黑曜石暗玻璃底 + 宝石红（刚更新）/ 铂银（已完结）/ 珍珠银（离线已存），禁红绿/红金混搭。
struct RDStatusBadgePill: View {
    enum Kind {
        case updated
        case completed
        case offline
    }

    let text: String
    let kind: Kind

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let pipColor: Color = switch kind {
        case .updated: RD.Palette.gemCaustic
        case .completed: RD.Palette.platinum
        case .offline: RD.Palette.pearl
        }
        let borderColor: Color = switch kind {
        case .updated: RD.Palette.gemBorder
        case .completed, .offline: Color.white.opacity(0.18)
        }
        HStack(spacing: 4) {
            Circle()
                .fill(pipColor)
                .frame(width: 5, height: 5)
            Text(text)
        }
        .font(RD.Font.micro)
        .foregroundStyle(.white)
        .padding(.horizontal, 6.5)
        .padding(.vertical, 2.5)
        .background(Color(red: 14/255, green: 14/255, blue: 16/255).opacity(0.84), in: shape)
        .overlay(shape.strokeBorder(borderColor, lineWidth: 0.65))
    }
}

/// Top 10 雕琢红宝石数字牌面：锐利单向亮棱切角 + 深红石榴内透体 + 收敛暗影（去除四向重影糊边）。
struct RDRankNumberView: View {
    let rank: Int

    var body: some View {
        let label = "\(rank)"
        let topTier = rank <= 3
        let font = SwiftUI.Font.system(size: rank >= 10 ? 64 : 78, weight: .black, design: .rounded)
        let tracking: CGFloat = rank >= 10 ? -4 : 0

        ZStack {
            // 1. 深沉底部倒角暗缘
            Text(label)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(Color.black.opacity(0.92))
                .offset(x: 1.1, y: 1.2)

            // 2. 左上「一线亮」晶体折射锋芒
            Text(label)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: topTier ? RD.Palette.gemFilament : RD.Palette.gemRim.opacity(0.88), location: 0.0),
                            .init(color: topTier ? RD.Palette.gemRim : RD.Palette.gemCore.opacity(0.55), location: 0.45),
                            .init(color: RD.Palette.gemDeep.opacity(0.35), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(x: -1.0, y: -1.0)

            // 3. 深石榴通透切面本体
            Text(label)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(
                    LinearGradient(
                        stops: topTier ? [
                            .init(color: RD.Palette.gemBright, location: 0.0),
                            .init(color: RD.Palette.gemCore, location: 0.35),
                            .init(color: RD.Palette.gemDeep, location: 0.72),
                            .init(color: RD.Palette.gemVoid, location: 1.0)
                        ] : [
                            .init(color: RD.Palette.gemDeep, location: 0.0),
                            .init(color: RD.Palette.gemAbyss, location: 0.55),
                            .init(color: RD.Palette.gemVoid, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .shadow(color: topTier ? RD.Palette.gemCore.opacity(0.45) : .clear, radius: 6, y: 2)
        .shadow(color: .black.opacity(0.75), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - 过期/提示横幅 & 统一顶栏大气氛围

struct RDNotice: View {
    let text: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: RD.Space.md) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(RD.Palette.warning)
            Text(text).font(RD.Font.caption).foregroundStyle(RD.Palette.textPrimary.opacity(0.9))
            Spacer(minLength: 0)
            Button(actionTitle, action: action)
                .font(RD.Font.caption.weight(.bold))
                .foregroundStyle(RD.Palette.gemRim)
        }
        .padding(RD.Space.md)
        .rdCard(fill: RD.Palette.surface, border: false)
        .overlay(RoundedRectangle(cornerRadius: RD.Radius.card, style: .continuous).stroke(RD.Palette.warning.opacity(0.4)))
    }
}

/// 顶栏暗石榴微光氛围（克制收敛，不抢主锚点）。
struct RDAmbientTopGlow: View {
    var body: some View {
        RadialGradient(
            colors: [
                RD.Palette.gemDeep.opacity(0.24),
                RD.Palette.gemAbyss.opacity(0.08),
                .clear
            ],
            center: .topLeading,
            startRadius: 12,
            endRadius: 320
        )
        .frame(height: 260)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

/// 滚动吸顶磨砂栏背景（与 HomeView 一致，随滚动平滑浮现）。
struct RDStickyTopBarBackground: View {
    let scrolled: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.black.opacity(scrolled ? 0.92 : 0.65), .black.opacity(scrolled ? 0.78 : 0)],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(RD.Palette.background.opacity(scrolled ? 0.72 : 0))
                .background(scrolled ? AnyShapeStyle(.ultraThinMaterial.opacity(0.65)) : AnyShapeStyle(.clear))
            if scrolled {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [RD.Palette.gemBorderSoft, RD.Palette.hairline],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 0.6)
            }
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .allowsHitTesting(false)
    }
}

/// 成套宝石风空状态卡片。
struct RDEmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: RD.Space.md) {
            ZStack {
                Circle()
                    .fill(RD.Palette.surfaceRaised)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle().strokeBorder(RD.Gem.anchorBorderGradient, lineWidth: 0.9)
                    )
                    .shadow(color: RD.Palette.gemCore.opacity(0.24), radius: 7, y: 2)
                Image(systemName: systemImage)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, RD.Palette.gemRim],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            Text(title)
                .font(RD.Font.title)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(RD.Font.body)
                .foregroundStyle(RD.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(RDGemPillButtonStyle(horizontalPadding: 22, verticalPadding: 10))
                    .padding(.top, RD.Space.xs)
            }
        }
        .padding(.vertical, RD.Space.xl)
        .padding(.horizontal, RD.Space.lg)
        .frame(maxWidth: .infinity)
        .rdGemCard(radius: RD.Radius.sheet, fill: RD.Palette.surface.opacity(0.84))
    }
}

// MARK: - 宝石风骨架屏 Shimmer

struct RDShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.8

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let w = max(geo.size.width, 60)
                    LinearGradient(
                        colors: [
                            .clear,
                            RD.Palette.gemDeep.opacity(0.10),
                            Color.white.opacity(0.12),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: w * 1.2)
                    .offset(x: phase * w * 1.6)
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

struct RDSkeletonBox: View {
    var cornerRadius: CGFloat = RD.Radius.poster
    var fill: Color = RD.Palette.surface
    var gemBorder: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(fill)
            .modifier(RDShimmerModifier())
            .overlay {
                if gemBorder {
                    shape.strokeBorder(RD.Palette.gemBorderSoft, lineWidth: 0.7)
                }
            }
    }
}

struct RDHomeSkeletonView: View {
    let width: CGFloat
    let wide: Bool
    let leadingPad: CGFloat
    let trailingPad: CGFloat

    var body: some View {
        let cardWidth = max(1, width - leadingPad - trailingPad)
        let heroH: CGFloat = wide
            ? min(max(cardWidth * 0.48, 320), 430)
            : min(max(cardWidth * 1.05, 360), 420)
        VStack(alignment: .leading, spacing: RD.Space.xl) {
            ZStack(alignment: .bottomLeading) {
                RDSkeletonBox(cornerRadius: wide ? 18 : RD.Radius.sheet, fill: RD.Palette.surface)
                    .frame(width: cardWidth, height: heroH)
                RDHeroScrim(wide: wide)
                    .frame(width: cardWidth, height: heroH)
                    .clipShape(RoundedRectangle(cornerRadius: wide ? 18 : RD.Radius.sheet, style: .continuous))
                VStack(alignment: .leading, spacing: RD.Space.sm) {
                    RDSkeletonBox(cornerRadius: 6, fill: RD.Palette.surfaceRaised, gemBorder: true)
                        .frame(width: 84, height: 18)
                    RDSkeletonBox(cornerRadius: 8, fill: RD.Palette.surfaceRaised)
                        .frame(width: min(cardWidth * (wide ? 0.42 : 0.72), 300), height: 30)
                    RDSkeletonBox(cornerRadius: 6, fill: RD.Palette.surfaceRaised)
                        .frame(width: min(cardWidth * (wide ? 0.44 : 0.62), 260), height: 14)
                    HStack(spacing: RD.Space.md) {
                        RDSkeletonBox(cornerRadius: 999, fill: RD.Palette.gemDeep.opacity(0.55), gemBorder: true)
                            .frame(width: 118, height: 40)
                        RDSkeletonBox(cornerRadius: 999, fill: RD.Palette.surfaceRaised)
                            .frame(width: 96, height: 40)
                    }
                }
                .padding(.horizontal, wide ? 24 : RD.Space.md)
                .padding(.bottom, wide ? 22 : RD.Space.md)
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)

            ForEach(0..<2, id: \.self) { row in
                VStack(alignment: .leading, spacing: RD.Space.sm) {
                    RDSkeletonBox(cornerRadius: 6, fill: RD.Palette.surfaceRaised)
                        .frame(width: 140, height: 20)
                        .padding(.leading, leadingPad)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RD.Space.md) {
                            ForEach(0..<(wide ? 6 : 4), id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 6) {
                                    RDSkeletonBox(cornerRadius: RD.Radius.poster, fill: RD.Palette.surface, gemBorder: true)
                                        .frame(width: row == 0 ? 128 : 116, height: row == 0 ? 192 : 174)
                                    RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surfaceRaised)
                                        .frame(width: 92, height: 12)
                                }
                            }
                        }
                        .padding(.leading, leadingPad)
                        .padding(.trailing, trailingPad)
                    }
                    .disabled(true)
                }
            }
        }
    }
}

struct RDDetailSkeletonView: View {
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: RD.Space.md) {
            HStack(spacing: RD.Space.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    RDSkeletonBox(cornerRadius: 16, fill: RD.Palette.surfaceRaised, gemBorder: true)
                        .frame(width: 70, height: 28)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: RD.Space.sm), count: columns), spacing: RD.Space.sm) {
                ForEach(0..<18, id: \.self) { _ in
                    RDSkeletonBox(cornerRadius: RD.Radius.control, fill: RD.Palette.surfaceRaised)
                        .frame(height: 44)
                }
            }
        }
    }
}

struct RDSearchSkeletonView: View {
    let contentWidth: CGFloat

    var body: some View {
        LazyVGrid(columns: RD.gridColumns(contentWidth: contentWidth, minCardWidth: 112, spacing: RD.Space.md), spacing: RD.Space.lg) {
            ForEach(0..<9, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    Color.clear
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .overlay { RDSkeletonBox(cornerRadius: RD.Radius.poster, fill: RD.Palette.surface, gemBorder: true) }
                    RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surfaceRaised)
                        .frame(height: 14)
                    RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surface)
                        .frame(width: 72, height: 11)
                }
            }
        }
    }
}

struct RDHistorySkeletonView: View {
    let wide: Bool

    var body: some View {
        let count = wide ? 6 : 4
        let cols = Array(repeating: GridItem(.flexible(), spacing: RD.Space.md), count: wide ? 2 : 1)
        VStack(alignment: .leading, spacing: RD.Space.lg) {
            // 精选卡骨架
            HStack(spacing: RD.Space.md) {
                RDSkeletonBox(cornerRadius: RD.Radius.poster, fill: RD.Palette.surfaceRaised, gemBorder: true)
                    .frame(width: 84, height: 124)
                VStack(alignment: .leading, spacing: 10) {
                    RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.gemDeep.opacity(0.45), gemBorder: true)
                        .frame(width: 68, height: 18)
                    RDSkeletonBox(cornerRadius: 6, fill: RD.Palette.surfaceRaised)
                        .frame(height: 20)
                    RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surfaceRaised)
                        .frame(width: 150, height: 13)
                    RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surface)
                        .frame(height: 4)
                }
            }
            .padding(RD.Space.md)
            .rdGemCard(radius: RD.Radius.sheet, glow: true)

            LazyVGrid(columns: cols, spacing: RD.Space.md) {
                ForEach(0..<count, id: \.self) { _ in
                    HStack(spacing: RD.Space.md) {
                        RDSkeletonBox(cornerRadius: RD.Radius.poster, fill: RD.Palette.surfaceRaised, gemBorder: true)
                            .frame(width: 68, height: 98)
                        VStack(alignment: .leading, spacing: 8) {
                            RDSkeletonBox(cornerRadius: 5, fill: RD.Palette.surfaceRaised)
                                .frame(height: 16)
                            RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surfaceRaised)
                                .frame(width: 130, height: 12)
                            RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surface)
                                .frame(width: 80, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(RD.Space.md)
                    .rdGemCard()
                }
            }
        }
    }
}

struct RDProfileSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RD.Space.md) {
            RDSkeletonBox(cornerRadius: 5, fill: RD.Palette.surfaceRaised)
                .frame(width: 128, height: 20)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: RD.Space.md) {
                    RDSkeletonBox(cornerRadius: RD.Radius.poster, fill: RD.Palette.surfaceRaised, gemBorder: true)
                        .frame(width: 56, height: 82)
                    VStack(alignment: .leading, spacing: 8) {
                        RDSkeletonBox(cornerRadius: 5, fill: RD.Palette.surfaceRaised)
                            .frame(height: 15)
                        RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surfaceRaised)
                            .frame(width: 120, height: 12)
                        RDSkeletonBox(cornerRadius: 4, fill: RD.Palette.surface)
                            .frame(width: 72, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(RD.Space.md)
                .rdGemCard()
            }
        }
    }
}

// MARK: - 封面图

/// 封面图：走借自 DouDuo 的 ImageCache（同步内存命中，列表回收后重建不闪）。
struct RemoteCover: View {
    let url: String
    var thumbnailMaxPixel: Int? = 600

    var body: some View {
        CachedAsyncImage(url: URL(string: url), thumbnailMaxPixel: thumbnailMaxPixel) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RD.Palette.surface
            RDSkeletonBox(cornerRadius: 0, fill: RD.Palette.surface)
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.14))
        }
    }
}

/// Hero 智能图面组件：
/// - 优先使用横版封面字段（或自然横屏比例图片）铺满卡面；
/// - 竖版海报在宽屏卡片中绝不做毁灭性 aspect-fill 裁切，改用「同图高斯模糊铺满打底 ＋ 右侧完整竖海报清晰呈现」；
/// - 在小屏中按可用宽度完整呈现上部主体，上下柔和渐变过渡到背景色，底部剧名区彻底压暗错开。
struct RDHeroArtworkView: View {
    let coverURL: String
    let landscapeURL: String
    let wide: Bool
    let width: CGFloat
    let artworkHeight: CGFloat

    private var preferredURL: URL? {
        if !landscapeURL.isEmpty, let u = URL(string: landscapeURL) {
            return u
        }
        return URL(string: coverURL)
    }

    var body: some View {
        CachedRawImage(url: preferredURL) { img in
            let isNaturalLandscape = !landscapeURL.isEmpty || img.size.width > img.size.height * 1.15
            if wide {
                wideArtwork(img: img, isLandscape: isNaturalLandscape)
            } else {
                compactArtwork(img: img, isLandscape: isNaturalLandscape)
            }
        } placeholder: {
            ZStack {
                RD.Palette.surface
                RDSkeletonBox(cornerRadius: 0, fill: RD.Palette.surface)
            }
            .frame(width: width, height: artworkHeight)
        }
    }

    @ViewBuilder
    private func wideArtwork(img: UIImage, isLandscape: Bool) -> some View {
        if isLandscape {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: artworkHeight)
                .clipped()
        } else {
            ZStack(alignment: .trailing) {
                // 1. 同图高斯模糊铺满卡片打底
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: artworkHeight)
                    .scaleEffect(1.18)
                    .blur(radius: 36)
                    .overlay(Color.black.opacity(0.42))
                    .clipped()

                // 2. 完整竖海报靠右清晰呈现（零裁切）
                let maxPosterH = max(120, artworkHeight - 28)
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: width * 0.45, maxHeight: maxPosterH)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: .black.opacity(0.65), radius: 16, x: -4, y: 6)
                    .padding(.trailing, 20)
                    .padding(.vertical, 14)
            }
            .frame(width: width, height: artworkHeight)
        }
    }

    @ViewBuilder
    private func compactArtwork(img: UIImage, isLandscape: Bool) -> some View {
        if isLandscape {
            ZStack {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: artworkHeight)
                    .scaleEffect(1.16)
                    .blur(radius: 28)
                    .overlay(Color.black.opacity(0.45))
                    .clipped()

                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white, location: 0.12),
                                .init(color: .white, location: 0.80),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: width, height: artworkHeight)
        } else {
            // 竖版海报按宽度完整显示（不裁左右），上部主角清晰，底部自带标题区渐隐至背景色
            ZStack(alignment: .top) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: artworkHeight)
                    .scaleEffect(1.14)
                    .blur(radius: 26)
                    .overlay(Color.black.opacity(0.50))
                    .clipped()

                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, alignment: .top)
                    .frame(width: width, height: artworkHeight, alignment: .top)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white, location: 0.07),
                                .init(color: .white, location: 0.62),
                                .init(color: .white.opacity(0.28), location: 0.84),
                                .init(color: .clear, location: 0.99)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: width, height: artworkHeight)
        }
    }
}
