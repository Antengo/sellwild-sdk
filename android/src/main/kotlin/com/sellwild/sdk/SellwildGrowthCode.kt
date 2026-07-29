// SellwildGrowthCode.kt — GrowthCode Signal Resolve (identity) on Android.
//
// GrowthCode is an identity provider. Once per session (subject to a persisted
// throttle), the SDK POSTs a "sync" to GrowthCode carrying a stored GCID and
// — when a Google Advertising ID (GAID) is available — the device id. GrowthCode
// returns a GCID we persist and an EID blob we merge into every Prebid auction
// via [SellwildEidRegistry] (partner-set eids win on conflict).
//
// Toggled from remote config, OFF by default, so it ships dormant and turns
// on/off from the CMS with no app release:
//   - Global:   GROWTHCODE_ENABLED          (bool / "1" / "true")
//   - Per-zone: GROWTHCODE_ENABLED_BY_ZONE  ({ "<zoneId>": true })
// Keys / params (partner id, endpoint, sync url, MAID policy, TTL) resolve
// local `config.growthCode.*` → remote `GROWTHCODE_*` → default, mirroring the
// S2S-config resolution precedence.
//
// GAID access is by REFLECTION, with no play-services-ads-identifier dependency
// added. Rationale: if the host app doesn't already bundle Play Services'
// ad-identifier, it isn't managing ad-tracking permissions / regulatory surface
// itself — so we don't pull that surface into every partner's app. When the
// client isn't present we simply have no GAID (call runs without a MAID, or is
// skipped when GROWTHCODE_SEND_MAID is off).
//
// Mirrors `core/src/growthcode.ts` and `SellwildGrowthCode.swift`. Touches NO
// Prebid fork API (feeds the already-shipping SellwildEid path).

package com.sellwild.sdk

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

object SellwildGrowthCode {

    private const val DEFAULT_ENDPOINT = "https://ids.api.gcprivacy.id/v4/sync/api"
    private const val DEFAULT_TTL_HOURS = 48.0
    private const val NULL_MAID = "00000000-0000-0000-0000-000000000000"

    data class Settings(
        val enabled: Boolean,
        val partnerId: String?,
        val endpoint: String,
        val syncUrl: String?,
        val sendMaid: Boolean,
        val ttlHours: Double,
    )

    // Session guard — the sync runs at most once per process launch. load() is
    // called per ad view, so without this every placement would re-trigger.
    private val lock = Any()
    @Volatile private var didAttempt = false

    /**
     * Resolve GrowthCode settings: local `config.growthCode.*` wins, else the
     * raw remote `GROWTHCODE_*` value, else a default. `enabled` also honours the
     * per-zone map when the global remote flag is falsy (video/native shape).
     */
    fun resolve(config: SellwildConfig, zoneId: String?): Settings {
        val local = config.growthCode
        val obj = config.remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() }

        val enabled: Boolean = when {
            local?.enabled != null -> local.enabled
            truthy(obj?.optAny("GROWTHCODE_ENABLED")) -> true
            zoneId != null -> {
                val byZone = obj?.optJSONObject("GROWTHCODE_ENABLED_BY_ZONE")
                if (byZone != null && byZone.has(zoneId) && !byZone.isNull(zoneId)) truthy(byZone.get(zoneId))
                else false
            }
            else -> false
        }

        val sendMaid: Boolean = when {
            local?.sendMaid != null -> local.sendMaid
            obj?.optAny("GROWTHCODE_SEND_MAID") != null -> truthy(obj.optAny("GROWTHCODE_SEND_MAID"))
            else -> true
        }

