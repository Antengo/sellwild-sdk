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
import com.sellwild.sdk.core.Fetch
import com.sellwild.sdk.core.GrowthCodeSync
import com.sellwild.sdk.core.RemoteValues
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

object SellwildGrowthCode {

    private const val DEFAULT_ENDPOINT = "https://ids.api.gcprivacy.id/v4/sync/api"
    private const val DEFAULT_TTL_HOURS = 48.0
    private const val ADVERTISING_ID_CLIENT = "com.google.android.gms.ads.identifier.AdvertisingIdClient"

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

    // growthcode.config.missing is reported once per launch too: every ad view load sees the
    // same config. A separate latch, so a later complete config still syncs.
    @Volatile private var didReportMissing = false

    private val daemonThread: (Runnable) -> Unit = { Thread(it).apply { isDaemon = true }.start() }
    private val systemClock: () -> Long = { System.currentTimeMillis() }
    private val playServicesId: (Context) -> Pair<String, String>? = { advertisingId(it) }

    /** Runs the sync off the main thread. Tests run it inline. */
    @Volatile
    internal var runner: (Runnable) -> Unit = daemonThread

    /** Epoch milliseconds for the throttle. Tests replace it. */
    @Volatile
    internal var clock: () -> Long = systemClock

    /** The device advertising id, by reflection. Tests replace it. */
    @Volatile
    internal var advertisingIdSource: (Context) -> Pair<String, String>? = playServicesId

    /**
     * Resolve GrowthCode settings: local `config.growthCode.*` wins, else the
     * raw remote `GROWTHCODE_*` value, else a default. `enabled` also honours the
     * per-zone map when the global remote flag is falsy (video/native shape).
     */
    fun resolve(config: SellwildConfig, zoneId: String?): Settings {
        val local = config.growthCode
        val obj = remoteObject(config.remoteJson)

        val enabled: Boolean = when {
            local?.enabled != null -> local.enabled
            RemoteValues.isOn(RemoteValues.optAny(obj, "GROWTHCODE_ENABLED")) -> true
            else -> RemoteValues.isOn(RemoteValues.byZone(obj, "GROWTHCODE_ENABLED_BY_ZONE", zoneId))
        }

        val remoteSendMaid = RemoteValues.optAny(obj, "GROWTHCODE_SEND_MAID")
        val sendMaid: Boolean = when {
            local?.sendMaid != null -> local.sendMaid
            remoteSendMaid != null -> RemoteValues.isOn(remoteSendMaid)
            else -> true
        }

        return Settings(
            enabled = enabled,
            partnerId = local?.partnerId ?: nonEmpty(RemoteValues.optText(obj, "GROWTHCODE_PARTNER_ID")),
            endpoint = local?.endpoint ?: nonEmpty(RemoteValues.optText(obj, "GROWTHCODE_ENDPOINT")) ?: DEFAULT_ENDPOINT,
            syncUrl = local?.syncUrl ?: nonEmpty(RemoteValues.optText(obj, "GROWTHCODE_SYNC_URL")),
            sendMaid = sendMaid,
            ttlHours = local?.ttlHours?.toDouble()
                ?: RemoteValues.number(RemoteValues.optAny(obj, "GROWTHCODE_TTL_HOURS"))
                ?: DEFAULT_TTL_HOURS,
        )
    }

