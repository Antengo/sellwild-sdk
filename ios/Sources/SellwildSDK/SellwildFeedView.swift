import UIKit

/// All-in-one native feed surface. As of 1.4.0 this view renders a
/// single-column scroll of native listing cards interleaved with native
/// Prebid + GAM ads, according to the CDN-published `COL1` token string.
///
/// COL1 grammar (one token = one row):
///   - `L` = listing card
///   - `G` = GAM 300x250 ad (zone ID drawn from `config.mobileZids` in order)
///   - `D` = direct ad unit (300x250, currently identical to `G` until a
///           direct-served path lands)
///   - `B` = 320x50 banner (zone ID = `config.mobileBannerZid`)
///
/// The renderer iterates the string left-to-right, emitting one row per
/// token, and stops when the string is exhausted. There is **no WKWebView**
/// anywhere in this surface — every row is native. The schedule, GPIDs and
/// formatting live in `SellwildFeedLayout` and `SellwildFormat`.
///
/// Usage:
/// ```swift
/// let config = await SellwildSDK.configure(partnerCode: "weatherbug",
///                                          slug: "weatherbug-weatherbug")
/// let feed = SellwildFeedView(config: config)
/// view.addSubview(feed)
/// feed.load()
/// ```
public protocol SellwildFeedViewDelegate: AnyObject {
    /// Called when a listing card is tapped. Return `true` to consume the
    /// event; return `false` to let the SDK open `listing.url` in
    /// `SFSafariViewController`.
    func sellwildFeed(_ feed: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdImpressionForZoneId zoneId: String)
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdClickForZoneId zoneId: String)
    func sellwildFeedDidLoad(_ feed: SellwildFeedView)
    /// Fires after a successful fetch with the number of listings bound to the
    /// feed. `count == 0` ⇒ empty / header-only render. Unlike `sellwildFeedDidLoad`
    /// (which also fires on empty), this reliably reflects whether listings were
    /// attached. Parity with Android `Listener.onFeedReady(listingCount)`.
    func sellwildFeed(_ feed: SellwildFeedView, didBecomeReadyWithListingCount count: Int)
    func sellwildFeed(_ feed: SellwildFeedView, didFailWithError message: String)
    /// Called whenever the feed's rendered content height changes (deduped
    /// against the last reported value). Use this to size the feed's
    /// container when embedding it inside a parent scroll view with
    /// `scrollEnabled = false`. `height` is in points.
    func sellwildFeed(_ feed: SellwildFeedView, didChangeContentHeight height: CGFloat)
    /// A house ad backfilled an empty ad slot in the feed (a no-fill). NOT a
    /// paid impression — report it separately. See `SellwildHouseAd`.
    func sellwildFeed(_ feed: SellwildFeedView, didRecordHouseAdImpressionForZoneId zoneId: String)
}

public extension SellwildFeedViewDelegate {
    func sellwildFeed(_ feed: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool { false }
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdImpressionForZoneId zoneId: String) {}
    func sellwildFeed(_ feed: SellwildFeedView, didRecordHouseAdImpressionForZoneId zoneId: String) {}
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdClickForZoneId zoneId: String) {}
    func sellwildFeedDidLoad(_ feed: SellwildFeedView) {}
    func sellwildFeed(_ feed: SellwildFeedView, didBecomeReadyWithListingCount count: Int) {}
    func sellwildFeed(_ feed: SellwildFeedView, didFailWithError message: String) {}
    func sellwildFeed(_ feed: SellwildFeedView, didChangeContentHeight height: CGFloat) {}
}

public final class SellwildFeedView: UIView {

    fileprivate typealias Row = SellwildFeedLayout.Row

    // MARK: Public

    public weak var delegate: SellwildFeedViewDelegate?
    public private(set) var config: SellwildConfig

