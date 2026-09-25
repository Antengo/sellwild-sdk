package com.sellwild.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.ResultCode
import com.sellwild.prebid.SellwildPrebid
import com.sellwild.prebid.TargetingParams
import com.sellwild.prebid.api.data.InitializationStatus
import com.sellwild.sdk.SellwildAdSizes.Size
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.plain
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * The Prebid Mobile bridge: bootstrap, the .both auction and the ORTB and eid plumbing, on
 * Robolectric with a fake ad network, so no GMA or Prebid call reaches a device or the network.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildPrebidMobileTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents

    @Before
    fun capture() {
        events = CapturedEvents().install()
    }

    private fun globalOrtb(): Any? = TargetingParams.getGlobalOrtbConfig()?.let { plain(JSONObject(it)) }

    // ── Resolvers ────────────────────────────────────────────────────────────

    @Test
    fun `the Prebid Server is the typed config, else an S2S_CONFIG object, else Sellwild's`() {
        val typed = SellwildConfig(
            partnerCode = "weatherbug",
            prebidServer = PrebidServerConfig("abc-123", "https://prebid.example.com/openrtb2/auction", listOf("appnexus")),
        )
        val s2s = AppConfigFactory.checked(
            mapOf("S2S_CONFIG" to JSONObject().put("endpoint", "https://prebid-cdn.example.com/openrtb2/auction").put("accountId", "cdn-account")),
        )
        val s2sAlternateKeys = AppConfigFactory.checked(mapOf("S2S_CONFIG" to JSONObject().put("url", "https://pbs.example.com/a").put("account", "acct-2")))
        val s2sEmpty = AppConfigFactory.checked(mapOf("S2S_CONFIG" to JSONObject()))

        val fromTyped = SellwildPrebidMobile.resolvePrebidServer(typed, s2s)
        val fromS2s = SellwildPrebidMobile.resolvePrebidServer(SellwildConfig(partnerCode = "weatherbug"), s2s)
        val fromAlternate = SellwildPrebidMobile.resolvePrebidServer(SellwildConfig(partnerCode = "weatherbug"), s2sAlternateKeys)
        val fromEmpty = SellwildPrebidMobile.resolvePrebidServer(SellwildConfig(partnerCode = "weatherbug"), s2sEmpty)
        // The CMS text form is not read (known drift, drift/android.json).
        val fromText = SellwildPrebidMobile.resolvePrebidServer(SellwildConfig(partnerCode = "weatherbug"), AppConfigFactory.checked(mapOf("S2S_CONFIG" to "{ accountId: 'x' }")))

        assertEquals("https://prebid.example.com/openrtb2/auction" to "abc-123", fromTyped.url to fromTyped.accountId)
        assertEquals("https://prebid-cdn.example.com/openrtb2/auction" to "cdn-account", fromS2s.url to fromS2s.accountId)
        assertEquals("https://pbs.example.com/a" to "acct-2", fromAlternate.url to fromAlternate.accountId)
        assertEquals("https://prebid.sellwild.com/openrtb2/auction" to "weatherbug", fromEmpty.url to fromEmpty.accountId)
        assertEquals("https://prebid.sellwild.com/openrtb2/auction" to "weatherbug", fromText.url to fromText.accountId)
    }

    @Test
    fun `the publisher id is PUBLISHER_ID, else SELLER_ID, else none`() {
        assertEquals("pub-1", SellwildPrebidMobile.resolvePublisherId(AppConfigFactory.checked(mapOf("PUBLISHER_ID" to "pub-1", "SELLER_ID" to "s"))))
        assertEquals("seller-9", SellwildPrebidMobile.resolvePublisherId(AppConfigFactory.checked(mapOf("PUBLISHER_ID" to "", "SELLER_ID" to "seller-9"))))
        assertNull(SellwildPrebidMobile.resolvePublisherId(AppConfigFactory.checked()))
        assertNull(SellwildPrebidMobile.resolvePublisherId(null))
    }

    @Test
    fun `the imp ext lower-cases bidders and skips null params`() {
        assertNull(SellwildPrebidMobile.ortbExtJson(emptyMap()))

        val json = SellwildPrebidMobile.ortbExtJson(
            mapOf("MEDIANET" to JSONObject().put("cid", "8CU9V99R6"), "AMX" to null),
            gpid = "/1/feed#2",
        )

        val ext = JSONObject(checkNotNull(json)).getJSONObject("ext")
        assertEquals(setOf("medianet"), ext.getJSONObject("prebid").getJSONObject("bidder").keys().asSequence().toSet())
        assertEquals("/1/feed#2", ext.getString("gpid"))
    }

    // ── Bootstrap ────────────────────────────────────────────────────────────

    @Test
    fun `bootstrap starts GMA and Prebid once, with the resolved server and ORTB`() {
        val remote = AppConfigFactory.checked(
            mapOf(
                "PUBLISHER_ID" to "pub-1",
                "S2S_CONFIG" to JSONObject().put("endpoint", "https://pbs.example.com/a").put("accountId", "acct"),
            ),
        )
        val config = configFrom(remote).copy(
            iabCats = listOf("IAB15"),
            geo = SellwildGeo(state = "GA"),
            debug = true,
            appBundleId = "com.fixture",
            appStoreUrl = "https://play.google.com/store/apps/details?id=com.fixture",
        )

        assertTrue(SellwildPrebidMobile.bootstrap(context, config))
        assertTrue(SellwildPrebidMobile.bootstrap(context, config))

        assertEquals(listOf(context.applicationContext), ads.network.gmaInits.toList())
        assertEquals(listOf("https://pbs.example.com/a"), ads.network.prebidHosts.toList())
        assertEquals("acct", SellwildPrebid.getPrebidServerAccountId())
        assertEquals("com.fixture", TargetingParams.getBundleName())
        assertEquals(
            mapOf("app" to mapOf("publisher" to mapOf("id" to "pub-1"), "cat" to listOf("IAB15")), "device" to mapOf("geo" to mapOf("region" to "GA"))),
            globalOrtb(),
        )
        assertEquals(SellwildGeo(state = "GA"), SellwildGeoStore.current)
        assertFalse(SellwildPrebidMobile.isReady())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `Prebid is ready when init finishes, and a status other than SUCCEEDED is reported once`() {
        SellwildPrebidMobile.bootstrap(context, SellwildConfig(partnerCode = "fixture"))

        ads.network.finishPrebidInit(InitializationStatus.FAILED)

        assertTrue(SellwildPrebidMobile.isReady())
        val attributes = events.attributes(SellwildFailureCode.AD_PREBID_INIT_INVALID)
        assertEquals("warn", attributes.getString("severity"))
        assertTrue(attributes.getString("msg").startsWith("Prebid init finished with status FAILED"))
    }

    @Test
    fun `a typed Prebid Server sets the host and the auction timeout`() {
        val config = SellwildConfig(
            partnerCode = "fixture",
            prebidServer = PrebidServerConfig("abc-123", "https://prebid.example.com/openrtb2/auction", listOf("appnexus"), timeout = 900),
        )

        SellwildPrebidMobile.bootstrap(context, config)

        assertEquals(listOf("https://prebid.example.com/openrtb2/auction"), ads.network.prebidHosts.toList())
        assertEquals(900, SellwildPrebid.getTimeoutMillis())
        assertEquals("abc-123", SellwildPrebid.getPrebidServerAccountId())
    }

    @Test
    fun `init that finishes with no status is ready, and reported once`() {
        SellwildPrebidMobile.bootstrap(context, SellwildConfig(partnerCode = "fixture"))

        ads.network.finishPrebidInit(null)

        assertTrue(SellwildPrebidMobile.isReady())
        assertEquals("Prebid init finished with status null", events.attributes(SellwildFailureCode.AD_PREBID_INIT_INVALID).getString("msg"))
    }

    @Test
    fun `with debug on the init status is traced`() {
        com.sellwild.sdk.failures.SellwildFailures.setContext { it.copy(debug = true) }

        ads.prebidReady(context)

        assertTrue(failures.lines.contains("SellwildPrebid.initializeSdk status: SUCCEEDED"))
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `init that succeeded reports nothing`() {
        ads.prebidReady(context)

        assertTrue(SellwildPrebidMobile.isReady())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `GMA init that throws is reported, and Prebid still starts`() {
        ads.network.gmaError = IllegalStateException("MobileAds is missing its app id")

        assertTrue(SellwildPrebidMobile.bootstrap(context, SellwildConfig(partnerCode = "fixture")))

        val attributes = events.attributes(SellwildFailureCode.AD_GMA_INIT_EXCEPTION)
        assertEquals("fatal", attributes.getString("severity"))
        assertEquals("IllegalStateException", attributes.getString("errName"))
        assertEquals(1, ads.network.prebidHosts.size)
    }

    @Test
    fun `Prebid init that throws is reported with the server host, and the stack stays not ready`() {
        ads.network.prebidError = IllegalArgumentException("bad host")

        assertTrue(SellwildPrebidMobile.bootstrap(context, SellwildConfig(partnerCode = "fixture")))

        val attributes = events.attributes(SellwildFailureCode.AD_PREBID_INIT_EXCEPTION)
        assertEquals("prebid.sellwild.com", attributes.getString("host"))
        assertFalse(SellwildPrebidMobile.isReady())
    }

    @Test
    fun `remote config that does not parse is reported once and bootstrap falls back`() {
        SellwildPrebidMobile.bootstrap(context, SellwildConfig(partnerCode = "fixture", remoteJson = "{not json"))

        events.single(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE)
        assertEquals(listOf("https://prebid.sellwild.com/openrtb2/auction"), ads.network.prebidHosts.toList())
    }

    @Test
    fun `a geo already set is kept over the config's`() {
        SellwildGeoStore.current = SellwildGeo(state = "AL")

        SellwildPrebidMobile.bootstrap(context, SellwildConfig(partnerCode = "fixture", geo = SellwildGeo(state = "GA")))

        assertEquals("AL", SellwildGeoStore.current?.state)
    }

    // ── The .both auction ────────────────────────────────────────────────────

    @Test
    fun `the banner auction builds the unit, then GAM loads with the same request whatever Prebid says`() {
        val view = AdManagerAdView(context)
        val results = mutableListOf<ResultCode>()

        SellwildPrebidMobile.runBannerAuction(
            adView = view,
            configId = "43",
            widthDp = 300,
            heightDp = 250,
            bidderParams = mapOf("MEDIANET" to JSONObject().put("cid", "c")),
            adSizes = listOf(Size(300, 250), Size(320, 50)),
            gpid = "/1/feed",
            completion = { results += it },
        )

        val auction = ads.network.bannerAuctions.single()
        @Suppress("DEPRECATION")
        assertEquals(2, auction.unit.configuration.sizes.size)
        assertEquals(setOf("medianet") to "/1/feed", impExt(auction.unit.impOrtbConfig))
        assertTrue(ads.network.gamLoads.isEmpty())

        auction.finish(ResultCode.NO_BIDS)

        assertSame(view, ads.network.gamLoads.single())
        assertSame(auction.request, ads.network.gamRequests.single())
        assertEquals(listOf(ResultCode.NO_BIDS), results)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a video auction asks for banner and video, and a plain one sets no imp ext`() {
        SellwildPrebidMobile.runBannerAuction(AdManagerAdView(context), "43", 300, 250, video = true)
        SellwildPrebidMobile.runBannerAuction(AdManagerAdView(context), "44", 320, 50)

        val (video, plain) = ads.network.bannerAuctions.toList()
        assertEquals(listOf("video/mp4"), video.unit.configuration.videoParameters?.mimes)
        assertNull(plain.unit.configuration.videoParameters)
        assertNull(plain.unit.impOrtbConfig)
        plain.finish(ResultCode.SUCCESS)
        assertEquals(1, ads.network.gamLoads.size)
    }

    @Test
    fun `an auction that fails for a reason other than no bids is reported once`() {
        SellwildPrebidMobile.runBannerAuction(AdManagerAdView(context), "43", 300, 250)

        ads.network.bannerAuctions.single().finish(ResultCode.INVALID_CONFIG_ID)

        val event = events.single(SellwildFailureCode.AD_PREBID_AUCTION_INVALID)
        assertEquals("banner", event.getString("label"))
        assertEquals("Prebid auction result INVALID_CONFIG_ID", event.getJSONObject("attributes").getString("msg"))
        assertEquals("43", event.getJSONObject("attributes").getString("zoneId"))
        assertEquals(1, ads.network.gamLoads.size)
    }

    // ── ORTB and eids ────────────────────────────────────────────────────────

    @Test
    fun `setGeo stores the geo and re-emits it with the publisher id`() {
        SellwildPrebidMobile.bootstrap(context, configFrom(AppConfigFactory.checked(mapOf("PUBLISHER_ID" to "pub-1"))))

        SellwildPrebidMobile.setGeo(SellwildGeo(state = "TX"))
        assertEquals(mapOf("app" to mapOf("publisher" to mapOf("id" to "pub-1")), "device" to mapOf("geo" to mapOf("region" to "TX"))), globalOrtb())

        SellwildPrebidMobile.setGeo(null)
        assertNull(SellwildGeoStore.current)
        assertEquals(mapOf("app" to mapOf("publisher" to mapOf("id" to "pub-1"))), globalOrtb())
    }

    @Test
    fun `external ids reach Prebid, merged with GrowthCode's, the partner's winning a shared source`() {
        SellwildEidRegistry.setGrowthCode(
            listOf(SellwildEid("growthcode.io", listOf(SellwildEidUid("gc", 1))), SellwildEid("uidapi.com", listOf(SellwildEidUid("gc-uid2", 3)))),
        )

        SellwildPrebidMobile.setExternalUserIds(
            listOf(SellwildEid("uidapi.com", listOf(SellwildEidUid("partner-uid2", 3, ext = mapOf("rtiPartner" to "UID2"))))),
        )

        val eids = TargetingParams.getExternalUserIds()
        assertEquals(listOf("uidapi.com", "growthcode.io"), eids.map { it.source })
        assertEquals("partner-uid2", eids.first().uniqueIds.single().id)
        assertEquals("UID2", checkNotNull(eids.first().uniqueIds.single().json).getJSONObject("ext").getString("rtiPartner"))
        SellwildPrebidMobile.setExternalUserIds(emptyList())
        SellwildEidRegistry.setGrowthCode(emptyList())
        assertTrue(TargetingParams.getExternalUserIds().isEmpty())
    }

    @Test
    fun `resetting for tests forgets readiness and the network`() {
        ads.prebidReady(context)

        SellwildPrebidMobile.resetForTesting()

        assertFalse(SellwildPrebidMobile.isReady())
        assertSame(LiveAdNetwork, SellwildPrebidMobile.network)
        SellwildPrebidMobile.network = ads.network
    }
}
