// Copyright (c) 2026 DouDuo contributors (https://github.com/81199000/DouDuo)
// License: MIT — see Licenses/DouDuo-MIT.txt.
// Derived from DouDuo's player gesture overlay approach.
// Modified for RedDuoDuo: dedicated UIKit gesture layer above the non-interactive
// RDPlayerSurface, below the floating controls.
import SwiftUI
import UIKit

/// 播放器专属 UIKit 手势层：
/// 挂在非交互式 `RDPlayerSurface`（`isUserInteractionEnabled = false`）之上、悬浮控件栏之下，
/// 彻底避免 VLC 内部 vout 子视图吞掉点击或控件隐藏后命中区域失效。
///
/// 共存与优先级纪律：
/// - `Pinch`（双指捏合）最高优先：触发瞬间临时屏蔽单指手势，收尾恢复。
/// - `Pan`（单指上下滑跟手切集，1.4 新增）：仅在 `allowVerticalSwipe` 为 true 时生效（设置开、非控件可见、非抽屉开启、非加载/错误态）；触发期间屏蔽点按/长按。
/// - `LongPress`（按住 ≥ 0.35s）优先于 `SingleTap`：`single.require(toFail: long)` + 抬手冷却窗，松手绝不误唤/误收控件。
/// - `DoubleTap` 优先于 `SingleTap`：`single.require(toFail: double)`，双击绝不先闪出控制栏。
/// - 加载中 / 错误态（`allowPlaybackGestures == false`）时在 `shouldReceive` 直接拒绝双击/长按/竖滑，使单击零延迟立即唤出顶栏以供返回退出。
struct RDPlayerGestureOverlay: UIViewRepresentable {
    var allowPlaybackGestures: Bool
    var allowVerticalSwipe: Bool = true
    var onSingleTap: () -> Void
    var onDoubleTap: () -> Void
    var onLongPress: (Bool) -> Void
    var onPinchBegan: () -> Void = {}
    var onPinchChanged: (CGFloat) -> Void
    var onPinchEnded: (CGFloat) -> Void
    var onPinchCancelled: () -> Void
    var onVerticalPanChanged: (_ translationY: CGFloat, _ velocityY: CGFloat) -> Void = { _, _ in }
    var onVerticalPanEnded: (_ translationY: CGFloat, _ velocityY: CGFloat) -> Void = { _, _ in }
    var onVerticalPanCancelled: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = true
        host.isMultipleTouchEnabled = true
        host.accessibilityElementsHidden = true

