package com.sellwild.sdk

import com.sellwild.sdk.SellwildHouseAd.Creative
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import kotlin.random.Random

/**
 * [SellwildHouseAd] creative resolution: `MOBILE_HOUSE_AD_IMAGE` (and the `image` of a
 * by-zone / by-size object) is one URL or a list, the random pick is injected, and click URLs
 * pair by index or are shared. Parity with iOS SellwildHouseAdResolveTests.
 */
class SellwildHouseAdResolveTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun obj(vararg entries: Pair<String, Any?>): JSONObject = AppConfigFactory.checked(mapOf(*entries))

    private fun candidates(obj: JSONObject, zone: String? = null): List<Creative> = SellwildHouseAd.candidates(obj, zone, 300, 250)

    private fun images(vararg urls: String) = jsonArrayOf(*urls)

    @Test
    fun `a single image and click`() {
        val json = FixtureLoader.text("fixtures/app-config/valid/house-image-string.json")

        assertEquals(
            Creative("https://cache.sellwild.com/house/fixture-300x250.png", "https://sellwild.com/?p=fixture"),
            SellwildHouseAd.resolve(json, null, 300, 250),
        )
    }

    @Test
    fun `an image list is every candidate, and the injected random picks one`() {
        val config = obj("MOBILE_HOUSE_AD_IMAGE" to images("https://x/a.png", "https://x/b.png", "https://x/c.png"))
        val all = candidates(config)

        assertEquals(listOf("https://x/a.png", "https://x/b.png", "https://x/c.png"), all.map { it.imageUrl })
        for (seed in 0 until 10) {
            assertEquals(all[Random(seed).nextInt(3)], SellwildHouseAd.resolve(config.toString(), null, 300, 250, Random(seed)))
        }
        assertTrue(SellwildHouseAd.resolve(config.toString(), null, 300, 250) in all)
    }

    @Test
    fun `blank images are skipped, and the click pairs by original index`() {
        val config = obj(
            "MOBILE_HOUSE_AD_IMAGE" to images("", "   ", "https://x/c.png", "https://x/d.png"),
            "MOBILE_HOUSE_AD_URL" to images("https://x/u0", "https://x/u1", "https://x/u2"),
        )

        assertEquals(listOf(Creative("https://x/c.png", "https://x/u2"), Creative("https://x/d.png", null)), candidates(config))
    }

    @Test
    fun `one click URL is shared by every image`() {
        val config = obj("MOBILE_HOUSE_AD_IMAGE" to images("https://x/a.png", "https://x/b.png"), "MOBILE_HOUSE_AD_URL" to "https://x/shared")

        assertEquals(listOf("https://x/shared", "https://x/shared"), candidates(config).map { it.clickUrl })
    }

    @Test
    fun `no image, an empty list or another type resolves nothing`() {
        assertNull(SellwildHouseAd.resolve(null, "43", 300, 250))
        assertNull(SellwildHouseAd.resolve(obj().toString(), "43", 300, 250))
        assertEquals(emptyList<Creative>(), candidates(obj("MOBILE_HOUSE_AD_IMAGE" to images())))
        assertEquals(emptyList<Creative>(), candidates(obj("MOBILE_HOUSE_AD_IMAGE" to "  ")))
        assertEquals(emptyList<Creative>(), candidates(AppConfigFactory.offSchema(mapOf("MOBILE_HOUSE_AD_IMAGE" to 7))))
        assertEquals(
            "a click of another type is no click",
            listOf(Creative("https://x/a.png", null)),
            candidates(AppConfigFactory.offSchema(mapOf("MOBILE_HOUSE_AD_IMAGE" to "https://x/a.png", "MOBILE_HOUSE_AD_URL" to 7))),
        )
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `by-zone wins, then by-size, then the app-wide image, each only when it has an image`() {
        val json = FixtureLoader.jsonObject("fixtures/app-config/valid/house-image-arrays.json")
        val byZone = JSONObject().put("43", JSONObject().put("image", "https://x/zone.png")).put("44", JSONObject().put("url", "https://x/no-image"))
        val bySize = JSONObject().put("300x250", JSONObject().put("image", images("https://x/m1.png")).put("url", "https://x/c"))
        val config = obj("MOBILE_HOUSE_AD_IMAGE" to "https://x/app.png", "MOBILE_HOUSE_AD_BY_ZONE" to byZone, "MOBILE_HOUSE_AD_BY_SIZE" to bySize)

        assertEquals(
            listOf("https://cache.sellwild.com/house/z1.png", "https://cache.sellwild.com/house/z2.png"),
            candidates(json, "43").map { it.imageUrl },
        )
        assertEquals(listOf(Creative("https://x/zone.png", null)), candidates(config, "43"))
        assertEquals(listOf(Creative("https://x/m1.png", "https://x/c")), candidates(config, "44"))
        assertEquals(listOf(Creative("https://x/m1.png", "https://x/c")), candidates(config, null))
        assertEquals(listOf("https://x/app.png"), SellwildHouseAd.candidates(config, "44", 320, 50).map { it.imageUrl })
    }

    @Test
    fun `the master switch turns backfill off`() {
        val off = FixtureLoader.text("fixtures/app-config/valid/house-disabled-string.json")

        assertFalse(SellwildHouseAd.isEnabled(off))
        assertNull(SellwildHouseAd.resolve(off, null, 300, 250))
        assertFalse(SellwildHouseAd.isEnabled(obj("MOBILE_HOUSE_AD_ENABLED" to 0).toString()))
        assertTrue(SellwildHouseAd.isEnabled(null))
        assertTrue(SellwildHouseAd.isEnabled(obj("MOBILE_HOUSE_AD_ENABLED" to "yes").toString()))
    }

    @Test
    fun `config that does not parse leaves backfill on with no creative, and is reported`() {
        val bad = FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")

        assertTrue(SellwildHouseAd.isEnabled(bad))
        assertNull(SellwildHouseAd.resolve(bad, "43", 300, 250))

        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), sink.pushed.map { it.action })
    }
}
