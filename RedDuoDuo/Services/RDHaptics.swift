import AVFoundation
import CoreHaptics
import Foundation
import UIKit

/// 触感浓度三档（默认：标准影院）。
enum RDHapticDensity: String, CaseIterable, Codable, Identifiable {
    case high
    case standard
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "宝石高敏"
        case .standard: return "标准影院"
        case .off: return "沉浸静音"
        }
    }

    var subtitle: String {
        switch self {
        case .high: return "棱面更透亮，全场景强效触感反馈"
        case .standard: return "清晰可感，平衡宝石质感与久看舒适"
        case .off: return "关闭全部触觉震动，全静沉浸"
        }
    }

    var scale: Float {
        switch self {
        case .high: return 1.32
        case .standard: return 1.0
        case .off: return 0.0
        }
    }
}

/// 搜索结果触觉状态。
enum RDSearchHapticOutcome {
    case success
    case empty
    case error
}

/// 红果宝石震动语言（Ruby Haptics）引擎。
/// - 三材质声部：晶石轻碰（高 sharpness 15-35ms）、丝绒气垫（低 sharpness 阻尼尾音）、微棘齿（表冠刻度）。
/// - 正反异构：所有成对语义（暂停/继续、上/下切集、收藏/取消、展开/合拢等）采用反向包络与锐度方向。
/// - 影院安全：playsHapticsOnly = true 防压剧声；单信道抢占 + 45ms 黑场留白；连续拖动速度自适应节流；引擎自愈。
@MainActor
final class RDHaptics: ObservableObject {
    static let shared = RDHaptics()
    static let densityStorageKey = "redduoduo.haptics.density.v1"

    @Published var density: RDHapticDensity {
        didSet {
            UserDefaults.standard.set(density.rawValue, forKey: Self.densityStorageKey)
            if density == .off {
                stopDynamicField()
            } else {
                ensureEngineStarted()
            }
        }
    }

    private var engine: CHHapticEngine?
    private var engineNeedsStart = false
    private var dynamicPlayer: CHHapticAdvancedPatternPlayer?
    private var isDynamicFieldActive = false

