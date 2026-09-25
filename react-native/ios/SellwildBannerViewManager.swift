import Foundation
import React
import SellwildSDK
import UIKit

/// Bridges the JS `<SellwildBanner>` component to the native
/// `SellwildAdView` (Prebid Mobile + AdManagerBannerView). Mirrors the
/// Android `SellwildBannerViewManager` shape.
///
/// Props (set from JS):
///   - config: object — the resolved SellwildConfig (from configure()).
///       Only the fields the native ad path reads are required.
///   - size: string — "320x50", "300x250", "728x90", "300x600", "160x600".
///   - zoneId: string — Sellwild zone tag, e.g. "43".
///
/// Events emitted to JS:
///   - onAdLoaded
///   - onAdImpression { zoneId }
///   - onAdClicked
///   - onAdFailed { message }
@objc(SellwildBannerViewManager)
public final class SellwildBannerViewManager: RCTViewManager {

    public override init() {
        super.init()
        SellwildRNWrapper.install()
    }

    public override static func requiresMainQueueSetup() -> Bool { true }

    public override func view() -> UIView! {
        return SellwildBannerHostView()
    }
}

/// The actual UIView that hosts a `SellwildAdView`. We can't construct
/// `SellwildAdView` until all three required props (config / size /
/// zoneId) have arrived, so we cache them and apply once on
/// `didSetProps:`.
final class SellwildBannerHostView: UIView, SellwildAdViewDelegate {

    // MARK: RN-set props

    @objc var config: NSDictionary? { didSet { needsApply = true } }
    @objc var size: NSString? { didSet { needsApply = true } }
    @objc var zoneId: NSString? { didSet { needsApply = true } }
    /// Resolved ad stack ('both' | 'gamOnly' | 'prebidOnly'), computed in JS.
    /// Applied as the native override so RN is driven deterministically by JS.
    @objc var adStack: NSString? { didSet { needsApply = true } }

    // MARK: RN events

    @objc var onAdLoaded: RCTDirectEventBlock?
    @objc var onAdImpression: RCTDirectEventBlock?
    /// A house ad backfilled an empty slot (no-fill). Not a paid impression.
    @objc var onHouseAdImpression: RCTDirectEventBlock?
    @objc var onAdClicked: RCTDirectEventBlock?
    @objc var onAdFailed: RCTDirectEventBlock?
    /// Emitted with the rendered creative size so JS can resize the slot.
    @objc var onAdResize: RCTDirectEventBlock?

    // MARK: Internals

    private var adView: SellwildAdView?
    private var lastAppliedKey: String?
    /// Last applied `config` map, compared by value (`isEqual:` ⇒
    /// `isEqualToDictionary:`, deep). NOT `NSDictionary.hash` — that is
    /// just the entry count, so a partnerCode / slug / geo / remote change
    /// with the same key count would be silently ignored.
    private var lastAppliedConfig: NSDictionary?
    private var needsApply: Bool = false
    /// The props problem last reported, so a re-render with the same bad
    /// props does not report it again.
    private var propsProblem = SellwildRNBridgeRules.ReportOnce()

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // RN calls didSetProps once per JS render after all @objc setters
    // have run, which lets us batch setup() + load() into a single
    // native call instead of firing one per prop change.
    override func didSetProps(_ changedProps: [String]) {
        guard needsApply else { return }
        needsApply = false
        applyIfReady()
    }

    private func applyIfReady() {
        let sizeLabel = size as String?
        let zoneLabel = zoneId as String?
        let problem = SellwildRNBridgeRules.bannerPropsProblem(
            hasConfig: config != nil,
            size: sizeLabel,
            zoneId: zoneLabel,
            nativeSupports: { AdSize(rawValue: $0) != nil }
        )
        if let report = propsProblem.take(problem) {
            SellwildFailures.log(code: .bridgePropsInvalid, component: .bridge, severity: .error,
                                 message: "\(report), so no ad was set up", zoneId: zoneLabel)
        }
        if problem != nil { return }
        guard
            let cfgMap = config,
            let sizeStr = sizeLabel,
            let zid = zoneLabel,
            let adSize = AdSize(rawValue: sizeStr)
        else {
            // Only a missing size, or a label that is not a JS AdSize, gets
            // here: <SellwildBanner> already reported it as ad.size.invalid,
            // and a failure is logged once (SellwildRNBridgeRules.bannerPropsProblem).
            return
        }

        // Skip if the props identity hasn't changed since last apply —
        // refresh of the rendered ad is driven by the SDK's internal
        // timer, not by JS re-renders.
        let stackStr = (adStack as String?) ?? ""
        let key = "\(sizeStr)|\(zid)|\(stackStr)"
        if lastAppliedKey == key, lastAppliedConfig?.isEqual(cfgMap) == true { return }
        lastAppliedKey = key
        lastAppliedConfig = cfgMap.copy() as? NSDictionary

        let sellwildConfig = Self.configFromMap(cfgMap)

        // Tear down any previous ad view; SellwildAdView itself does not
        // support adUnitId reassignment after load.
        adView?.removeFromSuperview()

        let view = SellwildAdView(config: sellwildConfig, adSize: adSize, zoneId: zid)
        view.adStackOverride = (adStack as String?).flatMap { SellwildAdStack.parse($0) }
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        // Fill the RN-sized host rather than hard-pinning to the primary size —
        // the host's dimensions are driven by JS style, which the JS component
        // updates from the onAdResize event so the slot tracks the actual
        // rendered creative (multi-size fallback, video, capped native).
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        adView = view
        view.load()
    }

