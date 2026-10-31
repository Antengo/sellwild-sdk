package com.sellwild.sdk

import android.app.Application
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/**
 * The manifest-merged init provider hands configure() the application Context, and
 * configure() then pre-warms GMA and Prebid on the main thread, as iOS does.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildInitProviderTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val app: Application = ApplicationProvider.getApplicationContext()
    private val configUrl = "https://widget.sellwild.com/app/weatherbug/weatherbug-main.json"

    @Before
    @After
    fun clearContext() {
        SellwildSDK.appContext = null
    }

    private fun configure(): SellwildConfig {
        val body = AppConfigFactory.checked().toString()
        return HttpStub.install { url -> StubResponse(200, body).takeIf { url.toString() == configUrl } }.use {
            runBlocking { SellwildSDK.configure("weatherbug", "weatherbug-main") }
        }
    }

    @Test
    fun `at app start it keeps the application context and serves no data`() {
        val provider = Robolectric.buildContentProvider(SellwildInitProvider::class.java).create().get()

        assertSame(app, SellwildSDK.appContext)
        val uri = Uri.parse("content://com.sellwild.sdk.test.sellwild-init/x")
        assertNull(provider.query(uri, null, null, null, null))
        assertNull(provider.getType(uri))
        assertNull(provider.insert(uri, null))
        assertEquals(0, provider.delete(uri, null, null))
        assertEquals(0, provider.update(uri, null, null, null))
    }

    @Test
    fun `without a context it starts and keeps none`() {
        assertTrue(SellwildInitProvider().onCreate())
        assertNull(SellwildSDK.appContext)
    }

    @Test
    fun `configure pre-warms GMA and Prebid on the main thread once it has a context`() {
        SellwildSDK.appContext = app

        configure()
        assertEquals("posted, not run on the IO thread", emptyList<Any>(), ads.network.gmaInits)
        idle()

        assertEquals(listOf<Any>(app), ads.network.gmaInits.toList())
        assertEquals(1, ads.network.prebidHosts.size)
    }

    @Test
    fun `configure without a context pre-warms nothing`() {
        configure()
        idle()

        assertEquals(emptyList<Any>(), ads.network.gmaInits.toList())
        assertEquals(emptyList<String>(), ads.network.prebidHosts.toList())
    }
}
