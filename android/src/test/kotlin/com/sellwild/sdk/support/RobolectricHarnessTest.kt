package com.sellwild.sdk.support

import android.content.Context
import android.net.Uri
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.IOException
import java.net.URL
import java.util.Properties

/**
 * Proves the Robolectric harness: real framework classes (plain JUnit tests only get the
 * android.jar stubs, where Uri.parse returns null), the default SDK from
 * robolectric.properties, the offline android-all jar, and the network block inside the
 * sandbox.
 */
@RunWith(RobolectricTestRunner::class)
class RobolectricHarnessTest {

    @get:Rule
    val network = NetworkBlockRule()

    @Test
    fun `Uri parse is the real framework parser`() {
        val uri = Uri.parse("https://widget.sellwild.com/app/weatherbug/weatherbug-main.json?v=1")

        assertEquals("https", uri.scheme)
        assertEquals("widget.sellwild.com", uri.host)
        assertEquals(listOf("app", "weatherbug", "weatherbug-main.json"), uri.pathSegments)
        assertEquals("1", uri.getQueryParameter("v"))
    }

    @Test
    fun `SharedPreferences round-trip through the application context`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("support-selftest", Context.MODE_PRIVATE)
            .edit().putString("uid", "abc").putInt("count", 3).commit()

        val prefs = context.getSharedPreferences("support-selftest", Context.MODE_PRIVATE)

        assertEquals("abc", prefs.getString("uid", null))
        assertEquals(3, prefs.getInt("count", 0))
    }

    @Test
    fun `Robolectric runs on the SDK 35 that robolectric properties sets`() {
        // testOptions.targetSdk is also 35, so SDK_INT alone would pass without the file.
        val properties = Properties()
        javaClass.classLoader!!.getResourceAsStream("robolectric.properties")!!.use(properties::load)

        assertEquals("35", properties.getProperty("sdk"))
        assertEquals(35, Build.VERSION.SDK_INT)
    }

    @Test
    fun `network stays blocked inside the sandbox`() {
        network.expectAttempts()

        val e = assertThrows(IOException::class.java) { URL("https://network-block.invalid/sandbox").openConnection() }

        assertTrue(NetworkBlock.isBlocked(e))
        assertEquals(listOf("https://network-block.invalid/sandbox"), network.attempts)
    }
}
