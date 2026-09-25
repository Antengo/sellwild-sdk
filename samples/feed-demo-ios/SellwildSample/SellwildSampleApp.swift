import SwiftUI
import UIKit
import SellwildSDK

/// Sellwild Sample: native listings and native ads first. The WebView
/// widget is only on the Legacy tab.
@main
struct SellwildSampleApp: App {
    @StateObject private var model = SampleModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let config = model.config {
                    SampleTabs(config: config, configSource: model.configSource)
                        .ignoresSafeArea()
                } else {
                    ProgressView("Loading Sellwild config")
                }
            }
            .task { await model.boot() }
        }
    }
}

/// The five tabs, in a UITabBarController so each tab button carries its
/// accessibility identifier (the e2e flows tap them by id).
struct SampleTabs: UIViewControllerRepresentable {
    let config: SellwildConfig
    let configSource: ConfigSource

    func makeUIViewController(context: Context) -> UITabBarController {
        let tabs = UITabBarController()
        tabs.viewControllers = [
            tab(FeedScreen(config: config), title: "Feed", symbol: "rectangle.grid.1x2", id: SampleID.tabFeed),
            tab(AdsScreen(config: config), title: "Ads", symbol: "megaphone", id: SampleID.tabAds),
            tab(ListingsScreen(config: config), title: "Listings", symbol: "list.bullet", id: SampleID.tabListings),
            tab(DiagnosticsScreen(config: config, configSource: configSource),
                title: "Diagnostics", symbol: "stethoscope", id: SampleID.tabDiagnostics),
            tab(LegacyScreen(config: config), title: "Legacy", symbol: "globe", id: SampleID.tabLegacy)
        ]
        return tabs
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {}

    private func tab<Screen: View>(_ screen: Screen, title: String, symbol: String, id: String) -> UIViewController {
        let host = UIHostingController(rootView: screen)
        host.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
        host.tabBarItem.accessibilityIdentifier = id
        return host
    }
}

/// The title block at the top of each screen.
struct ScreenHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(detail).font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