    /// Disable the feed's own scrolling so it can be embedded inside a parent
    /// `UIScrollView` (single-scroll pages, e.g. alongside a Taboola feed).
    /// When `false` the feed renders every row (no virtualization) and
    /// self-sizes via `intrinsicContentSize`; pull-to-refresh is also
    /// detached (it needs the scroll gesture), so the host must drive refresh.
    /// Defaults to `true` — existing full-screen integrations are unaffected.
    public var scrollEnabled: Bool = true {
        didSet {
            tableView.isScrollEnabled = scrollEnabled
            // Pull-to-refresh needs the scroll gesture; detach it when scroll
            // is off and restore it when scroll is back on.
            tableView.refreshControl = scrollEnabled ? refreshControl : nil
            invalidateIntrinsicContentSize()
        }
    }

    /// The feed's current rendered content height in points, for imperative
    /// reads. Also surfaced push-style via `sellwildFeed(_:didChangeContentHeight:)`.
    public var contentHeight: CGFloat { tableView.contentSize.height }

    // MARK: Private

    private var schedule: String
    private var listings: [SellwildListing] = []
    private var rows: [Row] = [.header]
    /// Effective GPID per ad row, keyed by row index. Repopulated on every
    /// `rebuildRows()` so `base#n` disambiguation reflects the current screen.
    private var gpidByRowIndex: [Int: String] = [:]

    let tableView = UITableView(frame: .zero, style: .plain)
    let refreshControl = UIRefreshControl()
    fileprivate let environment: Environment
    private let apiClient: SellwildAPIClient
    /// One `firstAdViewed` guard for the whole feed surface — shared across every
    /// ad row so `firstAdViewed` fires once per feed mount, not once per row (web
    /// parity). A new feed instance (screen mount) gets a fresh guard and fires
    /// again. `fileprivate` so the same-file `AdRowCell` can read it via `owner`.
    /// See `SellwildFirstAdViewedGuard`.
    fileprivate let firstAdViewedGuard = SellwildFirstAdViewedGuard()

    /// KVO token for `tableView.contentSize`, driving the content-height
    /// callback and self-sizing. Torn down in `deinit`.
    private var contentSizeObservation: NSKeyValueObservation?
    /// Last height reported to the delegate, so we dedupe repeated identical
    /// heights. `-1` means "nothing reported yet".
    private var lastReportedHeight: CGFloat = -1

    // MARK: Init

