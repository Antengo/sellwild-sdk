package com.sellwild.rnsdk

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildFeedView
import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.SellwildLocalizedListingsConfig
import com.sellwild.sdk.SellwildSDK
import org.json.JSONObject

/**
 * Bridges the JS <SellwildFeed> component to the native
 * com.sellwild.sdk.SellwildFeedView (all-in-one native feed: COL1-scheduled
 * listing cards + Prebid + GAM ads, no WebView).
 *
 * Props (set from JS):
 *   - config: object — the resolved SellwildConfig (from configure()).
 *     The bridge re-runs the CDN decoder against `config.remote` so
 *     feed-specific fields (COL1, bgColor, mobileZids, listingsUrl, …)
 *     are populated identically to a native [SellwildSDK.configure] call.
 *
 * Events emitted to JS:
 *   - onFeedLoaded
 *   - onListingTap   { listing }
 *   - onAdImpression { zoneId }
 *   - onAdClicked    { zoneId }
 *   - onFeedError    { message }
 */
class SellwildFeedViewManager : SimpleViewManager<SellwildFeedView>() {

    override fun getName(): String = REACT_CLASS

    /**
     * Per-view scratch state. SellwildFeedView.setup() kicks off a network
     * fetch + auctions for every COL1 ad slot, so we defer it to
     * onAfterUpdateTransaction and skip re-applying on JS re-renders.
     */
    private val pending = java.util.WeakHashMap<SellwildFeedView, PendingProps>()

    private data class PendingProps(
        var config: ReadableMap? = null,
        var lastAppliedKey: String? = null,
    )

    override fun createViewInstance(reactContext: ThemedReactContext): SellwildFeedView {
        val view = SellwildFeedView(reactContext)
        pending[view] = PendingProps()
        view.listener = object : SellwildFeedView.Listener {
            override fun onListingTap(listing: SellwildListing): Boolean {
                val payload = Arguments.createMap().apply {
                    putMap("listing", listingPayload(listing))
                }
                emit(reactContext, view, "onListingTap", payload)
                // SDK still owns navigation (Custom Tabs); JS just observes.
                return false
            }

            override fun onAdImpression(zoneId: String) {
                val payload = Arguments.createMap().apply { putString("zoneId", zoneId) }
                emit(reactContext, view, "onAdImpression", payload)
            }

            override fun onHouseAdImpression(zoneId: String) {
                val payload = Arguments.createMap().apply { putString("zoneId", zoneId) }
                emit(reactContext, view, "onHouseAdImpression", payload)
            }

            override fun onAdClicked(zoneId: String) {
                val payload = Arguments.createMap().apply { putString("zoneId", zoneId) }
                emit(reactContext, view, "onAdClicked", payload)
            }

            override fun onLoad() {
                emit(reactContext, view, "onFeedLoaded", null)
            }

            override fun onError(message: String) {
                val payload = Arguments.createMap().apply { putString("message", message) }
                emit(reactContext, view, "onFeedError", payload)
            }

            override fun onContentHeightChanged(feedView: SellwildFeedView, heightDp: Int) {
                val payload = Arguments.createMap().apply { putInt("height", heightDp) }
                emit(reactContext, view, "onContentSizeChange", payload)
            }
        }
        return view
    }

    @ReactProp(name = "config")
    fun setConfig(view: SellwildFeedView, value: ReadableMap?) {
        pendingFor(view).config = value
    }

    @ReactProp(name = "scrollEnabled", defaultBoolean = true)
    fun setScrollEnabled(view: SellwildFeedView, value: Boolean) {
        view.scrollEnabled = value
    }

    override fun onAfterUpdateTransaction(view: SellwildFeedView) {
        super.onAfterUpdateTransaction(view)

        val p = pending[view] ?: return
        val configMap = p.config ?: return

        val key = "${configMap.hashCode()}"
        if (p.lastAppliedKey == key) return
        p.lastAppliedKey = key

        val config = configFromMap(configMap)
        view.setup(config)
        view.load()
    }

    override fun onDropViewInstance(view: SellwildFeedView) {
        pending.remove(view)
        super.onDropViewInstance(view)
    }

    private fun pendingFor(view: SellwildFeedView): PendingProps =
        pending.getOrPut(view) { PendingProps() }

    override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> {
        return MapBuilder.builder<String, Any>()
            .put("onFeedLoaded", MapBuilder.of("registrationName", "onFeedLoaded"))
            .put("onListingTap", MapBuilder.of("registrationName", "onListingTap"))
            .put("onAdImpression", MapBuilder.of("registrationName", "onAdImpression"))
            .put("onHouseAdImpression", MapBuilder.of("registrationName", "onHouseAdImpression"))
            .put("onAdClicked", MapBuilder.of("registrationName", "onAdClicked"))
            .put("onFeedError", MapBuilder.of("registrationName", "onFeedError"))
            .put("onContentSizeChange", MapBuilder.of("registrationName", "onContentSizeChange"))
            .build()
    }