        return Settings(
            enabled = enabled,
            partnerId = local?.partnerId ?: nonEmpty(obj?.optString("GROWTHCODE_PARTNER_ID")),
            endpoint = local?.endpoint ?: nonEmpty(obj?.optString("GROWTHCODE_ENDPOINT")) ?: DEFAULT_ENDPOINT,
            syncUrl = local?.syncUrl ?: nonEmpty(obj?.optString("GROWTHCODE_SYNC_URL")),
            sendMaid = sendMaid,
            ttlHours = local?.ttlHours?.toDouble() ?: numeric(obj?.optAny("GROWTHCODE_TTL_HOURS")) ?: DEFAULT_TTL_HOURS,
        )
    }

    /**
     * Entry point — call from an ad load. Idempotent per launch. Runs off the
     * main thread: injects any cached eids immediately, then (subject to the
     * throttle) refreshes them from GrowthCode. No-op unless enabled with a
     * partner id and sync url.
     */
    fun resolveIfNeeded(context: Context, config: SellwildConfig, zoneId: String?) {
        val settings = resolve(config, zoneId)
        val pid = settings.partnerId
        val syncUrl = settings.syncUrl
        if (!settings.enabled || pid.isNullOrEmpty() || syncUrl.isNullOrEmpty()) return

        synchronized(lock) {
            if (didAttempt) return
            didAttempt = true
        }

        val appContext = context.applicationContext
        Thread {
            runCatching { work(appContext, settings, pid, syncUrl) }
        }.apply { isDaemon = true }.start()
    }

    private fun work(context: Context, settings: Settings, pid: String, syncUrl: String) {
        val prefs = prefs(context)

        // 1. Replay cached eids so the auction has GrowthCode signal even inside
        //    the throttle window (we only PAY for the call every ttlHours).
        nonEmpty(prefs.getString(ebKey(pid), null))?.let { cached ->
            val eids = parseEidBlob(cached)
            if (eids.isNotEmpty()) SellwildEidRegistry.setGrowthCode(eids)
        }

        // 2. Decide whether to make the (billed) network call.
        val gcid = nonEmpty(prefs.getString(gcidKey(pid), null))
        val lastSync = prefs.getLong(syncedAtKey(pid), -1L).takeIf { it >= 0 }
        if (!shouldSync(gcid, lastSync, settings.ttlHours)) return

        // 3. Advertising id, honouring the MAID policy. A null id means no usable
        //    GAID; when sending is off, skip the whole call for such devices.
        val maid = advertisingId(context)
        if (maid == null && !settings.sendMaid) return

        performSync(prefs, settings, pid, syncUrl, gcid, maid)
    }

    /** Sync only when there's no stored GCID or the TTL window has elapsed. */
    fun shouldSync(gcid: String?, lastSyncMs: Long?, ttlHours: Double): Boolean {
        if (gcid == null) return true
        if (lastSyncMs == null) return true
        return System.currentTimeMillis() - lastSyncMs >= ttlHours * 3_600_000
    }

    // ── Network ──────────────────────────────────────────────────────────────

    private fun performSync(
        prefs: SharedPreferences,
        settings: Settings,
        pid: String,
        syncUrl: String,
        gcid: String?,
        maid: Pair<String, String>?,
    ) {
        val sep = if (settings.endpoint.contains("?")) "&" else "?"
        val url = "${settings.endpoint}${sep}pid=${enc(pid)}&u=${enc(syncUrl)}"

        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        conn.connectTimeout = 10_000
        conn.readTimeout = 15_000
        conn.doOutput = true
        OutputStreamWriter(conn.outputStream).use { it.write(formBody(gcid, syncHost(syncUrl), maid)) }

        val code = conn.responseCode
        if (code !in 200..299) return
        val body = conn.inputStream.bufferedReader().readText()
        val json = runCatching { JSONObject(body) }.getOrNull() ?: return

        // Persist the throttle timestamp regardless, so a fill-less response
        // still holds off the next billed call for the TTL window.
        val edit = prefs.edit()
        edit.putLong(syncedAtKey(pid), System.currentTimeMillis())
        nonEmpty(json.optString("gc_id"))?.let { edit.putString(gcidKey(pid), it) }
        val eb = nonEmpty(json.optString("eb"))
        if (eb != null) edit.putString(ebKey(pid), eb)
        edit.apply()

        if (eb != null) {
            val eids = parseEidBlob(eb)
            if (eids.isNotEmpty()) SellwildEidRegistry.setGrowthCode(eids)
        }
    }

    /** Form body: gcid (omitted on first sync), h (host), maid + maid_type
     *  (only when a real device id is available). */
    private fun formBody(gcid: String?, host: String?, maid: Pair<String, String>?): String {
        val parts = mutableListOf<String>()
        fun add(k: String, v: String?) { if (!v.isNullOrEmpty()) parts.add("${enc(k)}=${enc(v)}") }
        add("gcid", gcid)
        add("h", host)
        if (maid != null) {
            add("maid", maid.first)
            add("maid_type", maid.second)
        }
        return parts.joinToString("&")
    }

    // ── Advertising id (reflection — no Play Services dependency) ─────────────

    /**
     * The device GAID via reflection when Play Services' AdvertisingIdClient is
     * present AND limit-ad-tracking is off, else null. No dependency is added:
     * if the client class isn't on the host app's classpath, we return null and
     * the sync runs without a MAID.
     */
    private fun advertisingId(context: Context): Pair<String, String>? {
        return runCatching {
            val clazz = Class.forName("com.google.android.gms.ads.identifier.AdvertisingIdClient")
            val info = clazz.getMethod("getAdvertisingIdInfo", Context::class.java).invoke(null, context)
                ?: return null
            val infoClass = info.javaClass
            val id = infoClass.getMethod("getId").invoke(info) as? String
            val limited = infoClass.getMethod("isLimitAdTrackingEnabled").invoke(info) as? Boolean ?: false
            if (id.isNullOrEmpty() || limited || id == NULL_MAID) null
            else Pair(id, "GAID")
        }.getOrNull()
    }

    // ── Parsing ───────────────────────────────────────────────────────────────

    /**
     * Parse the GrowthCode `eb` (a JSON string of
     * `[{ source, uids: [{ id, atype?, stype? }] }]`) into [SellwildEid]s.
     * Provider-only `inserter`/`matcher` are dropped; a uid `stype` (with no
     * atype) is preserved in `ext`. Never throws — returns [] on bad input.
     */
    fun parseEidBlob(eb: String): List<SellwildEid> {
        val arr = runCatching { JSONArray(eb) }.getOrNull() ?: return emptyList()
        val eids = mutableListOf<SellwildEid>()
        for (i in 0 until arr.length()) {
            val entry = arr.optJSONObject(i) ?: continue
            val source = nonEmpty(entry.optString("source")) ?: continue
            val rawUids = entry.optJSONArray("uids") ?: continue
            val uids = mutableListOf<SellwildEidUid>()
            for (j in 0 until rawUids.length()) {
                val u = rawUids.optJSONObject(j) ?: continue
                val id = nonEmpty(u.optString("id")) ?: continue
                val atype = (numeric(u.optAny("atype")) ?: 0.0).toInt()
                val stype = nonEmpty(u.optString("stype"))
                uids.add(
                    if (stype != null) SellwildEidUid(id, atype, mapOf("stype" to stype))
                    else SellwildEidUid(id, atype)
                )
            }
            if (uids.isNotEmpty()) eids.add(SellwildEid(source, uids))
        }
        return eids
    }

    // ── Persistence (SharedPreferences, per partner id) ───────────────────────

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("sellwild_sdk", Context.MODE_PRIVATE)

    private fun gcidKey(pid: String) = "_sw_gc_id.$pid"
    private fun syncedAtKey(pid: String) = "_sw_gc_synced_at.$pid"
    private fun ebKey(pid: String) = "_sw_gc_eb.$pid"

    /** The host param `h` — the sync url's host, or the raw value if not a URL. */
    private fun syncHost(syncUrl: String): String =
        runCatching { URL(syncUrl).host }.getOrNull()?.takeIf { it.isNotEmpty() } ?: syncUrl

    // ── Coercion helpers ──────────────────────────────────────────────────────

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")

    private fun truthy(v: Any?): Boolean = when (v) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v.lowercase() in setOf("1", "true", "yes", "on")
        else -> false
    }

    private fun numeric(v: Any?): Double? = when (v) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }

    private fun nonEmpty(s: String?): String? = if (s.isNullOrEmpty()) null else s

    private fun JSONObject.optAny(key: String): Any? =
        if (has(key) && !isNull(key)) get(key) else null

    // Test seam — reset the once-per-launch latch.
    internal fun resetForTesting() {
        synchronized(lock) { didAttempt = false }
    }
}
