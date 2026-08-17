package com.sellwild.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for [SellwildHouseAd.resolve] image resolution — the new support
 * for `MOBILE_HOUSE_AD_IMAGE` (and the `image` field of a by-zone / by-size
 * object) being either a single URL string OR an array of URL strings, with a
 * random non-empty pick per call (per no-fill). Parity with iOS
 * SellwildHouseAdResolveTests.
 */
class SellwildHouseAdResolveTest {

    @Test
    fun `single image string unchanged`() {
        val c = SellwildHouseAd.resolve(
            """{"MOBILE_HOUSE_AD_IMAGE":"https://x/a.png","MOBILE_HOUSE_AD_URL":"https://x/click"}""",
            null, 300, 250,
        )
        assertEquals("https://x/a.png", c?.imageUrl)
        assertEquals("https://x/click", c?.clickUrl)
    }

    @Test
    fun `image array always picks from the set and rotates`() {
        val set = setOf("https://x/a.png", "https://x/b.png", "https://x/c.png")
        val json = """{"MOBILE_HOUSE_AD_IMAGE":["https://x/a.png","https://x/b.png","https://x/c.png"]}"""
        val seen = mutableSetOf<String>()
        repeat(80) {
            val c = SellwildHouseAd.resolve(json, null, 300, 250)
            assertNotNull(c)
            assertTrue(set.contains(c!!.imageUrl))
            seen.add(c.imageUrl)
        }
        assertTrue("expected rotation across draws", seen.size > 1)
    }

    @Test
    fun `image array skips blank entries`() {
        val c = SellwildHouseAd.resolve(
            """{"MOBILE_HOUSE_AD_IMAGE":["","   ","https://x/only.png"]}""", null, 300, 250,
        )
        assertEquals("https://x/only.png", c?.imageUrl)
    }

    @Test
    fun `empty image array resolves null`() {
        val c = SellwildHouseAd.resolve("""{"MOBILE_HOUSE_AD_IMAGE":[]}""", null, 300, 250)
        assertNull(c)
    }

    @Test
    fun `by-size object image array`() {
        val json =
            """{"MOBILE_HOUSE_AD_BY_SIZE":{"300x250":{"image":["https://x/m1.png","https://x/m2.png"],"url":"https://x/c"}}}"""
        val c = SellwildHouseAd.resolve(json, null, 300, 250)
        assertNotNull(c)
        assertTrue(setOf("https://x/m1.png", "https://x/m2.png").contains(c!!.imageUrl))
        assertEquals("https://x/c", c.clickUrl)
    }

    @Test
    fun `disabled still wins over array`() {
        val c = SellwildHouseAd.resolve(
            """{"MOBILE_HOUSE_AD_ENABLED":false,"MOBILE_HOUSE_AD_IMAGE":["https://x/a.png"]}""",
            null, 300, 250,
        )
        assertNull(c)
    }
}
