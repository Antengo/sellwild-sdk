// SellwildID5.kt — ID5 Universal ID (identity) on Android, auto-resolved.
//
// ID5 mints a Universal ID from first-party / probabilistic signals with just a
// partner id — NO user login/email — so unlike UID2/LiveRamp the SDK can resolve
// it automatically (like GrowthCode). Once per launch (subject to a persisted
// throttle), the SDK fetches an ID5 id and merges it into every Prebid auction via
// [SellwildEidRegistry.setId5] (source id5-sync.com, coexists with GrowthCode and
// partner-supplied eids).
//
// Toggled from remote config, OFF by default:
//   - Global:   ID5_ENABLED          (bool / "1" / "true")
//   - Per-zone: ID5_ENABLED_BY_ZONE  ({ "<zoneId>": true })
// Params (partner id, endpoint, TTL) resolve from remote `ID5_*`, else defaults.
//
// GAID access is by REFLECTION (no play-services-ads-identifier dependency added),
// same rationale as GrowthCode; ID5 works without it.
//
// ‼️ VERIFY BEFORE ENABLING (off by default until then):
//   1. Partner id — set ID5_PARTNER_ID in the CMS to the real ID5 partner number.
//   2. Fetch contract — request/response below follow ID5's public Fetch API
//      (GET g/v2/{partner}.json -> { universal_uid, signature, link_type }).
//      Confirm against ID5's CURRENT mobile spec (ID5 may require the /gm/v3 POST
//      with the previously-stored signature for id continuity + gdpr params).
//   3. atype — confirm the OpenRTB agent type ID5 expects (1 used below).
//
// Mirrors `SellwildID5.swift`. Touches NO Prebid fork API (feeds SellwildEid path).

package com.sellwild.sdk

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

object SellwildID5 {

    private const val DEFAULT_ENDPOINT = "https://id5-sync.com/g/v2"
    private const val DEFAULT_TTL_HOURS = 24.0
    private const val EID_SOURCE = "id5-sync.com"
    private const val NULL_MAID = "00000000-0000-0000-0000-000000000000"

    data class Settings(
        val enabled: Boolean,
        val partnerId: String?,
        val endpoint: String,
        val ttlHours: Double,
    )

    private val lock = Any()
    @Volatile private var didAttempt = false

    /** Resolve ID5 settings from remote config; per-zone map honoured when the
     *  global flag is falsy (same shape as GrowthCode / video). */
    fun resolve(config: SellwildConfig, zoneId: String?): Settings {
        val obj = config.remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() }

        val enabled: Boolean = when {
            truthy(obj?.optAny("ID5_ENABLED")) -> true
            zoneId != null -> {
                val byZone = obj?.optJSONObject("ID5_ENABLED_BY_ZONE")
                if (byZone != null && byZone.has(zoneId) && !byZone.isNull(zoneId)) truthy(byZone.get(zoneId))
                else false
            }
            else -> false
        }

