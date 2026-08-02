package com.sellwild.sdk

import android.net.Uri

/**
 * Scheme allow-list for every externally-opened URL in the SDK.
 *
 * House-ad click URLs (`MOBILE_HOUSE_AD_URL` and friends) come from remote CMS
 * config, and listing tap URLs come from remote listings data — both untrusted.
 * `CustomTabsIntent.launchUrl` fires an `ACTION_VIEW` intent, so an arbitrary
 * scheme (`intent:`/`market:`/`tel:`/a third-party deep link) would resolve to
 * whatever app handles it. Only `http`/`https` are ever opened.
 */
internal object SellwildSafeUrl {
    fun external(url: String?): Uri? {
        if (url.isNullOrEmpty()) return null
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
        return when (uri.scheme?.lowercase()) {
            "http", "https" -> uri
            else -> null
        }
    }
}
