package com.sellwild.rnsdk

import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.sellwild.sdk.AdSize
import com.sellwild.sdk.SellwildAdStack
import com.sellwild.sdk.SellwildAdView
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildGrowthCodeConfig
import com.sellwild.sdk.SellwildLocalizedListingsConfig
import org.json.JSONObject

/**
 * Bridges the JS <SellwildBanner> component to the native
 * com.sellwild.sdk.SellwildAdView.
 *
 * Props (set from JS):
 *   - config: object — the resolved SellwildConfig (from configure()).
 *     Only the fields the native ad path reads are required:
 *       partnerCode, appBundleId, appStoreUrl, gamTag, debug,
 *       adRefreshMax, adRefreshMaxMobile, adRefreshIntervalMs,
 *       prebidServer (object), remote (object).
 *   - size: string — "320x50", "300x250", "728x90", "300x600", "160x600".
 *   - zoneId: string — Sellwild zone tag, e.g. "43".
 *
 * Events emitted to JS:
 *   - onAdLoaded
 *   - onAdImpression
 *   - onAdClicked
 *   - onAdFailed { message }
 *
 * The view defers calling SellwildAdView.setup() + load() until all three
 * required props (config, size, zoneId) have arrived in a single transaction.
 */
class SellwildBannerViewManager : SimpleViewManager<SellwildAdView>() {

    override fun getName(): String = REACT_CLASS

    /**
     * Per-view scratch state. We can't call SellwildAdView.setup() until
     * all three required props (config/size/zoneId) have arrived, so we
     * stash them here and apply on onAfterUpdateTransaction.
     *
     * Keyed by the ad view itself so multiple <SellwildBanner>s on screen
     * don't collide. Cleared on view drop.
     */
    private val pending = java.util.WeakHashMap<SellwildAdView, PendingProps>()

    private data class PendingProps(
        var config: ReadableMap? = null,
        var size: String? = null,
        var zoneId: String? = null,
        // Resolved ad stack ('both' | 'gamOnly' | 'prebidOnly'), computed in JS
        // and applied as the native override.
        var adStack: String? = null,
        // Guards against running fresh auctions on every JS re-render. We
        // only call setup() + load() once per identity tuple. Refresh of
        // the rendered ad is driven by the SDK's internal timer.
        var lastAppliedKey: String? = null,
    )