        return Settings(
            enabled = enabled,
            partnerId = nonEmpty(obj?.optString("ID5_PARTNER_ID")),
            endpoint = nonEmpty(obj?.optString("ID5_ENDPOINT")) ?: DEFAULT_ENDPOINT,
            ttlHours = numeric(obj?.optAny("ID5_TTL_HOURS")) ?: DEFAULT_TTL_HOURS,
        )
    }

    /** Entry point — call from an ad load. Idempotent per launch, runs off-main.
     *  Replays the cached id immediately, then (throttled) refreshes it. No-op
     *  unless enabled with a partner id. */
    fun resolveIfNeeded(context: Context, config: SellwildConfig, zoneId: String?) {
        val settings = resolve(config, zoneId)
        val pid = settings.partnerId
        if (!settings.enabled || pid.isNullOrEmpty()) return

        synchronized(lock) {
            if (didAttempt) return
            didAttempt = true
        }

        val appContext = context.applicationContext
        Thread {
            runCatching { work(appContext, settings, pid) }
        }.apply { isDaemon = true }.start()
    }

    private fun work(context: Context, settings: Settings, pid: String) {
        val prefs = prefs(context)

        // 1. Replay cached id so the auction has ID5 signal inside the throttle window.
        nonEmpty(prefs.getString(uidKey(pid), null))?.let { cached ->
            SellwildEidRegistry.setId5(listOf(eid(cached, prefs.getInt(linkTypeKey(pid), 0))))
        }

        // 2. Throttle the (billed) fetch.
        val uid = nonEmpty(prefs.getString(uidKey(pid), null))
        val lastSync = prefs.getLong(syncedAtKey(pid), -1L).takeIf { it >= 0 }
        if (!shouldSync(uid, lastSync, settings.ttlHours)) return

        performFetch(context, prefs, settings, pid)
    }

    fun shouldSync(uid: String?, lastSyncMs: Long?, ttlHours: Double): Boolean {
        if (uid == null) return true
        if (lastSyncMs == null) return true
        return System.currentTimeMillis() - lastSyncMs >= ttlHours * 3_600_000
    }

    // ── Network ──────────────────────────────────────────────────────────────
    // ‼️ ID5 public Fetch API shape — VERIFY against ID5's current mobile spec
    // (see header) before enabling. Off by default until then.
    private fun performFetch(context: Context, prefs: SharedPreferences, settings: Settings, pid: String) {
        val params = mutableListOf("gdpr=0")
        nonEmpty(prefs.getString(sigKey(pid), null))?.let { params.add("s=${enc(it)}") }
        advertisingId(context)?.let { params.add("ifa=${enc(it.first)}") }
        val url = "${settings.endpoint}/${enc(pid)}.json?${params.joinToString("&")}"

        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 10_000
        conn.readTimeout = 15_000

        val code = conn.responseCode
        if (code !in 200..299) return
        val body = conn.inputStream.bufferedReader().readText()
        val json = runCatching { JSONObject(body) }.getOrNull() ?: return

        val edit = prefs.edit()
        edit.putLong(syncedAtKey(pid), System.currentTimeMillis())

        val uid = nonEmpty(json.optString("universal_uid"))
        if (uid == null) { edit.apply(); return }
        edit.putString(uidKey(pid), uid)
        nonEmpty(json.optString("signature"))?.let { edit.putString(sigKey(pid), it) }
        val linkType = (numeric(json.optAny("link_type")) ?: 0.0).toInt()
        edit.putInt(linkTypeKey(pid), linkType)
        edit.apply()

        SellwildEidRegistry.setId5(listOf(eid(uid, linkType)))
    }

    /** OpenRTB eid for an ID5 id. atype 1 (cookie/first-party); ID5 link_type
     *  (0/1/2 = anon/probabilistic/deterministic) rides in ext. */
    private fun eid(uid: String, linkType: Int): SellwildEid =
        SellwildEid(EID_SOURCE, listOf(SellwildEidUid(uid, 1, mapOf("linkType" to linkType))))

    // ── Advertising id (reflection — no Play Services dependency) ─────────────

    private fun advertisingId(context: Context): Pair<String, String>? {
        return runCatching {
            val clazz = Class.forName("com.google.android.gms.ads.identifier.AdvertisingIdClient")
            val info = clazz.getMethod("getAdvertisingIdInfo", Context::class.java).invoke(null, context)
                ?: return null
            val infoClass = info.javaClass
            val id = infoClass.getMethod("getId").invoke(info) as? String
            val limited = infoClass.getMethod("isLimitAdTrackingEnabled").invoke(info) as? Boolean ?: false
            if (id.isNullOrEmpty() || limited || id == NULL_MAID) null else Pair(id, "GAID")
        }.getOrNull()
    }

    // ── Persistence (SharedPreferences, per partner id) ───────────────────────

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("sellwild_sdk", Context.MODE_PRIVATE)

    private fun uidKey(pid: String) = "_sw_id5_uid.$pid"
    private fun sigKey(pid: String) = "_sw_id5_sig.$pid"
    private fun linkTypeKey(pid: String) = "_sw_id5_lt.$pid"
    private fun syncedAtKey(pid: String) = "_sw_id5_synced_at.$pid"

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

    internal fun resetForTesting() {
        synchronized(lock) { didAttempt = false }
    }
}