    public init(config: SellwildConfig) {
        self.config = config
        self.schedule = SellwildFeedLayout.normalizeSchedule(config.col1)
        let environment = Self.environment
        self.environment = environment
        self.apiClient = environment.makeAPIClient()
        super.init(frame: .zero)
        setupTableView()
        applyTheme()
        rows = [.header]
        tableView.reloadData()
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design (storyboards are not supported).
    required init?(coder: NSCoder) { fatalError("Use init(config:)") }
    // sellwild-coverage:exclude-end

    // MARK: Public API

    /// Swap the config and re-derive the schedule without kicking off a fetch.
    public func update(config: SellwildConfig) {
        self.config = config
        self.schedule = SellwildFeedLayout.normalizeSchedule(config.col1)
        applyTheme()
        rebuildRows()
    }

    /// Fetch listings and render the feed. A failed fetch is reported by the
    /// API client; the feed only passes it to the delegate (FAILURES.md 9).
    public func load() {
        let config = self.config
        SellwildLog.debug("[Sellwild] feed load() partner=\(config.partnerCode) col1=\(config.col1 ?? "(nil)") listingsUrl=\(config.effectiveListingsUrl)")
        refreshControl.beginRefreshing()
        apiClient.fetchListings(config: config) { [weak self] result in
            DispatchQueue.main.async { self?.listingsFetched(result) }
        }
    }

    private func listingsFetched(_ result: Result<SellwildListingsResponse, Error>) {
        refreshControl.endRefreshing()
        switch result {
        case .success(let response):
            applyLocalizedDispersion(primary: response.listings)
        case .failure(let error):
            delegate?.sellwildFeed(self, didFailWithError: error.localizedDescription)
        }
    }

    /// Force a re-fetch. Wired to the pull-to-refresh control.
    @objc public func refresh() { load() }

    // MARK: Self-sizing

    /// When scrolling is disabled we report the full table content height as
    /// the view's intrinsic size, so Auto Layout hosts get a self-sizing feed
    /// for free. When scrolling is enabled we defer to the default behaviour.
    public override var intrinsicContentSize: CGSize {
        guard !scrollEnabled else { return super.intrinsicContentSize }
        return CGSize(width: UIView.noIntrinsicMetric, height: tableView.contentSize.height)
    }

    private func contentSizeDidChange() {
        let height = tableView.contentSize.height
        guard height != lastReportedHeight else { return }
        lastReportedHeight = height
        // Keep the self-sizing intrinsic size in sync when scroll is off.
        if !scrollEnabled { invalidateIntrinsicContentSize() }
        delegate?.sellwildFeed(self, didChangeContentHeight: height)
    }

    deinit {
        contentSizeObservation?.invalidate()
    }

    // MARK: Localized dispersion

    /// After the primary fetch, optionally disperse geo-based secondary
    /// listings into the feed before rendering. When the integration is off,
    /// no state resolves, or the secondary fetch fails/404s, the primary feed
    /// renders unchanged (current behavior). Runs on the main thread. The
    /// localized helpers and the API client report their own failures.
    private func applyLocalizedDispersion(primary: [SellwildListing]) {
        guard let integration = SellwildLocalizedListings.resolve(config: config) else {
            finishLoad(with: primary)
            return
        }
        let everyN = SellwildLocalizedListings.everyN(frequencyPercent: integration.frequency)
        guard everyN > 0,
              let state = SellwildLocalizedListings.resolveState(integration, geoState: SellwildGeoStore.current?.state),
              let url = SellwildLocalizedListings.buildCacheURL(integration, state: state) else {
            finishLoad(with: primary)
            return
        }

        apiClient.fetchCacheListings(url: url) { [weak self] result in
            DispatchQueue.main.async { self?.localizedFetched(result, primary: primary, everyN: everyN) }
        }
    }

    private func localizedFetched(_ result: Result<[SellwildListing], Error>, primary: [SellwildListing], everyN: Int) {
        switch result {
        case .success(let secondary):
            finishLoad(with: SellwildLocalizedListings.merge(primary: primary, secondary: secondary, everyN: everyN))
        case .failure:
            finishLoad(with: primary)
        }
    }

    private func finishLoad(with listings: [SellwildListing]) {
        self.listings = listings
        rebuildRows()
        SellwildLog.debug("[Sellwild] feed rows=\(rows.count) listings=\(listings.count)")
        delegate?.sellwildFeedDidLoad(self)
        // Reliable "listings bound" signal (count == 0 ⇒ empty/header-only).
        delegate?.sellwildFeed(self, didBecomeReadyWithListingCount: listings.count)
    }

    // MARK: Setup

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 280
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(HeaderCell.self, forCellReuseIdentifier: HeaderCell.reuseId)
        tableView.register(ListingCardCell.self, forCellReuseIdentifier: ListingCardCell.reuseId)
        tableView.register(AdRowCell.self, forCellReuseIdentifier: AdRowCell.reuseId)
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        // Observe content size so we can report height changes to the host
        // and self-size when scrolling is disabled.
        contentSizeObservation = tableView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            self?.contentSizeDidChange()
        }
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func applyTheme() {
        // Feed surface: prefer CDN `BG_COLOR` / `BACKGROUND`, otherwise a
        // light neutral so white listing cards aren't floating on near-black.
        let bg = SellwildFormat.color(config.bgColor) ?? UIColor(white: 0.96, alpha: 1)
        backgroundColor = bg
        tableView.backgroundColor = bg
        // Refresh spinner: pick a contrasting tint based on background luminance.
        refreshControl.tintColor = SellwildFormat.isDark(bg) ? .white : UIColor(white: 0.4, alpha: 1)
    }

    // MARK: Scheduler

