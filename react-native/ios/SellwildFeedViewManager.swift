import Foundation
import React
import SellwildSDK
import UIKit

/// Bridges the JS `<SellwildFeed>` component to the native
/// `SellwildFeedView` (all-in-one native feed: COL1-scheduled listing
/// cards + Prebid + GAM ads, zero WebView). Mirrors the Android
/// `SellwildFeedViewManager` shape.
///
/// Props (set from JS):
///   - config: object — the resolved SellwildConfig (from configure()).
///       The bridge re-runs the CDN decoder against `config.remote` so
///       feed-specific fields (COL1, bgColor, mobileZids, …) are
///       populated even though they're not all typed on the JS side.
///
/// Events emitted to JS:
///   - onFeedLoaded
///   - onListingTap   { listing }
///   - onAdImpression { zoneId }
///   - onAdClicked    { zoneId }
///   - onFeedError    { message }
@objc(SellwildFeedViewManager)
public final class SellwildFeedViewManager: RCTViewManager {

    public override init() {
        super.init()
        SellwildRNWrapper.install()
    }

    public override static func requiresMainQueueSetup() -> Bool { true }

    public override func view() -> UIView! {
        return SellwildFeedHostView()
    }
}

/// Hosts a `SellwildFeedView`. We can't construct the feed until the
/// `config` prop has arrived, so we cache it and apply on
/// `didSetProps:` — same pattern as the banner host view.
final class SellwildFeedHostView: UIView, SellwildFeedViewDelegate {

    // MARK: RN-set props

    @objc var config: NSDictionary? { didSet { needsApply = true } }
    /// Disable the feed's internal scrolling so it can be embedded inside a
    /// parent scroll view. Applied live and on feed creation.
    @objc var scrollEnabled: Bool = true { didSet { feedView?.scrollEnabled = scrollEnabled } }

    // MARK: RN events

    @objc var onFeedLoaded: RCTDirectEventBlock?
    /// Fires after a successful fetch with the bound listing count
    /// (`listingCount == 0` ⇒ empty / header-only). Reliable "ready" signal.
    @objc var onFeedReady: RCTDirectEventBlock?
    @objc var onListingTap: RCTDirectEventBlock?
    @objc var onAdImpression: RCTDirectEventBlock?
    /// A house ad backfilled an empty feed slot (no-fill). Not a paid impression.
    @objc var onHouseAdImpression: RCTDirectEventBlock?
    @objc var onAdClicked: RCTDirectEventBlock?
    @objc var onFeedError: RCTDirectEventBlock?
    /// Emitted whenever the feed's content height changes so JS can size the
    /// host container when embedding with `scrollEnabled={false}`.
    @objc var onContentSizeChange: RCTDirectEventBlock?

    // MARK: Internals

    private var feedView: SellwildFeedView?
    private var lastAppliedKey: String?
    private var needsApply: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func didSetProps(_ changedProps: [String]) {
        guard needsApply else { return }
        needsApply = false
        applyIfReady()
    }

    private func applyIfReady() {
        guard let cfgMap = config else { return }

        // Skip if the props identity hasn't changed since last apply.
        // Feed refresh is driven by user pull-to-refresh, not JS
        // re-renders.
        let key = "\(cfgMap.hash)"
        if lastAppliedKey == key { return }
        lastAppliedKey = key

        let sellwildConfig = Self.configFromMap(cfgMap)

        // Tear down any previous feed view; SellwildFeedView holds its
        // own table state and we want a clean fetch on identity change.
        feedView?.removeFromSuperview()

        let view = SellwildFeedView(config: sellwildConfig)
        view.delegate = self
        view.scrollEnabled = scrollEnabled
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        feedView = view
        view.load()
    }

    // MARK: SellwildFeedViewDelegate

    func sellwildFeedDidLoad(_ feed: SellwildFeedView) {
        onFeedLoaded?([:])
    }

    func sellwildFeed(_ feed: SellwildFeedView, didBecomeReadyWithListingCount count: Int) {
        onFeedReady?(["listingCount": count])
    }

    func sellwildFeed(_ feed: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool {
        // Forward the listing payload to JS as a plain dictionary. JS
        // can't return a value back through a direct event block, so
        // the SDK still owns whether to open the URL in
        // SFSafariViewController. Partners who want to fully consume
        // the tap can subclass via `useNativeNavigation` later;
        // current behaviour matches the WebView widget (always opens
        // in in-app browser) so there's no regression.
        let payload = Self.listingPayload(listing)
        onListingTap?(["listing": payload])
        return false
    }

    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdImpressionForZoneId zoneId: String) {
        onAdImpression?(["zoneId": zoneId])
    }