    private fun emit(
        context: ReactContext,
        view: SellwildFeedView,
        name: String,
        payload: WritableMap?,
    ) {
        context.getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(view.id, name, payload)
    }

    companion object {
        const val REACT_CLASS = "SellwildFeedView"

        /**
         * Build a full SellwildConfig from a JS map. The JS side passes the
         * resolved CDN payload under `remote`; we re-run the canonical CDN
         * decoder ([SellwildSDK.apply]) against it so feed-specific fields
         * (COL1, bgColor, mobileZids, listingsUrl, …) land identically to a
         * native [SellwildSDK.configure] call. Explicit JS overrides
         * (e.g. appBundleId from the host app) win.
         */
        internal fun configFromMap(map: ReadableMap): SellwildConfig {
            val partnerCode = if (map.hasKey("partnerCode")) map.getString("partnerCode") ?: "" else ""

            var config = SellwildConfig(partnerCode = partnerCode)

            // Apply the raw CDN payload first.
            if (map.hasKey("remote") && !map.isNull("remote")) {
                val remoteMap = map.getMap("remote")!!.toHashMap()
                val remoteJson = JSONObject(remoteMap)
                config = SellwildSDK.apply(remoteJson, config).copy(
                    remoteJson = remoteJson.toString()
                )
            }

            // JS-side overrides.
            if (map.hasKey("appBundleId")) config = config.copy(appBundleId = map.getString("appBundleId"))
            if (map.hasKey("appStoreUrl")) config = config.copy(appStoreUrl = map.getString("appStoreUrl"))
            if (map.hasKey("gamTag")) config = config.copy(gamTag = map.getString("gamTag"))
            if (map.hasKey("debug")) config = config.copy(debug = map.getBoolean("debug"))
            if (map.hasKey("pbsDebug")) config = config.copy(pbsDebug = map.getBoolean("pbsDebug"))
            if (map.hasKey("geo") && !map.isNull("geo")) config = config.copy(geo = RnGeo.readableMapToGeo(map.getMap("geo")))
            if (map.hasKey("adRefreshMax")) config = config.copy(adRefreshMax = map.getInt("adRefreshMax"))
            if (map.hasKey("adRefreshMaxMobile")) config = config.copy(adRefreshMaxMobile = map.getInt("adRefreshMaxMobile"))
            if (map.hasKey("adRefreshIntervalMs")) config = config.copy(adRefreshIntervalMs = map.getDouble("adRefreshIntervalMs").toLong())
            // Custom Prebid Server (S2S) config — mirror the iOS feed bridge.
            if (map.hasKey("prebidServer") && !map.isNull("prebidServer")) {
                config = config.copy(prebidServer = RnPrebidServer.fromMap(map.getMap("prebidServer")))
            }

            // Local override for the localized (geo-based) secondary-listings
            // integration; the remote LOCALIZED_LISTINGS object rides `remote`.
            if (map.hasKey("localizedListings") && !map.isNull("localizedListings")) {
                val ll = map.getMap("localizedListings")!!
                fun bool(k: String): Boolean? = if (ll.hasKey(k) && !ll.isNull(k)) ll.getBoolean(k) else null
                fun str(k: String): String? = if (ll.hasKey(k) && !ll.isNull(k)) ll.getString(k) else null
                fun int(k: String): Int? = if (ll.hasKey(k) && !ll.isNull(k)) ll.getInt(k) else null
                config = config.copy(
                    localizedListings = SellwildLocalizedListingsConfig(
                        enabled = bool("enabled"),
                        source = str("source"),
                        baseUrl = str("baseUrl"),
                        urlTemplate = str("urlTemplate"),
                        frequency = int("frequency"),
                        forceState = str("forceState"),
                    ),
                )
            }

            return config
        }

        /** Surface the listing payload to JS. Mirrors `SellwildListing` in @sellwild/sdk-core. */
        internal fun listingPayload(listing: SellwildListing): WritableMap = Arguments.createMap().apply {
            putString("id", listing.id)
            putString("title", listing.title)
            listing.url?.let { putString("url", it) }
            listing.currency?.let { putString("currency", it) }
            listing.price?.let { putString("price", it) }
            listing.remoteUrl?.let { putString("remoteUrl", it) }
            listing.primaryPhotoUrl?.let { putString("photoUrl", it) }
        }
    }
}
