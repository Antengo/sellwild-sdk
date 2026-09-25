package com.sellwild.sdk.core

import com.sellwild.sdk.AppnexusConfig
import com.sellwild.sdk.IxConfig
import com.sellwild.sdk.OpenxConfig
import com.sellwild.sdk.PrebidServerConfig
import com.sellwild.sdk.PubmaticConfig
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildSDK
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.BridgeMessageFactory
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The widget page (WidgetPage) and its bridge messages (WidgetBridge), pure. */
class WidgetPageTest {

    private fun lines(attributes: String): List<String> = attributes.split("\n    ")

    /** The JSON object in attribute [name] (quotes written as &quot;), as a map. */
    private fun json(attrs: List<String>, name: String): Map<String, Any> {
        val value = attrs.single { it.startsWith("$name=\"") }.removePrefix("$name=\"").removeSuffix("\"").replace("&quot;", "\"")
        val obj = org.json.JSONObject(value)
        return obj.keys().asSequence().associateWith { obj.get(it) }
    }

    @Test
    fun `a bare config gets the partner, the default listings, customize off and PrebidOnly`() {
        val attrs = lines(WidgetPage.attributes(SellwildConfig(partnerCode = "weatherbug"), null))

        assertEquals("partner-code=\"weatherbug\"", attrs[0])
        assertTrue(attrs[1].startsWith("listings=\""))
        assertEquals(listOf("customize=\"false\"", "ad-type=\"PrebidOnly\""), attrs.subList(2, 4))
        // Defaults that are set: refresh interval, font size, colors; zero and false are left out.
        assertTrue("ad-refresh-interval=\"30000\"" in attrs)
        assertTrue("font-size=\"13\"" in attrs)
        assertTrue("colors=\"#333333\"" in attrs)
        assertFalse(attrs.any { it.startsWith("debug=") || it.startsWith("ad-refresh-max=") || it.startsWith("boltive-client-id=") })
    }

    @Test
    fun `typed fields, bidder objects and the remote passthrough become attributes`() {
        val remote = AppConfigFactory.everyMappedKey()
        val config = SellwildSDK.apply(remote, SellwildConfig(partnerCode = "fixture")).copy(
            ix = IxConfig(disabled = true, siteIdM = "m", siteIdD = "d"),
            openx = OpenxConfig(delDomain = "x.openx.net", unitM = "1", unitD = "2"),
            pubmatic = PubmaticConfig(disabled = true, pubIdM = "p", adSlotM = "s", adSlotD = "t"),
            appnexus = AppnexusConfig(placementIdM = 1, placementIdD = 2),
            adType = "GAM",
            gptProxyUrl = "https://gpt.example.com/proxy",
            mobileZids = listOf("", "z1", "z2"),
            adRefreshIntervalMs = 0,
        )

        val attrs = lines(WidgetPage.attributes(config, remote))

        for (expected in listOf(
            "ad-type=\"GAM\"",
            "gam-tag=\"/1234/fixture\"",
            "gpt-proxy-url=\"https://gpt.example.com/proxy\"",
            "disable-gpt=\"true\"",
            "banner-zid=\"43\"",
            "mobile-zid=\"z1,z2\"",
            "hide-banner-top=\"true\"",
            "ad-refresh-max=\"5\"",
            "ad-refresh-max-mobile=\"6\"",
            "boltive=\"true\"",
            "boltive-client-id=\"boltive-fixture\"",
            "lotame=\"true\"",
            "title=\"Marketplace\"",
            "colors=\"#295baa,#000000\"",
            "debug=\"true\"",
            "enable-interstitial=\"true\"",
            "interstitials-per-session=\"2\"",
            // Passthrough: every remote key not emitted above, lower-kebab-case, quotes escaped.
            "partner-url=\"https://sellwild.com/?p=fixture\"",
            "iab-cats=\"[&quot;IAB2&quot;,&quot;IAB2-15&quot;]\"",
            "watermark-title=\"By Sellwild\"",
        )) {
            assertTrue("$expected in $attrs", expected in attrs)
        }
        // The typed interval is 0 (left out), so the remote AD_REFRESH_INTERVAL passes through.
        assertTrue("ad-refresh-interval=\"45000\"" in attrs)
        assertEquals(mapOf("siteIdM" to "m", "siteIdD" to "d", "disabled" to true), json(attrs, "ix"))
        assertEquals(mapOf("delDomain" to "x.openx.net", "unitM" to "1", "unitD" to "2"), json(attrs, "openx"))
        assertEquals(mapOf("pubIdM" to "p", "adSlotM" to "s", "adSlotD" to "t", "disabled" to true), json(attrs, "pubmatic"))
        assertEquals(mapOf("placementIdM" to 1, "placementIdD" to 2), json(attrs, "appnexus"))
        // A key the typed serializer already wrote is not passed through again.
        assertEquals(1, attrs.count { it.startsWith("title=") })
        assertEquals(1, attrs.count { it.startsWith("banner-zid=") })
    }

