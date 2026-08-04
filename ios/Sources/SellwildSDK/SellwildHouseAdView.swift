// SellwildHouseAdView.swift — renders the house-ad backdrop.
//
// Two content modes, driven by `SellwildHouseAd.resolve` precedence:
//   - image:   a CMS-configured house creative (aspect-fit into the slot).
//   - listing: a Sellwild listing card (full-bleed photo + title/price overlay),
//              used when no image is configured. Supplied by the feed; only
//              meaningful for the MREC slot (a 320x50 banner is too small).
//
// The view sits BEHIND the paid creative in `SellwildAdView` and is only ever
// seen when that creative is absent. A tap opens the creative's click URL (or
// the listing's tap URL) via the owning ad view.

import UIKit

final class SellwildHouseAdView: UIView {

    /// Invoked when the house ad is tapped. The owner routes this to the
    /// creative's click URL (image mode) or the listing's tap URL.
    var onTap: (() -> Void)?

    private let imageView = UIImageView()
    private let gradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 12

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.clipsToBounds = true
        addSubview(imageView)

        // Bottom scrim so overlaid text stays legible on any listing photo. Only
        // shown in listing mode.
        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.65).cgColor]
        gradient.isHidden = true
        layer.addSublayer(gradient)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.isHidden = true
        addSubview(titleLabel)

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.font = .systemFont(ofSize: 15, weight: .bold)
        priceLabel.textColor = .white
        priceLabel.isHidden = true
        addSubview(priceLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            priceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            priceLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: priceLabel.topAnchor, constant: -2),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = CGRect(x: 0, y: bounds.height * 0.5, width: bounds.width, height: bounds.height * 0.5)
    }

    @objc private func tapped() { onTap?() }

    /// Render a CMS house image (aspect-fit; creatives are designed to the slot).
    func showImage(_ creative: SellwildHouseAdCreative) {
        setListingChrome(visible: false)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        SellwildHouseAd.loadImage(creative.imageURL) { [weak self] image in
            self?.imageView.image = image
        }
    }

    /// Render a Sellwild listing as the house ad (full-bleed photo + overlay).
    func showListing(_ listing: SellwildListing, config: SellwildConfig) {
        setListingChrome(visible: true)
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor(white: 0.93, alpha: 1)
        titleLabel.text = listing.title
        priceLabel.text = Self.formatPrice(currency: listing.currency, price: listing.price)
        if let urlString = listing.photos?.first?.url {
            SellwildHouseAd.loadImage(urlString) { [weak self] image in
                self?.imageView.image = image
            }
        }
    }

    private func setListingChrome(visible: Bool) {
        gradient.isHidden = !visible
        titleLabel.isHidden = !visible
        priceLabel.isHidden = !visible
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
