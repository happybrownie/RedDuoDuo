// Copyright (c) 2026 DouDuo contributors (https://github.com/81199000/DouDuo)
// License: MIT — see Licenses/DouDuo-MIT.txt.
// Adapted from DouDuo DYVideoFit.swift (fill/fit approach and interaction).
// Modified for RedDuoDuo: full-screen fill incl. Duo unfolded state, own
// preference key.
import CoreGraphics
import SwiftUI

/// 播放画面填充模式（做法与交互参考 DouDuo/DYVideoFit.swift）：
/// - 「填充」（默认）：视频按比例放大铺满整个屏幕（含 Duo 展开态整屏），允许裁掉溢出的边；竖屏剧与横屏剧均成立。
/// - 「全屏」（完整显示）：完整显示整幅画面（aspect fit），黑边留空。
enum RDVideoFit {
    static let preferenceKey = "redduoduo.player.fill_mode.v1"
    static let defaultFillScreen = true
    static let releasedScale: CGFloat = 1
    static let pinchFitBelow: CGFloat = 0.94
    static let pinchFillAbove: CGFloat = 1.06

    enum Mode: Equatable {
        case fill
        case fit

        var title: String {
            switch self {
            case .fill: return "填充"
            case .fit: return "全屏"
            }
        }

        var toastText: String {
            switch self {
            case .fill: return "填充 · 铺满屏幕"
            case .fit: return "全屏 · 完整显示"
            }
        }
    }

    static func mode(fillScreen: Bool) -> Mode {
        fillScreen ? .fill : .fit
    }

    /// 捏合收拢提交完整显示（全屏 aspect fit），捏开展开提交填充铺满。死区内返回 nil，不改偏好。
    static func pinchCommit(magnitude: CGFloat) -> Bool? {
        if magnitude < pinchFitBelow { return false }
        if magnitude > pinchFillAbove { return true }
        return nil
    }

    /// VLC 在 scaleFactor=0 下默认按等比 aspect fit 渲染（居中、有黑边）。
    /// 填充模式下把渲染层等比放大 max(screenAspect/videoAspect, videoAspect/screenAspect)，
    /// 使短边刚好铺满屏幕、溢出边对称裁切；竖屏剧、横屏剧与 Duo 展开态全部适用。
    static func vlcScale(fillScreen: Bool, videoAspect: Double, screenAspect: Double) -> CGFloat {
        guard fillScreen,
              videoAspect.isFinite, screenAspect.isFinite,
              videoAspect > 0.01, screenAspect > 0.01 else {
            return 1
        }
        return CGFloat(max(screenAspect / videoAspect, videoAspect / screenAspect))
    }
}

/// 填充/完整显示图标（借自 DouDuo/DouyinFeedView.swift `DYFitCornerGlyph`）：
/// 遵循 DouDuo「按点击后动作显示」约定：
/// - 当前填充中（`inward == true`）：向内角标，点击收回到完整画面
/// - 当前完整画面（`inward == false`）：向外角标，点击放大铺满屏幕
struct RDVideoFitGlyph: Shape {
    var inward: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let a = rect.width * 0.17
        let b = rect.width * 0.83
        let leg = rect.width * 0.29
        if inward {
            p.move(to: CGPoint(x: a, y: a + leg))
            p.addLine(to: CGPoint(x: a + leg, y: a + leg))
            p.addLine(to: CGPoint(x: a + leg, y: a))
            p.move(to: CGPoint(x: b, y: b - leg))
            p.addLine(to: CGPoint(x: b - leg, y: b - leg))
            p.addLine(to: CGPoint(x: b - leg, y: b))
        } else {
            p.move(to: CGPoint(x: a, y: a + leg))
            p.addLine(to: CGPoint(x: a, y: a))
            p.addLine(to: CGPoint(x: a + leg, y: a))
            p.move(to: CGPoint(x: b - leg, y: b))
            p.addLine(to: CGPoint(x: b, y: b))
            p.addLine(to: CGPoint(x: b, y: b - leg))
        }
        return p
    }
}
