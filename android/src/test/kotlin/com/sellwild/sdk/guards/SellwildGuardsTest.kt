package com.sellwild.sdk.guards

import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.CapturedEvents
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.NetworkBlockRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowActivityManager.ApplicationExitInfoBuilder

/** Memory warnings and earlier process exits (FAILURES.md 18.2, 18.3) on Robolectric. */
@RunWith(RobolectricTestRunner::class)
class SellwildGuardsTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val app: Application = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents

    @Before
    fun setUp() {
        events = CapturedEvents().install()
        app.getSharedPreferences(SellwildGuards.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Suppress("DEPRECATION")
    @Test
    fun `low memory is reported once per process with the footprint and the live views`() {
        SellwildFailures.attach(app)
        SellwildViews.adViews.set(3)
        SellwildViews.feedViews.set(1)

        app.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN)
        app.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE)
        app.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
        app.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL)
        app.onLowMemory()
        app.onConfigurationChanged(android.content.res.Configuration())

        val attributes = events.attributes(SellwildFailureCode.SDK_MEMORY_WARNING)
        assertEquals("sdk", events.failures.single().getString("label"))
        assertEquals("warn", attributes.getString("severity"))
        assertEquals("3", attributes.getString("ctx.adViews"))
        assertEquals("1", attributes.getString("ctx.feedViews"))
        assertEquals("10", attributes.getString("ctx.level"))
        assertTrue(attributes.getString("ctx.footprintMb").toLong() >= 0)
    }

    @Suppress("DEPRECATION")
    @Test
    fun `the trim levels that mean memory is low`() {
        assertFalse(SellwildGuards.isLowMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE))
        assertTrue(SellwildGuards.isLowMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW))
        assertTrue(SellwildGuards.isLowMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL))
        assertFalse(
            "the UI went away; not memory",
            SellwildGuards.isLowMemory(ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN)
        )
        assertTrue(SellwildGuards.isLowMemory(ComponentCallbacks2.TRIM_MEMORY_COMPLETE))
    }

    private fun exit(reason: Int, at: Long, description: String? = null, trace: String? = null): ApplicationExitInfo =
        ApplicationExitInfoBuilder.newBuilder()
            .setProcessName(app.packageName)
            .setReason(reason)
            .setTimestamp(at)
            .setDescription(description)
            .apply { trace?.let { setTraceInputStream(it.byteInputStream()) } }
            .build()

    private val manager get() = shadowOf(app.getSystemService(ActivityManager::class.java))

    @Test
    fun `the first launch remembers the newest exit and reports nothing, the next reports what is new`() {
        manager.addApplicationExitInfo(exit(ApplicationExitInfo.REASON_LOW_MEMORY, 100))
        SellwildGuards.reportExits(app)
        assertEquals(emptyList<String>(), events.codes)
        assertEquals(
            100L,
            app.getSharedPreferences(
                SellwildGuards.PREFS,
                Context.MODE_PRIVATE
            ).getLong(SellwildGuards.LAST_EXIT_KEY, 0)
        )

        manager.addApplicationExitInfo(
            exit(
                ApplicationExitInfo.REASON_CRASH,
                200,
                "java.lang.IllegalStateException at com.sellwild.sdk.SellwildAdView"
            )
        )
        manager.addApplicationExitInfo(
            exit(
                ApplicationExitInfo.REASON_ANR,
                300,
                "Input dispatching timed out",
                "\"main\"\n  at com.sellwild.sdk.SellwildFeedView.load(SellwildFeedView.kt:262)\n"
            ),
        )
        SellwildGuards.reportExits(app)

        assertEquals(
            listOf(SellwildFailureCode.SDK_CRASH_EXCEPTION, SellwildFailureCode.SDK_HANG_TIMEOUT),
            events.codes
        )
        val hang = events.failures[1].getJSONObject("attributes")
        assertEquals("com.sellwild.sdk.SellwildFeedView.load(SellwildFeedView.kt:262)", hang.getString("stack"))
        assertEquals("fatal", events.failures[0].getJSONObject("attributes").getString("severity"))
    }

    @Test
    fun `install scans the exits once per process`() {
        SellwildGuards.install(app)
        manager.addApplicationExitInfo(exit(ApplicationExitInfo.REASON_LOW_MEMORY, 500))
        SellwildGuards.install(app)

        // The first scan found nothing and stored no timestamp; the second install does not scan.
        assertEquals(
            false,
            app.getSharedPreferences(SellwildGuards.PREFS, Context.MODE_PRIVATE).contains(SellwildGuards.LAST_EXIT_KEY)
        )
    }

    @Test
    fun `a context with no application context installs on itself, and the thread runner runs the work`() {
        val bare = object : ContextWrapper(app) {
            override fun getApplicationContext(): Context? = null
        }
        SellwildGuards.install(bare)

        val ran = java.util.concurrent.CountDownLatch(1)
        SellwildGuards.threadRunner(Runnable { ran.countDown() })
        assertTrue(ran.await(5, java.util.concurrent.TimeUnit.SECONDS))
    }

    @Test
    fun `before Android 11 there are no exit reasons to read`() {
        var scheduled = 0
        SellwildGuards.runner = { scheduled++ }
        val sdk = android.os.Build.VERSION.SDK_INT
        org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", 29)
        try {
            SellwildGuards.install(app)
        } finally {
            org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", sdk)
        }

        assertEquals(0, scheduled)
    }

    @Test
    fun `an ANR with no trace, and a trace longer than the read limit, are still read`() {
        manager.addApplicationExitInfo(exit(ApplicationExitInfo.REASON_LOW_MEMORY, 10))
        SellwildGuards.reportExits(app)
        val longTrace = "\"main\"\n  at com.sellwild.sdk.A.b(A.kt:1)\n" + "x".repeat(300 * 1024)
        manager.addApplicationExitInfo(exit(ApplicationExitInfo.REASON_ANR, 20, "no trace"))
        manager.addApplicationExitInfo(exit(ApplicationExitInfo.REASON_ANR, 30, "long", longTrace))

        SellwildGuards.reportExits(app)

        assertEquals(listOf(SellwildFailureCode.SDK_HANG_TIMEOUT), events.codes)
        assertEquals(
            "com.sellwild.sdk.A.b(A.kt:1)",
            events.failures.single().getJSONObject("attributes").getString("stack")
        )
    }

    @Test
    fun `exit reasons that cannot be read are reported`() {
        val broken = object : ContextWrapper(app) {
            override fun getSystemService(name: String): Any = throw SecurityException("no access")
        }

        SellwildGuards.reportExits(broken)

        events.single(SellwildFailureCode.SDK_EXIT_REASONS_EXCEPTION)
    }
}
