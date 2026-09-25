package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildEid
import com.sellwild.sdk.SellwildEidUid
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.net.MalformedURLException
import java.net.URL
import java.net.URLEncoder

/** Pure pieces of the GrowthCode sync (SellwildGrowthCode is the shell). */
internal object GrowthCodeSync {

    private const val NULL_MAID = "00000000-0000-0000-0000-000000000000"

    /** Sync only when there's no stored GCID or the TTL window has elapsed at [nowMs]. */
    fun shouldSync(gcid: String?, lastSyncMs: Long?, ttlHours: Double, nowMs: Long): Boolean {
        if (gcid == null) return true
        if (lastSyncMs == null) return true
        return nowMs - lastSyncMs >= ttlHours * 3_600_000
    }

    /** The sync POST URL: [endpoint] plus `pid` and `u` query params. */
    fun requestUrl(endpoint: String, pid: String, syncUrl: String): String {
        val sep = if (endpoint.contains("?")) "&" else "?"
        return "$endpoint${sep}pid=${enc(pid)}&u=${enc(syncUrl)}"
    }

    /**
     * Form body: gcid (omitted on first sync), h (host), maid + maid_type (only when a real
     * device id is available).
     */
    fun formBody(gcid: String?, host: String?, maid: Pair<String, String>?): String {
        val parts = mutableListOf<String>()
        fun add(k: String, v: String?) {
            if (!v.isNullOrEmpty()) parts.add("${enc(k)}=${enc(v)}")
        }
        add("gcid", gcid)
        add("h", host)
        if (maid != null) {
            add("maid", maid.first)
            add("maid_type", maid.second)
        }
        return parts.joinToString("&")
    }

    /** The host param `h`: the sync url's host, or the raw value if it is not a URL. */
    fun syncHost(syncUrl: String): String {
        val host = try {
            URL(syncUrl).host
        } catch (e: MalformedURLException) {
            null // A bare domain is allowed: it is sent as is.
        }
        return host?.takeIf { it.isNotEmpty() } ?: syncUrl
    }

    /**
     * A usable device advertising id, or null: none, limit-ad-tracking on, or the all-zero
     * id a device reports when the user reset or opted out.
     */
    fun maid(id: String?, limitAdTracking: Boolean): Pair<String, String>? =
        if (id.isNullOrEmpty() || limitAdTracking || id == NULL_MAID) null else Pair(id, "GAID")

    /** What a sync response carries. */
    data class Response(val gcId: String?, val eb: String?)

    /**
     * The sync response body. `gc_id` and `eb` are read as absent when missing, empty or
     * JSON null (a device's org.json reads JSON null as the text "null").
     *
     * @throws JSONException when [body] is not a JSON object.
     */
    fun parseResponse(body: String): Response {
        val json = JSONObject(body)
        return Response(gcId = ListingsParser.optTextOrNull(json, "gc_id"), eb = ListingsParser.optTextOrNull(json, "eb"))
    }

    /**
     * Parse the GrowthCode `eb` (a JSON string of `[{ source, uids: [{ id, atype?, stype? }] }]`)
     * into [SellwildEid]s. Provider-only `inserter`/`matcher` are dropped; a uid `stype`
     * (with no atype) is preserved in `ext`. Text that is not a JSON array is a
     * growthcode.eid.parse issue; entries without source or uids, and uids without id, are
     * dropped with one growthcode.eid.invalid issue. A JSON null source, id or stype is
     * absent (a device's org.json reads it as the text "null").
     */
    fun parseEidBlob(eb: String): Resolved<List<SellwildEid>> {
        val arr = try {
            JSONArray(eb)
        } catch (e: JSONException) {
            return Resolved(emptyList(), listOf(issue(SellwildFailureCode.GROWTHCODE_EID_PARSE, error = e)))
        }
        val eids = mutableListOf<SellwildEid>()
        var droppedUids = 0
        for (i in 0 until arr.length()) {
            val entry = arr.optJSONObject(i) ?: continue
            val source = nonEmpty(RemoteValues.optText(entry, "source")) ?: continue
            val rawUids = entry.optJSONArray("uids") ?: continue
            val uids = mutableListOf<SellwildEidUid>()
            for (j in 0 until rawUids.length()) {
                val uid = parseUid(rawUids.optJSONObject(j))
                if (uid == null) droppedUids++ else uids.add(uid)
            }
            if (uids.isNotEmpty()) eids.add(SellwildEid(source, uids))
        }
        val droppedEntries = arr.length() - eids.size
        if (droppedEntries == 0 && droppedUids == 0) return Resolved(eids)
        val message = "dropped $droppedEntries of ${arr.length()} entries and $droppedUids uids"
        return Resolved(eids, listOf(issue(SellwildFailureCode.GROWTHCODE_EID_INVALID, message = message)))
    }

    private fun parseUid(u: JSONObject?): SellwildEidUid? {
        if (u == null) return null
        val id = nonEmpty(RemoteValues.optText(u, "id")) ?: return null
        val atype = (RemoteValues.number(RemoteValues.optAny(u, "atype")) ?: 0.0).toInt()
        val stype = nonEmpty(RemoteValues.optText(u, "stype"))
        return if (stype != null) SellwildEidUid(id, atype, mapOf("stype" to stype)) else SellwildEidUid(id, atype)
    }

    private fun issue(code: String, message: String? = null, error: Throwable? = null) = Issue(
        code,
        SellwildFailureComponent.GROWTHCODE,
        SellwildFailureSeverity.WARN,
        message = message,
        error = error,
    )

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")

    private fun nonEmpty(s: String?): String? = s?.ifEmpty { null }
}
