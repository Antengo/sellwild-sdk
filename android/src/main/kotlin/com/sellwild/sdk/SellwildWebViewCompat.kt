package com.sellwild.sdk

import android.content.Context
import android.os.Build
import android.webkit.WebView

/**
 * Call this from Application.onCreate() BEFORE any WebView is created.
 * On Android 9+ (API 28+), using WebView from multiple processes with the same
 * data directory causes crashes (crbug.com/558377). GMA and Prebid render
 * creatives in WebViews, so multi-process hosts still need this with the
 * native ad path. This sets a process-specific suffix to avoid the conflict.
 *
 * Example in Application:
 * ```kotlin
 * override fun onCreate() {
 *     super.onCreate()
 *     SellwildWebViewCompat.configureForMultiProcess(this)
 * }
 * ```
 */
object SellwildWebViewCompat {
    fun configureForMultiProcess(context: Context) {
        // getProcessName() and setDataDirectorySuffix() exist from API 28.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        dataDirectorySuffix(context.packageName, android.app.Application.getProcessName())
            ?.let { WebView.setDataDirectorySuffix(it) }
    }

    /**
     * The WebView data directory suffix for a process other than the app's main one: the
     * process name with the package prefix and `:` removed. Null for the main process, and
     * when the process name is unknown.
     */
    internal fun dataDirectorySuffix(packageName: String, processName: String?): String? {
        val process = processName ?: packageName
        return process.takeIf { it != packageName }?.replace(packageName, "")?.trimStart(':')
    }
}
