package com.sellwild.sdk.core

import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONObject

/**
 * Pure decisions behind SellwildAdView: refresh, the Prebid cold-start wait, sizes, the house
 * backdrop, resume, layout self-heal, the GAM ad unit, bidder params and which ad failures
 * are real failures rather than no-fill. The view is the thin shell that acts on them.
 */
internal object AdDecisions {

    /**
     * Floor for both refresh timers: a storm guard against a mis-scaled AD_REFRESH_INTERVAL
     * (a seconds value read as milliseconds).
     */
    const val MIN_REFRESH_INTERVAL_MS = 10_000L

    /** The cold-start wait for Prebid init: up to 8 tries, 150 ms apart (about 1.2 s). */
    const val MAX_PREBID_WAIT_ATTEMPTS = 8
    const val PREBID_WAIT_INTERVAL_MS = 150L

    /** Google's test ad units. /6499/example/banner fills only 320x50; the adaptive unit fills the rest. */
    const val GAM_TEST_AD_UNIT_BANNER = "/6499/example/banner"
    const val GAM_TEST_AD_UNIT_ADAPTIVE = "/21775744923/example/adaptive-banner"

    /** GMA's no-fill codes (AdRequest.ERROR_CODE_NO_FILL, ERROR_CODE_MEDIATION_NO_FILL). */
    const val GAM_NO_FILL = 3
    const val GAM_MEDIATION_NO_FILL = 9

    /** The type the Prebid fork gives a no-fill render failure (AdException.NO_BIDS). */
    const val PREBID_NO_BIDS = "No bids"

    // ── Refresh ──────────────────────────────────────────────────────────────

    /**
     * The mobile refresh cap: AD_REFRESH_MAX_MOBILE when set, else the shared AD_REFRESH_MAX
     * (as on iOS and the web), so a partner who sets only the shared key still gets refresh.
     */
    fun refreshMax(mobileMax: Int, sharedMax: Int): Int = if (mobileMax > 0) mobileMax else sharedMax

    /** The refresh interval, floored at [MIN_REFRESH_INTERVAL_MS]. */
    fun refreshIntervalMs(configuredMs: Long): Long = configuredMs.coerceAtLeast(MIN_REFRESH_INTERVAL_MS)

    /** The Prebid rendering banner's own auto-refresh delay, in whole seconds. */
    fun autoRefreshDelaySeconds(configuredMs: Long): Int = (refreshIntervalMs(configuredMs) / 1000L).toInt()

    /** Whether one more refresh may be scheduled: refresh is on and [count] is under [max]. */
    fun mayRefresh(count: Int, max: Int): Boolean = max > 0 && count < max

    /**
     * Whether the Prebid rendering banner must stop its own auto-refresh after the render that
     * brought its render count to [count]: the fork's refresh is otherwise unbounded.
     */
    fun prebidRefreshSpent(count: Int, max: Int): Boolean = max > 0 && count > max

    // ── Prebid cold start ────────────────────────────────────────────────────

    /** What a load does while Prebid init may still be running. */
    enum class ColdStart {
        /** Prebid is ready: run the auction. */
        READY,

        /** Not ready yet: try again in [PREBID_WAIT_INTERVAL_MS]. */
        WAIT,

        /** Still not ready after the whole wait: load without Prebid (ad.prebid_init.timeout). */
        TIMED_OUT,
    }

    fun coldStart(ready: Boolean, attempts: Int, maxAttempts: Int = MAX_PREBID_WAIT_ATTEMPTS): ColdStart = when {
        ready -> ColdStart.READY
        attempts < maxAttempts -> ColdStart.WAIT
        else -> ColdStart.TIMED_OUT
    }

    // ── Resume ───────────────────────────────────────────────────────────────

    /** The stack SellwildAdView resolved, as [resume] sees it. */
    enum class Stack { GAM, PREBID_ONLY }

