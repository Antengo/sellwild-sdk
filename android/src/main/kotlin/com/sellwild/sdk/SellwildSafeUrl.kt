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

    /** Max bytes accepted for a remotely-fetched (or base64 `data:`) image. */
    const val MAX_IMAGE_BYTES = 8 * 1024 * 1024

    /**
     * A network image URL: `http`/`https` only, so a `file://` value from remote
     * config/listing data can't turn an image fetch into a local-file read.
     * (`data:` is decoded inline by callers, size-capped.)
     */
    fun imageUrl(url: String?): java.net.URL? {
        if (url.isNullOrEmpty()) return null
        val u = runCatching { java.net.URL(url) }.getOrNull() ?: return null
        return if (u.protocol?.lowercase() in setOf("http", "https")) u else null
    }
}
