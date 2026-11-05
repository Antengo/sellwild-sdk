package com.sellwild.sdk.core

import com.sellwild.sdk.factories.ListingFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Where a house or native ad image comes from, and its disk cache name. */
class HouseImagesTest {

    private fun photo(variant: String, index: Int): String =
        ListingFactory.variant(variant).getJSONArray("photos").getJSONObject(index).getString("url")

    @Test
    fun `a data URI decodes inline from after the first comma`() {
        val source = HouseImages.source(photo("data-uri-photos", 0))

        assertTrue(source is HouseImages.Source.Inline)
        assertEquals("AAAAHGZ0eXBhdmlm", (source as HouseImages.Source.Inline).base64)
    }

    @Test
    fun `a data URI without a comma is refused, with no host to report`() {
        val source = HouseImages.source("data:image/png;base64") as HouseImages.Source.Refused

        assertEquals("data URI without a comma", source.reason)
        assertNull(source.url)
    }

    @Test
    fun `an http(s) photo is fetched, and any other scheme is refused`() {
        val url = photo("default", 0)
        assertEquals(url, (HouseImages.source(url) as HouseImages.Source.Remote).url.toString())

        val refused = HouseImages.source("file:///sdcard/secret.png") as HouseImages.Source.Refused
        assertEquals("not an http(s) URL", refused.reason)
        assertEquals("file:///sdcard/secret.png", refused.url)
    }

    @Test
    fun `the disk name is djb2 of the URL, stable across launches`() {
        assertEquals(5381L, HouseImages.djb2(""))
        assertEquals(5381L * 33 + 'a'.code, HouseImages.djb2("a"))
        assertEquals(HouseImages.djb2(photo("default", 0)), HouseImages.djb2(photo("default", 0)))
    }
}
