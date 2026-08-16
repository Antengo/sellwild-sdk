// SellwildHouseAdView.swift — renders the house-ad backdrop.
//
// Two content modes, driven by `SellwildHouseAd.resolve` precedence:
//   - image:   a CMS-configured house creative (aspect-fit, full-bleed into the
//              slot; creatives are designed to the slot).
//   - listing: a Sellwild listing rendered as a compact card that mirrors the
//              feed's `ListingCardCell` — white card, photo on top, title + price
//              below. Used when no image is configured. Supplied by the feed;
//              only meaningful for the MREC slot (a 320x50 banner is too small).
//
// The view sits BEHIND the paid creative in `SellwildAdView` and is shown only
// when that creative is absent (no-fill). `SellwildAdView` hides it on paid
// fill, so a transparent or undersized creative can't let it bleed through. A
// tap opens the creative's click URL (or the listing's tap URL) via the owner.

import UIKit

final class SellwildHouseAdView: UIView {

    /// Invoked when the house ad is tapped. The owner routes this to the
    /// creative's click URL (image mode) or the listing's tap URL.
    var onTap: (() -> Void)?

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()

    // The image URL currently being loaded. Guards against a reused view (the
    // owning SellwildAdView is pooled in feed cells) applying a stale async
    // image after the content was swapped — the feed's own cell guards the same
    // way via `currentImageURL`.
    private var pendingImageURL: String?

    // Full-bleed (image mode) vs card (listing mode) layout, toggled per content.
    private var fullBleedConstraints: [NSLayoutConstraint] = []
    private var cardConstraints: [NSLayoutConstraint] = []

    // Card-mode price color — matches ListingCardCell's default link/price blue.
    private static let priceColor = UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
    private static let titleColor = UIColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 12

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.clipsToBounds = true
        addSubview(imageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = Self.titleColor
        titleLabel.numberOfLines = 2
        titleLabel.isHidden = true
        addSubview(titleLabel)

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.font = .systemFont(ofSize: 18, weight: .bold)
        priceLabel.textColor = Self.priceColor
        priceLabel.isHidden = true
        addSubview(priceLabel)

        // Common: image pinned to the top edges in both modes.
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Image mode: photo fills the whole slot.
        fullBleedConstraints = [
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        // Card mode: photo occupies the top ~60% of the slot; title + price sit
        // on the white card below it (mirrors ListingCardCell's stacking).
        cardConstraints = [
            imageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            priceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            priceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            priceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ]

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    @objc private func tapped() { onTap?() }

    /// Render a CMS house image (aspect-fit; creatives are designed to the slot).
    func showImage(_ creative: SellwildHouseAdCreative) {
        setCardLayout(false)
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        loadImage(creative.imageURL)
    }

    /// Render a Sellwild listing as a compact card (photo on top, title + price
    /// below on a white card) so it reads like the feed's listing cards.
    func showListing(_ listing: SellwildListing, config: SellwildConfig) {
        setCardLayout(true)
        backgroundColor = .white
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor(white: 0.93, alpha: 1)
        titleLabel.text = listing.title
        priceLabel.text = Self.formatPrice(currency: listing.currency, price: listing.price)
        loadImage(listing.photos?.first?.url)
    }

    /// Switch between full-bleed (image) and card (listing) layout, showing the
    /// title/price chrome only in card mode.
    private func setCardLayout(_ card: Bool) {
        titleLabel.isHidden = !card
        priceLabel.isHidden = !card
        NSLayoutConstraint.deactivate(card ? fullBleedConstraints : cardConstraints)
        NSLayoutConstraint.activate(card ? cardConstraints : fullBleedConstraints)
    }

    /// Load `urlString` into the image view, ignoring a result that arrives after
    /// the content was swapped (reused view). Clears any prior image first so a
    /// stale photo never lingers under new content.
    private func loadImage(_ urlString: String?) {
        pendingImageURL = urlString
        imageView.image = nil
        guard let urlString, !urlString.isEmpty else { return }
        SellwildHouseAd.loadImage(urlString) { [weak self] image in
            guard let self, self.pendingImageURL == urlString else { return }
            self.imageView.image = image
        }
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
}
