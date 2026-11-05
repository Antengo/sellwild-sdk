// SellwildNativeAdView.swift — renders a Prebid native ad into a default
// template and wires impression / click tracking.
//
// Native, unlike banner/outstream, is not auto-rendered by the fork: Prebid
// fetches demand and hands back a `NativeAd` of raw assets (title, body, icon,
// main image, CTA, sponsoredBy). We lay them out here and call
// `nativeAd.registerView(...)` so the fork fires the OMID / impression / click
// trackers against our views.
//
// This view is hosted inside `SellwildAdView` when NATIVE_ENABLED resolves on a
// `.prebidOnly` placement — it reuses the same ad slot (see the render-scope
// decision in SellwildNative.swift). The layout below is a standard template:
//
//   ┌─────────────────────────────────────────┐
//   │ [icon] Title                             │
//   │        Sponsored by …                    │
//   │ ┌───────────────────────────────────┐   │
//   │ │            main media             │   │
//   │ └───────────────────────────────────┘   │
//   │ Body copy …                              │
//   │                        [ Call to action ]│
//   └─────────────────────────────────────────┘

import UIKit
import SellwildPrebidSDK

public final class SellwildNativeAdView: UIView {

    // Forwarded to the hosting SellwildAdView's delegate.
    var onLoaded: (() -> Void)?
    var onImpression: (() -> Void)?
    var onClick: (() -> Void)?
    var onFailed: ((Error) -> Void)?

    private let config: SellwildConfig
    private let zoneId: String
    private let maxHeight: CGFloat

    // Strong reference: the fork's NativeAd must outlive fetchDemand or its
    // trackers/click handling are torn down.
    private(set) var nativeAd: NativeAd?

    let iconView = UIImageView()
    let titleLabel = UILabel()
    let sponsoredLabel = UILabel()
    let mediaView = UIImageView()
    let bodyLabel = UILabel()
    let ctaButton = UIButton(type: .system)

    private var imageTasks: [URLSessionDataTask] = []

    public init(config: SellwildConfig, zoneId: String, maxHeight: CGFloat) {
        self.config = config
        self.zoneId = zoneId
        self.maxHeight = maxHeight
        super.init(frame: .zero)
        buildLayout()
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design (storyboards are not supported).
    required init?(coder: NSCoder) { fatalError("Use init(config:zoneId:maxHeight:)") }
    // sellwild-coverage:exclude-end

    deinit {
        for task in imageTasks { task.cancel() }
    }

    // MARK: Load

    /// Request native demand and, on a win, bind + register the assets.
    public func load() {
        // Native may use a dedicated placement id (NATIVE_ZID*); resolve it with
        // the mobile-mirroring precedence, falling back to this slot's zoneId.
        let configId = SellwildNative.resolveConfigId(remoteValues: config.remoteValues, zoneId: zoneId)
        let request = SellwildNative.makeRequest(configId: configId)
        // The winning bid's local cache id is exposed via
        // `bidInfo.targetingKeywords?[PrebidLocalCacheIdKey]` and inflated
        // through `NativeAd.create(cacheId:)`.
        Self.environment.fetchDemand(request) { [weak self] bidInfo in
            self?.demandFetched(bidInfo)
        }
    }

    /// The native auction answered. No bids (no fill) is not a failure
    /// (FAILURES.md 4.3). Any other failed result (network, server, timeout,
    /// bad config id) is `ad.prebid_auction.invalid`, as on the banner path.
    /// A winning bid with no cache id, or one the fork cannot turn into an ad,
    /// is `ad.native_create.invalid`. Either way the host hears `nativeNoFill`,
    /// as before.
    func demandFetched(_ bidInfo: BidInfo) {
        guard bidInfo.resultCode == .prebidDemandFetchSuccess else {
            let result = bidInfo.resultCode
            if SellwildAdPolicy.isAuctionFailure(result.rawValue) {
                SellwildFailures.log(code: .adPrebidAuctionInvalid, component: .native, severity: .warn,
                                     message: "the native auction failed: \(result.name())", zoneId: zoneId)
            } else {
                SellwildLog.debug("[SellwildNativeAdView] no native fill — zone \(zoneId), result \(result.name())")
            }
            onFailed?(SellwildAdError.nativeNoFill)
            return
        }
        guard let cacheId = bidInfo.targetingKeywords?[PrebidLocalCacheIdKey] else {
            reportCreateFailure("a native bid won but carried no local cache id")
            return
        }
        guard let ad = NativeAd.create(cacheId: cacheId) else {
            reportCreateFailure("a native bid won but the native ad could not be created from the cache")
            return
        }
        DispatchQueue.main.async { self.bind(ad) }
    }

    private func reportCreateFailure(_ message: String) {
        SellwildFailures.log(code: .adNativeCreateInvalid, component: .native, message: message, zoneId: zoneId)
        onFailed?(SellwildAdError.nativeNoFill)
    }

    // MARK: Bind

    func bind(_ ad: NativeAd) {
        nativeAd = ad
        ad.delegate = self

        titleLabel.text = ad.title
        bodyLabel.text = ad.text
        sponsoredLabel.text = SellwildAdPolicy.sponsoredText(ad.sponsoredBy)
        ctaButton.setTitle(SellwildAdPolicy.callToActionText(ad.callToAction), for: .normal)

        loadImage(ad.iconUrl, into: iconView)
        loadImage(ad.imageUrl, into: mediaView)

        // Register the whole view for impression tracking; the CTA (and title)
        // are the clickable surfaces.
        ad.registerView(view: self, clickableViews: [ctaButton, titleLabel, mediaView])

        onLoaded?()
    }

    // MARK: Layout (pure UIKit — no fork API)

    private func buildLayout() {
        backgroundColor = .clear
        clipsToBounds = true

        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 6
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.numberOfLines = 2

        sponsoredLabel.font = .systemFont(ofSize: 11)
        sponsoredLabel.textColor = .secondaryLabel

        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = 8
        mediaView.backgroundColor = UIColor.secondarySystemBackground
        // The media absorbs the vertical squeeze under the height cap; text and
        // CTA keep their intrinsic size so they're never clipped.
        mediaView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        mediaView.setContentHuggingPriority(.defaultLow, for: .vertical)

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = 3
        for label in [titleLabel, sponsoredLabel, bodyLabel] {
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        ctaButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        ctaButton.backgroundColor = tintColor
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.layer.cornerRadius = 8
        ctaButton.setContentHuggingPriority(.required, for: .horizontal)
        // No addTarget here: the CTA is registered in `registerView(clickableViews:)`,
        // so Prebid's click tracker fires `adWasClicked` → `onClick` on tap. A
        // mirror action here would double-count every CTA click.

        // Header row: icon + (title / sponsored)
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, sponsoredLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let header = UIStackView(arrangedSubviews: [iconView, titleStack])
        header.axis = .horizontal
        header.spacing = 8
        header.alignment = .center

        // Footer row: body grows, CTA hugs the trailing edge.
        let footer = UIStackView(arrangedSubviews: [bodyLabel, ctaButton])
        footer.axis = .horizontal
        footer.spacing = 8
        footer.alignment = .center

        let root = UIStackView(arrangedSubviews: [header, mediaView, footer])
        root.axis = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        // Hard height cap (the render-side backstop). Let the content be shorter
        // than the slot without a conflict (bottom pin is high, not required),
        // and give the media a min it can break under a tight cap.
        let cap = heightAnchor.constraint(lessThanOrEqualToConstant: maxHeight)
        let bottom = root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        bottom.priority = .defaultHigh
        let mediaMin = mediaView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        mediaMin.priority = .defaultHigh

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            bottom,
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cap,
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            mediaMin,
        ])
    }

