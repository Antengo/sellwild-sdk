import UIKit
import SafariServices
import os.log

private let feedLog = OSLog(subsystem: "com.sellwild.sdk", category: "SellwildFeed")

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
/// anywhere in this surface — every row is native.
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
    func sellwildFeed(_ feed: SellwildFeedView, didFailWithError message: String)
}

public extension SellwildFeedViewDelegate {
    func sellwildFeed(_ feed: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool { false }
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdImpressionForZoneId zoneId: String) {}
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdClickForZoneId zoneId: String) {}
    func sellwildFeedDidLoad(_ feed: SellwildFeedView) {}
    func sellwildFeed(_ feed: SellwildFeedView, didFailWithError message: String) {}
}

public final class SellwildFeedView: UIView {

    // MARK: Public

    public weak var delegate: SellwildFeedViewDelegate?
    public private(set) var config: SellwildConfig

    // MARK: Private

    private var schedule: String
    private var listings: [SellwildListing] = []
    private var rows: [Row] = [.header]

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let apiClient = SellwildAPIClient()

    // MARK: Init

    public init(config: SellwildConfig) {
        self.config = config
        self.schedule = Self.normalizeSchedule(config.col1)
        super.init(frame: .zero)
        setupTableView()
        applyTheme()
        rows = [.header]
        tableView.reloadData()
    }

    required init?(coder: NSCoder) { fatalError("Use init(config:)") }

    // MARK: Public API

    /// Swap the config and re-derive the schedule without kicking off a fetch.
    public func update(config: SellwildConfig) {
        self.config = config
        self.schedule = Self.normalizeSchedule(config.col1)
        applyTheme()
        rebuildRows()
    }