    /**
     * Entry point — call from an ad load. Idempotent per launch. Runs off the
     * main thread: injects any cached eids immediately, then (subject to the
     * throttle) refreshes them from GrowthCode. No-op unless enabled; enabled
     * without a partner id or sync url is reported once per launch
     * (growthcode.config.missing). A sync that fails is reported once (growthcode.*).
     */
    fun resolveIfNeeded(context: Context, config: SellwildConfig, zoneId: String?) {
        config.claimFailurePartner()
        val settings = resolve(config, zoneId)
        if (!settings.enabled) return
        val pid = settings.partnerId
        val syncUrl = settings.syncUrl
        if (pid.isNullOrEmpty() || syncUrl.isNullOrEmpty()) {
            synchronized(lock) {
                if (didReportMissing) return
                didReportMissing = true
            }
            SellwildFailures.log(
                code = SellwildFailureCode.GROWTHCODE_CONFIG_MISSING,
                component = SellwildFailureComponent.GROWTHCODE,
                severity = SellwildFailureSeverity.WARN,
                message = if (pid.isNullOrEmpty()) "no partner id" else "no sync url",
                zoneId = zoneId,
            )
            return
        }

        synchronized(lock) {
            if (didAttempt) return
            didAttempt = true
        }

        val appContext = context.applicationContext
        runner(
            Runnable {
                runCatching { work(appContext, settings, pid, syncUrl) }.onFailure { e ->
                    SellwildFailures.log(
                        code = Fetch.codeFor(e, Fetch.GROWTHCODE),
                        component = SellwildFailureComponent.GROWTHCODE,
                        severity = SellwildFailureSeverity.WARN,
                        error = e,
                        url = settings.endpoint,
                    )
                }
            },
        )
    }

    private fun work(context: Context, settings: Settings, pid: String, syncUrl: String) {
        val prefs = prefs(context)

        // 1. Replay cached eids so the auction has GrowthCode signal even inside
        //    the throttle window (we only PAY for the call every ttlHours).
        val cachedEb = nonEmpty(prefs.getString(ebKey(pid), null))
        cachedEb?.let { cached ->
            val eids = parseEidBlob(cached)
            if (eids.isNotEmpty()) SellwildEidRegistry.setGrowthCode(eids)
        }

        // 2. Decide whether to make the (billed) network call.
        val gcid = nonEmpty(prefs.getString(gcidKey(pid), null))
        val lastSync = prefs.getLong(syncedAtKey(pid), -1L).takeIf { it >= 0 }
        if (!GrowthCodeSync.shouldSync(gcid, lastSync, settings.ttlHours, clock())) return

        // 3. Advertising id, honouring the MAID policy. A null id means no usable
        //    GAID; when sending is off, skip the whole call for such devices.
        val maid = advertisingIdSource(context)
        if (maid == null && !settings.sendMaid) return

        performSync(prefs, settings, pid, syncUrl, gcid, maid, cachedEb)
    }

    /** Sync only when there's no stored GCID or the TTL window has elapsed. */
    fun shouldSync(gcid: String?, lastSyncMs: Long?, ttlHours: Double): Boolean =
        GrowthCodeSync.shouldSync(gcid, lastSyncMs, ttlHours, clock())

    // ── Network ──────────────────────────────────────────────────────────────

    // A thrown request (network, timeout) reaches resolveIfNeeded's catch, which reports it.
    private fun performSync(
        prefs: SharedPreferences,
        settings: Settings,
        pid: String,
        syncUrl: String,
        gcid: String?,
        maid: Pair<String, String>?,
        cachedEb: String?,
    ) {
        val url = GrowthCodeSync.requestUrl(settings.endpoint, pid, syncUrl)
        val target = Fetch.httpUrl(url).getOrElse { e ->
            log(SellwildFailureCode.GROWTHCODE_URL_INVALID, error = e)
            return
        }

        val conn = target.openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        conn.connectTimeout = 10_000
        conn.readTimeout = 15_000
        conn.doOutput = true
        OutputStreamWriter(conn.outputStream).use {
            it.write(GrowthCodeSync.formBody(gcid, GrowthCodeSync.syncHost(syncUrl), maid))
        }

        val code = conn.responseCode
        if (code !in 200..299) {
            // The throttle is not saved, so the (billed) call retries next launch.
            log(SellwildFailureCode.GROWTHCODE_SYNC_HTTP, message = "HTTP $code", httpStatus = code, url = url)
            return
        }
        val body = conn.inputStream.use { String(it.readBytes(), Charsets.UTF_8) }
        val response = runCatching { GrowthCodeSync.parseResponse(body) }.getOrElse { e ->
            log(SellwildFailureCode.GROWTHCODE_SYNC_PARSE, error = e, url = url)
            return
        }

        // Persist the throttle timestamp regardless, so a fill-less response
        // still holds off the next billed call for the TTL window.
        val edit = prefs.edit()
        edit.putLong(syncedAtKey(pid), clock())
        response.gcId?.let { edit.putString(gcidKey(pid), it) }
        response.eb?.let { edit.putString(ebKey(pid), it) }
        edit.apply()

        // An eb equal to the cached one was parsed, fed and reported in step 1 of this run.
        response.eb?.takeIf { it != cachedEb }?.let { eb ->
            val eids = parseEidBlob(eb)
            if (eids.isNotEmpty()) SellwildEidRegistry.setGrowthCode(eids)
        }
    }

