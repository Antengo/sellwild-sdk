package com.sellwild.sdk

import android.content.Context
import android.net.Uri
import android.net.http.SslError
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.core.WidgetPage
import com.sellwild.sdk.factories.BridgeMessageFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.NetworkBlockRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowApplication
import java.io.ByteArrayInputStream

/**
 * The deprecated WebView widget on Robolectric (ShadowWebView stands in for the WebView): the
 * page it loads, the bridge messages it hears, and the failures it reports. No feature is tested
 * because none was added.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildWidgetViewTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val calls = mutableListOf<String>()
    private val listener = object : SellwildWidgetView.Listener {
        override fun onWidgetLoaded(widgetView: SellwildWidgetView) {
            calls += "loaded"
        }

        override fun onListingTapped(listing: SellwildListing) {
            calls += "tapped:${listing.url}"
        }

        override fun onAdImpression(widgetView: SellwildWidgetView, zoneId: String) {
            calls += "impression:$zoneId"
        }

        override fun onError(widgetView: SellwildWidgetView, message: String) {
            calls += "error:$message"
        }
    }

    private fun widget(config: SellwildConfig? = configWith("TITLE" to "Deals")): Pair<SellwildWidgetView, CapturedEvents> {
        val events = CapturedEvents().install()
        val view = SellwildWidgetView(context).apply {
            listener = this@SellwildWidgetViewTest.listener
            config?.let { setup(it) }
        }
        return view to events
    }

    private fun SellwildWidgetView.web(): WebView = getChildAt(0) as WebView

    private fun SellwildWidgetView.post(json: String) {
        val bridge = checkNotNull(shadowOf(web()).getJavascriptInterface("SellwildWidgetBridge"))
        bridge.javaClass.getMethod("postMessage", String::class.java).apply { isAccessible = true }.invoke(bridge, json)
        idle()
    }

    private fun SellwildWidgetView.client(): WebViewClient = shadowOf(web()).webViewClient

    private fun request(url: String, mainFrame: Boolean) = object : WebResourceRequest {
        override fun getUrl(): Uri = Uri.parse(url)
        override fun isForMainFrame() = mainFrame
        override fun isRedirect() = false
        override fun hasGesture() = false
        override fun getMethod() = "GET"
        override fun getRequestHeaders(): Map<String, String> = emptyMap()
    }

    // WebResourceError's constructor is hidden, so the WebView's error is a mock.
    private fun error(code: Int, description: String): WebResourceError = io.mockk.mockk {
        io.mockk.every { errorCode } returns code
        io.mockk.every { this@mockk.description } returns description
    }

    // SslErrorHandler's constructor is hidden, and SslError needs a certificate, so both are mocks.
    private fun sslError(url: String): SslError = io.mockk.mockk {
        io.mockk.every { this@mockk.url } returns url
        io.mockk.every { primaryError } returns SslError.SSL_UNTRUSTED
    }

    private fun gone(crashed: Boolean) = object : RenderProcessGoneDetail() {
        override fun didCrash() = crashed
        override fun rendererPriorityAtExit() = 0
    }

    // ── Setup and load ───────────────────────────────────────────────────────

    @Test
    fun `setup adds one WebView with the bridge, and sends failures held since configure`() {
        val events = CapturedEvents()
        SellwildEventQueue.setSharedForTests(events.queue)
        SellwildFailures.log(SellwildFailureCode.CONFIG_FETCH_HTTP, SellwildFailureComponent.REMOTE_CONFIG, SellwildFailureSeverity.ERROR, httpStatus = 403)
        val view = SellwildWidgetView(context)

        view.setup(configWith())
        view.setup(configWith())

        assertEquals(1, view.childCount)
        assertTrue(view.web().settings.javaScriptEnabled)
        assertEquals(listOf(SellwildFailureCode.CONFIG_FETCH_HTTP), events.codes)
    }

    @Test
    fun `load puts the widget page in the WebView`() {
        val (view, events) = widget()

        view.load()

        val loaded = shadowOf(view.web()).lastLoadDataWithBaseURL
        assertEquals(WidgetPage.BASE_URL, loaded.baseUrl)
        assertEquals("text/html", loaded.mimeType)
        assertTrue(loaded.data.contains("title=\"Deals\""))
        assertTrue(loaded.data.contains(WidgetPage.SCRIPT_URL))
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `load before setup is reported and heard, and does not crash`() {
        val (view, events) = widget(config = null)

        view.load()

        assertEquals(listOf("error:Call setup() before load()"), calls)
        assertEquals("load() called before setup()", events.attributes(SellwildFailureCode.WIDGET_SETUP_MISSING).getString("msg"))
    }

    @Test
    fun `remote config that does not parse is reported once, and the page has no passthrough`() {
        val (view, events) = widget(SellwildConfig(partnerCode = "fixture", remoteJson = "{not json"))

        view.load()
        view.load()

        events.single(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE)
        assertTrue(shadowOf(view.web()).lastLoadDataWithBaseURL.data.contains("partner-code=\"fixture\""))
    }

    @Test
    fun `pause, resume and destroy reach the WebView, and do nothing before setup`() {
        val (bare, _) = widget(config = null)
        bare.pause()
        bare.resume()
        bare.destroy()

        val (view, _) = widget()
        view.pause()
        view.resume()
        view.destroy()

        assertTrue(shadowOf(view.web()).wasOnPauseCalled())
        assertTrue(shadowOf(view.web()).wasOnResumeCalled())
        assertTrue(shadowOf(view.web()).wasDestroyCalled())
    }

    // ── Bridge messages ──────────────────────────────────────────────────────

    @Test
    fun `each bridge message reaches its listener callback`() {
        val (view, events) = widget()

        view.post(BridgeMessageFactory.variant("default").toString())
        view.post(BridgeMessageFactory.variant("listing-click").toString())
        view.post(BridgeMessageFactory.variant("ad-impression").toString())

        assertEquals(listOf("loaded", "tapped:https://sellwild.com/listing/105140231", "impression:43"), calls)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `the page's own error is reported and heard`() {
        val (view, events) = widget()

        view.post(BridgeMessageFactory.variant("error").toString())

        assertEquals(listOf("error:Uncaught TypeError: Cannot read properties of undefined"), calls)
        val event = events.single(SellwildFailureCode.BRIDGE_SCRIPT_EXCEPTION)
        assertEquals("webview", event.getString("label"))
        assertEquals("Uncaught TypeError: Cannot read properties of undefined", event.getJSONObject("attributes").getString("msg"))
    }

    @Test
    fun `a message that is not JSON is bridge_message_parse`() {
        val (view, events) = widget()

        view.post("{\"type\":")

        assertEquals(emptyList<String>(), calls)
        assertEquals("bridge", events.single(SellwildFailureCode.BRIDGE_MESSAGE_PARSE).getString("label"))
    }

    @Test
    fun `an unknown type and a bad listing are reported, not dispatched`() {
        val (view, events) = widget()

        view.post(BridgeMessageFactory.variant("unknown-type").toString())
        view.post(BridgeMessageFactory.variant("listing-click-bad-photo").toString())

        assertEquals(emptyList<String>(), calls)
        assertEquals(listOf(SellwildFailureCode.BRIDGE_MESSAGE_UNSUPPORTED, SellwildFailureCode.BRIDGE_MESSAGE_INVALID), events.codes)
    }

    @Test
    fun `a host listener that throws is reported and does not escape`() {
        val (view, events) = widget()
        view.listener = object : SellwildWidgetView.Listener {
            override fun onWidgetLoaded(widgetView: SellwildWidgetView) = throw IllegalStateException("host bug")
        }

        view.post(BridgeMessageFactory.variant("default").toString())

        val attributes = events.attributes(SellwildFailureCode.WIDGET_HOST_CALLBACK_EXCEPTION)
        assertEquals("IllegalStateException", attributes.getString("errName"))
        assertEquals("host bug", attributes.getString("msg"))
    }

    @Test
    fun `messages with no listener go nowhere`() {
        val (view, events) = widget()
        view.listener = null

        for (name in listOf("default", "listing-click", "ad-impression", "error")) view.post(BridgeMessageFactory.variant(name).toString())

        assertEquals(listOf(SellwildFailureCode.BRIDGE_SCRIPT_EXCEPTION), events.codes)
    }

    // ── WebView load failures ────────────────────────────────────────────────

    @Test
    fun `a page or widget bundle that fails to load is reported, other resources are not`() {
        val (view, events) = widget()
        val client = view.client()

        client.onReceivedError(view.web(), request("https://widget.sellwild.com/", mainFrame = true), error(-2, "net::ERR_NAME_NOT_RESOLVED"))
        client.onReceivedError(view.web(), request("https://cdn.example.com/photo.jpg", mainFrame = false), error(-6, "net::ERR_CONNECTION_REFUSED"))
        client.onReceivedError(view.web(), request(WidgetPage.SCRIPT_URL, mainFrame = false), error(-8, "net::ERR_TIMED_OUT"))

        assertEquals(listOf(SellwildFailureCode.WIDGET_WEBVIEW_LOAD_NETWORK, SellwildFailureCode.WIDGET_WEBVIEW_LOAD_NETWORK), events.codes)
        assertEquals(
            listOf("WebView error -2: net::ERR_NAME_NOT_RESOLVED", "WebView error -8: net::ERR_TIMED_OUT"),
            events.failures.map { it.getJSONObject("attributes").getString("msg") },
        )
        assertEquals("widget.sellwild.com", events.failures.first().getJSONObject("attributes").getString("host"))
    }

    @Test
    fun `an HTTP error on the page or bundle is reported with its status`() {
        val (view, events) = widget()
        val client = view.client()
        val notFound = WebResourceResponse("text/html", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))

        client.onReceivedHttpError(view.web(), request(WidgetPage.SCRIPT_URL, mainFrame = false), notFound)
        client.onReceivedHttpError(view.web(), request("https://cdn.example.com/photo.jpg", mainFrame = false), notFound)

        val attributes = events.attributes(SellwildFailureCode.WIDGET_WEBVIEW_LOAD_HTTP)
        assertEquals("404", attributes.getString("httpStatus"))
        assertEquals("HTTP 404", attributes.getString("msg"))
    }

    @Test
    fun `a certificate error on the widget bundle is reported and cancelled, one on another resource is only cancelled`() {
        val (view, events) = widget()
        val bundle = io.mockk.mockk<SslErrorHandler>(relaxed = true)
        val photo = io.mockk.mockk<SslErrorHandler>(relaxed = true)

        view.client().onReceivedSslError(view.web(), bundle, sslError(WidgetPage.SCRIPT_URL))
        view.client().onReceivedSslError(view.web(), photo, sslError("https://cdn.example.com/photo.jpg"))

        val attributes = events.attributes(SellwildFailureCode.WIDGET_WEBVIEW_LOAD_NETWORK)
        assertEquals("SSL error 3", attributes.getString("msg"))
        assertEquals("widget.sellwild.com", attributes.getString("host"))
        // The widget never proceeds past a bad certificate: both loads are cancelled, as the default does.
        io.mockk.verify(exactly = 1) { bundle.cancel() }
        io.mockk.verify(exactly = 1) { photo.cancel() }
        io.mockk.verify(exactly = 0) { bundle.proceed() }
        io.mockk.verify(exactly = 0) { photo.proceed() }
    }

    @Test
    fun `a render process that dies is handled, reported and heard, and the next load starts a new WebView`() {
        val (view, events) = widget()
        val dead = view.web()

        val handled = view.client().onRenderProcessGone(dead, gone(crashed = true))

        assertTrue(handled)
        assertEquals(0, view.childCount)
        assertTrue(shadowOf(dead).wasDestroyCalled())
        assertEquals(listOf("error:Widget WebView render process gone"), calls)
        assertEquals("WebView render process crashed", events.attributes(SellwildFailureCode.WIDGET_WEBVIEW_PROCESS_EXCEPTION).getString("msg"))

        view.load()
        assertNotSame(dead, view.web())
        assertTrue(shadowOf(view.web()).lastLoadDataWithBaseURL.data.contains("<sellwild-widget"))
    }

    @Test
    fun `a render process the system killed is told apart from a crash`() {
        val (view, events) = widget()
        view.listener = null

        view.client().onRenderProcessGone(view.web(), gone(crashed = false))
        view.setup(configWith())

        assertEquals("WebView render process was killed", events.attributes(SellwildFailureCode.WIDGET_WEBVIEW_PROCESS_EXCEPTION).getString("msg"))
        assertEquals(1, view.childCount)
    }

    // ── Multi-process WebView ────────────────────────────────────────────────

    @Test
    fun `a second process gets its own WebView data directory, the main one none`() {
        val suffix = Class.forName("android.webkit.WebViewFactory").getDeclaredField("sDataDirectorySuffix").apply { isAccessible = true }

        SellwildWebViewCompat.configureForMultiProcess(context)
        assertEquals(null, suffix.get(null))

        ShadowApplication.setProcessName("${context.packageName}:ads")
        SellwildWebViewCompat.configureForMultiProcess(context)
        assertEquals("ads", suffix.get(null))
        suffix.set(null, null)
        assertFalse(calls.isNotEmpty())
    }

    // ── No listener, a listener that overrides nothing, and a removed WebView ─

    @Test
    fun `a listener that overrides nothing takes every message`() {
        val (view, events) = widget()
        view.listener = object : SellwildWidgetView.Listener {}

        for (name in listOf("default", "listing-click", "ad-impression", "error")) view.post(BridgeMessageFactory.variant(name).toString())

        assertEquals(listOf(SellwildFailureCode.BRIDGE_SCRIPT_EXCEPTION), events.codes)
    }

    @Test
    fun `load before setup with no listener is still reported`() {
        val (view, events) = widget(config = null)
        view.listener = null

        view.load()

        events.single(SellwildFailureCode.WIDGET_SETUP_MISSING)
        assertEquals(0, view.childCount)
    }

    @Test
    fun `setup after the host removed the WebView puts the same WebView back`() {
        val (view, events) = widget()
        val web = view.web()

        view.removeAllViews()
        view.setup(configWith("TITLE" to "Deals"))

        assertEquals(1, view.childCount)
        assertTrue(web === view.web())
        assertEquals(emptyList<String>(), events.codes)
    }
}
