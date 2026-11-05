package com.sellwild.sdk.failures

import android.util.Log

/**
 * The SDK's debug logger (FAILURES.md section 2). One of the two Android files allowed
 * to print: every call is a no-op unless [enabled], which [SellwildFailures.setContext]
 * keeps equal to the SDK debug flag (config.debug).
 *
 * Trace output only. A failure is never handled by printing it here: it goes to
 * [SellwildFailures.log], whose debug echo is the one failure line printed through
 * [debug].
 */
object SellwildLog {
    const val TAG = "Sellwild"

    @Volatile
    var enabled: Boolean = false

    /** Where lines go: Logcat in the SDK; tests capture them. */
    @Volatile
    internal var printer: (String) -> Unit = ::logcat

    /** Prints [message] when [enabled]. */
    fun debug(message: String) {
        if (enabled) printer(message)
    }

    /** Builds and prints the line only when [enabled], so callers pay nothing when off. */
    fun debug(message: () -> String) {
        if (enabled) printer(message())
    }

    internal fun resetForTests() {
        enabled = false
        printer = ::logcat
    }

    private fun logcat(line: String) {
        Log.d(TAG, line)
    }
}
