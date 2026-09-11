package com.sellwild.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the house-ad listing-fallback SELECTION logic
 * ([SellwildHouseAd.pickListing] / [SellwildHouseAd.hasUsablePhoto]). The
 * fallback renders a grey placeholder when handed a photoless listing, so the
 * picker must prefer listings that actually have a photo. Parity with iOS
 * SellwildHouseAdTests. Rendering / hide-on-fill behavior is exercised on-device.
 */
class SellwildHouseAdTest {

    private fun listing(id: String, photoUrl: String? = null): SellwildListing =
        SellwildListing(
            id = id,
            status = "active",
            title = "listing $id",
            photos = photoUrl?.let { listOf(SellwildPhoto(url = it, thumbUrl = "")) } ?: emptyList(),
        )

    @Test
    fun `hasUsablePhoto reflects a non-blank primary photo url`() {
        assertTrue(SellwildHouseAd.hasUsablePhoto(listing("1", "https://x/a.jpg")))
        assertFalse(SellwildHouseAd.hasUsablePhoto(listing("2")))          // no photos
        assertFalse(SellwildHouseAd.hasUsablePhoto(listing("3", "  ")))    // blank url
    }

    @Test
    fun `pickListing prefers listings with photos`() {
        // Only "2" has a photo — every row resolves to it, never the neighbors.
        val ls = listOf(listing("1"), listing("2", "https://x/b.jpg"), listing("3"))
        for (row in 0 until 6) {
            assertEquals("2", SellwildHouseAd.pickListing(ls, row)?.id)
        }
    }

    @Test
    fun `pickListing rotates within the photo subset`() {
        val ls = listOf(
            listing("a", "https://x/a.jpg"),
            listing("b", "https://x/b.jpg"),
            listing("c"),
        )
        assertEquals("a", SellwildHouseAd.pickListing(ls, 0)?.id)
        assertEquals("b", SellwildHouseAd.pickListing(ls, 1)?.id)
        assertEquals("a", SellwildHouseAd.pickListing(ls, 2)?.id)
    }

    @Test
    fun `pickListing falls back to all when none have photos`() {
        val ls = listOf(listing("x"), listing("y"))
        assertEquals("x", SellwildHouseAd.pickListing(ls, 0)?.id)
        assertEquals("y", SellwildHouseAd.pickListing(ls, 1)?.id)
        assertEquals("x", SellwildHouseAd.pickListing(ls, 2)?.id)
    }

    @Test
    fun `pickListing on empty is null`() {
        assertNull(SellwildHouseAd.pickListing(emptyList(), 0))
    }

    // ── excludeIds (dedup vs. already-shown feed rows) ──────────────────────

    @Test
    fun `pickListing excludes already-shown ids`() {
        val ls = listOf(
            listing("1", "https://x/a.jpg"),
            listing("2", "https://x/b.jpg"),
            listing("3", "https://x/c.jpg"),
        )
        // Without exclusion, row 0 resolves to "1" (see rotation test above).
        // With "1" already shown as a normal feed row, it must never be picked.
        for (row in 0 until 6) {
            assertNotEquals("1", SellwildHouseAd.pickListing(ls, row, setOf("1"))?.id)
        }
    }

    @Test
    fun `pickListing falls back to a duplicate when every candidate is excluded`() {
        val ls = listOf(listing("1", "https://x/a.jpg"), listing("2", "https://x/b.jpg"))
        // Every candidate is already shown elsewhere — degrade to a duplicate
        // (matches the web widget's documented last-resort behavior) rather
        // than returning null and leaving the ad slot with no house content.
        assertNotNull(SellwildHouseAd.pickListing(ls, 0, setOf("1", "2")))
    }

    @Test
    fun `pickListing default excludeIds is unchanged`() {
        // No excludeIds argument at all — existing call sites/behavior untouched.
        val ls = listOf(listing("a", "https://x/a.jpg"), listing("b", "https://x/b.jpg"))
        assertEquals("a", SellwildHouseAd.pickListing(ls, 0)?.id)
    }
}
