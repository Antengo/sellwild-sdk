package com.sellwild.sample

/**
 * Stable element ids for the Maestro flows (e2e/maestro). The one list is
 * contracts/e2e/ids.json: add an id there first, and never rename one.
 *
 * The app sets them with Modifier.testTag. SampleApp turns on testTagsAsResourceId,
 * so UI Automator (and Maestro) reads each tag as the element's resource-id.
 */
object SampleIds {
    // Tabs
    const val TAB_FEED = "sw.tab.feed"
    const val TAB_ADS = "sw.tab.ads"
    const val TAB_LISTINGS = "sw.tab.listings"
    const val TAB_DIAGNOSTICS = "sw.tab.diagnostics"

    // Feed. The SDK feed sets sw.listing.card and sw.feed.ad on its own rows.
    const val FEED_LIST = "sw.feed.list"
    const val FEED_STATUS = "sw.feed.status"

    // Ads
    const val AD_BANNER = "sw.ad.banner"
    const val AD_BANNER_SIZE = "sw.ad.banner.size"
    const val AD_MREC = "sw.ad.mrec"
    const val AD_MREC_SIZE = "sw.ad.mrec.size"
    const val AD_NATIVE = "sw.ad.native"
    const val AD_NATIVE_SIZE = "sw.ad.native.size"

    // Listings
    const val LISTINGS_LIST = "sw.listings.list"
    const val LISTINGS_REFRESH = "sw.listings.refresh"
    const val LISTINGS_STATUS = "sw.listings.status"
    const val LISTING_CARD = "sw.listing.card"

    // Diagnostics
    const val DIAG_SDK_VERSION = "sw.diag.sdk_version"
    const val DIAG_PARTNER = "sw.diag.partner"
    const val DIAG_CONFIG_SOURCE = "sw.diag.config_source"
    const val DIAG_LISTINGS_URL = "sw.diag.listings_url"
    const val DIAG_FAILURES = "sw.diag.failures"
    const val DIAG_FAILURE_CONTEXT = "sw.diag.failure_context"
}