    @Test
    fun `bidder objects carry disabled only when it is set, and no colors writes no colors attribute`() {
        val config = SellwildConfig(
            partnerCode = "fixture",
            colors = emptyList(),
            ix = IxConfig(siteIdM = "m", siteIdD = "d"),
            openx = OpenxConfig(disabled = true, delDomain = "x.openx.net", unitM = "1", unitD = "2"),
            pubmatic = PubmaticConfig(pubIdM = "p", adSlotM = "s", adSlotD = "t"),
            appnexus = AppnexusConfig(disabled = true, placementIdM = 1, placementIdD = 2),
        )

        val attrs = lines(WidgetPage.attributes(config, null))

        assertFalse(attrs.any { it.startsWith("colors=") })
        assertEquals(mapOf("siteIdM" to "m", "siteIdD" to "d"), json(attrs, "ix"))
        assertEquals(mapOf("delDomain" to "x.openx.net", "unitM" to "1", "unitD" to "2", "disabled" to true), json(attrs, "openx"))
        assertEquals(mapOf("pubIdM" to "p", "adSlotM" to "s", "adSlotD" to "t"), json(attrs, "pubmatic"))
        assertEquals(mapOf("placementIdM" to 1, "placementIdD" to 2, "disabled" to true), json(attrs, "appnexus"))
    }

    @Test
    fun `the Prebid pre-config declares the app, and routes through Prebid Server when one is typed`() {
        val plain = WidgetPage.prebidPreConfig(SellwildConfig(partnerCode = "weatherbug"))
        val full = WidgetPage.prebidPreConfig(
            SellwildConfig(
                partnerCode = "weatherbug",
                appBundleId = "com.weatherbug",
                appStoreUrl = "https://play.google.com/store/apps/details?id=com.weatherbug",
                debug = true,
                prebidServer = PrebidServerConfig("acct", "https://pbs.example.com/auction", listOf("appnexus", "ix"), 900, "https://pbs.example.com/sync"),
            ),
        )
        val noSync = WidgetPage.prebidPreConfig(
            SellwildConfig(partnerCode = "weatherbug", prebidServer = PrebidServerConfig("acct", "https://pbs.example.com/auction", emptyList())),
        )

        assertTrue(plain.contains("ortb2: { app: {\"publisher\": {\"id\": \"weatherbug\"}} },"))
        assertFalse(plain.contains("s2sConfig"))
        assertFalse(plain.contains("\"debug\": true"))
        assertTrue(full.contains("\"bundle\": \"com.weatherbug\", \"storeurl\": \"https://play.google.com/store/apps/details?id=com.weatherbug\""))
        assertTrue(full.contains("\"bidders\": [\"appnexus\", \"ix\"]"))
        assertTrue(full.contains("\"timeout\": 900"))
        assertTrue(full.contains("\"syncEndpoint\": {\"p1Consent\": \"https://pbs.example.com/sync\""))
        assertTrue(full.contains("\"debug\": true"))
        assertTrue(noSync.contains("\"bidders\": [],"))
        assertFalse(noSync.contains("syncEndpoint"))
    }

    @Test
    fun `the page holds the pre-config, the element, the bridge script and the bundle`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        val html = WidgetPage.html(config, null)