    /** What resume() does after a pause. */
    enum class Resume {
        /** Restart the GAM refresh timer. */
        SCHEDULE_REFRESH,

        /** Keep the rendered Prebid creative and resume its refresh on a delayed timer. */
        KEEP_CREATIVE,

        /** Re-issue the Prebid banner's loadAd() to restart its own refresh cadence. */
        RELOAD_PREBID,

        /** Nothing refreshes (refresh off, or native). */
        NOTHING,
    }

    /**
     * [nativeEnabled] and [keepCreative] read remote config, so they are asked only when the
     * answer matters, in the order the view always asked them.
     */
    fun resume(
        stack: Stack,
        refreshMax: Int,
        nativeEnabled: () -> Boolean,
        hasRenderedCreative: Boolean,
        keepCreative: () -> Boolean,
    ): Resume = when {
        stack == Stack.GAM -> Resume.SCHEDULE_REFRESH
        refreshMax <= 0 || nativeEnabled() -> Resume.NOTHING
        hasRenderedCreative && keepCreative() -> Resume.KEEP_CREATIVE
        else -> Resume.RELOAD_PREBID
    }

    // ── Sizes and layout ─────────────────────────────────────────────────────

    /** [dp] in pixels at [density], truncated as the views always did. */
    fun px(dp: Int, density: Float): Int = (dp * density).toInt()

    /**
     * The size a Prebid render is reported and tightened to: the won creative size, or the
     * slot's primary size where the fork reports none (0).
     */
    fun renderedSize(wonWidth: Int, wonHeight: Int, primaryWidth: Int, primaryHeight: Int): Pair<Int, Int> =
        (if (wonWidth > 0) wonWidth else primaryWidth) to (if (wonHeight > 0) wonHeight else primaryHeight)

    /**
     * The size a view that the host never laid out heals to: its parent's, when the view is
     * 0-sized in either dimension and the parent is not. Null when there is nothing to heal.
     */
    fun healedSize(width: Int, height: Int, parentWidth: Int, parentHeight: Int): Pair<Int, Int>? {
        if (width != 0 && height != 0) return null
        if (parentWidth <= 0 || parentHeight <= 0) return null
        return parentWidth to parentHeight
    }

    // ── House backdrop ───────────────────────────────────────────────────────

    /** A slot big enough for a listing card: at least 300x250. */
    fun isMrec(widthDp: Int, heightDp: Int): Boolean = widthDp >= 300 && heightDp >= 250

    /** What the house backdrop behind the paid creative shows. */
    sealed class House<out I, out L> {
        object None : House<Nothing, Nothing>()

        class Image<out I>(val image: I) : House<I, Nothing>()

        class Listing<out L>(val listing: L) : House<Nothing, L>()
    }

    /**
     * CMS house [image] first, then a feed-supplied [listing] (MREC slots only: a 320x50 banner
     * is too small for a card), else nothing; nothing at all when house ads are off.
     */
    fun <I : Any, L : Any> house(enabled: Boolean, image: I?, listing: L?, widthDp: Int, heightDp: Int): House<I, L> = when {
        !enabled -> House.None
        image != null -> House.Image(image)
        listing != null && isMrec(widthDp, heightDp) -> House.Listing(listing)
        else -> House.None
    }

    // ── Video ────────────────────────────────────────────────────────────────

    /**
     * What a Prebid render whose winning bid is video means. [mismatch]: video won a zone that
     * never enabled it. [mute]: the players are muted unless the zone enabled video and sound.
     */
    class VideoCheck(val mismatch: Boolean, val mute: Boolean)

    /** [soundEnabled] reads remote config, so it is asked only for a zone that expects video. */
    fun videoCheck(expectedVideo: Boolean, soundEnabled: () -> Boolean): VideoCheck =
        VideoCheck(mismatch = !expectedVideo, mute = !(expectedVideo && soundEnabled()))

    // ── Which ad failures are failures ───────────────────────────────────────

