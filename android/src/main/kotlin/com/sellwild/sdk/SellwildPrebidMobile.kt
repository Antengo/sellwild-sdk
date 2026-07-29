// SellwildPrebidMobile.kt — Prebid Mobile SDK bridge (required, not optional).
//
// In 1.3.0+, Prebid Mobile (3.x) and the Google Mobile Ads SDK (24.x) are
// REQUIRED dependencies of SellwildSDK. SellwildAdView runs a native Prebid
// auction and renders into an `AdManagerAdView` — there is no WebView in the
// banner ad path.
//
// This file is the single point of contact between the SDK and Prebid Mobile.
// It reads its parameters off `SellwildConfig.prebidServer` /
// `config.remoteJson["S2S_CONFIG"]` so partners do not have to wire Prebid
// by hand.

package com.sellwild.sdk

import android.content.Context
import android.util.Log
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.admanager.AdManagerAdView
import org.json.JSONObject
import com.sellwild.prebid.BannerAdUnit
import com.sellwild.prebid.BannerParameters
import com.sellwild.prebid.OnCompleteListener
import com.sellwild.prebid.SellwildPrebid
import com.sellwild.prebid.ResultCode
import com.sellwild.prebid.Signals
import com.sellwild.prebid.TargetingParams
import com.sellwild.prebid.ExternalUserId

/**
 * Bootstrap + auction bridge for Prebid Mobile + GMA.
 *
 * Public surface:
 *  - [bootstrap] is idempotent. Safe to call from every `SellwildSDK.configure`
 *    result and from every `SellwildAdView.load()`. Only the first call
 *    actually initializes the underlying SDKs.
 *  - [runBannerAuction] runs a Prebid auction for an [AdManagerAdView] and
 *    triggers `loadAd()` after the auction completes. GAM still serves on
 *    no-bid, so ad fill is always attempted.
 */
object SellwildPrebidMobile {

    private const val TAG = "SellwildPrebidMobile"
    private const val DEFAULT_PREBID_ENDPOINT = "https://prebid.sellwild.com/openrtb2/auction"

    private val lock = Any()
    @Volatile private var didBootstrap = false
    // Whether PrebidMobile.initializeSdk reached SUCCEEDED. If not, callers
    // should skip the auction and load GAM directly so ads still serve when
    // Prebid Server is unreachable.
    @Volatile private var prebidReady = false

    // Publisher id resolved at bootstrap + partner-supplied geo, retained so
    // applyGlobalOrtb() re-emits both in one combined config (setGeo updates geo).
    @Volatile private var resolvedPublisherId: String? = null

    /** True once Prebid Mobile has reported a successful init. */
    @JvmStatic
    fun isReady(): Boolean = prebidReady

    /**
     * Initialize Prebid Mobile + GMA from a [SellwildConfig]. Idempotent —
     * subsequent calls are no-ops.
     *
     * Resolution order for the Prebid Server URL + account id:
     *   1. Typed [SellwildConfig.prebidServer] (set by SDK code or a partner override).
     *   2. Raw CDN passthrough at `config.remoteJson["S2S_CONFIG"]`.
     *   3. Sellwild's hosted Prebid Server (so the SDK does *something* on
     *      partial CMS configuration).
     */
    @JvmStatic
    fun bootstrap(context: Context, config: SellwildConfig): Boolean {
        synchronized(lock) {
            if (didBootstrap) return true

            // GMA first — Prebid hands off to GAM, GAM must be live before any
            // ad request runs. start() is idempotent on the GMA side too.
            try {
                MobileAds.initialize(context.applicationContext) { /* no-op */ }
            } catch (e: Throwable) {
                Log.w(TAG, "MobileAds.initialize threw: ${e.message}")
            }

            // Parse remoteJson ONCE per bootstrap — resolvePrebidServer and
            // resolvePublisherId both read S2S_CONFIG out of it, and each parse
            // allocates a fresh JSONObject tree over what can be a multi-KB blob.
            val remoteRoot = config.remoteJson?.let {
                runCatching { JSONObject(it) }.getOrNull()
            }
            val resolved = resolvePrebidServer(config, remoteRoot)

            SellwildPrebid.setPrebidServerAccountId(resolved.accountId)
            SellwildPrebid.setTimeoutMillis(config.prebidServer?.timeout ?: 1500)
            SellwildPrebid.setShareGeoLocation(true)
            if (config.debug) {
                SellwildPrebid.setLogLevel(SellwildPrebid.LogLevel.DEBUG)
            }
            // Server-side auction debug — adds ext.prebid.debug=1 + returnallbidstatus
            // so the PBS response carries the full debug block. Separate from log level.
            SellwildPrebid.setPbsDebug(config.pbsDebug)

            // Populate ortb2.app so DSPs see in-app traffic, not web traffic.
            config.appBundleId?.let { TargetingParams.setBundleName(it) }
            config.appStoreUrl?.let { TargetingParams.setStoreUrl(it) }

            // app.publisher.id must equal the sellers.json seller id (== schain
            // sid) for supply-chain coherence. No dedicated setter maps to
            // app.publisher.id, so inject it via the global ORTB config, sourced
            // from the CDN S2S_CONFIG blob (publisherId / sellerId).
            // Capture the resolved publisher id + declared geo, then emit ONE
            // combined global ORTB config (app.publisher.id + device.geo).
            // setGlobalOrtbConfig is last-write-wins, so both live in a single
            // object; a later setGeo(...) re-emits it with updated geo.
            resolvedPublisherId = resolvePublisherId(remoteRoot)
            if (SellwildGeoStore.current == null) SellwildGeoStore.current = config.geo
            applyGlobalOrtb()

            try {
                SellwildPrebid.initializeSdk(context.applicationContext, resolved.url) { status ->
                    Log.d(TAG, "SellwildPrebid.initializeSdk status: $status")
                    // Status enum values are SUCCEEDED / FAILED in Prebid 3.x.
                    prebidReady = status.toString().equals("SUCCEEDED", ignoreCase = true)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "SellwildPrebid.initializeSdk threw", e)
            }

            didBootstrap = true
            return true
        }
    }

