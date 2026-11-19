import SwiftUI

/// 1.4.7 外观三档手动开关（跟随系统 / 浅色 / 深色）。
/// 持久化键：`redduoduo.appearance.mode.v1`（UserDefaults / @AppStorage，String raw value，默认 system）。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "redduoduo.appearance.mode.v1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// 根部 `.preferredColorScheme` 入参；system 传 nil，完全跟随系统。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