    /// Fetch listings and render the feed.
    public func load() {
        NSLog("[Sellwild] load() partner=%@ col1=%@ listingsUrl=%@",
              config.partnerCode, config.col1 ?? "(nil)", config.effectiveListingsUrl)
        refreshControl.beginRefreshing()
        apiClient.fetchListings(config: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.refreshControl.endRefreshing()
                switch result {
                case .success(let response):
                    NSLog("[Sellwild] fetchListings success count=%d schedule=%@",
                          response.listings.count, self.schedule)
                    self.listings = response.listings
                    self.rebuildRows()
                    NSLog("[Sellwild] rebuildRows -> rowCount=%d", self.rows.count)
                    self.delegate?.sellwildFeedDidLoad(self)
                case .failure(let error):
                    NSLog("[Sellwild] fetchListings FAILED: %@", error.localizedDescription)
                    self.delegate?.sellwildFeed(self, didFailWithError: error.localizedDescription)
                }
            }
        }
    }

    /// Force a re-fetch. Wired to the pull-to-refresh control.
    @objc public func refresh() { load() }

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
        let bg = Self.parseColor(config.bgColor) ?? UIColor(white: 0.96, alpha: 1)
        backgroundColor = bg
        tableView.backgroundColor = bg
        // Refresh spinner: pick a contrasting tint based on background luminance.
        refreshControl.tintColor = Self.isDark(bg) ? .white : UIColor(white: 0.4, alpha: 1)
    }

    private static func isDark(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Rec. 709 luma; under 0.5 reads as dark.
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 0.5
    }

    // MARK: Scheduler

    fileprivate enum Row {
        case header
        case listing(SellwildListing)
        case gamAd(zoneId: String)
        case directAd(zoneId: String)
        case banner(zoneId: String)
    }

    private func rebuildRows() {
        rows = buildRows()
        tableView.reloadData()
    }

    private func buildRows() -> [Row] {
        var out: [Row] = [.header]
        var listingsIter = listings.makeIterator()
        let gamZones = config.mobileZids.filter { !$0.isEmpty }
        let bannerZone = (config.mobileBannerZid ?? config.bannerZid ?? config.bottomBannerZid) ?? ""
        var gamIdx = 0

        for token in schedule.uppercased() {
            switch token {
            case "L":
                if let listing = listingsIter.next() {
                    out.append(.listing(listing))
                }
            case "G":
                if let zone = Self.pickZone(gamZones, idx: gamIdx) {
                    out.append(.gamAd(zoneId: zone))
                    gamIdx += 1
                }
            case "D":
                if let zone = Self.pickZone(gamZones, idx: gamIdx) {
                    out.append(.directAd(zoneId: zone))
                    gamIdx += 1
                }
            case "B":
                if !bannerZone.isEmpty {
                    out.append(.banner(zoneId: bannerZone))
                }
            default:
                break
            }
        }
        return out
    }

    // MARK: Helpers

    fileprivate func openURL(_ urlString: String?) {
        guard let s = urlString, let url = URL(string: s), let vc = nearestViewController() else { return }
        let safari = SFSafariViewController(url: url)
        vc.present(safari, animated: true)
    }

    fileprivate func handleListingTap(_ listing: SellwildListing) {
        let handled = delegate?.sellwildFeed(self, didTapListing: listing) ?? false
        if !handled {
            openURL(listing.tapURL(partnerCode: config.partnerCode, bhTag: config.bhTag))
        }
    }

    fileprivate func handleAdImpression(_ zoneId: String) {
        delegate?.sellwildFeed(self, didRecordAdImpressionForZoneId: zoneId)
    }

    fileprivate func handleAdClick(_ zoneId: String) {
        delegate?.sellwildFeed(self, didRecordAdClickForZoneId: zoneId)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    // MARK: Statics

    private static let defaultSchedule = "LLGLLGLLG"

    private static func normalizeSchedule(_ raw: String?) -> String {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return s.isEmpty ? defaultSchedule : s
    }

    fileprivate static func pickZone(_ zones: [String], idx: Int) -> String? {
        guard !zones.isEmpty else { return nil }
        return zones[idx % zones.count]
    }

    fileprivate static func parseColor(_ hex: String?) -> UIColor? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 6 {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8)  & 0xFF) / 255
            b = CGFloat( v        & 0xFF) / 255
            a = 1
        } else {
            r = CGFloat((v >> 24) & 0xFF) / 255
            g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8)  & 0xFF) / 255
            a = CGFloat( v        & 0xFF) / 255
        }
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SellwildFeedView: UITableViewDataSource, UITableViewDelegate {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        switch row {
        case .header:
            let cell = tableView.dequeueReusableCell(withIdentifier: HeaderCell.reuseId, for: indexPath) as! HeaderCell
            cell.configure(config: config, onTitleTap: { [weak self] in
                if let url = self?.config.partnerUrl { self?.openURL(url) }
            }, onPoweredByTap: { [weak self] in
                self?.openURL("https://sellwild.com")
            })
            return cell
        case .listing(let listing):
            let cell = tableView.dequeueReusableCell(withIdentifier: ListingCardCell.reuseId, for: indexPath) as! ListingCardCell
            cell.configure(config: config, listing: listing)
            return cell
        case .gamAd(let zone), .directAd(let zone):
            let cell = tableView.dequeueReusableCell(withIdentifier: AdRowCell.reuseId, for: indexPath) as! AdRowCell
            cell.configure(config: config, adSize: .mrec300x250, zoneId: zone, owner: self)
            return cell
        case .banner(let zone):
            let cell = tableView.dequeueReusableCell(withIdentifier: AdRowCell.reuseId, for: indexPath) as! AdRowCell
            cell.configure(config: config, adSize: .banner320x50, zoneId: zone, owner: self)
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

    required init?(coder: NSCoder) { fatalError() }

    func configure(config: SellwildConfig, onTitleTap: @escaping () -> Void, onPoweredByTap: @escaping () -> Void) {
        titleLabel.text = config.title ?? "Marketplace"
        titleLabel.textColor = SellwildFeedView.parseColor(config.titleColor) ?? .white
        poweredByLabel.textColor = SellwildFeedView.parseColor(config.linkColor) ?? UIColor(white: 0.7, alpha: 1)
        self.onTitleTap = onTitleTap
        self.onPoweredByTap = onPoweredByTap
    }

    @objc private func titleTapped() { onTitleTap?() }
    @objc private func poweredByTapped() { onPoweredByTap?() }
}

// MARK: - ListingCardCell (full-bleed photo, title, price, seller line)

private final class ListingCardCell: UITableViewCell {
    static let reuseId = "SellwildFeedListingCardCell"

    private let card = UIView()
    private let photoView = UIImageView()
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private let sellerLabel = UILabel()
    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.clipsToBounds = true

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

        contentView.addSubview(card)
        card.addSubview(photoView)
        card.addSubview(titleLabel)
        card.addSubview(priceLabel)
        card.addSubview(sellerLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            photoView.topAnchor.constraint(equalTo: card.topAnchor),
            photoView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            photoView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            photoView.heightAnchor.constraint(equalToConstant: 200),

            titleLabel.topAnchor.constraint(equalTo: photoView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            priceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            priceLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            priceLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            sellerLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 6),
            sellerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            sellerLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            sellerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentImageURL = nil
        photoView.image = nil
        photoView.backgroundColor = UIColor(white: 0.93, alpha: 1)
    }

    func configure(config: SellwildConfig, listing: SellwildListing) {
        titleLabel.text = listing.title
        priceLabel.text = Self.formatPrice(currency: listing.currency, price: listing.price)
        priceLabel.textColor = SellwildFeedView.parseColor(config.linkColor) ?? UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
        sellerLabel.text = Self.formatSeller(listing.user)
        loadImage(listing.photos?.first?.url)
    }

    private func loadImage(_ urlString: String?) {
        currentImageURL = urlString
        guard let s = urlString, !s.isEmpty else { return }
        if let cached = Self.cache.object(forKey: s as NSString) {
            photoView.image = cached
            return
        }
        if s.hasPrefix("data:") {
            // data: URI — decode synchronously off-thread.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let bytes = Self.decodeDataURI(s), let image = UIImage(data: bytes) else { return }
                Self.cache.setObject(image, forKey: s as NSString)
                DispatchQueue.main.async {
                    guard let self = self, self.currentImageURL == s else { return }
                    self.photoView.image = image
                }
            }
            return
        }
        guard let url = URL(string: s) else { return }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            Self.cache.setObject(image, forKey: s as NSString)
            DispatchQueue.main.async {
                guard let self = self, self.currentImageURL == s else { return }
                self.photoView.image = image
            }
        }
        imageTask = task
        task.resume()
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()

    private static func decodeDataURI(_ s: String) -> Data? {
        guard let comma = s.firstIndex(of: ",") else { return nil }
        let payload = String(s[s.index(after: comma)...])
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }

    private static func formatPrice(currency: String?, price: String?) -> String {
        guard let p = price, let value = Double(p) else { return "" }
        let sym: String
        switch currency?.uppercased() {
        case "EUR": sym = "€"
        case "GBP": sym = "£"
        default:    sym = "$"
        }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(sym)\(Int(value))"
            : String(format: "%@%.2f", sym, value)
    }

    private static func formatSeller(_ user: SellwildUser?) -> String {
        guard let u = user else { return "sellwild.com" }
        let firstRaw = (u.firstName ?? "").trimmingCharacters(in: .whitespaces)
        let first = firstRaw.isEmpty ? "SELLER" : firstRaw.uppercased()
        let lastInit = (u.lastName ?? "").first.map { String($0).uppercased() }
        let name = lastInit.map { "\(first) \($0)." } ?? first
        return "\(name)  |  sellwild.com"
    }
}

