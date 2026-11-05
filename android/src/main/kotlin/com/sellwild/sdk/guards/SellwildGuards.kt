package com.sellwild.sdk.guards

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Debug
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Sellwild views attached to a window now, for the memory report. */
object SellwildViews {
    val adViews = AtomicInteger()
    val feedViews = AtomicInteger()
}

/**
 * The process-wide guards (contracts/FAILURES.md 18.2, 18.3), installed once on the first
 * [SellwildFailures.attach]: low-memory warnings, and the OS's record of how earlier processes
 * ended. No uncaught-exception handler: it would fight the host app's crash reporter.
 */
internal object SellwildGuards {
    private val installed = AtomicBoolean(false)
    private val memoryReported = AtomicBoolean(false)

    internal const val PREFS = "com.sellwild.sdk.guards"
    internal const val LAST_EXIT_KEY = "lastExitTimestamp"
    private const val TRACE_MAX_BYTES = 256 * 1024
    private const val KB_PER_MB = 1024L

    /** Runs work on its own thread. */
    internal val threadRunner: (Runnable) -> Unit = { Thread(it, "sellwild-guards").start() }

    /** Runs [work] off the main thread. Tests run it inline. */
    @Volatile
    internal var runner: (Runnable) -> Unit = threadRunner

    /** Installs the guards once per process. Never throws. */
    fun install(context: Context) {
        if (!installed.compareAndSet(false, true)) return
        val app = context.applicationContext ?: context
        app.registerComponentCallbacks(MemoryCallbacks())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runner(Runnable { reportExits(app) })
        }
    }

    /** Whether trim [level] means memory is low (TRIM_MEMORY_RUNNING_LOW or worse; not UI_HIDDEN). */
    @Suppress("DEPRECATION")
    fun isLowMemory(level: Int): Boolean =
        level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW && level != ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN

    /** One sdk.memory.warning per process, when [level] means memory is low. */
    fun onTrimMemory(level: Int, footprintMb: () -> Long) {
        if (!isLowMemory(level) || !memoryReported.compareAndSet(false, true)) return
        SellwildFailures.log(
            code = SellwildFailureCode.SDK_MEMORY_WARNING,
            component = SellwildFailureComponent.SDK,
            severity = SellwildFailureSeverity.WARN,
            message = "low memory (trim level $level)",
            context = mapOf(
                "footprintMb" to footprintMb(),
                "adViews" to SellwildViews.adViews.get(),
                "feedViews" to SellwildViews.feedViews.get(),
                "level" to level,
            ),
        )
    }

    /** The app's total PSS in MB (Debug.MemoryInfo). */
    fun footprintMb(): Long {
        val info = Debug.MemoryInfo()
        Debug.getMemoryInfo(info)
        return info.totalPss / KB_PER_MB
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
    internal fun reportExits(context: Context) {
        runCatching {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val lastSeen = if (prefs.contains(LAST_EXIT_KEY)) prefs.getLong(LAST_EXIT_KEY, 0L) else null
            val manager = context.getSystemService(ActivityManager::class.java)
            val records = manager.getHistoricalProcessExitReasons(context.packageName, 0, 0).map(::recordOf)
            val decision = ExitReasons.decide(records, lastSeen)
            decision.lastSeen?.let { prefs.edit().putLong(LAST_EXIT_KEY, it).apply() }
            decision.reports.forEach { report ->
                SellwildFailures.logStack(
                    code = report.code,
                    component = SellwildFailureComponent.SDK,
                    severity = report.severity,
                    message = report.message,
                    stack = report.stack,
                )
            }
        }.onFailure { e ->
            SellwildFailures.log(
                code = SellwildFailureCode.SDK_EXIT_REASONS_EXCEPTION,
                component = SellwildFailureComponent.SDK,
                severity = SellwildFailureSeverity.WARN,
                error = e,
            )
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
    private fun recordOf(info: ApplicationExitInfo): ExitRecord = ExitRecord(
        reason = info.reason,
        timestamp = info.timestamp,
        description = info.description,
        trace = if (info.reason == ApplicationExitInfo.REASON_ANR) readTrace(info) else null,
    )

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
    private fun readTrace(info: ApplicationExitInfo): String? =
        info.traceInputStream?.use { stream ->
            val bytes = ByteArray(TRACE_MAX_BYTES)
            var read = 0
            while (read < bytes.size) {
                val n = stream.read(bytes, read, bytes.size - read)
                if (n < 0) break
                read += n
            }
            String(bytes, 0, read, Charsets.UTF_8)
        }

    /** Tests: install again, report memory again. */
    fun resetForTests() {
        installed.set(false)
        memoryReported.set(false)
        SellwildViews.adViews.set(0)
        SellwildViews.feedViews.set(0)
        runner = threadRunner
    }

    @Suppress("DEPRECATION") // the TRIM_MEMORY_* levels Android still delivers
    private class MemoryCallbacks : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) = SellwildGuards.onTrimMemory(level, ::footprintMb)

        override fun onConfigurationChanged(newConfig: Configuration) = Unit

        @Deprecated("ComponentCallbacks.onLowMemory", ReplaceWith("onTrimMemory"))
        override fun onLowMemory() = SellwildGuards.onTrimMemory(
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE,
            ::footprintMb
        )
    }
}
