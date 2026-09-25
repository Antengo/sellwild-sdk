/// Stable element ids for the Maestro flows (e2e/maestro). The one list is
/// contracts/e2e/ids.json: add an id there first, and never rename one.
enum SampleID {
    // Tabs
    static let tabFeed = "sw.tab.feed"
    static let tabAds = "sw.tab.ads"
    static let tabListings = "sw.tab.listings"
    static let tabDiagnostics = "sw.tab.diagnostics"

    // Feed
    static let feedList = "sw.feed.list"
    static let feedStatus = "sw.feed.status"

    // Ads
    static let adBanner = "sw.ad.banner"
    static let adBannerSize = "sw.ad.banner.size"
    static let adMrec = "sw.ad.mrec"
    static let adMrecSize = "sw.ad.mrec.size"
    static let adNative = "sw.ad.native"
    static let adNativeSize = "sw.ad.native.size"

    // Listings
    static let listingsList = "sw.listings.list"
    static let listingsRefresh = "sw.listings.refresh"
    static let listingsStatus = "sw.listings.status"
    static let listingCard = "sw.listing.card"

    // Diagnostics
    static let diagSdkVersion = "sw.diag.sdk_version"
    static let diagPartner = "sw.diag.partner"
    static let diagConfigSource = "sw.diag.config_source"
    static let diagListingsUrl = "sw.diag.listings_url"
    static let diagFailures = "sw.diag.failures"
    static let diagFailureContext = "sw.diag.failure_context"
}
