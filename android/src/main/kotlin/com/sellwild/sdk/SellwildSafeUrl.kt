package com.sellwild.sdk

import android.net.Uri
import com.sellwild.sdk.core.Fetch

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
    /**
     * [url] as a Uri when it is http or https, else null. Uri.parse never throws for
     * non-null text (it parses lazily). The caller reports a refused URL.
     */
    fun external(url: String?): Uri? {
        if (url.isNullOrEmpty()) return null
        val uri = Uri.parse(url)
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
        // Null for text that is not a URL or has another scheme: an expected outcome that
        // the caller reports as a rejected image (house.image.invalid, feed.image.*).
        return Fetch.httpUrl(url).getOrNull()
    }
}
