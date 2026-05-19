package com.sellwild.sdk.docs

import com.sellwild.sdk.PrebidServerConfig
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.SellwildPhoto
import org.junit.Test

/**
 * Compiles every Kotlin block from docs-site/guide/android.md + quick-start.md
 * against the real Sellwild Android SDK. JVM-only — UI types (Activity, Compose,
 * View) are covered by androidTest source set verification done separately.
 *
 * Failures here mean docs reference APIs that don't exist or have wrong signatures.
 */
class DocsVerifyKotlinTest {

    // [Block 6] android.md:L448 — SellwildListing reference (data class is on classpath; we just touch known accessors)
    @Test
    fun `android_md L448 SellwildListing reference`() {
        val photo = SellwildPhoto(url = "https://example.com/p.jpg", thumbUrl = "https://example.com/p_thumb.jpg")
        val listing = SellwildListing(
            id = "1",
            status = "active",
            title = "Widget",
            price = "10",
            currency = "USD",
            photos = listOf(photo),
            url = "https://example.com/l/1",
        )
        val _displayPrice: String? = listing.displayPrice
        val _primary: String? = listing.primaryPhotoUrl
    }

    // [Block 10] android.md:L673 — PrebidServerConfig kwargs
    @Test
    fun `android_md L673 PrebidServerConfig`() {
        val prebidServer = PrebidServerConfig(
            accountId = "sellwild",
            endpoint = "https://prebid.sellwild.com/openrtb2/auction",
            bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx"),
            timeout = 1500,
            syncEndpoint = "https://prebid.sellwild.com/cookie_sync",
        )
        require(prebidServer.accountId == "sellwild")
    }

    // [Block 11] android.md:L718 — config with gpp + tcf + prebid
    @Test
    fun `android_md L718 SellwildConfig with privacy`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            listingsUrl = "https://your-cms-or-cache.example.com/listings.json",
            appBundleId = "com.aws.android",
            gppEnabled = true,
            tcfVersion = 2,
            prebidServer = PrebidServerConfig(
                accountId = "sellwild",
                endpoint = "https://prebid.sellwild.com/openrtb2/auction",
                bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx"),
            ),
        )
        require(config.gppEnabled && config.tcfVersion == 2)
    }

    // [Block 14] android.md:L803 — config with refresh tuning
    @Test
    fun `android_md L803 SellwildConfig with refresh`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            listingsUrl = "https://your-cms-or-cache.example.com/listings.json",
            appBundleId = "com.aws.android",
            adRefreshMaxMobile = 10,
            adRefreshIntervalMs = 30_000L,
            prebidServer = PrebidServerConfig(
                accountId = "sellwild",
                endpoint = "https://prebid.sellwild.com/openrtb2/auction",
                bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx"),
            ),
        )
        require(config.adRefreshMaxMobile == 10)
    }

    // [Block 18] quick-start.md:L194 — minimal manual config (packageName placeholder)
    @Test
    fun `quick_start_md L194 minimal SellwildConfig`() {
        val packageName = "com.example.myapp"
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            listingsUrl = "https://your-cms-or-cache.example.com/listings.json",
            appBundleId = packageName,
        )
        require(config.partnerCode == "weatherbug")
    }
}