    private func rebuildRows() {
        let layout = SellwildFeedLayout.build(
            schedule: schedule,
            listings: listings,
            adZones: SellwildFeedLayout.adZones(config.mobileZids),
            bannerZone: SellwildFeedLayout.bannerZone(mobile: config.mobileBannerZid, banner: config.bannerZid,
                                                      bottom: config.bottomBannerZid)
        )
        reportSkipped(layout.skipped)
        rows = layout.rows
        let remoteValues = config.remoteValues
        gpidByRowIndex = SellwildFeedLayout.gpids(rows: rows) { zone in
            SellwildGpid.resolveBase(remoteValues: remoteValues, zoneId: zone)
        }
        tableView.reloadData()
    }

    /// COL1 tokens that did not become rows, once a launch each.
    private func reportSkipped(_ skipped: [SellwildFeedLayout.Skip]) {
        for skip in skipped {
            switch skip {
            case .noAdZone:
                guard SellwildReportOnce.first(.feedAdZoneMissing, "ad") else { continue }
                SellwildFailures.log(code: .feedAdZoneMissing, component: .feed, severity: .warn,
                                     message: "COL1 asks for an ad row but no mobile ad zone is configured; the row is dropped")
            case .noBannerZone:
                guard SellwildReportOnce.first(.feedAdZoneMissing, "banner") else { continue }
                SellwildFailures.log(code: .feedAdZoneMissing, component: .feed, severity: .warn,
                                     message: "COL1 asks for a banner row but no banner zone is configured; the row is dropped")
            case .unknownToken(let token):
                guard SellwildReportOnce.first(.feedLayoutInvalid, String(token)) else { continue }
                SellwildFailures.log(code: .feedLayoutInvalid, component: .feed, severity: .warn,
                                     message: "COL1 holds the unknown token \"\(token)\"; it is ignored")
            }
        }
    }

    // MARK: Helpers

    /// Opens a listing or partner page in Safari over the app: http(s) only
    /// (SFSafariViewController traps on any other scheme), from the nearest
    /// view controller.
    fileprivate func openURL(_ urlString: String?) {
        switch SellwildFeedLayout.openTarget(urlString) {
        case .failure(let problem):
            SellwildFailures.log(code: .feedOpenUrlInvalid, component: .feed, severity: .warn, message: problem.rawValue)
        case .success(let url):
            guard let vc = nearestViewController() else {
                SellwildFailures.log(code: .feedOpenUrlInvalid, component: .feed, severity: .warn,
                                     message: "no view controller to present the page from")
                return
            }
            environment.present(url, vc)
        }
    }

    /// The header title opens the partner page, when one is configured.
    fileprivate func openPartnerPage() {
        guard let partnerUrl = config.partnerUrl else { return }
        openURL(partnerUrl)
    }

    fileprivate func handleListingTap(_ listing: SellwildListing) {
        let handled = delegate?.sellwildFeed(self, didTapListing: listing) == true
        if !handled {
            openURL(listing.tapURL(partnerCode: config.partnerCode, bhTag: config.bhTag))
        }
    }

    fileprivate func handleAdImpression(_ zoneId: String) {
        delegate?.sellwildFeed(self, didRecordAdImpressionForZoneId: zoneId)
    }

    fileprivate func handleHouseAdImpression(_ zoneId: String) {
        delegate?.sellwildFeed(self, didRecordHouseAdImpressionForZoneId: zoneId)
    }

    fileprivate func handleAdClick(_ zoneId: String) {
        delegate?.sellwildFeed(self, didRecordAdClickForZoneId: zoneId)
    }

