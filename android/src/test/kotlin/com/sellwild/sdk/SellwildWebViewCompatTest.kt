package com.sellwild.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowApplication

/** SellwildWebViewCompat: the multi-process WebView data directory, which ad creatives' WebViews need. */
@RunWith(RobolectricTestRunner::class)
class SellwildWebViewCompatTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `the WebView data directory suffix is set only for another process`() {
        assertNull(SellwildWebViewCompat.dataDirectorySuffix("com.app", "com.app"))
        assertNull(SellwildWebViewCompat.dataDirectorySuffix("com.app", null))
        assertEquals("ads", SellwildWebViewCompat.dataDirectorySuffix("com.app", "com.app:ads"))
        assertEquals("other", SellwildWebViewCompat.dataDirectorySuffix("com.app", "other"))
    }

    @Test
    fun `a second process gets its own WebView data directory, the main one none`() {
        val suffix = Class.forName("android.webkit.WebViewFactory")
            .getDeclaredField("sDataDirectorySuffix")
            .apply { isAccessible = true }

        SellwildWebViewCompat.configureForMultiProcess(context)
        assertEquals(null, suffix.get(null))

        ShadowApplication.setProcessName("${context.packageName}:ads")
        SellwildWebViewCompat.configureForMultiProcess(context)
        assertEquals("ads", suffix.get(null))
        suffix.set(null, null)
    }
}