    override fun createViewInstance(reactContext: ThemedReactContext): SellwildAdView {
        val view = SellwildAdView(reactContext)
        pending[view] = PendingProps()
        view.listener = object : SellwildAdView.Listener {
            override fun onAdLoaded(adView: SellwildAdView) {
                emit(reactContext, adView, "onAdLoaded", null)
            }

            override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                val payload = com.facebook.react.bridge.Arguments.createMap().apply {
                    putString("zoneId", zoneId)
                }
                emit(reactContext, adView, "onAdImpression", payload)
            }

            override fun onHouseAdImpression(adView: SellwildAdView, zoneId: String) {
                val payload = com.facebook.react.bridge.Arguments.createMap().apply {
                    putString("zoneId", zoneId)
                }
                emit(reactContext, adView, "onHouseAdImpression", payload)
            }

            override fun onAdClicked(adView: SellwildAdView) {
                emit(reactContext, adView, "onAdClicked", null)
            }

            override fun onAdFailed(adView: SellwildAdView, message: String) {
                val payload = com.facebook.react.bridge.Arguments.createMap().apply {
                    putString("message", message)
                }
                emit(reactContext, adView, "onAdFailed", payload)
            }

            override fun onAdResize(adView: SellwildAdView, width: Int, height: Int) {
                val payload = com.facebook.react.bridge.Arguments.createMap().apply {
                    putInt("width", width)
                    putInt("height", height)
                }
                emit(reactContext, adView, "onAdResize", payload)
            }
        }
        return view
    }

    @ReactProp(name = "config")
    fun setConfig(view: SellwildAdView, value: ReadableMap?) {
        pendingFor(view).config = value
    }

    @ReactProp(name = "size")
    fun setSize(view: SellwildAdView, value: String?) {
        pendingFor(view).size = value
    }

    @ReactProp(name = "zoneId")
    fun setZoneId(view: SellwildAdView, value: String?) {
        pendingFor(view).zoneId = value
    }

    @ReactProp(name = "adStack")
    fun setAdStack(view: SellwildAdView, value: String?) {
        pendingFor(view).adStack = value
    }

    override fun onAfterUpdateTransaction(view: SellwildAdView) {
        super.onAfterUpdateTransaction(view)

        val p = pending[view] ?: return
        val configMap = p.config ?: return
        val sizeLabel = p.size ?: return
        val zoneId = p.zoneId ?: return

        val adSize = adSizeFromLabel(sizeLabel) ?: return

        // Skip if the props identity hasn't changed since last apply.
        val key = "$sizeLabel|$zoneId|${p.adStack}|${configMap.hashCode()}"
        if (p.lastAppliedKey == key) return
        p.lastAppliedKey = key

        val config = configFromMap(configMap)
        // JS resolves the stack from config and passes it as the override so
        // RN is deterministic; native still reads the raw `remote` for the rest.
        view.adStackOverride = p.adStack?.let { SellwildAdStack.parse(it) }
        view.setup(config, adSize, zoneId)
        view.load()
    }

    override fun onDropViewInstance(view: SellwildAdView) {
        // Tear down the native ad view on unmount so its GMA / Prebid banners are
        // released deterministically. Without this the views leak until GC (iOS
        // RN gets this for free via ARC deinit). Mirrors SellwildFeedView cleanup.
        view.destroy()
        pending.remove(view)
        super.onDropViewInstance(view)
    }

    private fun pendingFor(view: SellwildAdView): PendingProps =
        pending.getOrPut(view) { PendingProps() }

    override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> {
        return MapBuilder.builder<String, Any>()
            .put("onAdLoaded", MapBuilder.of("registrationName", "onAdLoaded"))
            .put("onAdImpression", MapBuilder.of("registrationName", "onAdImpression"))
            .put("onHouseAdImpression", MapBuilder.of("registrationName", "onHouseAdImpression"))
            .put("onAdClicked", MapBuilder.of("registrationName", "onAdClicked"))
            .put("onAdFailed", MapBuilder.of("registrationName", "onAdFailed"))
            .put("onAdResize", MapBuilder.of("registrationName", "onAdResize"))
            .build()
    }

    private fun emit(
        context: ReactContext,
        view: SellwildAdView,
        name: String,
        payload: com.facebook.react.bridge.WritableMap?,
    ) {
        context.getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(view.id, name, payload)
    }

    companion object {
        const val REACT_CLASS = "SellwildBannerView"

        internal fun adSizeFromLabel(label: String): AdSize? = when (label) {
            "320x50" -> AdSize.BANNER_320x50
            "300x250" -> AdSize.MREC_300x250
            "728x90" -> AdSize.LEADERBOARD_728x90
            "300x600" -> AdSize.HALF_PAGE_300x600
            "160x600" -> AdSize.WIDE_SKYSCRAPER_160x600
            else -> null
        }

        /**
         * Build a minimal SellwildConfig from a JS map. Only the fields the
         * native banner path actually reads are mapped here; everything else
         * gets sane defaults from the data class. The raw CDN JSON (if
         * present under `remote`) is preserved as `remoteJson` for the
         * passthrough auction params.
         */
        internal fun configFromMap(map: ReadableMap): SellwildConfig {
            val partnerCode = if (map.hasKey("partnerCode")) map.getString("partnerCode") else null
            val appBundleId = if (map.hasKey("appBundleId")) map.getString("appBundleId") else null
            val appStoreUrl = if (map.hasKey("appStoreUrl")) map.getString("appStoreUrl") else null
            val gamTag = if (map.hasKey("gamTag")) map.getString("gamTag") else null
            val debug = map.hasKey("debug") && map.getBoolean("debug")
            val pbsDebug = map.hasKey("pbsDebug") && map.getBoolean("pbsDebug")
            val geo = RnGeo.readableMapToGeo(
                if (map.hasKey("geo") && !map.isNull("geo")) map.getMap("geo") else null
            )
            val adRefreshMax = if (map.hasKey("adRefreshMax")) map.getInt("adRefreshMax") else 0
            val adRefreshMaxMobile = if (map.hasKey("adRefreshMaxMobile")) map.getInt("adRefreshMaxMobile") else 0
            val adRefreshIntervalMs = if (map.hasKey("adRefreshIntervalMs")) map.getDouble("adRefreshIntervalMs").toLong() else 30_000L

            val remoteJson = if (map.hasKey("remote") && !map.isNull("remote")) {
                JSONObject(map.getMap("remote")!!.toHashMap()).toString()
            } else {
                null
            }

            val growthCode = if (map.hasKey("growthCode") && !map.isNull("growthCode")) {
                val gc = map.getMap("growthCode")!!
                fun bool(k: String): Boolean? = if (gc.hasKey(k) && !gc.isNull(k)) gc.getBoolean(k) else null
                fun str(k: String): String? = if (gc.hasKey(k) && !gc.isNull(k)) gc.getString(k) else null
                fun int(k: String): Int? = if (gc.hasKey(k) && !gc.isNull(k)) gc.getInt(k) else null
                SellwildGrowthCodeConfig(
                    enabled = bool("enabled"),
                    partnerId = str("partnerId"),
                    endpoint = str("endpoint"),
                    syncUrl = str("syncUrl"),
                    sendMaid = bool("sendMaid"),
                    ttlHours = int("ttlHours"),
                )
            } else {
                null
            }

            val localizedListings = if (map.hasKey("localizedListings") && !map.isNull("localizedListings")) {
                val ll = map.getMap("localizedListings")!!
                fun bool(k: String): Boolean? = if (ll.hasKey(k) && !ll.isNull(k)) ll.getBoolean(k) else null
                fun str(k: String): String? = if (ll.hasKey(k) && !ll.isNull(k)) ll.getString(k) else null
                fun int(k: String): Int? = if (ll.hasKey(k) && !ll.isNull(k)) ll.getInt(k) else null
                SellwildLocalizedListingsConfig(
                    enabled = bool("enabled"),
                    source = str("source"),
                    baseUrl = str("baseUrl"),
                    urlTemplate = str("urlTemplate"),
                    frequency = int("frequency"),
                    forceState = str("forceState"),
                )
            } else {
                null
            }

            // Custom Prebid Server (S2S) config — mirror the iOS bridge so the
            // same RN app auctions against the partner's PBS on both platforms.
            val prebidServer = RnPrebidServer.fromMap(
                if (map.hasKey("prebidServer") && !map.isNull("prebidServer")) map.getMap("prebidServer") else null
            )

            return SellwildConfig(
                partnerCode = partnerCode ?: "",
                appBundleId = appBundleId,
                appStoreUrl = appStoreUrl,
                gamTag = gamTag,
                debug = debug,
                pbsDebug = pbsDebug,
                geo = geo,
                adRefreshMax = adRefreshMax,
                adRefreshMaxMobile = adRefreshMaxMobile,
                adRefreshIntervalMs = adRefreshIntervalMs,
                remoteJson = remoteJson,
                growthCode = growthCode,
                localizedListings = localizedListings,
                prebidServer = prebidServer,
            )
        }
    }
}
