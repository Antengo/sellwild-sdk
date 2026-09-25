import Foundation
import SellwildSDK

/// What the sample passes to the SDK. It is the same on every platform's
/// sample app, so the e2e flows see the same app.
enum SampleSettings {
    /// Sellwild's own partner code. Never use a real partner's code here.
    static let partnerCode = "sellwild"
    /// There is no app config for this slug on the CDN (it answers 403). So
    /// `configure` keeps the SDK's built-in config and Google test ad units,
    /// and reports `config.fetch.http` once a launch. That is expected.
    static let slug = "sellwild-sample"
    /// Sellwild's own listings feed, passed with the public `listingsUrl`.
    static let listingsUrl = "https://cache.sellwild.com/listings-img-data-sm-avif-fandom"
    /// Feed rows: L = listing card, G = 300x250 ad, B = 320x50 banner.
    static let feedSchedule = "LGLLBLLGLL"
    static let mrecZone = "sellwild-sample-mrec"
    static let bannerZone = "sellwild-sample-banner"
    static let nativeZone = "sellwild-sample-native"
}

/// Where the config came from: the CDN, or the SDK's built-in fallback.
enum ConfigSource: String {
    case remote
    case fallback
}

/// Runs `SellwildSDK.configure` once at launch and holds the result.
@MainActor
final class SampleModel: ObservableObject {
    @Published private(set) var config: SellwildConfig?

    var configSource: ConfigSource {
        config?.remoteJSON == nil ? .fallback : .remote
    }

    func boot() async {
        guard config == nil else { return }
        let bundleId = Bundle.main.bundleIdentifier
        config = await SellwildSDK.configure(
            partnerCode: SampleSettings.partnerCode,
            slug: SampleSettings.slug
        ) { config in
            // App-controlled values. CDN values win where the CDN has them.
            config.listingsUrl = SampleSettings.listingsUrl
            config.appBundleId = bundleId
            config.debug = true
            if (config.col1 ?? "").isEmpty { config.col1 = SampleSettings.feedSchedule }
            if config.title == nil { config.title = "Sellwild Sample" }
            if config.mobileZids.isEmpty { config.mobileZids = [SampleSettings.mrecZone] }
            if (config.mobileBannerZid ?? "").isEmpty { config.mobileBannerZid = SampleSettings.bannerZone }
        }
    }
}
