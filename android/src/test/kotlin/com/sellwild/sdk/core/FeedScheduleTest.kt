package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The COL1 row scheduler (FeedSchedule), pure. */
class FeedScheduleTest {

    private fun listing(id: String, withPhoto: Boolean = true): SellwildListing = ListingsParser.parseListing(
        ListingFactory.checked(if (withPhoto) mapOf("id" to id) else mapOf("id" to id, "photos" to JSONArray())),
    )

    private val listings = (1..4).map { listing("l$it") }
    private val noGpid: (String) -> String? = { null }

    private fun ids(rows: List<FeedRow>): List<String> = rows.map {
        when (it) {
            FeedRow.Header -> "H"
            is FeedRow.Listing -> it.listing.id
            is FeedRow.GamAd -> "G:${it.zoneId}:${it.gpid}"
            is FeedRow.DirectAd -> "D:${it.zoneId}:${it.gpid}"
            is FeedRow.Banner -> "B:${it.zoneId}:${it.gpid}"
        }
    }

    @Test
    fun `COL1 is upper-cased, and unset or blank is the default`() {
        assertEquals("LLGB", FeedSchedule.normalize("llgb"))
        assertEquals(FeedSchedule.DEFAULT, FeedSchedule.normalize(null))
        assertEquals(FeedSchedule.DEFAULT, FeedSchedule.normalize("  "))
    }

    @Test
    fun `one row per token after the header, zones round robin, listings until they run out`() {
        val built = FeedSchedule.build("LGLDBLLLLX", listings, listOf("z1", "z2"), "b1", noGpid)

        assertEquals(
            listOf("H", "l1", "G:z1:null", "l2", "D:z2:null", "B:b1:null", "l3", "l4"),
            ids(built.value),
        )
        assertEquals(emptyList<Issue>(), built.issues)
    }

    @Test
    fun `ad tokens with no zone are dropped and counted per kind`() {
        val built = FeedSchedule.build("GDBG", listings, emptyList(), null, noGpid)

        assertEquals(listOf("H"), ids(built.value))
        assertEquals(
            listOf(
                Issue(SellwildFailureCode.FEED_AD_ZONE_MISSING, SellwildFailureComponent.FEED, SellwildFailureSeverity.WARN, message = "COL1 G/D rows dropped: no MOBILE_ZID zone (3)"),
                Issue(SellwildFailureCode.FEED_AD_ZONE_MISSING, SellwildFailureComponent.FEED, SellwildFailureSeverity.WARN, message = "COL1 B rows dropped: no banner zone (1)"),
            ),
            built.issues,
        )
    }

    @Test
    fun `an empty zone in the list and an empty banner zone drop their rows too`() {
        val built = FeedSchedule.build("GGB", listings, listOf("z1", ""), "", noGpid)

        assertEquals(listOf("H", "G:z1:null"), ids(built.value))
        assertEquals(listOf("COL1 G/D rows dropped: no MOBILE_ZID zone (1)", "COL1 B rows dropped: no banner zone (1)"), built.issues.map { it.message })
    }

    @Test
    fun `a GPID base used once is kept, a shared one is numbered in row order, and none is left out`() {
        val bases = mapOf("z1" to "/1/feed", "z2" to "/1/solo", "b1" to "/1/feed")

        val built = FeedSchedule.build("GGBGD", emptyList(), listOf("z1", "z2", "z3"), "b1") { bases[it] }

        assertEquals(
            listOf("H", "G:z1:/1/feed#1", "G:z2:/1/solo", "B:b1:/1/feed#2", "G:z3:null", "D:z1:/1/feed#3"),
            ids(built.value),
        )
    }

    @Test
    fun `the house listing has a photo, is not shown already, and rotates by position`() {
        val shown = listing("l1")
        val photoless = listing("l9", withPhoto = false)
        val pool = listOf(shown, photoless, listing("l2"), listing("l3"))
        val rows = listOf(FeedRow.Header, FeedRow.Listing(shown), FeedRow.GamAd("z1"))

        assertEquals("l2", FeedSchedule.houseListing(pool, rows, position = 2)?.id)
        assertEquals("l3", FeedSchedule.houseListing(pool, rows, position = 3)?.id)
        assertNull(FeedSchedule.houseListing(emptyList(), rows, position = 2))
    }

    @Test
    fun `a zone is picked round robin and an empty one is none`() {
        assertEquals("z2", FeedSchedule.pickZone(listOf("z1", "z2"), 3))
        assertNull(FeedSchedule.pickZone(emptyList(), 0))
        assertNull(FeedSchedule.pickZone(listOf(""), 5))
    }

    @Test
    fun `ad rows take a GPID without changing their zone`() {
        assertEquals(FeedRow.GamAd("z", "g"), FeedRow.GamAd("z").withGpid("g"))
        assertEquals(FeedRow.DirectAd("z", "g"), FeedRow.DirectAd("z").withGpid("g"))
        assertEquals(FeedRow.Banner("z", "g"), FeedRow.Banner("z").withGpid("g"))
    }
}
