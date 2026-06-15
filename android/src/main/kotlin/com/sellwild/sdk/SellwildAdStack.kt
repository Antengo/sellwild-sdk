package com.sellwild.sdk

import org.json.JSONObject

/**
 * Which ad SDK stack a placement runs. Toggled remotely via the CDN keys
 * `AD_STACK` (global) and `AD_STACK_BY_ZONE` (per-zone) so GAM (Google Ad
 * Manager / Google Ads) and Prebid can be segmented without an SDK release.
 *
 *  - [BOTH]        Prebid auction fetches demand, then GAM renders (default).
 *  - [GAM_ONLY]    Plain GAM request, no Prebid auction.
 *  - [PREBID_ONLY] Prebid's own rendering path; NO GAM ad request is made, so
 *                  no GAM request/serving fees are incurred.
 */
enum class SellwildAdStack {
    BOTH,
    GAM_ONLY,
    PREBID_ONLY;

    companion object {
        /** Parse a CDN string (case/alias tolerant). Returns null if unknown. */
        fun parse(raw: String?): SellwildAdStack? {
            if (raw == null) return null
            val k = raw.lowercase().filter { it != ' ' && it != '_' && it != '-' }
            return when (k) {
                "both", "all", "default" -> BOTH
                "gam", "gamonly", "google", "gads", "googleads" -> GAM_ONLY
                "prebid", "prebidonly", "prebidsdk" -> PREBID_ONLY
                else -> null
            }
        }

        /**
         * Resolve the effective stack for a placement.
         *
         * Precedence (matches all platforms):
         *   1. [override] (code-level, e.g. set on [SellwildAdView] for QA).
         *   2. Global `AD_STACK` — hard-wins for every placement.
         *   3. Per-zone `AD_STACK_BY_ZONE[zoneId]`.
         *   4. [BOTH] (today's default behavior).
         */
        fun resolve(
            remoteJson: String?,
            zoneId: String?,
            override: SellwildAdStack? = null,
        ): SellwildAdStack {
            if (override != null) return override

            val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() }

            parse(obj?.optStringOrNull("AD_STACK"))?.let { return it }

            if (zoneId != null) {
                val byZone = obj?.optJSONObject("AD_STACK_BY_ZONE")
                parse(byZone?.optStringOrNull(zoneId))?.let { return it }
            }

            return BOTH
        }

        private fun JSONObject.optStringOrNull(key: String): String? =
            if (has(key) && !isNull(key)) optString(key) else null
    }
}
