package com.sellwild.sdk.failures

import android.content.Context
import android.os.Build

/** The app context attributes logFailure sends (FAILURES.md 6.3), read once. */
internal data class AppInfo(val appId: String?, val appVersion: String?, val os: String, val device: String?) {
    companion object {
        /**
         * From [context]: package name, its versionName, `Android <release>` and Build.MODEL.
         * A versionName lookup that throws goes to [onError] and leaves the version out.
         */
        fun of(context: Context, onError: (Throwable) -> Unit): AppInfo = AppInfo(
            appId = context.packageName,
            appVersion = versionName(context, onError),
            os = "Android ${Build.VERSION.RELEASE}",
            device = Build.MODEL,
        )

        @Suppress("DEPRECATION")
        private fun versionName(context: Context, onError: (Throwable) -> Unit): String? =
            runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }
                .onFailure(onError)
                .getOrNull()
    }
}
