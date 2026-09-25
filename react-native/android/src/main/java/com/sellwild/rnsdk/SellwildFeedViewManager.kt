package com.sellwild.rnsdk

import android.content.Context
import android.view.View
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.WritableMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildFeedView
import com.sellwild.sdk.SellwildGrowthCodeConfig
import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.SellwildLocalizedListingsConfig
import com.sellwild.sdk.SellwildSDK
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import org.json.JSONObject

/**
 * React Native (Paper) only lays out its own shadow-tree views; children a
 * native component adds itself (the feed's RecyclerView + ad WebViews) are never
 * measured/laid out, so they render 0-size and fail the impression viewability
 * check — no viewable impression, no burl. Re-run measure + layout on our
 * RN-assigned bounds whenever a child requests layout. Standard RN native-view
 * fix; not needed on iOS RN (Auto Layout constraints handle it).
 */
internal class RnSellwildFeedView(context: Context) : SellwildFeedView(context) {
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
 * Bridges the JS <SellwildFeed> component to the native
 * com.sellwild.sdk.SellwildFeedView (all-in-one native feed: COL1-scheduled
 * listing cards + Prebid + GAM ads, no WebView).
 *
 * Props (set from JS):
 *   - config: object — the resolved SellwildConfig (from configure()).
 *     The bridge re-runs the CDN decoder against `config.remote` so
 *     feed-specific fields (COL1, bgColor, mobileZids, listingsUrl, …)
 *     are populated identically to a native [SellwildSDK.configure] call.
 *   - scrollEnabled: bool — disable internal scrolling for embedding.
 *   - consumeListingTaps: bool — when true the host owns listing taps; the
 *     SDK does not open Custom Tabs.
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
     * Per-view props. SellwildFeedView.setup() kicks off a network fetch +
     * auctions for every COL1 ad slot, so we defer it to
     * onAfterUpdateTransaction and skip re-applying on JS re-renders.
     */
    private val pending = java.util.WeakHashMap<SellwildFeedView, FeedProps>()

