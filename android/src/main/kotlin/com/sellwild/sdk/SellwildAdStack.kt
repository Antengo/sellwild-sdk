package com.sellwild.sdk

import com.sellwild.sdk.core.Issue
import com.sellwild.sdk.core.RemoteValues
import com.sellwild.sdk.core.Resolved
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
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
         *
         * A value that is set but not a known mode (or a by-zone value that is not a map)
         * is skipped and reported as config.adstack.invalid, once per config text.
         */
        fun resolve(
            remoteJson: String?,
            zoneId: String?,
            override: SellwildAdStack? = null,
        ): SellwildAdStack {
            if (override != null) return override
            return resolveFrom(remoteObject(remoteJson), zoneId).reportedOncePer(remoteJson)
        }

        /** [resolve] without the override, pure: global, then the zone's entry, then [BOTH]. */
        internal fun resolveFrom(obj: JSONObject?, zoneId: String?): Resolved<SellwildAdStack> {
            val global = global(obj)
            global.value?.let { return Resolved(it, global.issues) }
            val zones = byZone(obj)
            return Resolved(zoneId?.let { zones.value[it] } ?: BOTH, global.issues + zones.issues)
        }

        /** The parsed global `AD_STACK`; null when unset (absent, JSON null, '') or unknown. */
        internal fun global(obj: JSONObject?): Resolved<SellwildAdStack?> {
            val text = textOrNull(RemoteValues.optAny(obj, "AD_STACK")) ?: return Resolved(null)
            val stack = parse(text) ?: return Resolved(null, listOf(invalid("AD_STACK is not a known mode: $text")))
            return Resolved(stack)
        }

        /**
         * The parsed `AD_STACK_BY_ZONE` map, unknown modes dropped. '' (the CMS's unset
         * value) is an empty map; any other value that is not a map is dropped whole.
         */
        internal fun byZone(obj: JSONObject?): Resolved<Map<String, SellwildAdStack>> {
            val raw = RemoteValues.optAny(obj, "AD_STACK_BY_ZONE") ?: return Resolved(emptyMap())
            if (raw !is JSONObject) {
                if (raw == "") return Resolved(emptyMap())
                return Resolved(emptyMap(), listOf(invalid("AD_STACK_BY_ZONE is not a map")))
            }
            val issues = mutableListOf<Issue>()
            val zones = linkedMapOf<String, SellwildAdStack>()
            for (zone in raw.keys()) {
                val text = textOrNull(RemoteValues.optAny(raw, zone)) ?: continue
                val stack = parse(text)
                if (stack == null) {
                    issues += invalid("AD_STACK_BY_ZONE entry is not a known mode: $text", zone)
                } else {
                    zones[zone] = stack
                }
            }
            return Resolved(zones, issues)
        }

        // What optString reads (numbers and objects as their text); '' means unset.
        private fun textOrNull(v: Any?): String? {
            if (v == null) return null
            val text = v.toString()
            return if (text.isEmpty()) null else text
        }

        private fun invalid(message: String, zoneId: String? = null) = Issue(
            SellwildFailureCode.CONFIG_ADSTACK_INVALID,
            SellwildFailureComponent.REMOTE_CONFIG,
            SellwildFailureSeverity.WARN,
            message = message,
            zoneId = zoneId,
        )
    }
}
