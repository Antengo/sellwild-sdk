package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildHouseAd
import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity

/** One row of the native feed. Ad rows carry the GPID for their slot (base, or base#n). */
internal sealed class FeedRow {
    object Header : FeedRow()

    data class Listing(val listing: SellwildListing) : FeedRow()

    /** An ad row: its zone and the GPID for its slot. */
    sealed class Ad : FeedRow() {
        abstract val zoneId: String
        abstract val gpid: String?

        abstract fun withGpid(gpid: String): Ad
    }

    /** A `G` token: a 300x250 GAM ad. */
    data class GamAd(override val zoneId: String, override val gpid: String? = null) : Ad() {
        override fun withGpid(gpid: String) = copy(gpid = gpid)
    }

    /** A `D` token: a 300x250 direct ad unit (identical to [GamAd] until a direct-served path lands). */
    data class DirectAd(override val zoneId: String, override val gpid: String? = null) : Ad() {
        override fun withGpid(gpid: String) = copy(gpid = gpid)
    }

    /** A `B` token: a 320x50 banner. */
    data class Banner(override val zoneId: String, override val gpid: String? = null) : Ad() {
        override fun withGpid(gpid: String) = copy(gpid = gpid)
    }
}

/**
 * The COL1 row scheduler, pure: one row per token, left to right, after a header.
 * `L` is the next listing, `G`/`D` a 300x250 ad on the next MOBILE_ZID zone (round robin),
 * `B` a 320x50 banner on the banner zone. Unknown tokens are ignored for forward
 * compatibility.
 */
internal object FeedSchedule {
    const val DEFAULT = "LLGLLGLLG"

    /** COL1 upper-cased, or [DEFAULT] when it is unset or blank. */
    fun normalize(col1: String?): String = (col1?.takeIf { it.isNotBlank() } ?: DEFAULT).uppercase()

    /**
     * The rows for [schedule]. An ad token with no zone to fill is dropped and reported as
     * feed.ad_zone.missing, one issue per kind with the count dropped.
     *
     * GPIDs: [gpidBase] resolves each ad slot's base. A base used by exactly one slot is used
     * as is; a base shared by k slots becomes base#1 … base#k in row order.
     */
    fun build(
        schedule: String,
        listings: List<SellwildListing>,
        gamZones: List<String>,
        bannerZone: String?,
        gpidBase: (String) -> String?,
    ): Resolved<List<FeedRow>> {
        val rows = mutableListOf<FeedRow>(FeedRow.Header)
        val listingsLeft = listings.iterator()
        var gamIdx = 0
        var droppedGam = 0
        var droppedBanner = 0

        // Each ad row's index in `rows` and its GPID base, in row order.
        val adRows = mutableListOf<Pair<Int, String?>>()
        val baseCounts = mutableMapOf<String, Int>()

        fun addAd(zone: String, row: FeedRow.Ad) {
            val base = gpidBase(zone)
            if (base != null) baseCounts[base] = (baseCounts[base] ?: 0) + 1
            adRows += rows.size to base
            rows += row
        }

        for (token in schedule) {
            when (token) {
                'L' -> if (listingsLeft.hasNext()) rows += FeedRow.Listing(listingsLeft.next())
                'G', 'D' -> {
                    val zone = pickZone(gamZones, gamIdx++)
                    when {
                        zone == null -> droppedGam++
                        token == 'G' -> addAd(zone, FeedRow.GamAd(zone))
                        else -> addAd(zone, FeedRow.DirectAd(zone))
                    }
                }
                'B' -> if (bannerZone.isNullOrEmpty()) droppedBanner++ else addAd(bannerZone, FeedRow.Banner(bannerZone))
            }
        }

        val seen = mutableMapOf<String, Int>()
        for ((idx, base) in adRows) {
            if (base == null) continue
            val gpid = if (baseCounts.getValue(base) > 1) {
                val n = (seen[base] ?: 0) + 1
                seen[base] = n
                "$base#$n"
            } else {
                base
            }
            rows[idx] = (rows[idx] as FeedRow.Ad).withGpid(gpid)
        }

        val issues = listOfNotNull(
            dropped(droppedGam, "COL1 G/D rows dropped: no MOBILE_ZID zone"),
            dropped(droppedBanner, "COL1 B rows dropped: no banner zone"),
        )
        return Resolved(rows, issues)
    }

    /**
     * The listing that house-backfills the ad slot at [position] (MREC rows, when no CMS house
     * image is set): one with a photo, rotating by position, not already shown as a listing row
     * in [rows] unless every candidate is. Null when there are no listings.
     */
    fun houseListing(listings: List<SellwildListing>, rows: List<FeedRow>, position: Int): SellwildListing? {
        val shownIds = rows.filterIsInstance<FeedRow.Listing>().map { it.listing.id }.toSet()
        return SellwildHouseAd.pickListing(listings, position, shownIds)
    }

    /** The zone for the [idx]th G/D token: round robin over [zones]; null when there are none or it is empty. */
    fun pickZone(zones: List<String>, idx: Int): String? {
        if (zones.isEmpty()) return null
        return zones[idx % zones.size].takeIf { it.isNotEmpty() }
    }

    private fun dropped(count: Int, what: String): Issue? =
        if (count == 0) {
            null
        } else {
            Issue(
                SellwildFailureCode.FEED_AD_ZONE_MISSING,
                SellwildFailureComponent.FEED,
                SellwildFailureSeverity.WARN,
                message = "$what ($count)",
            )
        }
}