        assertTrue(html.startsWith("<!DOCTYPE html>"))
        assertTrue(html.contains(WidgetPage.prebidPreConfig(config)))
        assertTrue(html.contains("<sellwild-widget\n    ${WidgetPage.attributes(config, null)}\n  ></sellwild-widget>"))
        assertTrue(html.contains("SellwildWidgetBridge.postMessage"))
        // A message the bridge cannot take is counted, not dropped in an empty catch.
        assertTrue(html.contains("window.__sellwildBridgeFailures = (window.__sellwildBridgeFailures || 0) + 1;"))
        assertFalse(html.contains("catch(e) {}"))
        assertTrue(html.contains("<script async src=\"https://widget.sellwild.com/partner.js\"></script>"))
    }

    @Test
    fun `only the page and the widget bundle blank the widget when they fail to load`() {
        assertTrue(WidgetPage.isWidgetResource("https://widget.sellwild.com/", isMainFrame = true))
        assertTrue(WidgetPage.isWidgetResource(WidgetPage.SCRIPT_URL, isMainFrame = false))
        assertFalse(WidgetPage.isWidgetResource("https://cdn.example.com/photo.jpg", isMainFrame = false))
        assertFalse(WidgetPage.isWidgetResource(null, isMainFrame = false))
    }

    @Test
    fun `the WebView data directory suffix is set only for another process on API 28 and up`() {
        val never: () -> String? = { throw AssertionError("getProcessName() does not exist below API 28") }

        assertNull(WidgetPage.dataDirectorySuffix(27, "com.app", never))
        assertNull(WidgetPage.dataDirectorySuffix(28, "com.app") { "com.app" })
        assertNull(WidgetPage.dataDirectorySuffix(35, "com.app") { null })
        assertEquals("ads", WidgetPage.dataDirectorySuffix(28, "com.app") { "com.app:ads" })
        assertEquals("other", WidgetPage.dataDirectorySuffix(35, "com.app") { "other" })
    }

    // ── WidgetBridge ─────────────────────────────────────────────────────────

    @Test
    fun `each message type decodes to its message`() {
        assertEquals(BridgeMessage.Loaded, WidgetBridge.decode(BridgeMessageFactory.variant("default").toString()).value)
        assertEquals("43", (WidgetBridge.decode(BridgeMessageFactory.variant("ad-impression").toString()).value as BridgeMessage.AdImpression).zoneId)
        assertEquals("43", (WidgetBridge.decode(BridgeMessageFactory.variant("ad-impression-number-zone").toString()).value as BridgeMessage.AdImpression).zoneId)
        assertEquals(
            "Uncaught TypeError: Cannot read properties of undefined",
            (WidgetBridge.decode(BridgeMessageFactory.variant("error").toString()).value as BridgeMessage.Error).message,
        )
    }

    @Test
    fun `a listing click carries the URL stub, or the listing the page sent`() {
        val stub = (WidgetBridge.decode(BridgeMessageFactory.variant("listing-click").toString()).value as BridgeMessage.ListingClick).listing
        val full = (WidgetBridge.decode(BridgeMessageFactory.variant("listing-click-photos").toString()).value as BridgeMessage.ListingClick).listing
        val partial = (WidgetBridge.decode(BridgeMessageFactory.variant("listing-click-stub").toString()).value as BridgeMessage.ListingClick).listing

        assertEquals("", stub.id)
        assertEquals("active", stub.status)
        assertEquals("https://sellwild.com/listing/105140231", stub.url)
        assertEquals("105140231", full.id)
        assertEquals("19315", full.price)
        assertEquals("USD", full.currency)
        assertEquals("https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231_thumb.jpg", full.photos.single().thumbUrl)
        assertEquals(emptyList<Any>(), partial.photos)
        assertNull(partial.url)
        assertNull(partial.price)
    }

    @Test
    fun `a URL-less click stub has no URL`() {
        val message = BridgeMessageFactory.checked(mapOf("type" to "LISTING_CLICK"))

        assertNull((WidgetBridge.decode(message.toString()).value as BridgeMessage.ListingClick).listing.url)
    }

    @Test
    fun `text that is not JSON is bridge_message_parse`() {
        val decoded = WidgetBridge.decode("{\"type\": ")

        assertNull(decoded.value)
        val issue = decoded.issues.single()
        assertEquals(SellwildFailureCode.BRIDGE_MESSAGE_PARSE, issue.code)
        assertEquals(SellwildFailureComponent.BRIDGE, issue.component)
        assertEquals(SellwildFailureSeverity.WARN, issue.severity)
        assertTrue(issue.error is JSONException)
    }

    @Test
    fun `a listing photo that is not an object is bridge_message_invalid`() {
        val decoded = WidgetBridge.decode(BridgeMessageFactory.variant("listing-click-bad-photo").toString())

        assertNull(decoded.value)
        assertEquals(SellwildFailureCode.BRIDGE_MESSAGE_INVALID, decoded.issues.single().code)
        assertEquals("LISTING_CLICK listing is not valid", decoded.issues.single().message)
    }

    @Test
    fun `an unknown type is bridge_message_unsupported`() {
        val decoded = WidgetBridge.decode(BridgeMessageFactory.variant("unknown-type").toString())

        assertNull(decoded.value)
        assertEquals(SellwildFailureCode.BRIDGE_MESSAGE_UNSUPPORTED, decoded.issues.single().code)
        assertEquals("unsupported bridge message type: NOPE", decoded.issues.single().message)
    }
}