    /// Re-query self-sizing row heights after an ad row's content height changed
    /// (fixed ad slot ↔ full-width fallback card) without reloading/recreating
    /// cells — so the row grows to show a fallback listing fully in view, and
    /// shrinks back when a paid creative fills. No animation to avoid scroll jank.
    fileprivate func reflowRowHeights() {
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil)
        }
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    /// Pick a listing to house-backfill an ad slot with when no CMS house image
    /// is configured. Prefers listings that actually have a photo (a photoless
    /// listing renders a grey placeholder), rotating by row so adjacent ad slots
    /// don't repeat. Excludes listings already rendered as a normal `.listing`
    /// row in `rows` so an ad-slot backfill never duplicates a listing already
    /// shown elsewhere in the feed — falls back to a duplicate only if every
    /// candidate is already shown (see `SellwildHouseAd.pickListing`). Returns
    /// nil when there are no listings to draw from.
    private func houseListing(for row: Int) -> SellwildListing? {
        SellwildHouseAd.pickListing(from: listings, row: row, excludeIds: SellwildFeedLayout.shownListingIds(rows))
    }

    /// A dequeued cell of the registered type, else a blank cell and
    /// `feed.cell.invalid` (it used to be a force cast that crashed the app).
    private func dequeue<Cell: UITableViewCell>(_ type: Cell.Type, id: String, for indexPath: IndexPath,
                                                in tableView: UITableView) -> Cell? {
        let cell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath)
        if let typed = cell as? Cell { return typed }
        SellwildFailures.log(code: .feedCellInvalid, component: .feed, severity: .fatal,
                             message: "a dequeued feed cell had an unexpected type; the row is blank")
        return nil
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SellwildFeedView: UITableViewDataSource, UITableViewDelegate {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case .header:
            guard let cell = dequeue(HeaderCell.self, id: HeaderCell.reuseId, for: indexPath, in: tableView) else {
                return UITableViewCell()
            }
            cell.configure(config: config, onTitleTap: { [weak self] in
                self?.openPartnerPage()
            }, onPoweredByTap: { [weak self] in
                self?.openURL("https://sellwild.com")
            })
            return cell
        case .listing(let listing):
            guard let cell = dequeue(ListingCardCell.self, id: ListingCardCell.reuseId, for: indexPath, in: tableView) else {
                return UITableViewCell()
            }
            cell.configure(config: config, listing: listing)
            return cell
        case .gamAd(let zone), .directAd(let zone):
            guard let cell = dequeue(AdRowCell.self, id: AdRowCell.reuseId, for: indexPath, in: tableView) else {
                return UITableViewCell()
            }
            // MREC can house-backfill with a listing when no CMS image is set.
            cell.configure(config: config, adSize: .mrec300x250, zoneId: zone, owner: self,
                           houseListing: houseListing(for: indexPath.row),
                           gpid: gpidByRowIndex[indexPath.row])
            return cell
        case .banner(let zone):
            guard let cell = dequeue(AdRowCell.self, id: AdRowCell.reuseId, for: indexPath, in: tableView) else {
                return UITableViewCell()
            }
            // 320x50 is too small for a listing card — CMS house image only.
            cell.configure(config: config, adSize: .banner320x50, zoneId: zone, owner: self,
                           houseListing: nil,
                           gpid: gpidByRowIndex[indexPath.row])
            return cell
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if case .listing(let listing) = rows[indexPath.row] {
            handleListingTap(listing)
        }
    }
}

// MARK: - HeaderCell (title + Powered by Sellwild)

private final class HeaderCell: UITableViewCell {
    static let reuseId = "SellwildFeedHeaderCell"

    private let titleLabel = UILabel()
    private let poweredByLabel = UILabel()
    private var onTitleTap: (() -> Void)?
    private var onPoweredByTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))

        poweredByLabel.translatesAutoresizingMaskIntoConstraints = false
        poweredByLabel.font = .systemFont(ofSize: 11, weight: .regular)
        poweredByLabel.text = "Powered by Sellwild"
        poweredByLabel.textAlignment = .right
        poweredByLabel.isUserInteractionEnabled = true
        poweredByLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(poweredByTapped)))

        contentView.addSubview(titleLabel)
        contentView.addSubview(poweredByLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            poweredByLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            poweredByLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            poweredByLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design; the feed registers this cell by class.
    required init?(coder: NSCoder) { fatalError() }
    // sellwild-coverage:exclude-end

    func configure(config: SellwildConfig, onTitleTap: @escaping () -> Void, onPoweredByTap: @escaping () -> Void) {
        titleLabel.text = config.title ?? "Marketplace"
        titleLabel.textColor = SellwildFormat.color(config.titleColor) ?? .white
        poweredByLabel.textColor = SellwildFormat.color(config.linkColor) ?? UIColor(white: 0.7, alpha: 1)
        self.onTitleTap = onTitleTap
        self.onPoweredByTap = onPoweredByTap
    }

    @objc private func titleTapped() { onTitleTap?() }
    @objc private func poweredByTapped() { onPoweredByTap?() }
}