    // 单信道抢占 & 45ms 黑场节流
    private var lastPrimaryTime: TimeInterval = 0
    private var transitionLockUntil: TimeInterval = 0
    private var lastDragTickTime: TimeInterval = 0
    private var lastDynamicUpdateTime: TimeInterval = 0
    private var lastWideTransitionTime: TimeInterval = 0
    private var lastWideValue: Bool?

    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private let softGen = UIImpactFeedbackGenerator(style: .soft)
    private let selectionGen = UISelectionFeedbackGenerator()
    private var observers: [NSObjectProtocol] = []

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.densityStorageKey),
           let saved = RDHapticDensity(rawValue: raw) {
            density = saved
        } else {
            density = .standard
        }
        setupObservers()
        if density != .off {
            buildAndStartEngine()
        }
        prepareLightweight()
    }

    // MARK: - 生命周期与引擎自愈

    private func setupObservers() {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willEnterForegroundNotification,
            UIApplication.didBecomeActiveNotification,
            AVAudioSession.interruptionNotification,
            AVAudioSession.mediaServicesWereResetNotification,
        ]
        for name in names {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor [weak self] in
                    self?.handleLifecycleHeal(note)
                }
            }
            observers.append(token)
        }
    }

    private func handleLifecycleHeal(_ note: Notification) {
        guard density != .off else { return }
        if note.name == AVAudioSession.interruptionNotification,
           let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
           let type = AVAudioSession.InterruptionType(rawValue: raw),
           type == .began {
            stopDynamicField()
            return
        }
        if note.name == AVAudioSession.mediaServicesWereResetNotification {
            engine = nil
            dynamicPlayer = nil
            isDynamicFieldActive = false
        }
        ensureEngineStarted()
        prepareLightweight()
    }

    func prepareLightweight() {
        guard density != .off else { return }
        rigidGen.prepare()
        softGen.prepare()
        selectionGen.prepare()
    }

    private func buildAndStartEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let created = try CHHapticEngine()
            // 只震动不建隐式音频通道，防止压低 VLCKit 剧集音量或产生爆音
            created.playsHapticsOnly = true
            created.isAutoShutdownEnabled = true
            created.stoppedHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.engineNeedsStart = true
                    self?.dynamicPlayer = nil
                    self?.isDynamicFieldActive = false
                }
            }
            created.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.engineNeedsStart = true
                    self?.dynamicPlayer = nil
                    self?.isDynamicFieldActive = false
                    self?.ensureEngineStarted()
                }
            }
            try created.start()
            engine = created
            engineNeedsStart = false
        } catch {
            engine = nil
        }
    }

    private func ensureEngineStarted() {
        guard density != .off, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if engine == nil {
            buildAndStartEngine()
            return
        }
        if engineNeedsStart {
            do {
                try engine?.start()
                engineNeedsStart = false
            } catch {
                buildAndStartEngine()
            }
        }
    }

    // MARK: - 底层声部与节奏原语

    private struct PulseSpec {
        let time: TimeInterval
        let intensity: Float
        let sharpness: Float
        let duration: TimeInterval // 0 表示 transient；> 0 表示 continuous
        let endIntensity: Float?
        let endSharpness: Float?

        static func transient(at time: TimeInterval = 0, intensity: Float, sharpness: Float) -> PulseSpec {
            PulseSpec(time: time, intensity: intensity, sharpness: sharpness, duration: 0, endIntensity: nil, endSharpness: nil)
        }

        static func continuous(
            at time: TimeInterval = 0,
            duration: TimeInterval,
            startIntensity: Float,
            endIntensity: Float,
            startSharpness: Float,
            endSharpness: Float
        ) -> PulseSpec {
            PulseSpec(
                time: time,
                intensity: startIntensity,
                sharpness: startSharpness,
                duration: duration,
                endIntensity: endIntensity,
                endSharpness: endSharpness
            )
        }
    }

    private func scaled(_ raw: Float) -> Float {
        min(max(raw * density.scale, 0), 1)
    }

    private func canFirePrimary(preemptPriority: Bool = false, ignoreTransitionLock: Bool = false) -> Bool {
        guard density != .off else { return false }
        let now = CACurrentMediaTime()
        if !ignoreTransitionLock && now < transitionLockUntil {
            return false
        }
        if !preemptPriority && now - lastPrimaryTime < 0.045 {
            return false
        }
        lastPrimaryTime = now
        return true
    }

    private func playSpecs(_ specs: [PulseSpec], fallbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = .rigid, fallbackIntensity: CGFloat = 0.35) {
        guard density != .off else { return }
        ensureEngineStarted()
        guard let engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            playFallbackImpact(style: fallbackStyle, intensity: fallbackIntensity)
            return
        }

        do {
            var events: [CHHapticEvent] = []
            var curves: [CHHapticParameterCurve] = []

            for spec in specs {
                let startInt = scaled(spec.intensity)
                let startSharp = min(max(spec.sharpness, 0.05), 0.99)
                if spec.duration <= 0 {
                    let e = CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: startInt),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: startSharp),
                        ],
                        relativeTime: spec.time
                    )
                    events.append(e)
                } else {
                    let endInt = spec.endIntensity.map { scaled($0) }
                    let peakInt = max(startInt, endInt ?? startInt, 0.01)
                    let e = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: peakInt),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: startSharp),
                        ],
                        relativeTime: spec.time,
                        duration: spec.duration
                    )
                    events.append(e)

                    if let endInt {
                        let startRatio = min(max(startInt / peakInt, 0.0), 1.0)
                        let endRatio = min(max(endInt / peakInt, 0.0), 1.0)
                        let curve = CHHapticParameterCurve(
                            parameterID: .hapticIntensityControl,
                            controlPoints: [
                                .init(relativeTime: 0.0, value: startRatio),
                                .init(relativeTime: spec.duration, value: endRatio),
                            ],
                            relativeTime: spec.time
                        )
                        curves.append(curve)
                    }
                    if let endS = spec.endSharpness {
                        let clampedEnd = min(max(endS, 0.05), 0.99)
                        let delta = min(max(clampedEnd - startSharp, -0.94), 0.94)
                        let curve = CHHapticParameterCurve(
                            parameterID: .hapticSharpnessControl,
                            controlPoints: [
                                .init(relativeTime: 0.0, value: 0.0),
                                .init(relativeTime: spec.duration, value: delta),
                            ],
                            relativeTime: spec.time
                        )
                        curves.append(curve)
                    }
                }
            }

            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            engineNeedsStart = true
            playFallbackImpact(style: fallbackStyle, intensity: fallbackIntensity)
        }
    }

    private func playFallbackImpact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        let level = min(max(intensity * CGFloat(density.scale), 0), 1)
        guard level > 0.01 else { return }
        switch style {
        case .soft:
            softGen.impactOccurred(intensity: level)
        default:
            rigidGen.impactOccurred(intensity: level)
        }
    }

    private func playLightRigid(intensity: Float, sharpness: Float = 0.80) {
        guard canFirePrimary() else { return }
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            playSpecs([.transient(intensity: intensity, sharpness: sharpness)], fallbackStyle: .rigid, fallbackIntensity: CGFloat(intensity))
        } else {
            playFallbackImpact(style: .rigid, intensity: CGFloat(intensity))
        }
    }

    private func playLightSoft(intensity: Float, sharpness: Float = 0.28) {
        guard canFirePrimary() else { return }
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            playSpecs([.transient(intensity: intensity, sharpness: sharpness)], fallbackStyle: .soft, fallbackIntensity: CGFloat(intensity))
        } else {
            playFallbackImpact(style: .soft, intensity: CGFloat(intensity))
        }
    }

    // MARK: - 动态连续跟手场（双指捏合 / 上下滑拖拽）

    func beginDynamicField(baseIntensity: Float = 0.80, baseSharpness: Float = 0.48) {
        guard density != .off, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        ensureEngineStarted()
        guard let engine else { return }
        stopDynamicField()
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: scaled(baseIntensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: min(max(baseSharpness, 0.1), 0.9)),
                ],
                relativeTime: 0,
                duration: 24
            )
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            dynamicPlayer = player
            isDynamicFieldActive = true
            lastDynamicUpdateTime = 0
        } catch {
            dynamicPlayer = nil
            isDynamicFieldActive = false
        }
    }

    func updateDynamicField(intensityControl: Float, sharpnessOffset: Float) {
        guard density != .off else { return }
        if !isDynamicFieldActive {
            beginDynamicField()
        }
        let now = CACurrentMediaTime()
        guard now - lastDynamicUpdateTime >= 0.038 else { return }
        lastDynamicUpdateTime = now
        guard let dynamicPlayer else { return }
        let clampedInt = min(max(intensityControl, 0.05), 1.0)
        let clampedSharp = min(max(sharpnessOffset, -0.45), 0.45)
        do {
            try dynamicPlayer.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: clampedInt, relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: clampedSharp, relativeTime: 0),
            ], atTime: CHHapticTimeImmediate)
        } catch {
            stopDynamicField()
        }
    }

    func stopDynamicField() {
        lastDynamicUpdateTime = 0
        guard isDynamicFieldActive || dynamicPlayer != nil else { return }
        try? dynamicPlayer?.stop(atTime: CHHapticTimeImmediate)
        dynamicPlayer = nil
        isDynamicFieldActive = false
    }

    // MARK: - 1. 签名震动：红果开映 · 宝石点亮

    /// 正片第一帧真正亮屏起播（controller.time > 0.5）瞬间：
    /// 0ms 60ms 暗幕低沉落定 → 75ms 锐度 0.92 深红宝石棱面脆响 → 120ms 锐度 0.98 亮红高光余韵。
    func playSignaturePremiere() {
        guard canFirePrimary(preemptPriority: true, ignoreTransitionLock: true) else { return }
        playSpecs([
            .continuous(at: 0.0, duration: 0.060, startIntensity: 0.56, endIntensity: 0.16, startSharpness: 0.24, endSharpness: 0.18),
            .transient(at: 0.075, intensity: 0.78, sharpness: 0.92),
            .transient(at: 0.120, intensity: 0.44, sharpness: 0.98),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.76)
    }

    // MARK: - 2. 播放页全手势微观生命周期

    /// 单击唤醒 vs 主动收起控件（不用于 4s 自动隐藏）。
    func playControlsToggle(visible: Bool) {
        guard canFirePrimary() else { return }
        if visible {
            // 薄冰轻掀：18ms 空气微泡浮起
            playSpecs([
                .continuous(at: 0.0, duration: 0.018, startIntensity: 0.34, endIntensity: 0.50, startSharpness: 0.24, endSharpness: 0.40),
            ], fallbackStyle: .soft, fallbackIntensity: 0.46)
        } else {
            // 轻纱落幕：比唤醒再轻 30% 的下沉微气音
            playSpecs([
                .continuous(at: 0.0, duration: 0.018, startIntensity: 0.34, endIntensity: 0.14, startSharpness: 0.30, endSharpness: 0.15),
            ], fallbackStyle: .soft, fallbackIntensity: 0.32)
        }
    }

    /// 双击暂停（红宝石落锁下行）vs 双击恢复播放（晶石点火轻弹上行）。
    func playDoubleTapToggle(nowPlaying: Bool) {
        guard canFirePrimary(preemptPriority: true) else { return }
        if nowPlaying {
            // 晶石点火轻弹：先微沉蓄气、再向前弹出清亮火花（由低向高上行）
            playSpecs([
                .transient(at: 0.0, intensity: 0.42, sharpness: 0.36),
                .transient(at: 0.038, intensity: 0.74, sharpness: 0.92),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.72)
        } else {
            // 红宝石落锁：先干脆冷冽高锐制动，紧接低沉收闸落定（由高向低双段下行）
            playSpecs([
                .transient(at: 0.0, intensity: 0.74, sharpness: 0.92),
                .transient(at: 0.036, intensity: 0.44, sharpness: 0.36),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.72)
        }
    }

    /// 长按 >= 0.35s 进入 2.0x：140ms 连续升频滑坡 + 亮脆卡扣点（按住持续期不震）。
    func playSpeedBoostEngage() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .continuous(at: 0.0, duration: 0.140, startIntensity: 0.32, endIntensity: 0.68, startSharpness: 0.32, endSharpness: 0.86),
            .transient(at: 0.142, intensity: 0.78, sharpness: 0.94),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.76)
    }

    /// 长按 2.0x 松手回落原速：80ms 快速降坡滑尾。
    func playSpeedBoostRelease() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .continuous(at: 0.0, duration: 0.080, startIntensity: 0.62, endIntensity: 0.12, startSharpness: 0.68, endSharpness: 0.22),
        ], fallbackStyle: .soft, fallbackIntensity: 0.54)
    }

    /// 长按中被第二指捏合打断：40ms 退档尾音，接管给捏合张力场。
    func playSpeedBoostInterruptedByPinch() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .continuous(at: 0.0, duration: 0.040, startIntensity: 0.48, endIntensity: 0.14, startSharpness: 0.56, endSharpness: 0.22),
        ], fallbackStyle: .soft, fallbackIntensity: 0.44)
    }

    /// 双指捏合实时跟手张力。
    func updatePinchDynamic(scale: CGFloat) {
        let delta = Float(min(abs(scale - 1.0) / 0.2, 1.0))
        let intensity = 0.38 + delta * 0.62
        let sharpOffset = scale >= 1.0 ? (delta * 0.38) : (-delta * 0.25)
        updateDynamicField(intensityControl: intensity, sharpnessOffset: sharpOffset)
    }

    /// 捏合跨过阈值（> 1.06 外扣脆齿 / < 0.94 内收聚拢嗒）。
    func playPinchThresholdCrossed(toFill: Bool) {
        guard canFirePrimary() else { return }
        if toFill {
            playSpecs([.transient(intensity: 0.64, sharpness: 0.90)], fallbackStyle: .rigid, fallbackIntensity: 0.62)
        } else {
            playSpecs([.transient(intensity: 0.60, sharpness: 0.74)], fallbackStyle: .rigid, fallbackIntensity: 0.58)
        }
    }

    /// 捏合提交切换（填充铺满 vs 全屏完整）。
    func playPinchCommit(fillScreen: Bool) {
        stopDynamicField()
        guard canFirePrimary(preemptPriority: true) else { return }
        if fillScreen {
            // 宝石贴墙闷响：厚实一震接极微弹性回弹
            playSpecs([
                .transient(at: 0.0, intensity: 0.76, sharpness: 0.28),
                .transient(at: 0.055, intensity: 0.34, sharpness: 0.38),
            ], fallbackStyle: .soft, fallbackIntensity: 0.74)
        } else {
            // 画框悬停退让：中高锐度轻量回缩敲击
            playSpecs([
                .transient(at: 0.0, intensity: 0.58, sharpness: 0.72),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.56)
        }
    }

    /// 捏合死区（0.94~1.06）松手或取消：橡皮归位微叹。
    func playPinchDeadzoneCancel() {
        stopDynamicField()
        playLightSoft(intensity: 0.34, sharpness: 0.24)
    }

    /// 上下滑跟手拖拽实时阻尼场（带 38ms 速度自适应防嗡）。
    func updateSwipeDragField(progress: CGFloat, velocityY: CGFloat) {
        guard density != .off else { return }
        let clamped = Float(min(max(progress, 0), 1))
        let speedAtten: Float = abs(velocityY) > 950 ? 0.65 : 1.0
        updateDynamicField(intensityControl: (0.34 + clamped * 0.62) * speedAtten, sharpnessOffset: clamped * 0.26 - 0.10)
    }

    /// 上下滑拖拽越过 1/3 门槛瞬间：纸页折角微翘。
    func playSwipeThresholdCrossed() {
        guard canFirePrimary() else { return }
        playSpecs([.transient(intensity: 0.62, sharpness: 0.95)], fallbackStyle: .rigid, fallbackIntensity: 0.60)
    }

    /// 切集提交：下一集（上跃两连珠）vs 上一集（回溯双轻敲）。
    func playEpisodeSwitch(next: Bool) {
        stopDynamicField()
        guard canFirePrimary(preemptPriority: true, ignoreTransitionLock: true) else { return }
        // 切集过渡期间屏蔽低优先按钮震 220ms
        transitionLockUntil = CACurrentMediaTime() + 0.22
        if next {
            playSpecs([
                .transient(at: 0.0, intensity: 0.48, sharpness: 0.70),
                .transient(at: 0.045, intensity: 0.68, sharpness: 0.92),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.66)
        } else {
            playSpecs([
                .transient(at: 0.0, intensity: 0.66, sharpness: 0.78),
                .transient(at: 0.050, intensity: 0.44, sharpness: 0.50),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.62)
        }
    }

    /// 未过门槛松手弹回本集：卡片归槽低弹。
    func playSwipeBounceBack() {
        stopDynamicField()
        playLightSoft(intensity: 0.44, sharpness: 0.26)
    }

    /// 顶集继续下滑 / 末集继续上滑：硅胶撞墙硬阻尼。
    func playSwipeBoundaryWall() {
        stopDynamicField()
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .continuous(at: 0.0, duration: 0.055, startIntensity: 0.48, endIntensity: 0.80, startSharpness: 0.24, endSharpness: 0.16),
        ], fallbackStyle: .soft, fallbackIntensity: 0.76)
    }

    // MARK: - 3. 进度条微观刻度（按速度自适应降频）

    func playSliderGrab() {
        playLightRigid(intensity: 0.44, sharpness: 0.85)
    }

    func playSliderTick(velocity: Double) {
        guard density != .off else { return }
        let now = CACurrentMediaTime()
        // 速度越快间隔越宽、能量越低，防止嗡成一团
        let fast = velocity > 0.35
        let minGap: TimeInterval = fast ? 0.10 : 0.045
        guard now - lastDragTickTime >= minGap else { return }
        lastDragTickTime = now
        let energy: Float = fast ? 0.24 : 0.38
        let sharp: Float = fast ? 0.58 : 0.80
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            playSpecs([.transient(intensity: energy, sharpness: sharp)], fallbackStyle: .rigid, fallbackIntensity: CGFloat(energy))
        } else {
            selectionGen.selectionChanged()
        }
    }

    func playSliderAnchorSnap() {
        guard canFirePrimary() else { return }
        playSpecs([.transient(intensity: 0.68, sharpness: 0.82)], fallbackStyle: .rigid, fallbackIntensity: 0.66)
    }

    func playSliderBoundary() {
        guard canFirePrimary() else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.40, sharpness: 0.45),
            .transient(at: 0.045, intensity: 0.72, sharpness: 0.35),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.68)
    }

    func playSliderRelease() {
        playLightSoft(intensity: 0.52, sharpness: 0.34)
    }

    func playGlassTap(disabled: Bool = false) {
        if disabled {
            playLightSoft(intensity: 0.38, sharpness: 0.18)
        } else {
            playLightSoft(intensity: 0.48, sharpness: 0.46)
        }
    }

    // MARK: - 4. 起播、续播与异常态

    func playResumeBookmarkApplied() {
        guard canFirePrimary() else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.34, sharpness: 0.42),
            .transient(at: 0.045, intensity: 0.26, sharpness: 0.58),
        ], fallbackStyle: .soft, fallbackIntensity: 0.36)
    }

    func playPlaybackError() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.84, sharpness: 0.36),
            .transient(at: 0.070, intensity: 0.72, sharpness: 0.28),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.82)
    }

    func playRetryTap() {
        guard canFirePrimary() else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.44, sharpness: 0.72),
            .transient(at: 0.050, intensity: 0.72, sharpness: 0.86),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.70)
    }

    // MARK: - 5. 自动连播倒计时与离线缓存

    func playUpNextShown() {
        guard canFirePrimary() else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.44, sharpness: 0.32),
            .transient(at: 0.065, intensity: 0.58, sharpness: 0.52),
        ], fallbackStyle: .soft, fallbackIntensity: 0.54)
    }

    /// 倒计时最后 3 → 2 → 1 秒渐近胶片滴答（登录验证码倒数跳字禁止调用此方法）。
    func playUpNextCountdown(remaining: Int) {
        let intensity: Float
        let sharpness: Float
        switch remaining {
        case 3:
            intensity = 0.40
            sharpness = 0.65
        case 2:
            intensity = 0.58
            sharpness = 0.78
        case 1:
            intensity = 0.78
            sharpness = 0.90
        default:
            return
        }
        playLightRigid(intensity: intensity, sharpness: sharpness)
    }

    func playUpNextAutoAdvance() {
        guard canFirePrimary(preemptPriority: true) else { return }
        transitionLockUntil = CACurrentMediaTime() + 0.22
        playSpecs([
            .continuous(at: 0.0, duration: 0.100, startIntensity: 0.58, endIntensity: 0.20, startSharpness: 0.30, endSharpness: 0.18),
        ], fallbackStyle: .soft, fallbackIntensity: 0.54)
    }

    func playUpNextCancel() {
        playLightRigid(intensity: 0.52, sharpness: 0.58)
    }

    func playUpNextPlayNow() {
        playLightRigid(intensity: 0.68, sharpness: 0.86)
    }

    func playCacheSubmit(batch: Bool) {
        guard canFirePrimary(preemptPriority: true) else { return }
        if batch {
            playSpecs([
                .transient(at: 0.0, intensity: 0.42, sharpness: 0.82),
                .transient(at: 0.045, intensity: 0.56, sharpness: 0.88),
                .transient(at: 0.090, intensity: 0.72, sharpness: 0.94),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.70)
        } else {
            playSpecs([.transient(intensity: 0.58, sharpness: 0.88)], fallbackStyle: .rigid, fallbackIntensity: 0.56)
        }
    }

    func playCacheEpisodeDone() {
        playLightRigid(intensity: 0.46, sharpness: 0.90)
    }

    func playCacheSeriesDone() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.68, sharpness: 0.88),
            .transient(at: 0.060, intensity: 0.56, sharpness: 0.32),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.66)
    }

    func playCacheError() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.88, sharpness: 0.80),
            .transient(at: 0.055, intensity: 0.82, sharpness: 0.75),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.88)
    }

    // MARK: - 6. 首页、详情、搜索、历史、我的、登录与 Duo 形态跃迁

    func playGemButtonPressDown() {
        playLightRigid(intensity: 0.42, sharpness: 0.82)
    }

    func playGemButtonRelease() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([.transient(intensity: 0.74, sharpness: 0.86)], fallbackStyle: .rigid, fallbackIntensity: 0.72)
    }

    func playGlassHeroTap() {
        playLightRigid(intensity: 0.46, sharpness: 0.52)
    }

    func playResumeCardTap() {
        playLightRigid(intensity: 0.56, sharpness: 0.84)
    }

    func playTopRankSnap(velocity: Double) {
        guard density != .off else { return }
        // 甩滑静默，慢滑给清晰可控的微齿反馈
        guard abs(velocity) < 700 else { return }
        let now = CACurrentMediaTime()
        guard now - lastDragTickTime >= 0.060 else { return }
        lastDragTickTime = now
        playLightRigid(intensity: 0.30, sharpness: 0.76)
    }

    func playShelfEdgeBounce() {
        playLightSoft(intensity: 0.38, sharpness: 0.26)
    }

    func playStickyBarCrossed() {
        playLightSoft(intensity: 0.26, sharpness: 0.36)
    }

    func playPullRefreshTriggered() {
        playLightRigid(intensity: 0.58, sharpness: 0.82)
    }

    func playPullRefreshComplete() {
        playLightRigid(intensity: 0.64, sharpness: 0.88)
    }

    func playPaginationFetch() {
        playLightSoft(intensity: 0.30, sharpness: 0.28)
    }

    func playFeedEndReached() {
        playLightSoft(intensity: 0.44, sharpness: 0.42)
    }

    func playSessionExpiredNotice() {
        playLightSoft(intensity: 0.64, sharpness: 0.54)
    }

    func playCollectPreTap() {
        playLightRigid(intensity: 0.40, sharpness: 0.76)
    }

    func playCollectResult(collected: Bool) {
        guard canFirePrimary(preemptPriority: true) else { return }
        if collected {
            // 宝石镶嵌扣入：上扬两连亮震
            playSpecs([
                .transient(at: 0.0, intensity: 0.48, sharpness: 0.78),
                .transient(at: 0.045, intensity: 0.74, sharpness: 0.94),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.72)
        } else {
            // 轻拔退位：带空气感的下沉退位收尾
            playSpecs([
                .continuous(at: 0.0, duration: 0.045, startIntensity: 0.52, endIntensity: 0.18, startSharpness: 0.44, endSharpness: 0.18),
            ], fallbackStyle: .soft, fallbackIntensity: 0.48)
        }
    }

    func playCollectRollback() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.74, sharpness: 0.25),
            .transient(at: 0.060, intensity: 0.66, sharpness: 0.22),
        ], fallbackStyle: .soft, fallbackIntensity: 0.72)
    }

    func playRangeTabSwitch() {
        playLightRigid(intensity: 0.52, sharpness: 0.86)
    }

    func playEpisodeCellTap(watched: Bool) {
        if watched {
            playLightRigid(intensity: 0.60, sharpness: 0.60)
        } else {
            playLightRigid(intensity: 0.48, sharpness: 0.86)
        }
    }

    func playIntroToggle(expanded: Bool) {
        if expanded {
            playLightSoft(intensity: 0.44, sharpness: 0.46)
        } else {
            playLightSoft(intensity: 0.34, sharpness: 0.30)
        }
    }

    func playSquareGlassTap() {
        playLightRigid(intensity: 0.48, sharpness: 0.72)
    }

    func playTabSwitch(sameTabTop: Bool) {
        guard canFirePrimary() else { return }
        if sameTabTop {
            playSpecs([
                .transient(at: 0.0, intensity: 0.36, sharpness: 0.72),
                .transient(at: 0.048, intensity: 0.38, sharpness: 0.80),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.40)
        } else {
            playSpecs([.transient(intensity: 0.44, sharpness: 0.76)], fallbackStyle: .rigid, fallbackIntensity: 0.44)
        }
    }

    func playSearchFocus() {
        guard canFirePrimary() else { return }
        playSpecs([
            .continuous(at: 0.0, duration: 0.025, startIntensity: 0.38, endIntensity: 0.24, startSharpness: 0.66, endSharpness: 0.46),
        ], fallbackStyle: .soft, fallbackIntensity: 0.36)
    }

    func playSearchClear() {
        playLightRigid(intensity: 0.38, sharpness: 0.90)
    }

    func playChipSelect() {
        playLightRigid(intensity: 0.52, sharpness: 0.82)
    }

    func playSearchOutcome(_ outcome: RDSearchHapticOutcome) {
        guard canFirePrimary() else { return }
        switch outcome {
        case .success:
            playSpecs([.transient(intensity: 0.44, sharpness: 0.46)], fallbackStyle: .soft, fallbackIntensity: 0.44)
        case .empty:
            playSpecs([.transient(intensity: 0.44, sharpness: 0.20)], fallbackStyle: .soft, fallbackIntensity: 0.44)
        case .error:
            playSpecs([
                .transient(at: 0.0, intensity: 0.74, sharpness: 0.30),
                .transient(at: 0.065, intensity: 0.66, sharpness: 0.24),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.72)
        }
    }

    func playContextMenuPop() {
        playLightSoft(intensity: 0.60, sharpness: 0.44)
    }

    func playDeleteSingleItem() {
        playLightRigid(intensity: 0.58, sharpness: 0.82)
    }

    func playClearAllDestructive() {
        guard canFirePrimary(preemptPriority: true) else { return }
        // 碎冰倾倒三连衰减
        playSpecs([
            .transient(at: 0.0, intensity: 0.88, sharpness: 0.82),
            .transient(at: 0.055, intensity: 0.58, sharpness: 0.88),
            .transient(at: 0.100, intensity: 0.34, sharpness: 0.92),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.88)
    }

    func playLoginSheetOpen() {
        playLightSoft(intensity: 0.42, sharpness: 0.32)
    }

    func playSmsSent() {
        playLightRigid(intensity: 0.56, sharpness: 0.78)
    }

    func playMfaShieldAppear() {
        playLightSoft(intensity: 0.70, sharpness: 0.26)
    }

    func playCopyStamp() {
        playLightRigid(intensity: 0.58, sharpness: 0.88)
    }

    func playMfaResult(success: Bool) {
        guard canFirePrimary(preemptPriority: true) else { return }
        if success {
            // 三重递增宝石和弦
            playSpecs([
                .transient(at: 0.0, intensity: 0.46, sharpness: 0.75),
                .transient(at: 0.055, intensity: 0.66, sharpness: 0.85),
                .transient(at: 0.115, intensity: 0.84, sharpness: 0.94),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.82)
        } else {
            // 温和双短停
            playSpecs([
                .transient(at: 0.0, intensity: 0.54, sharpness: 0.30),
                .transient(at: 0.070, intensity: 0.46, sharpness: 0.26),
            ], fallbackStyle: .soft, fallbackIntensity: 0.52)
        }
    }

    func playLogoutConfirm() {
        playLightSoft(intensity: 0.64, sharpness: 0.30)
    }

    /// Duo 形态跃迁（跨过 RD.wideBreakpoint = 600）：带 350ms 防抖。
    func playWideTransition(toWide: Bool) {
        if lastWideValue == nil {
            lastWideValue = toWide
            return
        }
        guard lastWideValue != toWide else { return }
        let now = CACurrentMediaTime()
        guard now - lastWideTransitionTime >= 0.35 else { return }
        lastWideValue = toWide
        lastWideTransitionTime = now
        guard canFirePrimary(preemptPriority: true) else { return }

        if toWide {
            // 宝石折扇舒展：120ms 由高锐窄点渐化为宽阔饱满低频
            playSpecs([
                .continuous(at: 0.0, duration: 0.120, startIntensity: 0.46, endIntensity: 0.74, startSharpness: 0.85, endSharpness: 0.25),
            ], fallbackStyle: .soft, fallbackIntensity: 0.70)
        } else {
            // 折扇合拢咔嗒落锁：90ms 由宽沉收束到一枚干脆高锐小点
            playSpecs([
                .continuous(at: 0.0, duration: 0.090, startIntensity: 0.66, endIntensity: 0.40, startSharpness: 0.25, endSharpness: 0.88),
                .transient(at: 0.092, intensity: 0.62, sharpness: 0.94),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.64)
        }
    }

    // MARK: - 7. 1.4 追剧交互扩展触点（抽屉 / 倍速 / 跳过 / 随机挑剧 / 小窗与听剧）

    /// 屏内选集抽屉开合：开为丝绒上浮轻触，合为轻纱收回。
    func playDrawerToggle(open: Bool) {
        guard canFirePrimary() else { return }
        if open {
            playSpecs([
                .continuous(at: 0.0, duration: 0.026, startIntensity: 0.36, endIntensity: 0.56, startSharpness: 0.30, endSharpness: 0.55),
            ], fallbackStyle: .soft, fallbackIntensity: 0.52)
        } else {
            playSpecs([
                .continuous(at: 0.0, duration: 0.022, startIntensity: 0.44, endIntensity: 0.22, startSharpness: 0.44, endSharpness: 0.20),
            ], fallbackStyle: .soft, fallbackIntensity: 0.40)
        }
    }

    /// 切换并记住本剧倍速档位：表冠微棘齿 + 晶石确认。
    func playRateSelected() {
        playLightRigid(intensity: 0.52, sharpness: 0.86)
    }

    /// 一键跳过片头 / 片尾：干脆双短促跳转。
    func playSkipAction() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.46, sharpness: 0.78),
            .transient(at: 0.042, intensity: 0.62, sharpness: 0.92),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.60)
    }

    /// 「帮我挑一部」盲盒随机开剧：晶粒轻跃。
    func playSurprisePick() {
        guard canFirePrimary(preemptPriority: true) else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.44, sharpness: 0.74),
            .transient(at: 0.045, intensity: 0.58, sharpness: 0.84),
            .transient(at: 0.095, intensity: 0.74, sharpness: 0.94),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.72)
    }

    /// 画中画小窗开关：正反方向微异构。
    func playPiPToggle(active: Bool) {
        guard canFirePrimary() else { return }
        if active {
            playSpecs([
                .transient(at: 0.0, intensity: 0.54, sharpness: 0.84),
                .transient(at: 0.045, intensity: 0.36, sharpness: 0.56),
            ], fallbackStyle: .soft, fallbackIntensity: 0.50)
        } else {
            playSpecs([
                .transient(at: 0.0, intensity: 0.40, sharpness: 0.52),
                .transient(at: 0.045, intensity: 0.56, sharpness: 0.86),
            ], fallbackStyle: .rigid, fallbackIntensity: 0.52)
        }
    }

    /// 息屏听剧（音频模式）切换。
    func playAudioModeToggle(active: Bool) {
        guard canFirePrimary() else { return }
        if active {
            playSpecs([
                .continuous(at: 0.0, duration: 0.055, startIntensity: 0.52, endIntensity: 0.28, startSharpness: 0.40, endSharpness: 0.18),
            ], fallbackStyle: .soft, fallbackIntensity: 0.48)
        } else {
            playSpecs([
                .continuous(at: 0.0, duration: 0.045, startIntensity: 0.34, endIntensity: 0.58, startSharpness: 0.24, endSharpness: 0.68),
            ], fallbackStyle: .soft, fallbackIntensity: 0.52)
        }
    }

    /// 切换「触感浓度」档位时立即给出一颗预览轻碰（静音档静默）。
    func playDensitySample() {
        guard density != .off else { return }
        guard canFirePrimary(preemptPriority: true, ignoreTransitionLock: true) else { return }
        playSpecs([
            .transient(at: 0.0, intensity: 0.64, sharpness: 0.88),
            .transient(at: 0.055, intensity: 0.44, sharpness: 0.94),
        ], fallbackStyle: .rigid, fallbackIntensity: 0.62)
    }
}
