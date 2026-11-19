import SwiftUI
import UIKit

extension Notification.Name {
    static let rdScrollToTop = Notification.Name("redduoduo.scrollToTop")
}

@main
struct RedDuoDuoApp: App {
    @StateObject private var history = WatchHistory.shared
    @StateObject private var auth = AuthStore.shared
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system

    init() {
        AppLog.write("APP launch RedDuoDuo \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-") bundle=\(Bundle.main.bundleIdentifier ?? "-")")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(history)
                .environmentObject(auth)
                // 1.4.7 三档外观：system 传 nil 完全跟随系统，light/dark 全 App 立即生效。
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}

/// 1.4.8 悬浮导航丸：替换实体 TabBar，五项常驻、状态保留（ZStack 叠放不销毁页面）。
struct RootTabView: View {
    @State private var selection = 0
    @ObservedObject private var chrome = RDAlbumChrome.shared
    @Environment(\.colorScheme) private var colorScheme

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selection },
            set: { next in
                if next == selection {
                    RDHaptics.shared.playTabSwitch(sameTabTop: true)
                    NotificationCenter.default.post(name: .rdScrollToTop, object: next)
                } else {
                    RDHaptics.shared.playTabSwitch(sameTabTop: false)
                    withAnimation(RDAlbum.Motion.rearrange) { selection = next }
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RDAlbum.C.base.ignoresSafeArea()

            ZStack {
                HomeView(onOpenGoldenHooks: {
                    tabSelection.wrappedValue = 1
                })
                .opacity(selection == 0 ? 1 : 0)
                .allowsHitTesting(selection == 0)
                .accessibilityHidden(selection != 0)

                GoldenHookFeedView(isActive: selection == 1)
                    .opacity(selection == 1 ? 1 : 0)
                    .allowsHitTesting(selection == 1)
                    .accessibilityHidden(selection != 1)

                SearchView()
                    .opacity(selection == 2 ? 1 : 0)
                    .allowsHitTesting(selection == 2)
                    .accessibilityHidden(selection != 2)

                HistoryView()
                    .opacity(selection == 3 ? 1 : 0)
                    .allowsHitTesting(selection == 3)
                    .accessibilityHidden(selection != 3)

                ProfileView()
                    .opacity(selection == 4 ? 1 : 0)
                    .allowsHitTesting(selection == 4)
                    .accessibilityHidden(selection != 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !chrome.hidesBrowseChrome {
                RDAlbumFloatingNav(selection: selectionBinding) { idx in
                    tabSelection.wrappedValue = idx
                }
                // 试看流是恒深色媒体舞台，悬浮丸随舞台取深色玻璃。
                .environment(\.colorScheme, selection == 1 ? .dark : colorScheme)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: selection) { _, newValue in
            if newValue != 2 {
                chrome.setBrowseChromeHidden(false, reason: "searchTyping")
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
        }
        .background {
            GeometryReader { geo in
                let wide = RD.isWide(geo.size.width)
                Color.clear
                    .onAppear { RDHaptics.shared.playWideTransition(toWide: wide) }
                    .onChange(of: wide) { _, newWide in
                        RDHaptics.shared.playWideTransition(toWide: newWide)
                    }
            }
            .allowsHitTesting(false)
        }
        .animation(RDAlbum.Motion.rearrange, value: selection)
        .animation(RDAlbum.Motion.rearrange, value: chrome.hidesBrowseChrome)
    }

    private var selectionBinding: Binding<Int> {
        Binding(
            get: { selection },
            set: { next in
                guard next != selection else {
                    RDHaptics.shared.playTabSwitch(sameTabTop: true)
                    NotificationCenter.default.post(name: .rdScrollToTop, object: next)
                    return
                }
                RDHaptics.shared.playTabSwitch(sameTabTop: false)
                withAnimation(RDAlbum.Motion.rearrange) { selection = next }
            }
        )
    }
}