// MARK: - SellwildListingCardView (shared listing card: photo, title, price, seller)
//
// The single source of truth for how a listing renders in the feed — used by
// `ListingCardCell` (organic listings) AND by `AdRowCell` as the full-width
// house-ad fallback, so a fallback listing is pixel-identical to every other
// listing card. The view IS the white card; hosts pin it with the feed's 8/16
// insets.

final class SellwildListingCardView: UIView {

    /// Set to make the card tappable. Used by the ad-row fallback, which isn't
    /// routed through the table's `didSelectRowAt`; organic listing cells leave
    /// this nil and are tapped via row selection instead.
    var onTap: (() -> Void)? {
        didSet { tapRecognizer.isEnabled = onTap != nil }
    }

    let photoView = UIImageView()
    let titleLabel = UILabel()
    let priceLabel = UILabel()
    let sellerLabel = UILabel()
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = 12
        clipsToBounds = true

        photoView.translatesAutoresizingMaskIntoConstraints = false
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.backgroundColor = UIColor(white: 0.93, alpha: 1)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1)
        titleLabel.numberOfLines = 2

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.font = .systemFont(ofSize: 18, weight: .bold)

        sellerLabel.translatesAutoresizingMaskIntoConstraints = false
        sellerLabel.font = .systemFont(ofSize: 11, weight: .regular)
        sellerLabel.textColor = UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1)

        addSubview(photoView)
        addSubview(titleLabel)
        addSubview(priceLabel)
        addSubview(sellerLabel)

        NSLayoutConstraint.activate([
            photoView.topAnchor.constraint(equalTo: topAnchor),
            photoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            photoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            photoView.heightAnchor.constraint(equalToConstant: 200),

            titleLabel.topAnchor.constraint(equalTo: photoView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            priceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            priceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            priceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            sellerLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 6),
            sellerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sellerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sellerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])

        addGestureRecognizer(tapRecognizer)
        tapRecognizer.isEnabled = false
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design; the feed builds the card in code.
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    // sellwild-coverage:exclude-end

    @objc private func tapped() { onTap?() }

    func configure(config: SellwildConfig, listing: SellwildListing) {
        titleLabel.text = listing.title
        priceLabel.text = SellwildFormat.price(currency: listing.currency, price: listing.price)
        priceLabel.textColor = SellwildFormat.color(config.linkColor) ?? UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
        sellerLabel.text = SellwildFormat.seller(listing.user)
        loadImage(listing.photos?.first?.url)
    }

    /// Clear transient state before reuse (mirrors the old cell's prepareForReuse).
    func reset() {
        imageTask?.cancel()
        imageTask = nil
        currentImageURL = nil
        photoView.image = nil
        photoView.backgroundColor = UIColor(white: 0.93, alpha: 1)
    }

    /// Loads the listing photo: memory cache, then a data: URI decoded off the
    /// main thread (size-capped), then an http(s) download. A refused or
    /// failed photo stays grey and is reported (`feed.image.*`); a download
    /// cancelled by reuse is not.
    private func loadImage(_ urlString: String?) {
        currentImageURL = urlString
        guard let s = urlString, !s.isEmpty else { return }
        if let cached = Self.cache.object(forKey: s as NSString) {
            photoView.image = cached
            return
        }
        if s.hasPrefix("data:") {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let outcome = SellwildImageLoad.decoded(SellwildHouseAd.decodeDataURI(s))
                Self.imageLoaded(outcome, key: s, reportURL: nil) { self?.show($0, for: s) }
            }
            return
        }
        // http/https only (reject file://) — listing photo URLs are remote data.
        guard let url = SellwildSafeURL.imageURL(s) else {
            SellwildFailures.log(code: .feedImageInvalid, component: .feed, severity: .warn,
                                 message: "listing photo URL is not http(s)")
            return
        }
        let task = SellwildFeedView.environment.imageSession.dataTask(with: url) { [weak self] data, response, error in
            let outcome = SellwildImageLoad.outcome(data: data, response: response, error: error)
            Self.imageLoaded(outcome, key: s, reportURL: s) { self?.show($0, for: s) }
        }
        imageTask = task
        task.resume()
    }

    /// Caches and shows a loaded photo, or reports why there is none.
    private static func imageLoaded(_ outcome: SellwildImageLoad.Outcome, key: String, reportURL: String?,
                                    show: @escaping (UIImage) -> Void) {
        switch outcome {
        case .image(let image):
            cache.setObject(image, forKey: key as NSString)
            DispatchQueue.main.async { show(image) }
        case .cancelled:
            break
        case .network(let error):
            SellwildFailures.log(code: .feedImageNetwork, component: .feed, severity: .warn, error: error,
                                 message: "listing photo failed to download",
                                 httpStatus: SellwildImageLoad.httpStatus(error), url: reportURL)
        case .invalid(let problem):
            SellwildFailures.log(code: .feedImageInvalid, component: .feed, severity: .warn,
                                 message: "listing photo: \(problem.rawValue)")
        }
    }

    /// Shows `image` unless the card moved on to another photo meanwhile.
    private func show(_ image: UIImage, for url: String) {
        guard currentImageURL == url else { return }
        photoView.image = image
    }

    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()
}

