package com.sellwild.sdk

import com.sellwild.sdk.SellwildFeedView.Row
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for [SellwildFeedScheduler] — the pure row scheduler behind
 * [SellwildFeedView]. Pins down that ad rows do not depend on listings: when
 * the listings fetch fails (zero listings) the schedule's ad rows still render.
 */
class SellwildFeedSchedulerTest {

    private val config = SellwildConfig(
        partnerCode = "acme",
        mobileZids = listOf("101", "102"),
        mobileBannerZid = "201",
    )

    private fun listing(id: String) = SellwildListing(id = id, status = "active", title = "Item $id")

    @Test
    fun `zero listings still yields the schedule's ad rows`() {
        val rows = SellwildFeedScheduler.buildRows(config, "LLGLLBLD", emptyList())

        assertEquals(
            listOf(
                Row.Header,
                Row.GamAd("101"),
                Row.Banner("201"),
                Row.DirectAd("102"),
            ),
            rows,
        )
    }

    @Test
    fun `zero listings and no configured zones yields only the header`() {
        val noZones = SellwildConfig(partnerCode = "acme")

        assertEquals(
            listOf<Row>(Row.Header),
            SellwildFeedScheduler.buildRows(noZones, "LLGLLBLD", emptyList()),
        )
        assertEquals(
            listOf<Row>(Row.Header),
            SellwildFeedScheduler.buildRows(null, "LLGLLBLD", emptyList()),
        )
    }

    @Test
    fun `rebuilding with the same inputs yields equal rows`() {
        // The feed skips a rebind when a repeated failure produces the same rows.
        assertEquals(
            SellwildFeedScheduler.buildRows(config, "LLGLLB", emptyList()),
            SellwildFeedScheduler.buildRows(config, "LLGLLB", emptyList()),
        )
    }

    @Test
    fun `listings interleave with the same ad rows once they load`() {
        val a = listing("a")
        val b = listing("b")
        val c = listing("c")

        val rows = SellwildFeedScheduler.buildRows(config, "LLGLLB", listOf(a, b, c))

        assertEquals(
            listOf(
                Row.Header,
                Row.Listing(a),
                Row.Listing(b),
                Row.GamAd("101"),
                Row.Listing(c),
                Row.Banner("201"),
            ),
            rows,
        )
    }

    @Test
    fun `ad rows carry the configured gpid with zero listings`() {
        val withGpid = config.copy(remoteJson = """{"GPID_BASE":"/acme/feed"}""")

        val rows = SellwildFeedScheduler.buildRows(withGpid, "GB", emptyList())

        // Two slots share one base → disambiguated in row order.
        assertEquals(
            listOf(
                Row.Header,
                Row.GamAd("101", "/acme/feed#1"),
                Row.Banner("201", "/acme/feed#2"),
            ),
            rows,
        )
    }
}
