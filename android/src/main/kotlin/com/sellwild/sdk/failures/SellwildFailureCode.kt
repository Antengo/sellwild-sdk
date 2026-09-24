package com.sellwild.sdk.failures

/**
 * Android mirror of contracts/failure-codes.json: every code whose `clients` include
 * `android` (FAILURES.md 4.2). FailureCodesParityTest checks this list against the JSON.
 *
 * To add a code, add it to failure-codes.json first (FAILURES.md 4.4), then here, in
 * code order.
 */
object SellwildFailureCode {
    /** The WebView mute shim (evaluateJavaScript) failed, so ad audio may not be muted. */
    const val AD_AUDIO_GUARD_EXCEPTION = "ad.audio_guard.exception"
    /** Reading the winning bid (isVideo) threw, so video mute enforcement was skipped. */
    const val AD_BID_INSPECT_EXCEPTION = "ad.bid_inspect.exception"
    /** GAM failed to load an ad for a reason other than no-fill (network, invalid request, internal). No-fill stays on adError. */
    const val AD_GAM_LOAD_EXCEPTION = "ad.gam_load.exception"
    /** No GAM ad unit is configured (gamTag and GAM both empty), so Google's test ad unit is used. */
    const val AD_GAM_UNIT_MISSING = "ad.gam_unit.missing"
    /** Google Mobile Ads initialization threw. */
    const val AD_GMA_INIT_EXCEPTION = "ad.gma_init.exception"
    /** A native bid won but the cache id was missing or the native ad could not be created. No-fill stays on adError. */
    const val AD_NATIVE_CREATE_INVALID = "ad.native_create.invalid"
    /** A video creative won a banner-only zone (the existing placementMismatch event is also sent). */
    const val AD_PLACEMENT_INVALID = "ad.placement.invalid"
    /** The Prebid auction returned an error result code other than no-bids (for example an invalid config id). */
    const val AD_PREBID_AUCTION_INVALID = "ad.prebid_auction.invalid"
    /** Prebid Mobile initialization threw or completed with an error, so every auction waits and may run without Prebid. */
    const val AD_PREBID_INIT_EXCEPTION = "ad.prebid_init.exception"
    /** Prebid Mobile initialization finished with a non-success status. */
    const val AD_PREBID_INIT_INVALID = "ad.prebid_init.invalid"
    /** Prebid was not ready after the cold-start wait, so the ad loaded without header bidding. */
    const val AD_PREBID_INIT_TIMEOUT = "ad.prebid_init.timeout"
    /** The Prebid rendering banner failed to load an ad for a reason other than no-fill. */
    const val AD_PREBID_RENDER_EXCEPTION = "ad.prebid_render.exception"
    /** The ad view was loaded or resumed before setup(). */
    const val AD_SETUP_MISSING = "ad.setup.missing"
    /** An ad placement needs a zone id and none was given, so the auction is skipped. */
    const val AD_ZONE_MISSING = "ad.zone.missing"
    /** A config value from JS has the wrong type or is incomplete for the native bridge. */
    const val BRIDGE_CONFIG_INVALID = "bridge.config.invalid"
    /** setExternalUserIds got an entry without source, uids or id; it was skipped. */
    const val BRIDGE_EIDS_INVALID = "bridge.eids.invalid"
    /** Emitting an event to JS failed because the React instance is gone. */
    const val BRIDGE_EVENT_EMIT_EXCEPTION = "bridge.event_emit.exception"
    /** A WebView bridge message was not valid JSON. */
    const val BRIDGE_MESSAGE_PARSE = "bridge.message.parse"
    /** A native view got missing props or an unsupported size label, so no ad was set up. */
    const val BRIDGE_PROPS_INVALID = "bridge.props.invalid"
    /** The widget page reported a JavaScript error through the bridge ERROR message. */
    const val BRIDGE_SCRIPT_EXCEPTION = "bridge.script.exception"
    /** Replacement action when a call site passes a code that fails the registry format. The label keeps the caller component. Never pass it directly. */
    const val CLIENT_CODE_INVALID = "client.code.invalid"
    /** AD_STACK or an AD_STACK_BY_ZONE entry is not a known mode (or not a map); the default is used. */
    const val CONFIG_ADSTACK_INVALID = "config.adstack.invalid"
    /** A BANNER_SIZES entry could not be parsed or has non-positive dimensions; it was dropped. */
    const val CONFIG_BANNER_SIZES_INVALID = "config.banner_sizes.invalid"
    /** A configured color string is not a valid color; the fallback color is used. */
    const val CONFIG_COLOR_INVALID = "config.color.invalid"
    /** The remote config request returned a non-2xx status (a missing file returns 403 AccessDenied XML). */
    const val CONFIG_FETCH_HTTP = "config.fetch.http"
    /** The remote config request failed at the network level (DNS, offline, TLS, reset). */
    const val CONFIG_FETCH_NETWORK = "config.fetch.network"
    /** The remote config body is not valid JSON. */
    const val CONFIG_FETCH_PARSE = "config.fetch.parse"
    /** The remote config request did not answer within the client timeout. */
    const val CONFIG_FETCH_TIMEOUT = "config.fetch.timeout"
    /** A config field has an unexpected type or value and was ignored or coerced. */
    const val CONFIG_FIELD_INVALID = "config.field.invalid"
    /** The stored remote config JSON could not be parsed, so every remote flag falls back to its default. */
    const val CONFIG_REMOTE_VALUES_PARSE = "config.remote_values.parse"
    /** The COL1 layout asks for an ad or banner row but no zone is configured, so the row is dropped. */
    const val FEED_AD_ZONE_MISSING = "feed.ad_zone.missing"
    /** A listing photo failed to download. */
    const val FEED_IMAGE_NETWORK = "feed.image.network"
    /** Opening a listing or partner URL threw (no browser, no presenter). */
    const val FEED_OPEN_URL_EXCEPTION = "feed.open_url.exception"
    /** A listing or partner URL was refused because it is not http(s). */
    const val FEED_OPEN_URL_INVALID = "feed.open_url.invalid"
    /** The feed was loaded before setup(). */
    const val FEED_SETUP_MISSING = "feed.setup.missing"
    /** The feed adapter got an unknown view type. */
    const val FEED_VIEW_TYPE_INVALID = "feed.view_type.invalid"
    /** The GrowthCode eid blob (eb) is not valid JSON. */
    const val GROWTHCODE_EID_PARSE = "growthcode.eid.parse"
    /** The GrowthCode sync returned a non-2xx status; the throttle is not saved, so it retries next launch. */
    const val GROWTHCODE_SYNC_HTTP = "growthcode.sync.http"
    /** The GrowthCode sync request failed at the network level. */
    const val GROWTHCODE_SYNC_NETWORK = "growthcode.sync.network"
    /** The GrowthCode sync response is not valid JSON. */
    const val GROWTHCODE_SYNC_PARSE = "growthcode.sync.parse"
    /** GrowthCode sync POST timed out. The throttle is not persisted, so it retries next launch. */
    const val GROWTHCODE_SYNC_TIMEOUT = "growthcode.sync.timeout"
    /** A house ad image was rejected (scheme), too large, or could not be decoded. */
    const val HOUSE_IMAGE_INVALID = "house.image.invalid"
    /** A house ad image failed to download. */
    const val HOUSE_IMAGE_NETWORK = "house.image.network"
    /** Opening a house ad click URL threw. */
    const val HOUSE_OPEN_URL_EXCEPTION = "house.open_url.exception"
    /** The listings GET returned a non-2xx status. */
    const val LISTINGS_FETCH_HTTP = "listings.fetch.http"
    /** The listings GET failed at the network level (DNS, offline, TLS, reset). */
    const val LISTINGS_FETCH_NETWORK = "listings.fetch.network"
    /** The listings body is not valid JSON (for example an HTML error page). */
    const val LISTINGS_FETCH_PARSE = "listings.fetch.parse"
    /** Listings GET did not answer within the client timeout. */
    const val LISTINGS_FETCH_TIMEOUT = "listings.fetch.timeout"
    /** The listings response had zero items, so listing slots stay empty. */
    const val LISTINGS_RESULT_MISSING = "listings.result.missing"
    /** LOCALIZED_LISTINGS is set but not an object, or lacks baseUrl/urlTemplate; the feature is off. */
    const val LOCALIZED_CONFIG_INVALID = "localized.config.invalid"
    /** The localized cache returned a non-2xx status other than the expected 403/404 for a state without a cache. */
    const val LOCALIZED_FETCH_HTTP = "localized.fetch.http"
    /** The localized (per-state) cache request failed at the network level. */
    const val LOCALIZED_FETCH_NETWORK = "localized.fetch.network"
    /** The localized cache body is not valid JSON. */
    const val LOCALIZED_FETCH_PARSE = "localized.fetch.parse"
    /** Localized (per-state) listings cache GET timed out. The primary feed renders alone. */
    const val LOCALIZED_FETCH_TIMEOUT = "localized.fetch.timeout"
    /** The native widget view was loaded before setup(). */
    const val WIDGET_SETUP_MISSING = "widget.setup.missing"
    /** The widget WebView failed to load its page or a main resource (offline, DNS, TLS, navigation failure). */
    const val WIDGET_WEBVIEW_LOAD_NETWORK = "widget.webview_load.network"
    /** The WebView content process crashed or was killed (iOS webViewWebContentProcessDidTerminate, Android onRenderProcessGone). The widget is blank until reloaded. */
    const val WIDGET_WEBVIEW_PROCESS_EXCEPTION = "widget.webview_process.exception"

