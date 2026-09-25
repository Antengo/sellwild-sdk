package com.sellwild.sdk

import android.annotation.SuppressLint
import android.content.Context
import android.net.http.SslError
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import com.sellwild.sdk.core.BridgeMessage
import com.sellwild.sdk.core.WidgetBridge
import com.sellwild.sdk.core.WidgetPage
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures

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
        // getProcessName() exists from API 28, and WidgetPage asks for it only there.
        WidgetPage.dataDirectorySuffix(Build.VERSION.SDK_INT, context.packageName) { android.app.Application.getProcessName() }
            ?.let { WebView.setDataDirectorySuffix(it) }
    }
}

/**
 * The WebView marketplace widget. Deprecated in favor of the native surfaces (SellwildFeedView,
 * SellwildAdView): it gets failure reporting and nothing new. The page it loads is built by
 * [WidgetPage]; the messages the page posts are decoded by [WidgetBridge].
 */
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

    // Created on first use; dropped when its render process is gone, so the next
    // setup() or load() starts a new one.
    private var web: WebView? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Attaches [config]. It is also the widget-only app's first Context, so logFailure is
     * attached here and failures held since configure() go out.
     */
    fun setup(config: SellwildConfig) {
        this.config = config
        config.claimFailurePartner()
        SellwildFailures.attach(context)
        if (childCount == 0) addView(webView(), fullSize())
    }

    fun load() {
        if (!::config.isInitialized) {
            // This used to throw (check()) and crash the host.
            log(SellwildFailureCode.WIDGET_SETUP_MISSING, SellwildFailureSeverity.ERROR, message = "load() called before setup()")
            listener?.onError(this, "Call setup() before load()")
            return
        }
        val html = WidgetPage.html(config, remoteObject(config.remoteJson))
        // A WebView whose render process died was dropped: start a new one in its place.
        val wv = web ?: webView().also { addView(it, fullSize()) }
        wv.loadDataWithBaseURL(WidgetPage.BASE_URL, html, "text/html", "UTF-8", null)
    }

    fun pause() {
        web?.onPause()
    }

    fun resume() {
        web?.onResume()
    }

    fun destroy() {
        web?.destroy()
    }

    /** The WebView, created on first use. */
    private fun webView(): WebView = web ?: createWebView().also { web = it }

    private fun fullSize() = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)

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
        // The widget sends WIDGET_LOADED through the JS bridge; the client only reports
        // what blanks the widget.
        wv.webViewClient = WidgetClient()
        wv.webChromeClient = WebChromeClient()
        wv.addJavascriptInterface(WidgetJSBridge(), "SellwildWidgetBridge")
        wv.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        return wv
    }

    /** Reports the load failures that leave the widget blank (the page or partner.js). */
    private inner class WidgetClient : WebViewClient() {
        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            val url = request.url.toString()
            if (!WidgetPage.isWidgetResource(url, request.isForMainFrame)) return
            log(
                SellwildFailureCode.WIDGET_WEBVIEW_LOAD_NETWORK,
                SellwildFailureSeverity.ERROR,
                message = "WebView error ${error.errorCode}: ${error.description}",
                url = url,
            )
        }

        override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
            val url = request.url.toString()
            if (!WidgetPage.isWidgetResource(url, request.isForMainFrame)) return
            log(
                SellwildFailureCode.WIDGET_WEBVIEW_LOAD_HTTP,
                SellwildFailureSeverity.ERROR,
                message = "HTTP ${errorResponse.statusCode}",
                httpStatus = errorResponse.statusCode,
                url = url,
            )
        }

        /**
         * A certificate error. On the widget bundle (partner.js) it blanks the widget, so it is
         * reported; other subresources are not. Either way the load is cancelled, as the default
         * does: the widget never proceeds past a bad certificate.
         */
        override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
            if (WidgetPage.isWidgetResource(error.url, isMainFrame = false)) {
                log(
                    SellwildFailureCode.WIDGET_WEBVIEW_LOAD_NETWORK,
                    SellwildFailureSeverity.ERROR,
                    message = "SSL error ${error.primaryError}",
                    url = error.url,
                )
            }
            super.onReceivedSslError(view, handler, error)
        }

        /**
         * The WebView's render process crashed or was killed. Unhandled (the default returns
         * false) the system kills the app. The widget reports it, drops the dead WebView so the
         * next setup() or load() starts a new one, tells the listener, and keeps the app alive.
         */
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            log(
                SellwildFailureCode.WIDGET_WEBVIEW_PROCESS_EXCEPTION,
                SellwildFailureSeverity.ERROR,
                message = if (detail.didCrash()) "WebView render process crashed" else "WebView render process was killed",
            )
            web = null
            removeView(view)
            view.destroy()
            listener?.onError(this@SellwildWidgetView, "Widget WebView render process gone")
            return true
        }
    }

    private inner class WidgetJSBridge {
        @JavascriptInterface
        fun postMessage(json: String) {
            mainHandler.post { handleMessage(json) }
        }
    }

    /**
     * One message from the page, on the main thread. A message that cannot be used is
     * reported (bridge.message.*); a host listener that throws is reported
     * (widget.host_callback.exception) and does not reach the WebView.
     */
    private fun handleMessage(json: String) {
        val message = WidgetBridge.decode(json).reported() ?: return
        try {
            dispatch(message)
        } catch (e: Exception) {
            log(SellwildFailureCode.WIDGET_HOST_CALLBACK_EXCEPTION, SellwildFailureSeverity.WARN, error = e)
        }
    }

    /** Hands [message] to the host listener. */
    private fun dispatch(message: BridgeMessage) = when (message) {
        BridgeMessage.Loaded -> listener?.onWidgetLoaded(this)
        is BridgeMessage.ListingClick -> listener?.onListingTapped(message.listing)
        is BridgeMessage.AdImpression -> listener?.onAdImpression(this, message.zoneId)
        is BridgeMessage.Error -> {
            // The page's own window error: the widget is broken, whatever the listener does.
            log(SellwildFailureCode.BRIDGE_SCRIPT_EXCEPTION, SellwildFailureSeverity.ERROR, message = message.message)
            listener?.onError(this, message.message)
        }
    }

    private fun log(code: String, severity: String, message: String? = null, error: Throwable? = null, httpStatus: Int? = null, url: String? = null) {
        SellwildFailures.log(
            code = code,
            component = SellwildFailureComponent.WEBVIEW,
            severity = severity,
            error = error,
            message = message,
            httpStatus = httpStatus,
            url = url,
        )
    }
}
