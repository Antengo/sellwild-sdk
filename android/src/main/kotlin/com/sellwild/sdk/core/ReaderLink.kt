package com.sellwild.sdk.core

import java.net.URLEncoder

/**
 * Adds the reader's id to a sellwild.com link as `sw_wuid`, so sellwild.com can match an
 * app reader to their visit (next-sellwild utils/identity-bridge.ts linkWidgetToBrowser).
 * The same rule as the web widget's `withWidgetUid` (sellwild-widget
 * src/core/customizations/urls.ts).
 */
internal object ReaderLink {

    const val PARAM = "sw_wuid"

    private val SELLWILD_LINK = Regex("^https://(www\\.)?sellwild\\.com(?=[/?#]|$)", RegexOption.IGNORE_CASE)

    /**
     * [url] with `sw_wuid=<readerId>` as its last query param, any earlier `sw_wuid` dropped
     * and the #fragment kept. Only https links to sellwild.com or www.sellwild.com change; any
     * other host, a relative link or an empty id come back as is. The rest of the URL is kept
     * byte for byte (no decode and re-encode), so a link that would not parse is not made worse.
     */
    fun withReaderId(url: String, readerId: String?): String {
        if (readerId.isNullOrEmpty() || !SELLWILD_LINK.containsMatchIn(url)) return url
        val hashAt = url.indexOf('#')
        val fragment = if (hashAt >= 0) url.substring(hashAt) else ""
        val beforeFragment = if (hashAt >= 0) url.substring(0, hashAt) else url
        val queryAt = beforeFragment.indexOf('?')
        val base = if (queryAt >= 0) beforeFragment.substring(0, queryAt) else beforeFragment
        val kept = if (queryAt >= 0) {
            beforeFragment.substring(queryAt + 1).split('&')
                .filter { it.isNotEmpty() && it.substringBefore('=') != PARAM }
        } else {
            emptyList()
        }
        val param = "$PARAM=${URLEncoder.encode(readerId, "UTF-8")}"
        return "$base?${(kept + param).joinToString("&")}$fragment"
    }
}
