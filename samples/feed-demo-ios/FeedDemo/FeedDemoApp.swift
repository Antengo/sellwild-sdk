import SwiftUI
import SellwildSDK

@main
struct FeedDemoApp: App {
    @StateObject private var loader = ConfigLoader()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 10/255, green: 31/255, blue: 61/255).ignoresSafeArea()
                if let cfg = loader.config {
                    SellwildFeed(
                        config: cfg,
                        onListingTap: { listing in
                            print("[FeedDemo] Listing tapped: \(listing.title) → \(listing.url ?? "(no url)")")
                            return false
                        },
                        onAdImpression: { z in print("[FeedDemo] Ad impression zone=\(z)") },
                        onAdClicked:   { z in print("[FeedDemo] Ad click zone=\(z)") },
                        onLoad:        { print("[FeedDemo] Feed loaded") },
                        onError:       { msg in print("[FeedDemo] Feed error: \(msg)") }
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .task { await loader.boot() }
        }
    }
}

@MainActor
final class ConfigLoader: ObservableObject {
    @Published var config: SellwildConfig?

    func boot() async {
        let cfg = await SellwildSDK.configure(
            partnerCode: "weatherbug",
            slug: "weatherbug-weatherbug"
        ) { cfg in
            // Demo overrides: WeatherBug's CDN doesn't yet publish COL1 /
            // PARTNER_URL / zone IDs. Inject them locally so we can see the
            // spec on screen today. Remove once the CMS ships these keys.
            cfg.col1 = "BLGLGLGLGLG"
            cfg.partnerUrl = "https://www.weatherbug.com"
            if cfg.title == nil { cfg.title = "Marketplace" }
            // Seed mobile zone IDs so the COL1 `G` tokens render a
            // SellwildAdView. With no GAM tag the ad view falls back to
            // Google's public 300x250 test ad unit (same behavior the
            // Android demo uses to prove the native auction path).
            if cfg.mobileZids.isEmpty {
                cfg.mobileZids = ["demo-mrec-1", "demo-mrec-2", "demo-mrec-3"]
            }
            if (cfg.mobileBannerZid ?? "").isEmpty {
                cfg.mobileBannerZid = "demo-banner"
            }
            if (cfg.appBundleId ?? "").isEmpty {
                cfg.appBundleId = "com.sellwild.feeddemo"
            }
            if (cfg.appStoreUrl ?? "").isEmpty {
                cfg.appStoreUrl = "https://apps.apple.com/us/app/sellwild/id0000000000"
            }
            cfg.debug = true
        }
        print("[FeedDemo] Config ready: partner=\(cfg.partnerCode) col1=\(cfg.col1 ?? "") listingsUrl=\(cfg.effectiveListingsUrl)")
        self.config = cfg
    }
}
