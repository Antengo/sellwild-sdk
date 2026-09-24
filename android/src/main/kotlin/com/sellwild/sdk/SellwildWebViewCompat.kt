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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val processName = context.packageName.let { pkg ->
                // getProcessName() is available from API 28
                android.app.Application.getProcessName() ?: pkg
            }
            val packageName = context.packageName
            if (processName != packageName) {
                WebView.setDataDirectorySuffix(processName.replace(packageName, "").trimStart(':'))
            }
        }
    }
}
