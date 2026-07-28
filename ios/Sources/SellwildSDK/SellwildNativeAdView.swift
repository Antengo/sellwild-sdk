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

    // Strong reference: the fork's NativeAd must outlive fetchDemand or its
    // trackers/click handling are torn down. Cleared on failure.
    private var nativeAd: NativeAd?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let sponsoredLabel = UILabel()
    private let mediaView = UIImageView()
    private let bodyLabel = UILabel()
    private let ctaButton = UIButton(type: .system)

    private var imageTasks: [URLSessionDataTask] = []

    public init(config: SellwildConfig, zoneId: String) {
        self.config = config
        self.zoneId = zoneId
        super.init(frame: .zero)
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("Use init(config:zoneId:)") }

    deinit { imageTasks.forEach { $0.cancel() } }

    // MARK: Load

    /// Request native demand and, on a win, bind + register the assets.
    public func load() {
        let request = SellwildNative.makeRequest(configId: zoneId)
        // NOTE (verify on build): `fetchDemand`'s completion shape and the
        // success `ResultCode` case (`.prebidDemandFetchSuccess`) are Prebid
        // Mobile 3.x. The winning bid's local cache id key is
        // `hb_cache_id_local`; `NativeAd.create(cacheId:)` inflates it.
        request.fetchDemand { [weak self] result, kvResultDict in
            guard let self else { return }
            guard result == .prebidDemandFetchSuccess,
                  let cacheId = kvResultDict?["hb_cache_id_local"],
                  let ad = NativeAd.create(cacheId: cacheId) else {
                let err = SellwildAdError.nativeNoFill
                #if DEBUG
                print("[SellwildNativeAdView] no native fill — zone \(self.zoneId), result \(result)")
                #endif
                self.onFailed?(err)
                return
            }
            DispatchQueue.main.async { self.bind(ad) }
        }
    }

    // MARK: Bind

    private func bind(_ ad: NativeAd) {
        nativeAd = ad
        ad.delegate = self

        titleLabel.text = ad.title
        bodyLabel.text = ad.text
        sponsoredLabel.text = ad.sponsoredBy.map { "Sponsored · \($0)" } ?? "Sponsored"
        let cta = (ad.callToAction?.isEmpty == false) ? ad.callToAction! : "Learn more"
        ctaButton.setTitle(cta, for: .normal)

        loadImage(ad.iconUrl, into: iconView)
        loadImage(ad.imageUrl, into: mediaView)

        // Register the whole view for impression tracking; the CTA (and title)
        // are the clickable surfaces. NOTE (verify on build):
        // `registerView(view:clickableViews:)` signature.
        ad.registerView(view: self, clickableViews: [ctaButton, titleLabel, mediaView])

        onLoaded?()
    }

    // MARK: Layout (pure UIKit — no fork API)

    private func buildLayout() {
        backgroundColor = .clear

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

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = 3

        ctaButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        ctaButton.backgroundColor = tintColor
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.layer.cornerRadius = 8
        ctaButton.setContentHuggingPriority(.required, for: .horizontal)
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)

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

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            mediaView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    @objc private func ctaTapped() {
        // registerView drives the real click tracker; this mirrors the tap to
        // the host delegate for analytics parity with the banner path.
        onClick?()
    }

    private func loadImage(_ urlString: String?, into imageView: UIImageView) {
        guard let urlString, let url = URL(string: urlString) else { return }
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { imageView.image = image }
        }
        imageTasks.append(task)
        task.resume()
    }
}

// MARK: - NativeAdEventDelegate
//
// NOTE (verify on build): the delegate protocol name (`NativeAdEventDelegate`)
// and method signatures are Prebid Mobile 3.x. They drive analytics parity with
// the banner path; the fork's registerView still fires the real trackers.

extension SellwildNativeAdView: NativeAdEventDelegate {

    public func adDidLogImpression(ad: NativeAd) {
        onImpression?()
    }

    public func adWasClicked(ad: NativeAd) {
        onClick?()
    }

    public func adDidExpire(ad: NativeAd) {
        #if DEBUG
        print("[SellwildNativeAdView] native ad expired — zone \(zoneId)")
        #endif
    }
}