    // MARK: SellwildAdViewDelegate

    func sellwildAdViewDidLoad(_ adView: SellwildAdView) {
        onAdLoaded?([:])
    }

    func sellwildAdView(_ adView: SellwildAdView, didReceiveImpressionForZoneId zoneId: String) {
        onAdImpression?(["zoneId": zoneId])
    }

    func sellwildAdView(_ adView: SellwildAdView, didRecordHouseImpressionForZoneId zoneId: String) {
        onHouseAdImpression?(["zoneId": zoneId])
    }

    func sellwildAdViewDidRecordClick(_ adView: SellwildAdView) {
        onAdClicked?([:])
    }

    func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error) {
        onAdFailed?(["message": error.localizedDescription])
    }

    func sellwildAdView(_ adView: SellwildAdView, didRenderWithSize size: CGSize) {
        onAdResize?(["width": size.width, "height": size.height])
    }

    // MARK: Config marshalling

    /// Build a minimal SellwildConfig from a JS dictionary. Only the
    /// fields the native banner path actually reads are mapped; the
    /// rest get the data class defaults. The raw CDN JSON (if present
    /// under `remote`) is preserved as `remoteJSON` for passthrough.
    ///
    /// JS builds this map from core's typed SellwildConfig
    /// (react-native/src/nativeConfig.ts), so a field that is absent keeps the
    /// SDK default and is not a failure. The fields a failure was surveyed
    /// for are checked and reported together, once: a geo or geo field of the
    /// wrong type (dropped, as before) and an incomplete prebidServer
    /// (bridge.config.invalid); and a remote that cannot be serialized
    /// (bridge.config.exception).
    static func configFromMap(_ map: NSDictionary) -> SellwildConfig {
        let partnerCode = (map["partnerCode"] as? String) ?? ""

        var cfg = SellwildConfig(partnerCode: partnerCode)
        var problems: [String] = []

        if let v = map["appBundleId"] as? String { cfg.appBundleId = v }
        if let v = map["appStoreUrl"] as? String { cfg.appStoreUrl = v }
        if let problem = SellwildRNBridgeRules.configGeoProblem(map["geo"]) { problems.append(problem) }
        if let geoMap = map["geo"] as? [String: Any] { cfg.geo = SellwildGeo(bridged: geoMap) }
        if let v = map["gamTag"] as? String { cfg.gamTag = v }
        if let v = map["debug"] as? Bool { cfg.debug = v }
        if let v = map["pbsDebug"] as? Bool { cfg.pbsDebug = v }
        if let v = map["adRefreshMax"] as? Int { cfg.adRefreshMax = v }
        if let v = map["adRefreshMaxMobile"] as? Int { cfg.adRefreshMaxMobile = v }

        // JS bridge passes ms; iOS API is seconds (TimeInterval).
        if let v = map["adRefreshIntervalMs"] as? NSNumber {
            cfg.adRefreshInterval = v.doubleValue / 1000.0
        }

        if let problem = SellwildRNBridgeRules.prebidServerProblem(map["prebidServer"]) {
            problems.append(problem)
        }
        if let prebid = map["prebidServer"] as? NSDictionary,
           let accountId = prebid["accountId"] as? String,
           let endpoint = prebid["endpoint"] as? String {
            let bidders = (prebid["bidders"] as? [String]) ?? []
            let timeout = (prebid["timeout"] as? Int) ?? 1500
            cfg.prebidServer = PrebidServerConfig(
                accountId: accountId,
                endpoint: endpoint,
                bidders: bidders,
                timeout: timeout,
                syncEndpoint: prebid["syncEndpoint"] as? String
            )
        }

        if let gc = map["growthCode"] as? NSDictionary {
            cfg.growthCode = SellwildGrowthCodeConfig(
                enabled: gc["enabled"] as? Bool,
                partnerId: gc["partnerId"] as? String,
                endpoint: gc["endpoint"] as? String,
                syncUrl: gc["syncUrl"] as? String,
                sendMaid: gc["sendMaid"] as? Bool,
                ttlHours: gc["ttlHours"] as? Int
            )
        }

        if let ll = map["localizedListings"] as? NSDictionary {
            cfg.localizedListings = SellwildLocalizedListingsConfig(
                enabled: ll["enabled"] as? Bool,
                source: ll["source"] as? String,
                baseUrl: ll["baseUrl"] as? String,
                urlTemplate: ll["urlTemplate"] as? String,
                frequency: ll["frequency"] as? Int,
                forceState: ll["forceState"] as? String
            )
        }

        if let remote = map["remote"] as? NSDictionary {
            switch SellwildRNBridgeRules.remoteJSON(remote) {
            case .success(let data):
                cfg.remoteJSON = data
            case .failure(let error):
                SellwildFailures.log(code: .bridgeConfigException, component: .bridge, severity: .warn, error: error,
                                     message: "remote could not be serialized, so the bidder passthrough is lost")
            }
        }

        // One report for the config, however many fields it has wrong.
        if !problems.isEmpty {
            SellwildFailures.log(code: .bridgeConfigInvalid, component: .bridge, severity: .error,
                                 message: problems.joined(separator: "; "))
        }

        return cfg
    }
}
