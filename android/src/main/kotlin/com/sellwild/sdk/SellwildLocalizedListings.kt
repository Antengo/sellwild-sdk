// SellwildLocalizedListings.kt — geo-based secondary-listings on Android.
//
// When enabled, the feed loads a SECOND listings cache keyed by the user's
// state and disperses those listings into the primary feed at a configured
// frequency (every Nth slot). This file is the single verify point for the
// native Android logic: config resolution, state resolution, URL templating,
// and the every-Nth de-duped merge. It performs no I/O — [SellwildFeedView]
// drives the fetch through [SellwildAPIClient.fetchCacheListings].
//
// State resolution order (highest first):
//   1. integration.forceState  (remote/CMS force — a known-Alabama site, etc.)
//   2. geo state ([SellwildGeoStore.current].state — seeded from partner geo or
//      the CloudFront viewer-country-region header off the primary fetch)
//   3. none → skip the localized cache entirely
//
// The cache payload is identical to the primary feed (`result.rs` of listings),
// so [SellwildAPIClient] reuses `parseListingsResponse`; a non-200 (e.g. a 404
// for a state with no data) is a normal skip.
//
// Mirrors `core/src/localized-listings.ts` and `SellwildLocalizedListings.swift`.
// Touches NO Prebid fork API.

package com.sellwild.sdk

import org.json.JSONObject

object SellwildLocalizedListings {

    /** A fully-resolved localized-listings integration (config validated). */
    data class Integration(
        /** Optional label for the source, e.g. "sportserver". */
        val source: String?,
        /** Cache base URL (required). */
        val baseUrl: String,
        /** Filename template with a `{state}` token (required). */
        val urlTemplate: String,
        /** Dispersion percent (25 → every 4th slot). */
        val frequency: Int,
        /** Forced state (2-letter upper), or null. */
        val forceState: String?,
    )

    /**
     * Resolve the active integration: local `config.localizedListings` wins
     * entirely, else the raw remote `LOCALIZED_LISTINGS` value (which may be a
     * JSONObject or a JSON String). Returns null when disabled (explicit
     * `enabled == false`) or missing a baseUrl / urlTemplate.
     */
    fun resolve(config: SellwildConfig): Integration? {
        config.localizedListings?.let { local ->
            if (local.enabled == false) return null // explicit off; absent = on
            return make(local.source, local.baseUrl, local.urlTemplate, local.frequency, local.forceState)
        }

        val raw = safeParseObject(remoteValue(config)) ?: return null
        val enabled = raw.optAny("enabled")
        if (enabled is Boolean && !enabled) return null
        return make(
            source = nonEmpty(raw.optString("source")),
            baseUrl = nonEmpty(raw.optString("baseUrl")),
            urlTemplate = nonEmpty(raw.optString("urlTemplate")),
            frequency = numeric(raw.optAny("frequency"))?.toInt(),
            forceState = nonEmpty(raw.optString("forceState")),
        )
    }

    private fun make(
        source: String?,
        baseUrl: String?,
        urlTemplate: String?,
        frequency: Int?,
        forceState: String?,
    ): Integration? {
        val base = nonEmpty(baseUrl) ?: return null
        val tmpl = nonEmpty(urlTemplate) ?: return null
        return Integration(nonEmpty(source), base, tmpl, frequency ?: 0, normState(forceState))
    }

    /** Forced state wins, then the resolved geo state, else null. */
    fun resolveState(integration: Integration, geoState: String?): String? =
        integration.forceState ?: normState(geoState)

    /**
     * Normalize to a 2-letter uppercase state/region code, or null. A CloudFront
     * viewer-country-region can be "GA" or a longer subdivision; take the
     * trailing 2-letter token when present, else the raw upper value.
     */
    fun normState(value: String?): String? {
        val trimmed = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val code = trimmed.uppercase()
        if (Regex("^[A-Z]{2}$").matches(code)) return code
        return Regex("[A-Z]{2}$").find(code)?.value ?: code
    }

    /**
     * Build the cache URL by filling `{state}` (case-insensitive, lowercased)
     * into the template and joining to `baseUrl` with exactly one slash.
     */
    fun buildCacheUrl(integration: Integration, state: String): String {
        val lower = state.lowercase()
        val path = Regex("(?i)\\{state\\}").replace(integration.urlTemplate) { lower }
        val base = integration.baseUrl
        return when {
            base.endsWith("/") && path.startsWith("/") -> base + path.substring(1)
            !base.endsWith("/") && !path.startsWith("/") -> "$base/$path"
            else -> base + path
        }
    }

    /**
     * Slots between localized listings for a given percent. 25 → 4 (every 4th
     * slot). 0/absent → 0 (disabled); >= 100 → 1 (every slot).
     */
    fun everyN(frequencyPercent: Int): Int {
        if (frequencyPercent <= 0) return 0
        if (frequencyPercent >= 100) return 1
        return maxOf(1, Math.round(100.0 / frequencyPercent).toInt())
    }

    /**
     * Replace every Nth slot of [primary] with a localized listing, keeping the
     * total count unchanged. Secondary listings are first de-duped against
     * primary ids, then shuffled (random pick "from whatever was returned"),
     * then cycled so every Nth slot is filled. Returns [primary] unchanged when
     * there's nothing to disperse.
     */
    fun merge(
        primary: List<SellwildListing>,
        secondary: List<SellwildListing>,
        everyN: Int,
    ): List<SellwildListing> {
        if (everyN <= 0 || secondary.isEmpty() || primary.isEmpty()) return primary
        val primaryIds = primary.mapTo(HashSet()) { it.id }
        val pool = secondary.filter { it.id !in primaryIds }.shuffled()
        if (pool.isEmpty()) return primary

        val out = ArrayList<SellwildListing>(primary.size)
        var s = 0
        for (i in primary.indices) {
            if ((i + 1) % everyN == 0) {
                out.add(pool[s % pool.size])
                s++
            } else {
                out.add(primary[i])
            }
        }
        return out
    }

    // ── Remote parsing ────────────────────────────────────────────────────────

    private fun remoteValue(config: SellwildConfig): Any? {
        val obj = config.remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
        return obj.optAny("LOCALIZED_LISTINGS")
    }

    /** The remote value may be a JSONObject or a JSON String; coerce both. */
    private fun safeParseObject(value: Any?): JSONObject? = when (value) {
        is JSONObject -> value
        is String -> runCatching { JSONObject(value) }.getOrNull()
        else -> null
    }

    // ── Coercion helpers ────────────────────────────────────────────────────────

    private fun numeric(v: Any?): Double? = when (v) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }

    private fun nonEmpty(s: String?): String? = s?.trim()?.takeIf { it.isNotEmpty() }

    private fun JSONObject.optAny(key: String): Any? =
        if (has(key) && !isNull(key)) get(key) else null
}
