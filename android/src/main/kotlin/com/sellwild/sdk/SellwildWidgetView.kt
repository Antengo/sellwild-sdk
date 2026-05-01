package com.sellwild.sdk

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.util.AttributeSet
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.os.Handler
import android.os.Looper
import org.json.JSONObject

/**
 * Full Sellwild marketplace widget rendered via WebView.
 * Embeds the Sellwild web widget and bridges listing click events
 * and ad impressions back to native Android listeners.
 *
 * Usage:
 * ```kotlin
 * val widget = SellwildWidgetView(context)
 * widget.setup(config)
 * widget.listener = object : SellwildWidgetView.Listener {
 *     override fun onListingTapped(listing: SellwildListing) {
 *         // Open listing detail
 *     }
 * }
 * widget.load()
 * ```
 */
/**
 * Call this from Application.onCreate() BEFORE any WebView is created.
 * On Android 9+ (API 28+), using WebView from multiple processes with the same
 * data directory causes crashes (crbug.com/558377). This sets a process-specific
 * suffix to avoid the conflict.
 *
 * Example in Application:
 * ```kotlin
 * override fun onCreate() {
 *     super.onCreate()
 *     SellwildWidgetView.configureWebViewForMultiProcess(this)
 * }
 * ```
 */
object SellwildWebViewCompat {
    fun configureForMultiProcess(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val processName = context.packageName.let { pkg ->
                // getProcessName() is available from API 28
                android.app.Application.getProcessName() ?: pkg
            }
            val packageName = context.packageName
            if (processName != packageName) {
                WebView.setDataDirectorySuffix(processName.replace(packageName, "").trimStart(':'))
            }
        }
    }
}

