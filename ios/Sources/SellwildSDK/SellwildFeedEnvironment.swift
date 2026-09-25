import UIKit
import SafariServices

// SellwildFeedView's seams and fixed names. They live apart from the view
// because SellwildFeedView.swift may not grow (its SwiftLint file_length
// baseline).

// MARK: - Environment

extension SellwildFeedView {
    /// What the feed calls outside itself. Partners always get `live`; tests
    /// set `SellwildFeedView.environment` before they make feeds.
    struct Environment {
        /// A listings client for one feed (each feed keeps its own cache).
        var makeAPIClient: () -> SellwildAPIClient
        /// The ad view of an ad row.
        var makeAdView: (SellwildConfig, AdSize, String?) -> SellwildAdView
        /// Shows a listing or partner page over `from`.
        var present: (URL, UIViewController) -> Void
        /// Where listing photos download from.
        var imageSession: URLSession

        static let live = Environment(
            makeAPIClient: { SellwildAPIClient() },
            makeAdView: SellwildAdView.init(config:adSize:zoneId:),
            present: presentSafari,
            imageSession: .shared
        )

        /// SFSafariViewController over the app. It loads the page from the
        /// network, so it never runs in tests.
        static let presentSafari: (URL, UIViewController) -> Void = { url, viewController in
            viewController.present(SFSafariViewController(url: url), animated: true)
        }
    }

    static var environment = Environment.live

    /// Accessibility identifiers on the feed's rows, so UI tests (the sample
    /// apps' Maestro flows, a partner's XCUITest) can find them. They are
    /// listed in contracts/e2e/ids.json; never rename one.
    static let listingCardAccessibilityID = "sw.listing.card"
    static let adRowAccessibilityID = "sw.feed.ad"
}
