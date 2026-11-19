// Copyright (c) 2026 DouDuo contributors (https://github.com/81199000/DouDuo)
// License: MIT — see Licenses/DouDuo-MIT.txt.
// Derived from DouDuo's foldable-layout handling.
// Modified for RedDuoDuo: iPhone Duo half-fold geometry engine using iOS 27.1
// reservedRegions.
import SwiftUI
import UIKit

/// A2：iPhone Duo 半折「追剧台」几何引擎。
/// - iOS 27.1+ 读取 `GeometryProxy.reservedRegions(kind: .division)` 物理铰链折痕带，
///   在系统分屏/小窗以外的全屏占屏场景下自动切出严格避开折痕的两块窗格（上播剧/下控制台 或 左播剧/右控制台）。
/// - 同时支持用户在宽屏展开态手动开关「追剧台」分屏工作台。
enum DuoFoldLayout {
    struct SplitPanes: Equatable {
        let videoRect: CGRect
        let panelRect: CGRect
        let hingeRect: CGRect?
        let isBookPosture: Bool
        let isPhysicalFold: Bool
    }

    private struct DivisionBand {
        let isBook: Bool
        let frame: CGRect
    }

    static var canUsePhysicalFold: Bool {
        if #available(iOS 27.1, *) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.keyWindow != nil }) else { return false }
            let space = scene.effectiveGeometry.coordinateSpace
            let display = scene.screen.coordinateSpace
            let sRect = display.convert(space.bounds, from: space).standardized
            let dRect = display.bounds.standardized
            return abs(sRect.minX - dRect.minX) <= 1
                && abs(sRect.minY - dRect.minY) <= 1
                && abs(sRect.maxX - dRect.maxX) <= 1
                && abs(sRect.maxY - dRect.maxY) <= 1
        }
        return false
    }

    static func physicalFoldPanes(in geo: GeometryProxy) -> SplitPanes? {
        guard #available(iOS 27.1, *), canUsePhysicalFold else { return nil }
        let bounds = CGRect(origin: .zero, size: geo.size).standardized
        guard bounds.width > 120, bounds.height > 120 else { return nil }

        let active = geo.reservedRegions(kind: .division).filter { region in
            let f = region.frame.standardized
            return region.isActive && f.width.isFinite && f.height.isFinite && f.width > 0 && f.height > 0
        }
        guard active.count == 1 else { return nil }
        let clipped = active[0].frame.standardized.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }

        let band: DivisionBand?
        if clipped.width >= clipped.height * 2.0,
           clipped.width >= bounds.width * 0.65,
           clipped.height <= bounds.height * 0.25 {
            band = DivisionBand(isBook: false, frame: clipped)
        } else if clipped.height >= clipped.width * 2.0,
                  clipped.height >= bounds.height * 0.65,
                  clipped.width <= bounds.width * 0.25 {
            band = DivisionBand(isBook: true, frame: clipped)
        } else {
            band = nil
        }
        guard let band else { return nil }

        if band.isBook {
            let videoW = band.frame.minX - bounds.minX
            let panelW = bounds.maxX - band.frame.maxX
            guard videoW >= bounds.width * 0.25, panelW >= bounds.width * 0.25 else { return nil }
            let videoRect = CGRect(x: bounds.minX, y: bounds.minY, width: videoW, height: bounds.height)
            let panelRect = CGRect(x: band.frame.maxX, y: bounds.minY, width: panelW, height: bounds.height)
            return SplitPanes(videoRect: videoRect, panelRect: panelRect, hingeRect: band.frame, isBookPosture: true, isPhysicalFold: true)
        } else {
            let videoH = band.frame.minY - bounds.minY
            let panelH = bounds.maxY - band.frame.maxY
            guard videoH >= bounds.height * 0.25, panelH >= bounds.height * 0.25 else { return nil }
            let videoRect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: videoH)
            let panelRect = CGRect(x: bounds.minX, y: band.frame.maxY, width: bounds.width, height: panelH)
            return SplitPanes(videoRect: videoRect, panelRect: panelRect, hingeRect: band.frame, isBookPosture: false, isPhysicalFold: true)
        }
    }

    /// 计算半折「追剧台」布局：物理半折优先避折痕；否则在用户手动开启追剧台时按横竖宽屏划分双屏区域。
    static func resolvePanes(in geo: GeometryProxy, manualWorkbench: Bool) -> SplitPanes? {
        if let physical = physicalFoldPanes(in: geo) {
            return physical
        }
        guard manualWorkbench else { return nil }
        let size = geo.size
        guard size.width > 200, size.height > 200 else { return nil }

        if size.width >= size.height {
            // 横向宽屏：左 56% 播剧，右 44% 追剧台
            let splitX = floor(size.width * 0.56)
            let gap: CGFloat = 1
            let videoRect = CGRect(x: 0, y: 0, width: splitX, height: size.height)
            let panelRect = CGRect(x: splitX + gap, y: 0, width: max(1, size.width - splitX - gap), height: size.height)
            return SplitPanes(videoRect: videoRect, panelRect: panelRect, hingeRect: nil, isBookPosture: true, isPhysicalFold: false)
        } else {
            // 竖向折叠台：上 46% 播剧，下 54% 追剧台
            let splitY = floor(size.height * 0.46)
            let gap: CGFloat = 1
            let videoRect = CGRect(x: 0, y: 0, width: size.width, height: splitY)
            let panelRect = CGRect(x: 0, y: splitY + gap, width: size.width, height: max(1, size.height - splitY - gap))
            return SplitPanes(videoRect: videoRect, panelRect: panelRect, hingeRect: nil, isBookPosture: false, isPhysicalFold: false)
        }
    }
}
