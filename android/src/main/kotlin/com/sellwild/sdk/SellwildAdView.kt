package com.sellwild.sdk

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import org.json.JSONObject

/**
 * Android View that renders a Sellwild ad unit via WebView.
 * Supports banner ads using GPT or zone-based delivery.
 *
 * Usage:
 * ```kotlin
 * val adView = SellwildAdView(context)
 * adView.setup(config, AdSize.MREC_300x250, zoneId = "12345")
 * adView.load()
 * ```
 */
class SellwildAdView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    interface Listener {
        fun onAdLoaded(adView: SellwildAdView) {}
        fun onAdImpression(adView: SellwildAdView, zoneId: String) {}
        fun onAdClicked(adView: SellwildAdView) {}
        fun onAdFailed(adView: SellwildAdView, message: String) {}
    }

    private lateinit var config: SellwildConfig
    private lateinit var adSize: AdSize
    private var zoneId: String? = null
    var listener: Listener? = null

    private val webView: WebView by lazy { createWebView() }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var refreshHandler: Handler? = null
    private var refreshCount = 0

    fun setup(config: SellwildConfig, adSize: AdSize, zoneId: String? = null) {
        this.config = config
        this.adSize = adSize
        this.zoneId = zoneId

        if (childCount == 0) {
            val dp = context.resources.displayMetrics.density
            val widthPx = (adSize.width * dp).toInt()
            val heightPx = (adSize.height * dp).toInt()
            addView(webView, LayoutParams(widthPx, heightPx))
        }
    }

    fun load() {
        val html = buildAdHTML()
        val baseUrl = "https://widget.sellwild.com"
        webView.loadDataWithBaseURL(baseUrl, html, "text/html", "UTF-8", null)
    }

    fun pause() {
        refreshHandler?.removeCallbacksAndMessages(null)
        refreshHandler = null
        webView.onPause()
    }

    fun resume() {
        webView.onResume()
    }

    fun destroy() {
        pause()
        webView.destroy()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(): WebView {
        val wv = WebView(context)
        with(wv.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            useWideViewPort = true
            loadWithOverviewMode = true
        }
        wv.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                mainHandler.post { listener?.onAdLoaded(this@SellwildAdView) }
            }
        }
        wv.webChromeClient = WebChromeClient()
        wv.addJavascriptInterface(SellwildJSBridge(), "SellwildBridge")
        wv.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        return wv
    }

    private inner class SellwildJSBridge {
        @JavascriptInterface
        fun postMessage(json: String) {
            mainHandler.post {
                try {
                    val obj = JSONObject(json)
                    when (obj.optString("type")) {
                        "impression" -> {
                            val zid = obj.optString("zoneId").ifEmpty { zoneId ?: "" }
                            listener?.onAdImpression(this@SellwildAdView, zid)
                            scheduleRefresh()
                        }
                        "click" -> listener?.onAdClicked(this@SellwildAdView)
                        "error" -> listener?.onAdFailed(this@SellwildAdView, obj.optString("message"))
                    }
                } catch (_: Exception) {}
            }
        }
    }

    private fun scheduleRefresh() {
        val maxRefresh = config.adRefreshMaxMobile.takeIf { it > 0 } ?: config.adRefreshMax
        if (maxRefresh <= 0 || refreshCount >= maxRefresh) return

        val handler = Handler(Looper.getMainLooper())
        refreshHandler = handler
        handler.postDelayed({
            refreshCount++
            load()
        }, config.adRefreshIntervalMs)
    }

    private fun buildAdHTML(): String {
        val w = adSize.width
        val h = adSize.height
        val gptBase = config.gptProxyUrl ?: "https://securepubads.g.doubleclick.net"
        val gptSrc = "$gptBase/tag/js/gpt.js"

        val adScript = when {
            !config.gamTag.isNullOrEmpty() && !config.disableGpt ->
                buildGptScript(config.gamTag!!, gptSrc, w, h)
            !zoneId.isNullOrEmpty() ->
                buildZoneScript(zoneId!!, w, h)
            else -> "// No ad configuration"
        }

        return """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: ${w}px; height: ${h}px; overflow: hidden; background: transparent; }
    #ad { width: ${w}px; height: ${h}px; }
  </style>
</head>
<body>
  <div id="ad"></div>
  <script>
    function notify(type, data) {
      var msg = JSON.stringify(Object.assign({ type: type }, data || {}));
      SellwildBridge.postMessage(msg);
    }
    $adScript
  </script>
</body>
</html>"""
    }

    private fun buildGptScript(gamTag: String, gptSrc: String, w: Int, h: Int) = """
        window.googletag = window.googletag || { cmd: [] };
        var s = document.createElement('script');
        s.src = '$gptSrc';
        s.async = true;
        document.head.appendChild(s);
        googletag.cmd.push(function() {
          var slot = googletag.defineSlot('$gamTag', [$w, $h], 'ad');
          if (slot) {
            slot.addService(googletag.pubads());
            googletag.pubads().enableSingleRequest();
            googletag.pubads().addEventListener('slotRenderEnded', function(e) {
              if (!e.isEmpty) notify('impression', { zoneId: '' });
            });
            googletag.enableServices();
            googletag.display('ad');
          }
        });
    """.trimIndent()

    private fun buildZoneScript(zoneId: String, w: Int, h: Int) = """
        var s = document.createElement('script');
        s.src = 'https://bidstream.sellwild.com/ads?zone=$zoneId&w=$w&h=$h';
        s.async = true;
        s.onload = function() { notify('impression', { zoneId: '$zoneId' }); };
        document.getElementById('ad').appendChild(s);
    """.trimIndent()
}
