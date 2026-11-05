package com.sellwild.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The http/https allow-list for opened URLs and image fetches, on the real Uri parser. */
@RunWith(RobolectricTestRunner::class)
class SellwildSafeUrlTest {

    @Test
    fun `only http and https open`() {
        assertEquals("https://sellwild.com/product/1", SellwildSafeUrl.external("https://sellwild.com/product/1").toString())
        assertEquals("HTTP://sellwild.com", SellwildSafeUrl.external("HTTP://sellwild.com").toString())
        listOf(null, "", "intent://x#Intent;end", "market://details?id=x", "tel:123", "javascript:alert(1)", "sellwild.com/x")
            .forEach { assertNull("$it", SellwildSafeUrl.external(it)) }
    }

    @Test
    fun `only http and https images are fetched`() {
        assertEquals("https://cache.sellwild.com/a.png", SellwildSafeUrl.imageUrl("https://cache.sellwild.com/a.png").toString())
        assertEquals("http", SellwildSafeUrl.imageUrl("http://cache.sellwild.com/a.png")?.protocol)
        listOf(null, "", "file:///sdcard/a.png", "data:image/png;base64,AAAA", "not a url")
            .forEach { assertNull("$it", SellwildSafeUrl.imageUrl(it)) }
        assertEquals(8 * 1024 * 1024, SellwildSafeUrl.MAX_IMAGE_BYTES)
    }
}