// MARK: - AdRowCell (wraps SellwildAdView)

private final class AdRowCell: UITableViewCell, SellwildAdViewDelegate {
    static let reuseId = "SellwildFeedAdRowCell"

    private var adView: SellwildAdView?
    private var boundZoneId: String?
    private weak var owner: SellwildFeedView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(config: SellwildConfig, adSize: AdSize, zoneId: String, owner: SellwildFeedView) {
        self.owner = owner
        if boundZoneId == zoneId, adView != nil { return }
        boundZoneId = zoneId
        adView?.removeFromSuperview()

        let ad = SellwildAdView(config: config, adSize: adSize, zoneId: zoneId)
        // Inherit ad-stack from CDN config so feed ads respect AD_STACK / AD_STACK_BY_ZONE
        ad.adStackOverride = SellwildAdStack.resolve(
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            override: nil
        )
        ad.translatesAutoresizingMaskIntoConstraints = false
        ad.delegate = self
        contentView.addSubview(ad)
        NSLayoutConstraint.activate([
            ad.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            ad.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            ad.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            ad.widthAnchor.constraint(equalToConstant: adSize.cgSize.width),
            ad.heightAnchor.constraint(equalToConstant: adSize.cgSize.height),
        ])
        adView = ad
        ad.load()
    }

    // MARK: SellwildAdViewDelegate

    func sellwildAdView(_ adView: SellwildAdView, didReceiveImpressionForZoneId zoneId: String) {
        owner?.handleAdImpression(zoneId)
    }

    func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error) { /* swallow */ }

    func sellwildAdViewDidRecordClick(_ adView: SellwildAdView) {
        if let z = boundZoneId { owner?.handleAdClick(z) }
    }
}