    /** Every code above, in code order. */
    val ALL: List<String> = listOf(
        AD_AUDIO_GUARD_EXCEPTION,
        AD_BID_INSPECT_EXCEPTION,
        AD_GAM_LOAD_EXCEPTION,
        AD_GAM_UNIT_MISSING,
        AD_GMA_INIT_EXCEPTION,
        AD_NATIVE_CREATE_INVALID,
        AD_PLACEMENT_INVALID,
        AD_PREBID_AUCTION_INVALID,
        AD_PREBID_INIT_EXCEPTION,
        AD_PREBID_INIT_INVALID,
        AD_PREBID_INIT_TIMEOUT,
        AD_PREBID_RENDER_EXCEPTION,
        AD_SETUP_MISSING,
        AD_ZONE_MISSING,
        BRIDGE_CONFIG_INVALID,
        BRIDGE_EIDS_INVALID,
        BRIDGE_EVENT_EMIT_EXCEPTION,
        BRIDGE_MESSAGE_PARSE,
        BRIDGE_PROPS_INVALID,
        BRIDGE_SCRIPT_EXCEPTION,
        CLIENT_CODE_INVALID,
        CONFIG_ADSTACK_INVALID,
        CONFIG_BANNER_SIZES_INVALID,
        CONFIG_COLOR_INVALID,
        CONFIG_FETCH_HTTP,
        CONFIG_FETCH_NETWORK,
        CONFIG_FETCH_PARSE,
        CONFIG_FETCH_TIMEOUT,
        CONFIG_FIELD_INVALID,
        CONFIG_REMOTE_VALUES_PARSE,
        FEED_AD_ZONE_MISSING,
        FEED_IMAGE_NETWORK,
        FEED_OPEN_URL_EXCEPTION,
        FEED_OPEN_URL_INVALID,
        FEED_SETUP_MISSING,
        FEED_VIEW_TYPE_INVALID,
        GROWTHCODE_EID_PARSE,
        GROWTHCODE_SYNC_HTTP,
        GROWTHCODE_SYNC_NETWORK,
        GROWTHCODE_SYNC_PARSE,
        GROWTHCODE_SYNC_TIMEOUT,
        HOUSE_IMAGE_INVALID,
        HOUSE_IMAGE_NETWORK,
        HOUSE_OPEN_URL_EXCEPTION,
        LISTINGS_FETCH_HTTP,
        LISTINGS_FETCH_NETWORK,
        LISTINGS_FETCH_PARSE,
        LISTINGS_FETCH_TIMEOUT,
        LISTINGS_RESULT_MISSING,
        LOCALIZED_CONFIG_INVALID,
        LOCALIZED_FETCH_HTTP,
        LOCALIZED_FETCH_NETWORK,
        LOCALIZED_FETCH_PARSE,
        LOCALIZED_FETCH_TIMEOUT,
        WIDGET_SETUP_MISSING,
        WIDGET_WEBVIEW_LOAD_NETWORK,
        WIDGET_WEBVIEW_PROCESS_EXCEPTION,
    )
}

/** The `component` values logFailure accepts (FAILURES.md 6.2). Anything else becomes `unknown`. */
object SellwildFailureComponent {
    const val CONFIGURE = "configure"
    const val REMOTE_CONFIG = "remoteConfig"
    const val LISTINGS = "listings"
    const val LOCALIZED = "localized"
    const val FEED = "feed"
    const val BANNER = "banner"
    const val NATIVE = "native"
    const val VIDEO = "video"
    const val HOUSE = "house"
    const val BRIDGE = "bridge"
    const val WEBVIEW = "webview"
    const val WIDGET = "widget"
    const val GROWTHCODE = "growthcode"
    const val GEO = "geo"
    const val STORAGE = "storage"
}

/**
 * The `severity` values (FAILURES.md 6.3). logFailure defaults to [ERROR]; anything
 * else also becomes [ERROR].
 */
object SellwildFailureSeverity {
    /** The surface could not render. Sent at once, never sampled out. */
    const val FATAL = "fatal"

    /** The operation failed and a fallback was used. */
    const val ERROR = "error"

    /** Degraded but handled. */
    const val WARN = "warn"
}
