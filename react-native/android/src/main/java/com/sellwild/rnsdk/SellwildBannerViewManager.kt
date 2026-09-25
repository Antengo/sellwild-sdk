package com.sellwild.rnsdk

import android.content.Context
import android.view.View
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.sellwild.sdk.AdSize
import com.sellwild.sdk.SellwildAdStack
import com.sellwild.sdk.SellwildAdView
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildGrowthCodeConfig
import com.sellwild.sdk.SellwildLocalizedListingsConfig
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import org.json.JSONObject

/**
 * React Native (Paper) only lays out views in its own shadow tree; the child
 * views a native component adds itself — here the GAM/Prebid banner and the
 * WebView the viewability tracker watches — are never measured or laid out, so
 * they render 0-size and fail the impression viewability check
 * (getWidth()>0 / getGlobalVisibleRect), which means NO viewable impression and
 * NO burl fires. Re-run measure + layout on our RN-assigned bounds whenever a
 * child requests layout (e.g. when the ad renders asynchronously). This is the
 * standard RN native-view fix (react-native-webview/maps/video do the same).
 * Not needed on iOS RN, which lays subviews out via Auto Layout constraints.
 */
internal class RnSellwildAdView(context: Context) : SellwildAdView(context) {
    private val measureAndLayout = Runnable {
        measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
        )
        layout(left, top, right, bottom)
    }

    override fun requestLayout() {
        super.requestLayout()
        post(measureAndLayout)
    }
}

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
     * Per-view props. We can't call SellwildAdView.setup() until all three
     * required props (config/size/zoneId) have arrived, so they wait here
     * and are applied on onAfterUpdateTransaction.
     *
     * Keyed by the ad view itself so multiple <SellwildBanner>s on screen
     * don't collide. Cleared on view drop.
     */
    private val pending = java.util.WeakHashMap<SellwildAdView, BannerProps>()

    override fun createViewInstance(reactContext: ThemedReactContext): SellwildAdView {
        val view = RnSellwildAdView(reactContext)
        pending[view] = BannerProps()
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

        // Every view gets its entry in createViewInstance; none means the view
        // was already dropped, so there is nothing to set up.
        val setUp = pending[view]?.nextSetUp() ?: return
        // JS resolves the stack from config and passes it as the override so
        // RN is deterministic; native still reads the raw `remote` for the rest.
        view.adStackOverride = setUp.adStack?.let { SellwildAdStack.parse(it) }
        view.setup(setUp.config, setUp.adSize, setUp.zoneId)
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

    private fun pendingFor(view: SellwildAdView): BannerProps =
        pending.getOrPut(view) { BannerProps() }

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
    ) = RnEvents.emit(context, view.id, name, payload)

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
            // One it cannot use is reported, and the default is used, as on iOS.
            val server = RnPrebidServer.fromConfig(map)
            server.problem?.let {
                SellwildFailures.log(
                    code = SellwildFailureCode.BRIDGE_CONFIG_INVALID,
                    component = SellwildFailureComponent.BRIDGE,
                    severity = SellwildFailureSeverity.ERROR,
                    message = it,
                )
            }

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
                prebidServer = server.config,
            )
        }
    }
}

/**
 * One <SellwildBanner>'s props, as React Native sets them, and what to do
 * after a props transaction. Apart from the view, so the JVM checks
 * (react-native/native-checks) run it without Android views.
 */
internal class BannerProps {
    var config: ReadableMap? = null
    var size: String? = null
    var zoneId: String? = null

    // Resolved ad stack ('both' | 'gamOnly' | 'prebidOnly'), computed in JS
    // and applied as the native override.
    var adStack: String? = null

    // Guards against running fresh auctions on every JS re-render. We only
    // call setup() + load() once per identity tuple. Refresh of the rendered
    // ad is driven by the SDK's internal timer.
    private var lastAppliedKey: String? = null

    // A re-render with the same bad props does not report them again.
    private val propsProblem = ReportOnce()

    /** What SellwildAdView.setup() needs, and the ad stack override. */
    class SetUp(val config: SellwildConfig, val adSize: AdSize, val zoneId: String, val adStack: String?)

    /**
     * The ad to set up after this props transaction, or null when there is
     * none: props it cannot use (reported once per distinct problem,
     * bridge.props.invalid), the same props as last time, or a config prop it
     * cannot read (reported, bridge.config.invalid, fatal).
     */
    fun nextSetUp(): SetUp? {
        val configMap = config
        val zone = zoneId
        val sizeLabel = size
        val problem = RnBridgeRules.bannerPropsProblem(configMap != null, sizeLabel, zone) {
            SellwildBannerViewManager.adSizeFromLabel(it) != null
        }
        propsProblem.take(problem)?.let {
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_PROPS_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.ERROR,
                message = "$it, so no ad was set up",
                zoneId = zone,
            )
        }
        if (problem != null) return null
        // bannerPropsProblem checked config and zoneId. A missing size, or a
        // label that is not a JS AdSize, returns here without a report:
        // <SellwildBanner> already reported it as ad.size.invalid (log once).
        if (configMap == null || zone == null || sizeLabel == null) return null
        val adSize = SellwildBannerViewManager.adSizeFromLabel(sizeLabel) ?: return null

        // Skip if the props identity hasn't changed since last apply.
        val key = "$sizeLabel|$zone|$adStack|${configMap.hashCode()}"
        if (lastAppliedKey == key) return null
        lastAppliedKey = key

        val cfg = try {
            SellwildBannerViewManager.configFromMap(configMap)
        } catch (e: Exception) {
            // A config field of the wrong type (ReadableMap getters throw), or a
            // remote JSON cannot hold. It used to crash the host app.
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_CONFIG_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.FATAL,
                error = e,
                message = "the config prop could not be read, so no ad was set up",
                zoneId = zone,
            )
            return null
        }
        return SetUp(cfg, adSize, zone, adStack)
    }
}
