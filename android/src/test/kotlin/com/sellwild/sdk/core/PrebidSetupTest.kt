package com.sellwild.sdk.core

import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.plain
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The pure parts of the Prebid Mobile bootstrap (PrebidSetup). */
class PrebidSetupTest {

    private fun parsed(json: String?): Any? = json?.let { plain(JSONObject(it)) }

    @Test
    fun `the global ORTB config holds each part only when it is set`() {
        val geo = JSONObject().put("region", "GA")

        assertEquals(
            mapOf(
                "app" to mapOf("publisher" to mapOf("id" to "pub-1"), "cat" to listOf("IAB15")),
                "device" to mapOf("geo" to mapOf("region" to "GA")),
            ),
            parsed(PrebidSetup.globalOrtb("pub-1", listOf("IAB15"), geo)),
        )
        assertEquals(mapOf("app" to mapOf("cat" to listOf("IAB1"))), parsed(PrebidSetup.globalOrtb("", listOf("IAB1"), null)))
        assertEquals(mapOf("device" to mapOf("geo" to mapOf("region" to "GA"))), parsed(PrebidSetup.globalOrtb(null, emptyList(), geo)))
        assertNull(PrebidSetup.globalOrtb(null, null, null))
    }

    @Test
    fun `init that succeeded is fine, anything else is ad_prebid_init_invalid`() {
        assertNull(PrebidSetup.initStatus("SUCCEEDED", "ok"))

        val failed = PrebidSetup.initStatus("FAILED", "Prebid Server status check failed")
        val warning = PrebidSetup.initStatus("SERVER_STATUS_WARNING", null)
        val none = PrebidSetup.initStatus(null, "")

        assertEquals(
            Issue(
                SellwildFailureCode.AD_PREBID_INIT_INVALID,
                SellwildFailureComponent.BANNER,
                SellwildFailureSeverity.WARN,
                message = "Prebid init finished with status FAILED: Prebid Server status check failed",
            ),
            failed,
        )
        assertEquals("Prebid init finished with status SERVER_STATUS_WARNING", warning?.message)
        assertEquals("Prebid init finished with status null", none?.message)
    }

    @Test
    fun `an auction result is reported only when it is a failure other than no bids`() {
        assertNull(PrebidSetup.auctionResult("SUCCESS", SellwildFailureComponent.BANNER, "43"))
        assertNull(PrebidSetup.auctionResult("NO_BIDS", SellwildFailureComponent.BANNER, "43"))
        assertNull(PrebidSetup.auctionResult("TIMEOUT", SellwildFailureComponent.NATIVE, "43"))

        assertEquals(
            Issue(
                SellwildFailureCode.AD_PREBID_AUCTION_INVALID,
                SellwildFailureComponent.NATIVE,
                SellwildFailureSeverity.WARN,
                message = "Prebid auction result INVALID_CONFIG_ID",
                zoneId = "43",
            ),
            PrebidSetup.auctionResult("INVALID_CONFIG_ID", SellwildFailureComponent.NATIVE, "43"),
        )
    }
}