    /** GAM no-fill is not a failure: the adError event covers it (FAILURES.md 4.3). */
    fun isGamNoFill(code: Int): Boolean = code == GAM_NO_FILL || code == GAM_MEDIATION_NO_FILL

    /**
     * A Prebid rendering failure is no-fill when the fork's AdException message starts with
     * its NO_BIDS type ("No bids: ..."), which is how the fork reports an auction without a
     * usable bid.
     */
    fun isPrebidNoFill(message: String?): Boolean = message != null && message.startsWith(PREBID_NO_BIDS)

    /**
     * Whether a Prebid auction result is a failure worth reporting: anything but success,
     * no bids, or a timeout without bids (FAILURES.md 4.3 item 1). [resultName] is the fork's
     * ResultCode name; null (a callback without one) is a failure.
     */
    fun isAuctionFailure(resultName: String?): Boolean =
        resultName != "SUCCESS" && resultName != "NO_BIDS" && resultName != "TIMEOUT"

    // ── GAM ad unit ──────────────────────────────────────────────────────────

    /**
     * The GAM ad unit: the typed [gamTag], else the remote `GAM` value, else Google's test unit
     * for the slot size (320x50: the banner unit; any other size, or 0x0 for none: the adaptive
     * unit). The test unit earns nothing, so choosing it is reported as ad.gam_unit.missing.
     */
    fun gamAdUnit(gamTag: String?, remote: JSONObject?, widthDp: Int, heightDp: Int): Resolved<String> {
        if (!gamTag.isNullOrEmpty()) return Resolved(gamTag)
        // JSON null is no unit: a device's optString would give the text "null".
        val remoteUnit = RemoteValues.optText(remote, "GAM")
        if (!remoteUnit.isNullOrEmpty()) return Resolved(remoteUnit)
        val testUnit = if (widthDp == 320 && heightDp == 50) GAM_TEST_AD_UNIT_BANNER else GAM_TEST_AD_UNIT_ADAPTIVE
        val issue = Issue(
            SellwildFailureCode.AD_GAM_UNIT_MISSING,
            SellwildFailureComponent.BANNER,
            SellwildFailureSeverity.FATAL,
            message = "no GAM ad unit configured; using the test unit $testUnit",
        )
        return Resolved(testUnit, listOf(issue))
    }

    // ── Bidder params ────────────────────────────────────────────────────────

    /**
     * Bidder configs from the raw CDN payload, forwarded as the .both auction's
     * imp.ext.prebid.bidder: every CONSTANT_CASE key that is not first-class typed config. A
     * per-platform or _ALL suffix (…_ANDROID, _IOS, _ALL_ANDROID, _ALL_IOS) is stripped before
     * the deny check, so per-platform zone ids never leak in as bidders.
     */
    fun bidderParams(remote: JSONObject?): Map<String, Any?> {
        if (remote == null) return emptyMap()
        val params = linkedMapOf<String, Any?>()
        for (key in remote.keys()) {
            if (key != key.uppercase()) continue
            val base = key.removeSuffix("_ANDROID").removeSuffix("_IOS").removeSuffix("_ALL")
            if (key in NON_BIDDER_REMOTE_KEYS || base in NON_BIDDER_REMOTE_KEYS) continue
            params[key] = remote.opt(key)
        }
        return params
    }