    /// Loads a native asset image. A missing asset is fine; a URL that is not
    /// http(s), a failed download or an unusable image is `ad.native_image.network`.
    /// Native asset URLs are bidder-supplied, so file:// is refused and the
    /// payload is capped.
    func loadImage(_ urlString: String?, into imageView: UIImageView) {
        guard let urlString else { return }
        guard let url = SellwildSafeURL.imageURL(urlString) else {
            reportImageFailure(message: "native ad image URL is not http(s)", error: nil)
            return
        }
        let task = Self.environment.imageSession.dataTask(with: url) { [weak self] data, response, error in
            switch SellwildImageLoad.outcome(data: data, response: response, error: error) {
            case .image(let image):
                DispatchQueue.main.async { imageView.image = image }
            case .cancelled:
                break
            case .network(let error):
                self?.reportImageFailure(message: "native ad image failed to download", error: error)
            case .invalid(let problem):
                self?.reportImageFailure(message: "native ad image: \(problem.rawValue)", error: nil)
            }
        }
        imageTasks.append(task)
        task.resume()
    }

    private func reportImageFailure(message: String, error: Error?) {
        SellwildFailures.log(code: .adNativeImageNetwork, component: .native, severity: .warn, error: error,
                             message: message, zoneId: zoneId)
    }
}

// MARK: - Environment

extension SellwildNativeAdView {
    /// Where native demand and asset images come from. Partners always get
    /// `live`; tests replace `SellwildNativeAdView.environment`.
    struct Environment {
        /// Runs the native auction (a Prebid Server request).
        var fetchDemand: (NativeRequest, @escaping (BidInfo) -> Void) -> Void
        /// Downloads asset images.
        var imageSession: URLSession

        static let live = Environment(fetchDemand: fetchLiveDemand, imageSession: .shared)

        // sellwild-coverage:exclude-begin(fetch-demand) NativeRequest.fetchDemand sends the Prebid Server request.
        private static let fetchLiveDemand: (NativeRequest, @escaping (BidInfo) -> Void) -> Void = { request, completion in
            request.fetchDemand(completionBidInfo: completion)
        }
        // sellwild-coverage:exclude-end
    }

    static var environment = Environment.live
}

// MARK: - NativeAdEventDelegate
//
// They drive analytics parity with the banner path; the fork's registerView
// still fires the real trackers.

extension SellwildNativeAdView: NativeAdEventDelegate {

    public func adDidLogImpression(ad: NativeAd) {
        onImpression?()
    }

    public func adWasClicked(ad: NativeAd) {
        onClick?()
    }

    /// The ad's cached bid expired. Its lifecycle, not a failure.
    public func adDidExpire(ad: NativeAd) {
        SellwildLog.debug("[SellwildNativeAdView] native ad expired — zone \(zoneId)")
    }
}