    override fun createViewInstance(reactContext: ThemedReactContext): SellwildFeedView {
        val view = RnSellwildFeedView(reactContext)
        pending[view] = FeedProps()
        view.listener = object : SellwildFeedView.Listener {
            override fun onListingTap(listing: SellwildListing): Boolean {
                val payload = Arguments.createMap().apply {
                    putMap("listing", listingPayload(listing))
                }
                emit(reactContext, view, "onListingTap", payload)
                // JS can't return a value through an (async) RN event, so the
                // `consumeListingTaps` prop decides whether the SDK opens
                // Custom Tabs (false, default) or leaves navigation to the host.
                return pending[view]?.consumeListingTaps ?: false
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

            override fun onFeedReady(listingCount: Int) {
                val payload = Arguments.createMap().apply { putInt("listingCount", listingCount) }
                emit(reactContext, view, "onFeedReady", payload)
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

    @ReactProp(name = "consumeListingTaps", defaultBoolean = false)
    fun setConsumeListingTaps(view: SellwildFeedView, value: Boolean) {
        pendingFor(view).consumeListingTaps = value
    }

    override fun onAfterUpdateTransaction(view: SellwildFeedView) {
        super.onAfterUpdateTransaction(view)

        // Every view gets its entry in createViewInstance; none means the view
        // was already dropped, so there is nothing to set up.
        val config = pending[view]?.nextConfig() ?: return
        view.setup(config)
        view.load()
    }

    override fun onDropViewInstance(view: SellwildFeedView) {
        pending.remove(view)
        // RN unmounted the feed for good: stop its ad rows' refresh and release
        // the Activity (detach alone doesn't when MOBILE_PAUSE_REFRESH_DETACHED=false).
        view.destroy()
        super.onDropViewInstance(view)
    }

    private fun pendingFor(view: SellwildFeedView): FeedProps =
        pending.getOrPut(view) { FeedProps() }

    override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> {
        return MapBuilder.builder<String, Any>()
            .put("onFeedLoaded", MapBuilder.of("registrationName", "onFeedLoaded"))
            .put("onFeedReady", MapBuilder.of("registrationName", "onFeedReady"))
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
    ) = RnEvents.emit(context, view.id, name, payload)

    companion object {
        const val REACT_CLASS = "SellwildFeedView"

        /**
         * Build a full SellwildConfig from a JS map. The JS side passes the
         * resolved CDN payload under `remote`; we re-run the canonical CDN
         * decoder ([SellwildSDK.apply]) against it so feed-specific fields
         * (COL1, bgColor, mobileZids, listingsUrl, …) land identically to a
         * native [SellwildSDK.configure] call. Explicit JS overrides
         * (e.g. appBundleId from the host app) win.
         *
         * Zone ids that are not text, and a prebidServer without accountId
         * and endpoint text, are dropped and reported together, once
         * (bridge.config.invalid), as on iOS; reading a zone id with
         * getString used to throw. Any other field of the wrong type still
         * throws, and the caller reports it.
         */
        internal fun configFromMap(map: ReadableMap): SellwildConfig {
            val partnerCode = if (map.hasKey("partnerCode")) map.getString("partnerCode") ?: "" else ""

            var config = SellwildConfig(partnerCode = partnerCode)
            val problems = ArrayList<String>()

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

            // Flat identity/display/zone fields — mirror the iOS feed bridge so
            // static buildConfig() and overrides land identically. SellwildSDK.apply
            // (above) resolves these from `remote` when present; these overlay on top.
            if (map.hasKey("slug")) config = config.copy(slug = map.getString("slug") ?: config.slug)
            if (map.hasKey("listingsUrl")) config = config.copy(listingsUrl = map.getString("listingsUrl"))
            if (map.hasKey("priceColor")) config = config.copy(priceColor = map.getString("priceColor") ?: config.priceColor)
            readText(map, "bannerZid", problems) { config = config.copy(bannerZid = it) }
            readText(map, "bottomBannerZid", problems) { config = config.copy(bottomBannerZid = it) }
            // mobileZids / mobileBannerZid are OS-suffix-resolved by SellwildSDK.apply
            // when `remote` is present; only fall back to the flat (OS-agnostic) JS
            // values when there was no remote payload to resolve from (parity w/ iOS).
            if (!map.hasKey("remote") || map.isNull("remote")) {
                readText(map, "mobileBannerZid", problems) { config = config.copy(mobileBannerZid = it) }
                readTextList(map, "mobileZids", problems) { config = config.copy(mobileZids = it) }
            }

            // Custom Prebid Server (S2S) config — mirror the iOS feed bridge. A
            // prebidServer it cannot use joins this config's one report.
            if (map.hasKey("prebidServer") && !map.isNull("prebidServer")) {
                val server = RnPrebidServer.fromConfig(map)
                server.problem?.let { problems += it }
                config = config.copy(prebidServer = server.config)
            }

            // Local GrowthCode override — parity with the banner bridge and the
            // iOS feed bridge. Without it the feed's ad rows only see remote
            // GROWTHCODE_* keys; a code-supplied partnerId never reaches the
            // auction, so the identity sync never fires for feed ad rows.
            if (map.hasKey("growthCode") && !map.isNull("growthCode")) {
                val gc = map.getMap("growthCode")!!
                fun bool(k: String): Boolean? = if (gc.hasKey(k) && !gc.isNull(k)) gc.getBoolean(k) else null
                fun str(k: String): String? = if (gc.hasKey(k) && !gc.isNull(k)) gc.getString(k) else null
                fun int(k: String): Int? = if (gc.hasKey(k) && !gc.isNull(k)) gc.getInt(k) else null
                config = config.copy(
                    growthCode = SellwildGrowthCodeConfig(
                        enabled = bool("enabled"),
                        partnerId = str("partnerId"),
                        endpoint = str("endpoint"),
                        syncUrl = str("syncUrl"),
                        sendMaid = bool("sendMaid"),
                        ttlHours = int("ttlHours"),
                    ),
                )
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

            // One report for the config, however many fields it has wrong.
            if (problems.isNotEmpty()) {
                SellwildFailures.log(
                    code = SellwildFailureCode.BRIDGE_CONFIG_INVALID,
                    component = SellwildFailureComponent.BRIDGE,
                    severity = SellwildFailureSeverity.ERROR,
                    message = problems.joinToString("; "),
                )
            }

            return config
        }

        /**
         * Reads [key] as text into [set]: text as it is, and null for a JSON
         * null (it clears the field, as before). A value of another type is
         * dropped and added to [problems]. Nothing happens when the key is absent.
         */
        private inline fun readText(map: ReadableMap, key: String, problems: MutableList<String>, set: (String?) -> Unit) {
            if (!map.hasKey(key)) return
            when (val type = map.getType(key)) {
                ReadableType.Null -> set(null)
                ReadableType.String -> set(map.getString(key))
                else -> problems += RnBridgeRules.wrongType(key, type.name, "text")
            }
        }

        /**
         * Reads [key] as a list of text into [set], null entries left out, as
         * before. A value that is not a list, or holds an entry of another type,
         * is dropped and added to [problems]. Nothing happens when it is absent
         * or null.
         */
        private inline fun readTextList(map: ReadableMap, key: String, problems: MutableList<String>, set: (List<String>) -> Unit) {
            if (!map.hasKey(key) || map.isNull(key)) return
            val type = map.getType(key)
            val arr = if (type == ReadableType.Array) map.getArray(key) else null
            if (arr == null) {
                problems += RnBridgeRules.wrongType(key, type.name, "a list")
                return
            }
            val entries = (0 until arr.size()).map { arr.getType(it) }
            val bad = entries.count { it != ReadableType.String && it != ReadableType.Null }
            if (bad > 0) {
                problems += RnBridgeRules.notTextEntries(key, bad, entries.size)
                return
            }
            set((0 until arr.size()).mapNotNull { arr.getString(it) })
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

/**
 * One <SellwildFeed>'s config prop, as React Native sets it, and what to do
 * after a props transaction. Apart from the view, so the JVM checks
 * (react-native/native-checks) run it without Android views.
 */
internal class FeedProps {
    var config: ReadableMap? = null

    // When true, listing taps are only forwarded to JS and the SDK does not
    // open Custom Tabs. Read at tap time, so it applies live.
    var consumeListingTaps: Boolean = false

    // The config last set up, compared by value, so a JS re-render does not
    // set the feed up again. A hashCode() key is only a probabilistic match
    // (collisions ⇒ a real config change is skipped).
    private var lastAppliedConfig: Map<String, Any?>? = null

    /**
     * The config to set the feed up with after this transaction, or null:
     * no config yet (JS always sends one with the first props), the same
     * config as last time, or one it cannot read (reported,
     * bridge.config.invalid, fatal).
     */
    fun nextConfig(): SellwildConfig? {
        val configMap = config ?: return null
        val configValue = configMap.toHashMap()
        if (lastAppliedConfig == configValue) return null
        lastAppliedConfig = configValue
        return try {
            SellwildFeedViewManager.configFromMap(configMap)
        } catch (e: Exception) {
            // A config field of the wrong type (ReadableMap getters throw), or a
            // remote JSON cannot hold. It used to crash the host app.
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_CONFIG_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.FATAL,
                error = e,
                message = "the config prop could not be read, so the feed was not set up",
            )
            null
        }
    }
}