// MARK: - ListingCardCell (thin wrapper hosting a SellwildListingCardView)

private final class ListingCardCell: UITableViewCell {
    static let reuseId = "SellwildFeedListingCardCell"

    private let cardView = SellwildListingCardView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        accessibilityIdentifier = SellwildFeedView.listingCardAccessibilityID

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design; the feed registers this cell by class.
    required init?(coder: NSCoder) { fatalError() }
    // sellwild-coverage:exclude-end

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView.reset()
    }

    func configure(config: SellwildConfig, listing: SellwildListing) {
        cardView.configure(config: config, listing: listing)
    }
}

// MARK: - AdRowCell (wraps SellwildAdView)

private final class AdRowCell: UITableViewCell, SellwildAdViewDelegate {
    static let reuseId = "SellwildFeedAdRowCell"

    private var adView: SellwildAdView?
    // Full-width listing fallback shown when the ad no-fills and no CMS house
    // IMAGE is configured — rendered with the SAME card as organic listings so
    // it's pixel-identical, and it grows the row to its natural height.
    private let fallbackCard = SellwildListingCardView()
    private var boundZoneId: String?
    /// The zone this row reports its ad events under.
    private var zone = ""
    private weak var owner: SellwildFeedView?
    private var config: SellwildConfig?
    private var houseListing: SellwildListing?
    // A CMS house IMAGE renders in-slot via the ad view (MREC), so when one is
    // configured we keep the fixed slot instead of the full-width listing card.
    private var hasHouseImage = false
    private var adConstraints: [NSLayoutConstraint] = []
    private var cardConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        accessibilityIdentifier = SellwildFeedView.adRowAccessibilityID

        fallbackCard.translatesAutoresizingMaskIntoConstraints = false
        fallbackCard.isHidden = true
        contentView.addSubview(fallbackCard)
        cardConstraints = [
            fallbackCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            fallbackCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            fallbackCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            fallbackCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ]
        fallbackCard.onTap = { [weak self] in self?.fallbackTapped() }
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design; the feed registers this cell by class.
    required init?(coder: NSCoder) { fatalError() }
    // sellwild-coverage:exclude-end

    private func fallbackTapped() {
        guard let listing = houseListing else { return }
        owner?.handleListingTap(listing)
    }

