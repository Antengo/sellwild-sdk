package com.sellwild.sdk.core

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pure decisions behind SellwildAdView (AdDecisions) and its remote flags (AdFlags). */
class AdDecisionsTest {

    private fun remote(vararg overrides: Pair<String, Any?>): JSONObject = AppConfigFactory.checked(mapOf(*overrides))

    // ── Refresh ──────────────────────────────────────────────────────────────

    @Test
    fun `the mobile refresh cap wins when set, else the shared one`() {
        assertEquals(6, AdDecisions.refreshMax(mobileMax = 6, sharedMax = 5))
        assertEquals(5, AdDecisions.refreshMax(mobileMax = 0, sharedMax = 5))
        assertEquals(0, AdDecisions.refreshMax(mobileMax = -1, sharedMax = 0))
    }

    @Test
    fun `the refresh interval is floored at 10 seconds, and Prebid gets whole seconds`() {
        assertEquals(10_000L, AdDecisions.refreshIntervalMs(45))
        assertEquals(30_000L, AdDecisions.refreshIntervalMs(30_000))
        assertEquals(10, AdDecisions.autoRefreshDelaySeconds(0))
        assertEquals(45, AdDecisions.autoRefreshDelaySeconds(45_999))
    }

    @Test
    fun `one more refresh needs refresh on and the count under the cap`() {
        assertTrue(AdDecisions.mayRefresh(count = 2, max = 3))
        assertFalse(AdDecisions.mayRefresh(count = 3, max = 3))
        assertFalse(AdDecisions.mayRefresh(count = 0, max = 0))
    }

    @Test
    fun `Prebid's own refresh is spent once its renders pass the cap`() {
        assertFalse(AdDecisions.prebidRefreshSpent(count = 3, max = 3))
        assertTrue(AdDecisions.prebidRefreshSpent(count = 4, max = 3))
        assertFalse(AdDecisions.prebidRefreshSpent(count = 9, max = 0))
    }

    // ── Cold start ───────────────────────────────────────────────────────────

    @Test
    fun `a load waits for Prebid 8 times, then times out, and runs at once when it is ready`() {
        assertEquals(AdDecisions.ColdStart.READY, AdDecisions.coldStart(ready = true, attempts = 8))
        assertEquals(AdDecisions.ColdStart.WAIT, AdDecisions.coldStart(ready = false, attempts = 0))
        assertEquals(AdDecisions.ColdStart.WAIT, AdDecisions.coldStart(ready = false, attempts = 7))
        assertEquals(AdDecisions.ColdStart.TIMED_OUT, AdDecisions.coldStart(ready = false, attempts = 8))
        assertEquals(AdDecisions.ColdStart.TIMED_OUT, AdDecisions.coldStart(ready = false, attempts = 1, maxAttempts = 1))
    }

    @Test
    fun `the prebidOnly refresh budget is the first render plus max refreshes (origin d8c2d96)`() {
        assertTrue(AdDecisions.hasPrebidRefreshBudget(renderCount = 1, max = 1))
        assertFalse(AdDecisions.hasPrebidRefreshBudget(renderCount = 2, max = 1))
        assertFalse(AdDecisions.hasPrebidRefreshBudget(renderCount = 0, max = 0))
    }

    // ── Resume ───────────────────────────────────────────────────────────────

    private val never: () -> Boolean = { throw AssertionError("asked a remote flag it did not need") }

    @Test
    fun `resume on GAM restarts the refresh timer without reading remote flags`() {
        assertEquals(
            AdDecisions.Resume.SCHEDULE_REFRESH,
            AdDecisions.resume(
                AdDecisions.Stack.GAM,
                hasRefreshBudget = false,
                nativeEnabled = never,
                hasRenderedCreative = true,
                keepCreative = never,
            ),
        )
    }

    @Test
    fun `resume on Prebid does nothing without refresh budget or for native`() {
        assertEquals(
            AdDecisions.Resume.NOTHING,
            AdDecisions.resume(
                AdDecisions.Stack.PREBID_ONLY,
                hasRefreshBudget = false,
                nativeEnabled = never,
                hasRenderedCreative = true,
                keepCreative = never,
            ),
        )
        assertEquals(
            AdDecisions.Resume.NOTHING,
            AdDecisions.resume(
                AdDecisions.Stack.PREBID_ONLY,
                hasRefreshBudget = true,
                nativeEnabled = { true },
                hasRenderedCreative = true,
                keepCreative = never,
            ),
        )
    }