class SellwildWidgetView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    interface Listener {
        fun onWidgetLoaded(widgetView: SellwildWidgetView) {}
        fun onListingTapped(listing: SellwildListing) {}
        fun onAdImpression(widgetView: SellwildWidgetView, zoneId: String) {}
        fun onError(widgetView: SellwildWidgetView, message: String) {}
    }

    private lateinit var config: SellwildConfig
    var listener: Listener? = null

    private val webView: WebView by lazy { createWebView() }
    private val mainHandler = Handler(Looper.getMainLooper())

    fun setup(config: SellwildConfig) {
        this.config = config
        if (childCount == 0) {
            addView(webView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        }
    }

    fun load() {
        check(::config.isInitialized) { "Call setup() before load()" }
        val html = buildWidgetHTML()
        val baseUrl = "https://widget.sellwild.com"
        webView.loadDataWithBaseURL(baseUrl, html, "text/html", "UTF-8", null)
    }

    fun pause() = webView.onPause()
    fun resume() = webView.onResume()
    fun destroy() {
        webView.destroy()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(): WebView {
        val wv = WebView(context)
        with(wv.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            cacheMode = WebSettings.LOAD_DEFAULT
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            useWideViewPort = true
            loadWithOverviewMode = true
        }
        wv.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                // Widget sends WIDGET_LOADED via JS bridge
            }
        }
        wv.webChromeClient = WebChromeClient()
        wv.addJavascriptInterface(WidgetJSBridge(), "SellwildWidgetBridge")
        wv.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        return wv
    }

    private inner class WidgetJSBridge {
        @JavascriptInterface
        fun postMessage(json: String) {
            mainHandler.post {
                try {
                    val obj = JSONObject(json)
                    when (obj.optString("type")) {
                        "WIDGET_LOADED" ->
                            listener?.onWidgetLoaded(this@SellwildWidgetView)
                        "LISTING_CLICK" -> {
                            // The web widget sends window.open(url) on listing tap.
                            // A full listing object is not available at the WebView boundary.
                            val listing = obj.optJSONObject("listing")?.let { parseListing(it) }
                                ?: SellwildListing(
                                    id = "",
                                    status = "active",
                                    title = "",
                                    url = obj.optString("url").ifEmpty { null },
                                )
                            listener?.onListingTapped(listing)
                        }
                        "AD_IMPRESSION" -> {
                            val zoneId = obj.optString("zoneId")
                            listener?.onAdImpression(this@SellwildWidgetView, zoneId)
                        }
                        "ERROR" -> {
                            val msg = obj.optString("message")
                            listener?.onError(this@SellwildWidgetView, msg)
                        }
                    }
                } catch (_: Exception) {}
            }
        }
    }

    private fun parseListing(json: JSONObject): SellwildListing {
        val photosArray = json.optJSONArray("photos")
        val photos = if (photosArray != null) {
            (0 until photosArray.length()).map { i ->
                val p = photosArray.getJSONObject(i)
                SellwildPhoto(
                    url = p.optString("url"),
                    thumbUrl = p.optString("thumbUrl"),
                )
            }
        } else emptyList()

        return SellwildListing(
            id = json.optString("id"),
            status = json.optString("status"),
            title = json.optString("title"),
            url = json.optString("url").ifEmpty { null },
            price = json.optString("price").ifEmpty { null },
            currency = json.optString("currency").ifEmpty { null },
            photos = photos,
        )
    }

    // Serialize config as element attributes.
    // The widget reads config via withCustomizationsFromElement() — attribute names in any case.
    // Complex objects (bidder configs) are JSON-encoded; parseValue() in the widget JSON.parses them.
    private fun configAttributes(): String {
        val parts = mutableListOf<String>()

        fun add(name: String, value: String?) { if (!value.isNullOrEmpty()) parts.add("$name=\"$value\"") }
        fun addBool(name: String, value: Boolean) { if (value) parts.add("$name=\"true\"") }
        fun addInt(name: String, value: Int) { if (value != 0) parts.add("$name=\"$value\"") }
        // Serialize a data class to a JSON attribute by building the JSONObject field-by-field.
        // Do NOT use value.toString() — Kotlin data class toString() is not valid JSON.
        fun addJsonObj(name: String, json: JSONObject?) {
            if (json == null) return
            val escaped = json.toString().replace("\"", "&quot;")
            parts.add("$name=\"$escaped\"")
        }

        add("partner-code", config.partnerCode)
        add("listings", config.listingsUrl)
        // Disable remote customization fetch — see RN htmlBuilder.ts for details.
        parts.add("customize=\"false\"")
        // Ad system selection — REQUIRED. See RN htmlBuilder.ts for details.
        add("ad-type", config.adType ?: "PrebidOnly")
        add("gam-tag", config.gamTag)
        add("gpt-proxy-url", config.gptProxyUrl)
        addBool("disable-gpt", config.disableGpt)
        add("banner-zid", config.bannerZid)
        add("bottom-banner-zid", config.bottomBannerZid)
        add("mobile-banner-zid", config.mobileBannerZid)
        // Filter empties — widget parser does not strip empty strings post-split.
        config.mobileZids.filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }
            ?.let { add("mobile-zid", it.joinToString(",")) }
        addBool("hide-banner-top", config.hideBannerTop)
        addBool("hide-banner-bottom", config.hideBannerBottom)
        addInt("ad-refresh-max", config.adRefreshMax)
        addInt("ad-refresh-max-mobile", config.adRefreshMaxMobile)
        if (config.adRefreshIntervalMs > 0) parts.add("ad-refresh-interval=\"${config.adRefreshIntervalMs}\"")
        addBool("boltive", config.boltive)
        if (config.boltiveClientId.isNotEmpty()) add("boltive-client-id", config.boltiveClientId)
        addBool("lotame", config.lotame)
        add("title", config.title)
        add("link-text", config.linkText)
        addInt("font-size", config.fontSize)
        add("font-color", config.fontColor)
        add("price-color", config.priceColor)
        add("price-font-color", config.priceFontColor)
        if (config.colors.isNotEmpty()) add("colors", config.colors.joinToString(","))
        addBool("debug", config.debug)

        // Ad network bidder configs — serialized as JSON-encoded attributes.
        // The widget's parseValue() will JSON.parse these on the JS side.
        addJsonObj("ix", config.ix?.let { ix ->
            JSONObject().apply {
                put("siteIdM", ix.siteIdM)
                put("siteIdD", ix.siteIdD)
                if (ix.disabled) put("disabled", true)
            }
        })
        addJsonObj("openx", config.openx?.let { ox ->
            JSONObject().apply {
                put("delDomain", ox.delDomain)
                put("unitM", ox.unitM)
                put("unitD", ox.unitD)
                if (ox.disabled) put("disabled", true)
            }
        })
        addJsonObj("pubmatic", config.pubmatic?.let { pm ->
            JSONObject().apply {
                put("pubIdM", pm.pubIdM)
                put("adSlotM", pm.adSlotM)
                put("adSlotD", pm.adSlotD)
                if (pm.disabled) put("disabled", true)
            }
        })
        addJsonObj("appnexus", config.appnexus?.let { an ->
            JSONObject().apply {
                put("placementIdM", an.placementIdM)
                put("placementIdD", an.placementIdD)
                if (an.disabled) put("disabled", true)
            }
        })

        // Mobile ad controls
        addBool("enable-interstitial", config.enableInterstitial)
        addBool("enable-fullscreen-video", config.enableFullscreenVideo)
        addInt("interstitials-per-session", config.interstitialsPerSession)
        addInt("video-takeovers-per-session", config.videoTakeoversPerSession)

        return parts.joinToString("\n    ")
    }

    // Build a Prebid.js pre-configuration <script> block.
    // Runs before prebid.js loads (via pbjs.que). Addresses two WebView issues:
    //  1. ortb2.app — declares in-app inventory so DSPs bid on app traffic, not web.
    //  2. userSync — disables iframe syncs (no 3rd-party cookies in WebView).
    private fun prebidPreConfigScript(): String {
        val fields = mutableListOf("\"publisher\": {\"id\": \"${config.partnerCode}\"}")
        config.appBundleId?.let { fields.add("\"bundle\": \"$it\"") }
        config.appStoreUrl?.let { fields.add("\"storeurl\": \"$it\"") }
        val ortb2App = "{${fields.joinToString(", ")}}"

        val s2sConfigBlock = config.prebidServer?.let { ps ->
            val bidderList = ps.bidders.joinToString(", ") { "\"$it\"" }
            val syncLine = ps.syncEndpoint?.let { url ->
                ", \"syncEndpoint\": {\"p1Consent\": \"$url\", \"noP1Consent\": \"$url\"}"
            } ?: ""
            """,
                // Route all bidder calls through Prebid Server (S2S mode).
                s2sConfig: {
                  "accountId": "${ps.accountId}",
                  "bidders": [$bidderList],
                  "timeout": ${ps.timeout},
                  "adapter": "prebidServer",
                  "endpoint": {"p1Consent": "${ps.endpoint}", "noP1Consent": "${ps.endpoint}"}$syncLine
                }"""
        } ?: ""

        val debugFlag = if (config.debug) ", \"debug\": true" else ""
        return """
          <script>
            window.pbjs = window.pbjs || {};
            window.pbjs.que = window.pbjs.que || [];
            window.pbjs.que.push(function() {
              window.pbjs.setConfig({
                ortb2: { app: $ortb2App },
                userSync: {
                  filterSettings: { iframe: { bidders: '*', filter: 'exclude' } },
                  syncDelay: 5000
                }$s2sConfigBlock$debugFlag
              });
            });
          </script>
        """.trimIndent()
    }

    private fun buildWidgetHTML(): String {
        // Default: generic bundle that reads all config from element attributes.
        // Override by setting widgetJsUrl for a publisher-specific pre-compiled bundle.
        // partner.js loads its own Prebid build internally — do not inject a
        // separate prebid <script> tag (causes double-load and breaks header bidding).
        val widgetSrc = "https://widget.sellwild.com/partner.js"
        val attrs = configAttributes()

        val prebidPreConfig = prebidPreConfigScript()

        return """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: 100%; background: transparent; overflow-x: hidden; }
  </style>
  $prebidPreConfig
</head>
<body>
  <sellwild-widget
    $attrs
  ></sellwild-widget>

  <script>
    (function() {
      function send(type, payload) {
        try {
          SellwildWidgetBridge.postMessage(JSON.stringify(Object.assign({ type: type }, payload || {})));
        } catch(e) {}
      }
      // partner/index.tsx calls window.open() on listing tap — intercept it
      var _open = window.open;
      window.open = function(url) {
        if (url && (url.indexOf('itemDetail') !== -1 || url.indexOf('sellwild.com') !== -1)) {
          send('LISTING_CLICK', { url: url });
          return null;
        }
        return _open.apply(window, arguments);
      };
      document.addEventListener('DOMContentLoaded', function() {
        setTimeout(function() { send('WIDGET_LOADED'); }, 600);
      });
      window.addEventListener('error', function(e) {
        send('ERROR', { message: e.message || 'Widget load error' });
      });
    })();
  </script>

  <script async src="$widgetSrc"></script>
</body>
</html>"""
    }
}
