package com.sellwild.sdk

// SellwildPrebidMobile.kt — Optional Prebid Mobile SDK integration
//
// This file wraps the Prebid Mobile SDK (declared as `compileOnly` in build.gradle.kts).
// All public methods are guarded by a ClassNotFoundException check at runtime so the
// SDK works normally even if the host app does NOT include PrebidMobile.
//
// REQUIREMENTS (host app's build.gradle.kts)
// ────────────────────────────────────────────
// implementation("org.prebid:prebid-mobile-sdk-core:2.3.2")
// implementation("org.prebid:prebid-mobile-sdk-gamEventHandlers:2.3.2")  // if using GAM
//
// USAGE
// ─────
// 1. In Application.onCreate():
//    SellwildPrebidMobile.initialize(
//        context  = this,
//        host     = PrebidHost.APPNEXUS,   // or RUBICON / CUSTOM
//        accountId = "YOUR_ACCOUNT_ID"
//    )
//
// 2. Create a native banner ad unit:
//    val banner = SellwildPrebidMobile.makeBannerAdUnit(
//        configId = "YOUR_CONFIG_ID",
//        widthPts = 320,
//        heightPts = 50
//    ) ?: return
//    banner.fetchDemand(gamBannerView) { _ ->
//        gamBannerView.loadAd(AdManagerAdRequest.Builder().build())
//    }
//
// NOTE: When using the Prebid Mobile SDK, you typically replace or supplement the
// SellwildWidgetView WebView with a GAM/MoPub view managed by PrebidMobile.
// The two approaches (WebView widget + native Prebid Mobile) can coexist — use
// SellwildWidgetView for the listing carousel and native Prebid Mobile for standalone
// banner / interstitial placements.

import android.content.Context
import android.util.Log

private const val TAG = "SellwildPrebidMobile"
private const val PREBID_SDK_CLASS = "org.prebid.mobile.PrebidMobile"

/**
 * Whether the Prebid Mobile SDK is available on the classpath.
 * Returns false when the host app has not added the PrebidMobile dependency.
 */
val isPrebidMobileAvailable: Boolean
    get() = try {
        Class.forName(PREBID_SDK_CLASS)
        true
    } catch (_: ClassNotFoundException) {
        false
    }

/**
 * Convenience wrapper for bootstrapping Prebid Mobile SDK from SellwildConfig.
 * All calls are no-ops (with a log warning) when PrebidMobile is not on the classpath.
 */
object SellwildPrebidMobile {

    /**
     * Initialize the Prebid Mobile SDK.
     * Call once from `Application.onCreate()`.
     *
     * @param context    Application context.
     * @param host       Prebid Server host — "appnexus", "rubicon", or "custom".
     *                   Pass "custom" and set [serverUrl] for a self-hosted instance.
     * @param accountId  Your Prebid Server account ID.
     * @param serverUrl  Required when [host] is "custom". Full host URL,
     *                   e.g. "https://prebid-server.example.com".
     * @param timeoutMs  Auction timeout in milliseconds. Default: 1000.
     * @param debug      Enable Prebid SDK console logging.
     */
    @JvmStatic
    @JvmOverloads
    fun initialize(
        context: Context,
        host: String = "appnexus",
        accountId: String,
        serverUrl: String? = null,
        timeoutMs: Int = 1000,
        debug: Boolean = false,
    ) {
        if (!isPrebidMobileAvailable) {
            Log.w(TAG, "PrebidMobile not on classpath — add prebid-mobile-sdk-core to your app's dependencies.")
            return
        }
        try {
            val cls = Class.forName(PREBID_SDK_CLASS)
            // PrebidMobile.setPrebidServerHost(PrebidServerHost.APPNEXUS / RUBICON / CUSTOM)
            val hostEnumClass = Class.forName("org.prebid.mobile.PrebidServerHost")
            val serverHost = when (host.lowercase()) {
                "rubicon"  -> hostEnumClass.getField("RUBICON").get(null)
                "custom"   -> {
                    requireNotNull(serverUrl) { "serverUrl must be provided for custom host" }
                    val customMethod = hostEnumClass.getMethod("CUSTOM", String::class.java)
                    customMethod.invoke(null, serverUrl)
                }
                else       -> hostEnumClass.getField("APPNEXUS").get(null)
            }
            cls.getMethod("setPrebidServerHost", hostEnumClass)
                .invoke(null, serverHost)
            cls.getMethod("setPrebidServerAccountId", String::class.java)
                .invoke(null, accountId)
            cls.getMethod("setTimeoutMillis", Int::class.java)
                .invoke(null, timeoutMs)
            if (debug) {
                try {
                    cls.getMethod("setDebugLogEnabled", Boolean::class.java).invoke(null, true)
                } catch (_: Exception) { /* Optional method — older SDK versions may not have it */ }
            }
            Log.d(TAG, "Prebid Mobile SDK initialized (host=$host, accountId=$accountId)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Prebid Mobile SDK", e)
        }
    }

    /**
     * Create a Prebid Mobile banner ad unit.
     * Returns null when PrebidMobile is not on the classpath.
     *
     * @param configId  The Prebid config ID for this placement.
     * @param widthPts  Ad width in density-independent points.
     * @param heightPts Ad height in density-independent points.
     * @return A configured `BannerAdUnit` instance, or null.
     */
    @JvmStatic
    fun makeBannerAdUnit(
        configId: String,
        widthPts: Int,
        heightPts: Int,
    ): Any? {
        if (!isPrebidMobileAvailable) return null
        return try {
            val adSizeCls = Class.forName("org.prebid.mobile.AdSize")
            val adSize = adSizeCls.getConstructor(Int::class.java, Int::class.java)
                .newInstance(widthPts, heightPts)
            val bannerCls = Class.forName("org.prebid.mobile.BannerAdUnit")
            bannerCls.getConstructor(String::class.java, Int::class.java, Int::class.java)
                .newInstance(configId, widthPts, heightPts)
        } catch (e: Exception) {
            Log.e(TAG, "makeBannerAdUnit failed", e)
            null
        }
    }

    /**
     * Create a Prebid Mobile interstitial ad unit.
     * Returns null when PrebidMobile is not on the classpath.
     *
     * @param configId The Prebid config ID for this placement.
     */
    @JvmStatic
    fun makeInterstitialAdUnit(configId: String): Any? {
        if (!isPrebidMobileAvailable) return null
        return try {
            Class.forName("org.prebid.mobile.InterstitialAdUnit")
                .getConstructor(String::class.java)
                .newInstance(configId)
        } catch (e: Exception) {
            Log.e(TAG, "makeInterstitialAdUnit failed", e)
            null
        }
    }
}
