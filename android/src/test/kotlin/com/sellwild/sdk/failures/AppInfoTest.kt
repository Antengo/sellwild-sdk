package com.sellwild.sdk.failures

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The app context logFailure sends on every event (fv 2), read once at attach. */
@RunWith(RobolectricTestRunner::class)
class AppInfoTest {

    @get:Rule
    val failures = FailuresRule()

    private val app: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `attach sets the package, version, OS and model once`() {
        SellwildFailures.attach(app)
        val first = SellwildFailures.context
        assertEquals(app.packageName, first.appId)
        assertEquals("Android ${Build.VERSION.RELEASE}", first.os)
        assertEquals(Build.MODEL, first.device)
        assertEquals(app.packageManager.getPackageInfo(app.packageName, 0).versionName, first.appVersion)

        SellwildFailures.setContext { it.copy(appVersion = "kept") }
        SellwildFailures.attach(app)
        assertEquals("a second attach leaves it alone", "kept", SellwildFailures.context.appVersion)
    }

    @Test
    fun `a version lookup that fails leaves the version out and is counted`() {
        val context = mockk<Context>()
        every { context.packageName } returns "com.example"
        every { context.packageManager } throws PackageManager.NameNotFoundException("gone")
        val errors = mutableListOf<Throwable>()

        val info = AppInfo.of(context) { errors += it }

        assertEquals("com.example", info.appId)
        assertNull(info.appVersion)
        assertEquals(1, errors.size)
    }
}