    @Test
    fun `resume on Prebid keeps a rendered creative only when the flag says so`() {
        assertEquals(
            AdDecisions.Resume.KEEP_CREATIVE,
            AdDecisions.resume(
                AdDecisions.Stack.PREBID_ONLY,
                hasRefreshBudget = true,
                nativeEnabled = { false },
                hasRenderedCreative = true,
                keepCreative = { true },
            ),
        )
        assertEquals(
            AdDecisions.Resume.RELOAD_PREBID,
            AdDecisions.resume(
                AdDecisions.Stack.PREBID_ONLY,
                hasRefreshBudget = true,
                nativeEnabled = { false },
                hasRenderedCreative = true,
                keepCreative = { false },
            ),
        )
        // Nothing rendered yet: the flag is not even read.
        assertEquals(
            AdDecisions.Resume.RELOAD_PREBID,
            AdDecisions.resume(
                AdDecisions.Stack.PREBID_ONLY,
                hasRefreshBudget = true,
                nativeEnabled = { false },
                hasRenderedCreative = false,
                keepCreative = never,
            ),
        )
    }

    // ── Sizes and layout ─────────────────────────────────────────────────────

    @Test
    fun `dp to px truncates`() {
        assertEquals(787, AdDecisions.px(300, 2.625f))
        assertEquals(50, AdDecisions.px(50, 1f))
    }

    @Test
    fun `a Prebid render reports the won size, or the primary where the fork reports none`() {
        assertEquals(320 to 50, AdDecisions.renderedSize(320, 50, 300, 250))
        assertEquals(300 to 250, AdDecisions.renderedSize(0, 0, 300, 250))
        assertEquals(320 to 250, AdDecisions.renderedSize(320, -1, 300, 250))
        assertEquals(300 to 50, AdDecisions.renderedSize(0, 50, 300, 250))
    }

    @Test
    fun `a collapsed view heals to its parent, and a sized one does not`() {
        assertEquals(1080 to 600, AdDecisions.healedSize(0, 0, 1080, 600))
        assertEquals(1080 to 600, AdDecisions.healedSize(1080, 0, 1080, 600))
        assertEquals(1080 to 600, AdDecisions.healedSize(0, 600, 1080, 600))
        assertNull(AdDecisions.healedSize(1080, 600, 1080, 600))
        assertNull(AdDecisions.healedSize(0, 0, 0, 600))
        assertNull(AdDecisions.healedSize(0, 0, 1080, 0))
    }

    // ── House backdrop ───────────────────────────────────────────────────────

    @Test
    fun `the house backdrop shows the image first, a listing only in an MREC, and nothing when off`() {
        val image = "image"
        val listing = 7
        assertEquals("image", (AdDecisions.house(true, image, listing, 320, 50) as AdDecisions.House.Image).image)
        assertEquals(7, (AdDecisions.house(true, null, listing, 300, 250) as AdDecisions.House.Listing).listing)
        assertSame(AdDecisions.House.None, AdDecisions.house(true, null, listing, 320, 50))
        assertSame(AdDecisions.House.None, AdDecisions.house(true, null, listing, 300, 50))
        assertSame(AdDecisions.House.None, AdDecisions.house<String, Int>(true, null, null, 300, 250))
        assertSame(AdDecisions.House.None, AdDecisions.house(false, image, listing, 300, 250))
        assertTrue(AdDecisions.isMrec(728, 600))
        assertFalse(AdDecisions.isMrec(299, 250))
    }

    // ── Video ────────────────────────────────────────────────────────────────

    @Test
    fun `video on a banner-only zone is a mismatch and muted, and sound is asked only for a video zone`() {
        val banner = AdDecisions.videoCheck(expectedVideo = false, soundEnabled = never)
        assertTrue(banner.mismatch)
        assertTrue(banner.mute)

        val quiet = AdDecisions.videoCheck(expectedVideo = true) { false }
        assertFalse(quiet.mismatch)
        assertTrue(quiet.mute)

        val loud = AdDecisions.videoCheck(expectedVideo = true) { true }
        assertFalse(loud.mute)
    }

    // ── Failures vs no-fill ──────────────────────────────────────────────────

    @Test
    fun `GAM no-fill and mediation no-fill are not failures, other codes are`() {
        assertTrue(AdDecisions.isGamNoFill(3))
        assertTrue(AdDecisions.isGamNoFill(9))
        assertFalse(AdDecisions.isGamNoFill(0))
        assertFalse(AdDecisions.isGamNoFill(2))
    }

    @Test
    fun `a Prebid render failure is no-fill only when the fork says No bids`() {
        assertTrue(AdDecisions.isPrebidNoFill("No bids: There are no bids or bids don't have required targeting keywords"))
        assertFalse(AdDecisions.isPrebidNoFill("Server error: 503"))
        assertFalse(AdDecisions.isPrebidNoFill(null))
    }

    @Test
    fun `an auction fails unless it succeeded, had no bids or timed out without bids`() {
        assertFalse(AdDecisions.isAuctionFailure("SUCCESS"))
        assertFalse(AdDecisions.isAuctionFailure("NO_BIDS"))
        assertFalse(AdDecisions.isAuctionFailure("TIMEOUT"))
        assertTrue(AdDecisions.isAuctionFailure("INVALID_CONFIG_ID"))
        assertTrue(AdDecisions.isAuctionFailure("NETWORK_ERROR"))
        assertTrue(AdDecisions.isAuctionFailure(null))
    }

