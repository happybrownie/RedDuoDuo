import SwiftUI

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

struct RootTabView: View {
    @State private var selection = 0
    init() {
        // 自适应明暗半透明磨砂底栏、选中项品牌红
        let ap = UITabBarAppearance()
        ap.configureWithDefaultBackground()
        ap.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        ap.backgroundColor = RD.Palette.tabBarBackgroundUI
        ap.shadowColor = RD.Palette.hairlineUI
        UITabBar.appearance().standardAppearance = ap
        UITabBar.appearance().scrollEdgeAppearance = ap
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selection },
            set: { next in
                if next == selection {
                    RDHaptics.shared.playTabSwitch(sameTabTop: true)
                    NotificationCenter.default.post(name: .rdScrollToTop, object: next)
                } else {
                    RDHaptics.shared.playTabSwitch(sameTabTop: false)
                    selection = next
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            HomeView(onOpenGoldenHooks: {
                if selection != 1 {
                    RDHaptics.shared.playTabSwitch(sameTabTop: false)
                    selection = 1
                }
            })
            .tabItem { Label("首页", systemImage: "house.fill") }
            .tag(0)

            GoldenHookFeedView(isActive: selection == 1)
                .tabItem { Label("试看", systemImage: "flame.fill") }
                .tag(1)

            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(2)

            HistoryView()
                .tabItem { Label("观看", systemImage: "clock.arrow.circlepath") }
                .tag(3)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(4)
        }
        .tint(RD.Palette.accent)
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
        .background(RD.Palette.background.ignoresSafeArea())
    }
}
