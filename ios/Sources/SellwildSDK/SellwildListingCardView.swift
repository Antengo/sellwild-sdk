import UIKit

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
            sellerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
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
        priceLabel.textColor = SellwildFormat.color(config.linkColor)
            ?? UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
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