        let c = context.coordinator
        c.view = host

        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleSingle(_:)))
        single.numberOfTapsRequired = 1
        single.numberOfTouchesRequired = 1
        single.delegate = c
        c.single = single

        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleDouble(_:)))
        double.numberOfTapsRequired = 2
        double.numberOfTouchesRequired = 1
        double.delegate = c
        c.double = double

        let long = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.handleLong(_:)))
        long.minimumPressDuration = 0.35
        long.allowableMovement = 16
        long.numberOfTouchesRequired = 1
        long.delegate = c
        c.long = long

        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = c
        c.pan = pan

        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = c
        c.pinch = pinch

        // 消歧依赖：单击必须等待双击与长按均判定失败后才触发
        single.require(toFail: double)
        single.require(toFail: long)

        host.addGestureRecognizer(pinch)
        host.addGestureRecognizer(pan)
        host.addGestureRecognizer(long)
        host.addGestureRecognizer(double)
        host.addGestureRecognizer(single)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 仅刷新闭包与开关状态，绝不重建视图或重置进行中的长按/捏合/拖拽状态
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RDPlayerGestureOverlay
        weak var view: UIView?
        weak var single: UITapGestureRecognizer?
        weak var double: UITapGestureRecognizer?
        weak var long: UILongPressGestureRecognizer?
        weak var pan: UIPanGestureRecognizer?
        weak var pinch: UIPinchGestureRecognizer?

        private var longActive = false
        private var panActive = false
        private var lastLongEnd = Date.distantPast

        init(_ parent: RDPlayerGestureOverlay) {
            self.parent = parent
        }

        @objc func handleSingle(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            if longActive || panActive || Date().timeIntervalSince(lastLongEnd) < 0.40 { return }
            parent.onSingleTap()
        }

        @objc func handleDouble(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, parent.allowPlaybackGestures else { return }
            if longActive || panActive || Date().timeIntervalSince(lastLongEnd) < 0.40 { return }
            parent.onDoubleTap()
        }

        @objc func handleLong(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                guard parent.allowPlaybackGestures, !panActive else { return }
                longActive = true
                // 识别成功后放开位移限制，避免按住倍速时手指轻微漂移中断加速
                g.allowableMovement = .greatestFiniteMagnitude
                parent.onLongPress(true)
            case .ended, .cancelled, .failed:
                g.allowableMovement = 16
                if longActive {
                    longActive = false
                    lastLongEnd = Date()
                    parent.onLongPress(false)
                }
            default:
                break
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let translation = g.translation(in: g.view)
            let velocity = g.velocity(in: g.view)
            switch g.state {
            case .began:
                guard parent.allowPlaybackGestures, parent.allowVerticalSwipe, !longActive else {
                    g.isEnabled = false
                    g.isEnabled = true
                    return
                }
                panActive = true
                single?.isEnabled = false
                double?.isEnabled = false
                long?.isEnabled = false
                parent.onVerticalPanChanged(translation.y, velocity.y)
            case .changed:
                guard panActive else { return }
                parent.onVerticalPanChanged(translation.y, velocity.y)
            case .ended:
                guard panActive else { return }
                panActive = false
                restoreAfterPan()
                parent.onVerticalPanEnded(translation.y, velocity.y)
            case .cancelled, .failed:
                let wasActive = panActive
                panActive = false
                restoreAfterPan()
                if wasActive {
                    parent.onVerticalPanCancelled()
                }
            default:
                break
            }
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                // 第二根手指落入捏合时立即抑制单指手势，若正在长按倍速或上下滑则安全恢复
                single?.isEnabled = false
                double?.isEnabled = false
                long?.isEnabled = false
                pan?.isEnabled = false
                parent.onPinchBegan()
                if longActive {
                    longActive = false
                    lastLongEnd = Date()
                    parent.onLongPress(false)
                }
                if panActive {
                    panActive = false
                    parent.onVerticalPanCancelled()
                }
                parent.onPinchChanged(g.scale)
            case .changed:
                parent.onPinchChanged(g.scale)
            case .ended:
                parent.onPinchEnded(g.scale)
                restoreSingleFingerRecognizers()
            case .cancelled, .failed:
                parent.onPinchCancelled()
                restoreSingleFingerRecognizers()
            default:
                break
            }
        }

        private func restoreAfterPan() {
            single?.isEnabled = true
            double?.isEnabled = true
            long?.isEnabled = true
        }

        private func restoreSingleFingerRecognizers() {
            single?.isEnabled = true
            double?.isEnabled = true
            long?.isEnabled = true
            pan?.isEnabled = true
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if g === double || g === long {
                return parent.allowPlaybackGestures
            }
            if g === pan {
                return parent.allowPlaybackGestures && parent.allowVerticalSwipe
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if g === pinch { return true }
            if let pinch, pinch.state == .began || pinch.state == .changed {
                return false
            }
            if g.numberOfTouches > 1 {
                return false
            }
            if g === pan {
                guard parent.allowPlaybackGestures, parent.allowVerticalSwipe, !longActive else { return false }
                let vel = (g as? UIPanGestureRecognizer)?.velocity(in: g.view) ?? .zero
                return abs(vel.y) > abs(vel.x) * 1.15 && abs(vel.y) > 8
            }
            if panActive { return false }
            if g === double || g === long {
                guard parent.allowPlaybackGestures else { return false }
            }
            if g === double {
                if let long, long.state == .began || long.state == .changed {
                    return false
                }
            }
            if g === single {
                if longActive || Date().timeIntervalSince(lastLongEnd) < 0.40 {
                    return false
                }
            }
            return true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // 同层播放器手势严格互斥；不阻断系统级边缘手势（Home 条 / 控制中心）
            return other.view !== g.view
        }
    }
}
