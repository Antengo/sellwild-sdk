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

    // URL pairing

    @Test
    fun `image and url arrays pair by index`() {
        val json =
            """{"MOBILE_HOUSE_AD_IMAGE":["https://x/a.png","https://x/b.png","https://x/c.png"],"MOBILE_HOUSE_AD_URL":["https://x/ua","https://x/ub","https://x/uc"]}"""
        val paired = mapOf(
            "https://x/a.png" to "https://x/ua",
            "https://x/b.png" to "https://x/ub",
            "https://x/c.png" to "https://x/uc",
        )
        repeat(80) {
            val c = SellwildHouseAd.resolve(json, null, 300, 250)
            assertNotNull(c)
            assertEquals("click URL must pair with its image", paired[c!!.imageUrl], c.clickUrl)
        }
    }

    @Test
    fun `image array with single shared url`() {
        val json = """{"MOBILE_HOUSE_AD_IMAGE":["https://x/a.png","https://x/b.png"],"MOBILE_HOUSE_AD_URL":"https://x/shared"}"""
        repeat(20) {
            assertEquals("https://x/shared", SellwildHouseAd.resolve(json, null, 300, 250)?.clickUrl)
        }
    }

    @Test
    fun `shorter url array leaves unpaired click null`() {
        val json =
            """{"MOBILE_HOUSE_AD_IMAGE":["https://x/a.png","https://x/b.png","https://x/c.png"],"MOBILE_HOUSE_AD_URL":["https://x/only0"]}"""
        repeat(80) {
            val c = SellwildHouseAd.resolve(json, null, 300, 250)
            if (c?.imageUrl == "https://x/a.png") assertEquals("https://x/only0", c.clickUrl) else assertNull(c?.clickUrl)
        }
    }

    @Test
    fun `blank images keep url pairing by original index`() {
        val json =
            """{"MOBILE_HOUSE_AD_IMAGE":["","https://x/b.png","https://x/c.png"],"MOBILE_HOUSE_AD_URL":["https://x/u0","https://x/u1","https://x/u2"]}"""
        repeat(80) {
            val c = SellwildHouseAd.resolve(json, null, 300, 250)
            assertNotNull(c)
            if (c!!.imageUrl == "https://x/b.png") {
                assertEquals("https://x/u1", c.clickUrl)
            } else {
                assertEquals("https://x/c.png", c.imageUrl)
                assertEquals("https://x/u2", c.clickUrl)
            }
        }
    }
}