    /**
     * Run a Prebid auction for an already-constructed [AdManagerAdView] and
     * trigger `loadAd()` once the auction completes. GAM serves on no-bid.
     *
     * @param adView         A configured [AdManagerAdView] (ad unit id, ad
     *                       sizes, ad listener already set by the caller).
     * @param configId       Prebid Server stored impression id.
     * @param widthDp        Banner width in dp.
     * @param heightDp       Banner height in dp.
     * @param bidderParams   Optional CDN bidder params (raw CONSTANT_CASE
     *                       passthrough). Forwarded to Prebid Server as
     *                       `imp.ext.prebid.bidder` JSON.
     * @param completion     Called with the Prebid [ResultCode] after the
     *                       auction completes (and after `loadAd()` is fired).
     */
    @JvmStatic
    @JvmOverloads
    fun runBannerAuction(
        adView: AdManagerAdView,
        configId: String,
        widthDp: Int,
        heightDp: Int,
        bidderParams: Map<String, Any?> = emptyMap(),
        video: Boolean = false,
        adSizes: List<SellwildAdSizes.Size> = emptyList(),
        completion: ((ResultCode) -> Unit)? = null,
    ) {
        val unit = if (video) {
            // Multiformat: request banner AND outstream video. GAM renders the
            // winning creative (video fill needs a GAM outstream line item).
            BannerAdUnit(configId, widthDp, heightDp, SellwildVideo.bannerVideoFormats()).apply {
                videoParameters = SellwildVideo.outstreamParameters()
            }
        } else {
            BannerAdUnit(configId, widthDp, heightDp)
        }
        // Additional banner sizes for the Prebid bid — `adSizes` is primary-first
        // (matching the ctor size), so applyPrebid drops the primary.
        if (adSizes.isNotEmpty()) SellwildAdSizes.applyPrebid(adSizes, unit)
        unit.bannerParameters = BannerParameters().apply {
            api = listOf(Signals.Api.MRAID_3, Signals.Api.OMID_1)
        }

        ortbExtJson(bidderParams)?.let { unit.setImpOrtbConfig(it) }

        val request = AdManagerAdRequest.Builder().build()
        unit.fetchDemand(request, OnCompleteListener { result ->
            // Whether or not Prebid won, always trigger GAM load so GAM's own
            // demand can fill on no-bid.
            adView.loadAd(request)
            completion?.invoke(result)
        })
    }

    /**
     * Set partner-supplied external/extended user IDs, emitted as OpenRTB
     * `user.ext.eids` on every native Prebid auction.
     *
     * - Call once per user session, after [bootstrap] and before/at the first
     *   [SellwildAdView] load.
     * - Prebid Mobile does NOT persist eids across app restarts — re-set on launch.
     * - Delivery to each bidder is additionally governed by eid permissions in the
     *   Prebid Server stored request; by default Prebid Server forwards eids.
     * - Pass an empty list to clear previously set eids (e.g. on logout).
     */
    @JvmStatic
    fun setExternalUserIds(eids: List<SellwildEid>) {
        val mapped = eids.map { eid ->
            val uids = eid.uids.map { u ->
                ExternalUserId.UniqueId(u.id, u.atype).apply {
                    u.ext?.let { setExt(HashMap<String, Any>(it)) }
                }
            }
            ExternalUserId(eid.source, uids)
        }
        TargetingParams.setExternalUserIds(mapped)
    }