    private fun log(code: String, error: Throwable? = null, message: String? = null, httpStatus: Int? = null, url: String? = null) =
        SellwildFailures.log(
            code = code,
            component = SellwildFailureComponent.GROWTHCODE,
            severity = SellwildFailureSeverity.WARN,
            error = error,
            message = message,
            httpStatus = httpStatus,
            url = url,
        )

    // ── Advertising id (reflection — no Play Services dependency) ─────────────

    /**
     * The device GAID via reflection when Play Services' AdvertisingIdClient is
     * present AND limit-ad-tracking is off, else null. No dependency is added:
     * if the client class isn't on the host app's classpath, we return null and
     * the sync runs without a MAID.
     */
    internal fun advertisingId(context: Context, clientClass: String = ADVERTISING_ID_CLIENT): Pair<String, String>? {
        // Null is an expected outcome, not a failure: no Play Services, no binding, or a
        // user's privacy choice. Device-id state is never reported (FAILURES.md 4.2 privacy).
        return runCatching {
            val clazz = Class.forName(clientClass)
            val info = clazz.getMethod("getAdvertisingIdInfo", Context::class.java).invoke(null, context)
                ?: return null
            val infoClass = info.javaClass
            val id = infoClass.getMethod("getId").invoke(info) as? String
            val limited = infoClass.getMethod("isLimitAdTrackingEnabled").invoke(info) as? Boolean ?: false
            GrowthCodeSync.maid(id, limited)
        }.getOrNull()
    }

    // ── Parsing ───────────────────────────────────────────────────────────────

    /**
     * Parse the GrowthCode `eb` (a JSON string of
     * `[{ source, uids: [{ id, atype?, stype? }] }]`) into [SellwildEid]s.
     * Provider-only `inserter`/`matcher` are dropped; a uid `stype` (with no
     * atype) is preserved in `ext`. Never throws — returns [] on bad input, which
     * is reported (growthcode.eid.parse, growthcode.eid.invalid).
     */
    fun parseEidBlob(eb: String): List<SellwildEid> = GrowthCodeSync.parseEidBlob(eb).reported()

    // ── Persistence (SharedPreferences, per partner id) ───────────────────────

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("sellwild_sdk", Context.MODE_PRIVATE)

    private fun gcidKey(pid: String) = "_sw_gc_id.$pid"
    private fun syncedAtKey(pid: String) = "_sw_gc_synced_at.$pid"
    private fun ebKey(pid: String) = "_sw_gc_eb.$pid"

    private fun nonEmpty(s: String?): String? = if (s.isNullOrEmpty()) null else s

    // Test seam — reset the once-per-launch latches and the injected clock, id and runner.
    internal fun resetForTesting() {
        synchronized(lock) {
            didAttempt = false
            didReportMissing = false
        }
        runner = daemonThread
        clock = systemClock
        advertisingIdSource = playServicesId
    }
}