    // ── GAM ad unit ──────────────────────────────────────────────────────────

    @Test
    fun `the GAM unit is the typed tag, else the remote GAM, with no issue`() {
        val cdn = remote("GAM" to "/99999/cdn/banner")

        assertEquals(Resolved("/12345/weatherbug/banner_top"), AdDecisions.gamAdUnit("/12345/weatherbug/banner_top", cdn, 320, 50))
        assertEquals(Resolved("/99999/cdn/banner"), AdDecisions.gamAdUnit(null, cdn, 320, 50))
        assertEquals(Resolved("/99999/cdn/banner"), AdDecisions.gamAdUnit("", cdn, 320, 50))
    }

    @Test
    fun `no unit falls back to the size's test unit and reports ad_gam_unit_missing`() {
        val banner = AdDecisions.gamAdUnit(null, remote("GAM" to ""), 320, 50)
        val mrec = AdDecisions.gamAdUnit(null, null, 300, 250)
        val unsized = AdDecisions.gamAdUnit(null, remote(), 0, 0)
        val tall = AdDecisions.gamAdUnit(null, null, 320, 250)

        assertEquals(AdDecisions.GAM_TEST_AD_UNIT_BANNER, banner.value)
        assertEquals(AdDecisions.GAM_TEST_AD_UNIT_ADAPTIVE, mrec.value)
        assertEquals(AdDecisions.GAM_TEST_AD_UNIT_ADAPTIVE, unsized.value)
        assertEquals(AdDecisions.GAM_TEST_AD_UNIT_ADAPTIVE, tall.value)
        val issue = banner.issues.single()
        assertEquals(SellwildFailureCode.AD_GAM_UNIT_MISSING, issue.code)
        assertEquals(SellwildFailureComponent.BANNER, issue.component)
        assertEquals(SellwildFailureSeverity.FATAL, issue.severity)
        assertEquals("no GAM ad unit configured; using the test unit /6499/example/banner", issue.message)
    }

    @Test
    fun `a JSON null GAM is no unit`() {
        val resolved = AdDecisions.gamAdUnit(null, AppConfigFactory.offSchema(mapOf("GAM" to JSONObject.NULL)), 300, 250)

        assertEquals(AdDecisions.GAM_TEST_AD_UNIT_ADAPTIVE, resolved.value)
        assertEquals(1, resolved.issues.size)
    }

    // ── AdFlags ──────────────────────────────────────────────────────────────

    @Test
    fun `keep-creative and self-heal are default-off flags`() {
        assertFalse(AdFlags.keepCreativeOnReattach(null))
        assertFalse(AdFlags.keepCreativeOnReattach(remote()))
        assertTrue(AdFlags.keepCreativeOnReattach(remote("MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH" to true)))
        assertTrue(AdFlags.keepCreativeOnReattach(remote("MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH" to "Yes")))
        assertFalse(AdFlags.keepCreativeOnReattach(remote("MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH" to 0)))

        assertFalse(AdFlags.layoutSelfHeal(remote()))
        assertTrue(AdFlags.layoutSelfHeal(remote("MOBILE_LAYOUT_SELF_HEAL" to 1)))
        assertFalse(AdFlags.layoutSelfHeal(remote("MOBILE_LAYOUT_SELF_HEAL" to "off")))
    }

    @Test
    fun `pause-when-detached is on unless false, 0 or text other than an on word`() {
        assertTrue(AdFlags.pauseRefreshWhenDetached(null))
        assertTrue(AdFlags.pauseRefreshWhenDetached(remote()))
        assertTrue(AdFlags.pauseRefreshWhenDetached(remote("MOBILE_PAUSE_REFRESH_DETACHED" to true)))
        assertFalse(AdFlags.pauseRefreshWhenDetached(remote("MOBILE_PAUSE_REFRESH_DETACHED" to false)))
        assertFalse(AdFlags.pauseRefreshWhenDetached(remote("MOBILE_PAUSE_REFRESH_DETACHED" to 0)))
        assertTrue(AdFlags.pauseRefreshWhenDetached(remote("MOBILE_PAUSE_REFRESH_DETACHED" to "on")))
        // Text that is not an on word turns it off (unlike the other default-on flags).
        assertFalse(AdFlags.pauseRefreshWhenDetached(remote("MOBILE_PAUSE_REFRESH_DETACHED" to "maybe")))
        // A value of another type keeps the default.
        assertTrue(AdFlags.pauseRefreshWhenDetached(AppConfigFactory.offSchema(mapOf("MOBILE_PAUSE_REFRESH_DETACHED" to JSONObject()))))
    }
}