    func sellwildFeed(_ feed: SellwildFeedView, didRecordHouseAdImpressionForZoneId zoneId: String) {
        onHouseAdImpression?(["zoneId": zoneId])
    }

    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdClickForZoneId zoneId: String) {
        onAdClicked?(["zoneId": zoneId])
    }

    func sellwildFeed(_ feed: SellwildFeedView, didFailWithError message: String) {
        onFeedError?(["message": message])
    }

    func sellwildFeed(_ feed: SellwildFeedView, didChangeContentHeight height: CGFloat) {
        onContentSizeChange?(["height": height])
    }

    // MARK: Config marshalling

    /// Build a full SellwildConfig from a JS dictionary. The JS side
    /// passes the raw CDN payload under `remote`; we re-run the
    /// canonical CDN decoder against it so feed-specific fields (COL1,
    /// bgColor, mobileZids, listingsUrl, …) are populated identically
    /// to a native `SellwildSDK.configure(...)` call.
    ///
    /// JS builds this map from core's typed SellwildConfig
    /// (react-native/src/nativeConfig.ts toNativeFeedConfig), so a field that
    /// is absent keeps the SDK default and is not a failure. The fields a
    /// failure was surveyed for are checked and reported together, once: a
    /// geo or geo field of the wrong type (dropped, as before), zone ids that
    /// are not text and an incomplete prebidServer (bridge.config.invalid);
    /// and a remote that cannot be serialized (bridge.config.exception).
    static func configFromMap(_ map: NSDictionary) -> SellwildConfig {
        let partnerCode = (map["partnerCode"] as? String) ?? ""
        var cfg = SellwildConfig(partnerCode: partnerCode)
        var problems: [String] = []

        // Apply the raw CDN payload first so explicit JS overrides
        // (e.g. appBundleId from the host app) win.
        if let remote = map["remote"] as? [String: Any] {
            cfg = SellwildSDK.apply(remote, to: cfg)
            switch SellwildRNBridgeRules.remoteJSON(remote) {
            case .success(let data):
                cfg.remoteJSON = data
            case .failure(let error):
                SellwildFailures.log(code: .bridgeConfigException, component: .bridge, severity: .warn, error: error,
                                     message: "remote could not be serialized, so the bidder passthrough is lost")
            }
        }

        if let v = map["slug"] as? String { cfg.slug = v }
        if let v = map["appBundleId"] as? String { cfg.appBundleId = v }
        if let v = map["appStoreUrl"] as? String { cfg.appStoreUrl = v }
        if let problem = SellwildRNBridgeRules.configGeoProblem(map["geo"]) { problems.append(problem) }
        if let geoMap = map["geo"] as? [String: Any] { cfg.geo = SellwildGeo(bridged: geoMap) }
        if let v = map["gamTag"] as? String { cfg.gamTag = v }
        if let v = map["debug"] as? Bool { cfg.debug = v }
        if let v = map["pbsDebug"] as? Bool { cfg.pbsDebug = v }
        if let v = map["adRefreshMax"] as? Int { cfg.adRefreshMax = v }
        if let v = map["adRefreshMaxMobile"] as? Int { cfg.adRefreshMaxMobile = v }
        if let v = map["listingsUrl"] as? String { cfg.listingsUrl = v }
        if let v = map["priceColor"] as? String { cfg.priceColor = v }
        // Zone ids are text. JS sends them as text (nativeZoneId); a value of
        // another type is dropped, as before, and reported.
        let bannerZid = SellwildRNBridgeRules.text(map["bannerZid"], key: "bannerZid")
        if let v = bannerZid.value { cfg.bannerZid = v }
        let bottomBannerZid = SellwildRNBridgeRules.text(map["bottomBannerZid"], key: "bottomBannerZid")
        if let v = bottomBannerZid.value { cfg.bottomBannerZid = v }
        problems += [bannerZid.problem, bottomBannerZid.problem].compactMap { $0 }

        // mobileZids / mobileBannerZid are resolved per-platform (iOS here) by
        // SellwildSDK.apply(_:to:) above, which reads the OS-suffixed CDN keys
        // (MOBILE_ZID_IOS / MOBILE_BANNER_ZID_IOS) out of `remote`. Only fall
        // back to the flat JS-passed values when there was no `remote` payload
        // to resolve from — otherwise the iOS-resolved zones would be clobbered
        // by the unsuffixed values the JS core mapped (which are OS-agnostic).
        if map["remote"] == nil {
            let mobileBannerZid = SellwildRNBridgeRules.text(map["mobileBannerZid"], key: "mobileBannerZid")
            if let v = mobileBannerZid.value { cfg.mobileBannerZid = v }
            let mobileZids = SellwildRNBridgeRules.textList(map["mobileZids"], key: "mobileZids")
            if let v = mobileZids.value { cfg.mobileZids = v }
            problems += [mobileBannerZid.problem, mobileZids.problem].compactMap { $0 }
        }

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

        // Local GrowthCode override — parity with the banner bridge. Without
        // this the feed's ad rows only see remote GROWTHCODE_* keys (via
        // remoteJSON); a code-supplied partnerId never reaches the auction, so
        // the identity sync never fires and feed ad rows lose eids enrichment.
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

        // Local override for the localized (geo-based) secondary-listings
        // integration; remote LOCALIZED_LISTINGS rides `remote` verbatim.
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

        // One report for the config, however many fields it has wrong.
        if !problems.isEmpty {
            SellwildFailures.log(code: .bridgeConfigInvalid, component: .bridge, severity: .error,
                                 message: problems.joined(separator: "; "))
        }

        return cfg
    }

    /// Serialize a SellwildListing to a JS-friendly dictionary. Surfaces
    /// the fields the JS callback is most likely to act on; the rest
    /// can be added on demand.
    static func listingPayload(_ listing: SellwildListing) -> [String: Any] {
        var dict: [String: Any] = [
            "id": listing.id,
            "title": listing.title,
        ]
        if let v = listing.url { dict["url"] = v }
        if let v = listing.currency { dict["currency"] = v }
        if let v = listing.price { dict["price"] = v }
        if let v = listing.remoteUrl { dict["remoteUrl"] = v }
        if let firstPhoto = listing.photos?.first?.url { dict["photoUrl"] = firstPhoto }
        return dict
    }
}