    func configure(config: SellwildConfig, adSize: AdSize, zoneId: String, owner: SellwildFeedView,
                   houseListing: SellwildListing?, gpid: String?) {
        self.owner = owner
        self.config = config
        self.zone = zoneId
        self.houseListing = houseListing
        self.hasHouseImage = SellwildHouseAd.resolve(
            remoteValues: config.remoteValues, zoneId: zoneId, size: adSize.cgSize
        ) != nil
        if boundZoneId == zoneId, adView != nil {
            // Reused for the same zone: keep the ad view (and its refresh cadence).
            // Refresh the fallback content if it's currently showing.
            if !fallbackCard.isHidden, let listing = houseListing {
                fallbackCard.configure(config: config, listing: listing)
            }
            return
        }
        boundZoneId = zoneId
        adView?.removeFromSuperview()

        let ad = owner.environment.makeAdView(config, adSize, zoneId)
        // Share the feed's surface guard so firstAdViewed fires once for the whole
        // feed, not once per ad row (web parity).
        ad.firstAdViewedGuard = owner.firstAdViewedGuard
        // The feed owns the LISTING fallback (rendered full-width below); the ad
        // view only handles a house IMAGE backdrop in-slot, so don't hand it a
        // listing.
        ad.houseFallbackListing = nil
        // Inherit ad-stack from CDN config so feed ads respect AD_STACK / AD_STACK_BY_ZONE
        ad.adStackOverride = SellwildAdStack.resolve(
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            override: nil
        )
        // Inject the feed-computed GPID (base, or base#n when the base repeats on
        // this screen). nil ⇒ the ad view auto-resolves the bare base from config.
        ad.gpidOverride = gpid
        ad.translatesAutoresizingMaskIntoConstraints = false
        ad.delegate = self
        contentView.addSubview(ad)
        adConstraints = [
            ad.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            ad.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            ad.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            ad.widthAnchor.constraint(equalToConstant: adSize.cgSize.width),
            ad.heightAnchor.constraint(equalToConstant: adSize.cgSize.height),
        ]
        adView = ad
        showAdSlot()   // start on the fixed ad slot; swap to the card only on no-fill
        ad.load()
    }

    /// Show the fixed MREC ad slot (paid creative or in-slot house image).
    private func showAdSlot() {
        NSLayoutConstraint.deactivate(cardConstraints)
        fallbackCard.isHidden = true
        adView?.isHidden = false
        NSLayoutConstraint.activate(adConstraints)
    }

    /// Swap to the full-width listing fallback and grow the row to fit it.
    private func showFallbackCard(_ listing: SellwildListing, config: SellwildConfig) {
        NSLayoutConstraint.deactivate(adConstraints)
        adView?.isHidden = true
        fallbackCard.configure(config: config, listing: listing)
        fallbackCard.isHidden = false
        NSLayoutConstraint.activate(cardConstraints)
        owner?.handleHouseAdImpression(zone)
        owner?.reflowRowHeights()
    }

    // MARK: SellwildAdViewDelegate

    func sellwildAdViewDidLoad(_ adView: SellwildAdView) {
        // Paid creative filled — ensure the ad slot is showing (shrinks the row
        // back if a fallback card had grown it).
        let wasCard = !fallbackCard.isHidden
        showAdSlot()
        if wasCard { owner?.reflowRowHeights() }
    }

    func sellwildAdView(_ adView: SellwildAdView, didReceiveImpressionForZoneId zoneId: String) {
        owner?.handleAdImpression(zoneId)
    }

    func sellwildAdView(_ adView: SellwildAdView, didRecordHouseImpressionForZoneId zoneId: String) {
        // Fired when the ad view's own house IMAGE backdrop shows on no-fill.
        owner?.handleHouseAdImpression(zoneId)
    }

    func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error) {
        // No-fill. A CMS house image (if any) renders in-slot via the ad view, so
        // keep the fixed slot; otherwise show the full-width listing fallback.
        let view = SellwildFeedLayout.noFillView(hasHouseImage: hasHouseImage, hasListing: houseListing != nil)
        if view == .fallbackCard, let listing = houseListing, let config {
            showFallbackCard(listing, config: config)
        } else {
            showAdSlot()
        }
    }

    func sellwildAdViewDidRecordClick(_ adView: SellwildAdView) {
        owner?.handleAdClick(zone)
    }
}