    /** CDN keys that are first-class typed config, not bidder params. */
    private val NON_BIDDER_REMOTE_KEYS: Set<String> = setOf(
        "CODE", "LISTINGS", "SLUG", "NAME", "TITLE", "COLORS", "LINK_TEXT",
        "BUY_NOW_TEXT", "FONT_FAMILY", "FONT_URL", "FONT_COLOR", "PRICE_COLOR",
        "PRICE_FONT_COLOR", "MARGIN_BOTTOM", "CARD_WIDTH", "OVERLAY_TITLE",
        "CSS", "WATERMARK", "WATERMARK_TITLE", "BANNER_ZID", "BOTTOM_BANNER_ZID",
        "MOBILE_BANNER_ZID", "MOBILE_ZID", "DISPLAY_ZID", "HIDE_BANNER_TOP",
        "HIDE_BANNER_BOTTOM", "GAM", "DISABLE_GPT", "AD_UNITS", "SAFE_FRAME",
        "AD_DISABLE_DISPLAY", "AD_STACK", "AD_STACK_BY_ZONE", "AD_REFRESH_MAX",
        "AD_REFRESH_MAX_MOBILE", "AD_REFRESH_INTERVAL", "MAX_FAILED_AUCTIONS",
        "PREBID_DEFER", "PREBID_SRC", "AD_GEO_BLOCK", "AD_GEO_BLOCK_REFRESH",
        "GPP_ENABLED", "TCF_VERSION", "CONSENT_MANAGEMENT", "SCHAIN_SID",
        "S2S_CONFIG", "IAB_CATS", "APP_BUNDLE_ID", "APP_STORE_URL",
        "ENABLE_INTERSTITIAL", "ENABLE_FULLSCREEN_VIDEO",
        "INTERSTITIALS_PER_SESSION", "VIDEO_TAKEOVERS_PER_SESSION", "DEBUG",
        "MEMBERSHIP_TYPE", "PBS_DEBUG",
        // Ad-format toggles, read by SellwildVideo and SellwildNative.
        "VIDEO_ENABLED", "VIDEO_ENABLED_BY_ZONE",
        "VIDEO_SOUND_ENABLED", "VIDEO_SOUND_ENABLED_BY_ZONE",
        "NATIVE_ENABLED", "NATIVE_ENABLED_BY_ZONE",
        "NATIVE_MAX_HEIGHT", "NATIVE_MAX_HEIGHT_BY_ZONE",
        // Native placement id (SellwildNative.resolveConfigId); the per-platform and _ALL
        // variants are caught by the suffix strip.
        "NATIVE_ZID",
        "BANNER_SIZES", "BANNER_SIZES_BY_ZONE",
        // GrowthCode identity, read by SellwildGrowthCode.
        "GROWTHCODE_ENABLED", "GROWTHCODE_ENABLED_BY_ZONE",
        "GROWTHCODE_PARTNER_ID", "GROWTHCODE_ENDPOINT", "GROWTHCODE_SYNC_URL",
        "GROWTHCODE_SEND_MAID", "GROWTHCODE_TTL_HOURS",
    )
}

/** Remote flags the ad and feed views read, with the exact coercion each always had. */
internal object AdFlags {
    private const val KEEP_CREATIVE = "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH"
    private const val PAUSE_DETACHED = "MOBILE_PAUSE_REFRESH_DETACHED"
    private const val SELF_HEAL = "MOBILE_LAYOUT_SELF_HEAL"

    /**
     * MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH, default off: a prebidOnly reattach keeps the
     * rendered creative (so its viewability tracker can fire) instead of re-auctioning.
     */
    fun keepCreativeOnReattach(remote: JSONObject?): Boolean = RemoteValues.isOn(RemoteValues.optAny(remote, KEEP_CREATIVE))

    /** MOBILE_LAYOUT_SELF_HEAL, default off. */
    fun layoutSelfHeal(remote: JSONObject?): Boolean = RemoteValues.isOn(RemoteValues.optAny(remote, SELF_HEAL))

    /**
     * MOBILE_PAUSE_REFRESH_DETACHED, default on. A boolean or number as usual; text is on only
     * for "1"/"true"/"yes"/"on"; any other value (object, array) and no value keep it on.
     */
    fun pauseRefreshWhenDetached(remote: JSONObject?): Boolean = when (val v = RemoteValues.optAny(remote, PAUSE_DETACHED)) {
        null -> true
        is String -> RemoteValues.isOn(v)
        else -> RemoteValues.isNotOff(v)
    }
}
