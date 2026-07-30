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
    @objc var onListingTap: RCTDirectEventBlock?
    @objc var onAdImpression: RCTDirectEventBlock?
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
    static func configFromMap(_ map: NSDictionary) -> SellwildConfig {
        let partnerCode = (map["partnerCode"] as? String) ?? ""
        var cfg = SellwildConfig(partnerCode: partnerCode)

        // Apply the raw CDN payload first so explicit JS overrides
        // (e.g. appBundleId from the host app) win.
        if let remote = map["remote"] as? [String: Any] {
            cfg = SellwildSDK.apply(remote, to: cfg)
            if let data = try? JSONSerialization.data(withJSONObject: remote, options: []) {
                cfg.remoteJSON = data
            }
        }

        if let v = map["slug"] as? String { cfg.slug = v }
        if let v = map["appBundleId"] as? String { cfg.appBundleId = v }
        if let v = map["appStoreUrl"] as? String { cfg.appStoreUrl = v }
        if let geoMap = map["geo"] as? [String: Any] { cfg.geo = SellwildGeo(bridged: geoMap) }
        if let v = map["gamTag"] as? String { cfg.gamTag = v }
        if let v = map["debug"] as? Bool { cfg.debug = v }
        if let v = map["pbsDebug"] as? Bool { cfg.pbsDebug = v }
        if let v = map["adRefreshMax"] as? Int { cfg.adRefreshMax = v }
        if let v = map["adRefreshMaxMobile"] as? Int { cfg.adRefreshMaxMobile = v }
        if let v = map["listingsUrl"] as? String { cfg.listingsUrl = v }
        if let v = map["priceColor"] as? String { cfg.priceColor = v }
        if let v = map["bannerZid"] as? String { cfg.bannerZid = v }
        if let v = map["bottomBannerZid"] as? String { cfg.bottomBannerZid = v }
        if let v = map["mobileBannerZid"] as? String { cfg.mobileBannerZid = v }
        if let v = map["mobileZids"] as? [String] { cfg.mobileZids = v }

        // JS bridge passes ms; iOS API is seconds (TimeInterval).
        if let v = map["adRefreshIntervalMs"] as? NSNumber {
            cfg.adRefreshInterval = v.doubleValue / 1000.0
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