    /**
     * Set or update partner-supplied geo at runtime, emitted as OpenRTB
     * `device.geo` on subsequent native Prebid auctions. Use when location is
     * resolved or changes after [bootstrap]. Re-emits the combined ORTB config so
     * `app.publisher.id` is preserved. Pass null to clear geo.
     *
     * The value is also stored in [SellwildGeoStore.current], so other SDK
     * surfaces (e.g. the listings feed) and host-app code can read the current
     * geo — it is not confined to the Prebid auction path.
     */
    @JvmStatic
    fun setGeo(geo: SellwildGeo?) {
        SellwildGeoStore.current = geo
        applyGlobalOrtb()
    }

    /**
     * Emit one combined global ORTB config carrying `app.publisher.id` and
     * `device.geo`. setGlobalOrtbConfig is last-write-wins, so both live in a
     * single object.
     */
    private fun applyGlobalOrtb() {
        val root = JSONObject()
        resolvedPublisherId?.takeIf { it.isNotEmpty() }?.let { pid ->
            root.put("app", JSONObject().apply {
                put("publisher", JSONObject().apply { put("id", pid) })
            })
        }
        SellwildGeoStore.current?.toOrtbGeo()?.let { geo ->
            root.put("device", JSONObject().apply { put("geo", geo) })
        }
        if (root.length() > 0) {
            TargetingParams.setGlobalOrtbConfig(root.toString())
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    internal data class PrebidServerResolution(val url: String, val accountId: String)

    /**
     * Pull the OpenRTB app.publisher.id (== sellers.json seller id / schain sid)
     * from the CDN S2S_CONFIG blob. Accepts `publisherId` or `sellerId`.
     *
     * Takes the already-parsed remoteJson root so bootstrap() and its siblings
     * don't each re-parse the same string.
     */
    internal fun resolvePublisherId(remoteRoot: JSONObject?): String? {
        val s2s = remoteRoot?.optJSONObject("S2S_CONFIG") ?: return null
        val id = s2s.optString("publisherId", "").ifEmpty { s2s.optString("sellerId", "") }
        return id.ifEmpty { null }
    }

    /**
     * Resolve the Prebid Server URL + account id. [remoteRoot] is the
     * already-parsed [SellwildConfig.remoteJson]; callers should parse once and
     * share it across resolvers to avoid duplicate work.
     */
    internal fun resolvePrebidServer(
        config: SellwildConfig,
        remoteRoot: JSONObject?,
    ): PrebidServerResolution {
        // 1. Typed config.
        config.prebidServer?.let {
            return PrebidServerResolution(url = it.endpoint, accountId = it.accountId)
        }

        // 2. Raw CDN passthrough.
        val s2s = remoteRoot?.optJSONObject("S2S_CONFIG")
        if (s2s != null) {
            val url = s2s.optString("endpoint", "")
                .ifEmpty { s2s.optString("url", "") }
                .ifEmpty { DEFAULT_PREBID_ENDPOINT }
            val account = s2s.optString("accountId", "")
                .ifEmpty { s2s.optString("account", "") }
                .ifEmpty { config.partnerCode }
            return PrebidServerResolution(url = url, accountId = account)
        }

        // 3. Sellwild-hosted default.
        return PrebidServerResolution(
            url = DEFAULT_PREBID_ENDPOINT,
            accountId = config.partnerCode,
        )
    }

    /**
     * Wrap CDN bidder params as `imp.ext.prebid.bidder` JSON. Bidder names are
     * lowercased — CDN ships CONSTANT_CASE, Prebid expects lowercase.
     */
    internal fun ortbExtJson(params: Map<String, Any?>): String? {
        if (params.isEmpty()) return null
        val bidders = JSONObject()
        for ((k, v) in params) {
            if (v == null) continue
            bidders.put(k.lowercase(), v)
        }
        if (bidders.length() == 0) return null
        val ext = JSONObject().apply {
            put("ext", JSONObject().apply {
                put("prebid", JSONObject().apply {
                    put("bidder", bidders)
                })
            })
        }
        return ext.toString()
    }

    // Test-only seam to reset the bootstrap latch.
    internal fun resetForTesting() {
        synchronized(lock) { didBootstrap = false }
    }
}

/** One id value within a [SellwildEid] source. */
data class SellwildEidUid(
    /** The raw ID token from the provider. */
    val id: String,
    /** OpenRTB agent type: 1 = cookie/web, 2 = in-app device id, 3 = person-based. */
    val atype: Int,
    /** Optional provider-specific extension, e.g. mapOf("rtiPartner" to "TDID"). */
    val ext: Map<String, Any>? = null,
)

/** One identity source for user.ext.eids (e.g. "uidapi.com", "id5-sync.com"). */
data class SellwildEid(
    val source: String,
    val uids: List<SellwildEidUid>,
)
