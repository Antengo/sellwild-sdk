package com.sellwild.sdk

import android.content.Context
import android.content.SharedPreferences
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

// MARK: - Data Models

data class SellwildPhoto(
    val url: String,
    val thumbUrl: String,
    val background: String? = null,
)

data class SellwildUser(
    val id: String,
    val firstName: String,
    val lastName: String,
    val username: String,
    val membershipType: String,
    val trustLevel: String,
)

data class SellwildListing(
    val id: String,
    val status: String,
    val title: String,
    val text: String? = null,
    val url: String? = null,
    val categoryId: String? = null,
    val currency: String? = null,
    val price: String? = null,
    val strikePrice: String? = null,
    val hasPhoto: Boolean = false,
    val photos: List<SellwildPhoto> = emptyList(),
    val createdDate: String? = null,
    val shippable: String? = null,
    val dataSourceId: String? = null,
    val user: SellwildUser? = null,
    val distance: Double? = null,
    /** Off-platform destination ("remote_url" on the cache payload). */
    val remoteUrl: String? = null,
) {
    val displayPrice: String?
        get() {
            val value = price?.toDoubleOrNull() ?: return null
            return if (value > 0) String.format("%.0f", value) else null
        }

    val primaryPhotoUrl: String?
        get() = photos.firstOrNull()?.url

    /**
     * The URL a listing card should open when tapped. Mirrors the web widget's
     * `getListingUrl()` from `widget.sellwild.com/partner.js` so native feeds
     * route to the same destination:
     *
     * 1. [url] (optionally rewritten with `?tag={bhTag}` for Bargain Hunter)
     * 2. [remoteUrl] when `dataSourceId == "31"` (off-platform partner link)
     * 3. `https://sellwild.com/product/{id}?p={partner}&utm_source={partner}` fallback
     */
    fun tapUrl(partnerCode: String?, bhTag: String? = null): String? {
        // 1. Direct URL on the listing.
        url?.takeIf { it.isNotEmpty() }?.let { direct ->
            if (!bhTag.isNullOrEmpty()) {
                val u = android.net.Uri.parse(direct)
                val builder = u.buildUpon().clearQuery()
                u.queryParameterNames.filter { it != "tag" }.forEach { k ->
                    builder.appendQueryParameter(k, u.getQueryParameter(k))
                }
                builder.appendQueryParameter("tag", bhTag)
                return builder.build().toString()
            }
            return direct
        }
        // 2. Off-platform remote_url only when dataSourceId == "31".
        if (dataSourceId == "31" && !remoteUrl.isNullOrEmpty()) {
            return remoteUrl
        }
        // 3. Canonical Sellwild product URL.
        if (id.isEmpty()) return null
        val partner = (if (!partnerCode.isNullOrEmpty()) partnerCode else "sellwild")
        val encoded = android.net.Uri.encode(partner)
        return "https://sellwild.com/product/$id?p=$encoded&utm_source=$encoded"
    }
}

data class SellwildListingsResponse(
    val listings: List<SellwildListing>,
    val config: Map<String, Any>,
    val widgetCacheVersionId: String?,
)

// MARK: - API Client

class SellwildAPIClient(private val context: Context) {

    private val listingCache = java.util.concurrent.ConcurrentHashMap<String, SellwildListingsResponse>()

    /**
     * A feed-only app never builds an ad view or calls prewarm, so this client may be
     * the first Context the SDK sees: attach logFailure here, so failures held since
     * configure() (and this client's own) go out. Runs on the IO dispatcher because
     * attaching reads the queue uid from SharedPreferences. Idempotent, never throws.
     */
    private fun attachFailures() = SellwildFailures.attach(context)

    suspend fun fetchListings(config: SellwildConfig): Result<SellwildListingsResponse> =
        withContext(Dispatchers.IO) {
            attachFailures()
            runCatching {
                val listingsUrl = config.effectiveListingsUrl
                listingCache[listingsUrl]?.let { return@withContext Result.success(it) }

                val connection = URL(listingsUrl).openConnection() as HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 10_000
                connection.readTimeout = 15_000

                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    throw SellwildException("HTTP $responseCode from $listingsUrl")
                }

                // Seed the geo state from CloudFront's viewer-country-region
                // header when the partner hasn't supplied one, so the
                // localized-listings path can key a per-state cache. Mirrors the
                // web widget's appendViewerHeaders seeding userLocation.state.
                seedGeoFromCloudFrontIfEmpty(
                    connection.getHeaderField("CloudFront-Viewer-Country-Region"),
                    connection.getHeaderField("CloudFront-Viewer-Country"),
                )

                val body = connection.inputStream.bufferedReader().readText()
                val response = parseListingsResponse(body)
                listingCache[listingsUrl] = response
                response
            }
        }

    /**
     * GET a state-keyed secondary listings cache and reuse the primary listing
     * parser. The payload shape is identical to the primary feed (`result.rs`),
     * so the same parser applies. A non-200 (e.g. a 404 for a state with no
     * data) resolves to [Result.failure] — the caller treats that as a skip and
     * renders the primary feed unchanged.
     */
    suspend fun fetchCacheListings(url: String): Result<List<SellwildListing>> =
        withContext(Dispatchers.IO) {
            attachFailures()
            runCatching {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 10_000
                connection.readTimeout = 15_000
                connection.setRequestProperty("Accept", "application/json")

                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    throw SellwildException("HTTP $responseCode from $url")
                }

                val body = connection.inputStream.bufferedReader().readText()
                parseListingsResponse(body).listings
            }
        }

    /**
     * Seed [SellwildGeoStore] region + country from the CloudFront viewer
     * headers when not already set, then re-emit so `device.geo` reaches the
     * auction. `applyGlobalOrtb()` runs only at bootstrap + [SellwildPrebidMobile.setGeo]
     * (not per-auction), so a bare store write would never make it into a
     * request — setGeo persists AND re-emits. Never overwrites a partner-supplied
     * or previously-seeded value. Country is restricted to a North America
     * alpha-2 → alpha-3 map (oRTB wants alpha-3); anything outside NA is skipped.
     */
    private fun seedGeoFromCloudFrontIfEmpty(region: String?, countryAlpha2: String?) {
        var geo = SellwildGeoStore.current ?: SellwildGeo()
        var changed = false

        val r = region?.trim()?.takeIf { it.isNotEmpty() }
        if (geo.state.isNullOrEmpty() && r != null) {
            geo = geo.copy(state = r)
            changed = true
        }

        val alpha3 = countryAlpha2?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { SellwildGeo.northAmericaAlpha3(it) }
        if (geo.country.isNullOrEmpty() && alpha3 != null) {
            geo = geo.copy(country = alpha3)
            changed = true
        }

        if (!changed) return
        SellwildPrebidMobile.setGeo(geo)
    }

    fun clearCache() = listingCache.clear()

    private fun parseListingsResponse(json: String): SellwildListingsResponse {
        val root = JSONObject(json)
        val result = root.optJSONObject("result") ?: root
        val rs = result.optJSONArray("rs") ?: JSONArray()
        val config = result.optJSONObject("config")?.toMap() ?: emptyMap()
        val versionId = result.optString("widgetCacheVersionId").ifEmpty { null }

        val listings = (0 until rs.length()).map { i ->
            parseListing(rs.getJSONObject(i))
        }

        return SellwildListingsResponse(listings, config, versionId)
    }

    private fun parseListing(json: JSONObject): SellwildListing {
        val photosArray = json.optJSONArray("photos") ?: JSONArray()
        val photos = (0 until photosArray.length()).map { i ->
            val p = photosArray.getJSONObject(i)
            SellwildPhoto(
                url = p.optString("url"),
                thumbUrl = p.optString("thumbUrl"),
                background = p.optString("background").ifEmpty { null },
            )
        }

        val userJson = json.optJSONObject("user")
        val user = userJson?.let {
            SellwildUser(
                id = it.optString("id"),
                firstName = it.optString("firstName"),
                lastName = it.optString("lastName"),
                username = it.optString("username"),
                membershipType = it.optString("membershipType"),
                trustLevel = it.optString("trustLevel"),
            )
        }

        return SellwildListing(
            id = json.optString("id"),
            status = json.optString("status"),
            title = json.optString("title"),
            text = json.optString("text").ifEmpty { null },
            url = json.optString("url").ifEmpty { null },
            categoryId = json.optString("categoryId").ifEmpty { null },
            currency = json.optString("currency").ifEmpty { null },
            price = json.optString("price").ifEmpty { null },
            strikePrice = json.optString("strikePrice").ifEmpty { null },
            hasPhoto = json.optBoolean("has_photo"),
            photos = photos,
            createdDate = json.optString("createdDate").ifEmpty { null },
            shippable = json.optString("shippable").ifEmpty { null },
            dataSourceId = json.optString("dataSourceId").ifEmpty { null },
            user = user,
            remoteUrl = json.optTextOrNull("remote_url"),
        )
    }

    // The cache sends `"remote_url": null` on some items, and a device's org.json
    // returns the text "null" from optString for JSON null (the JVM org.json used by
    // plain unit tests returns ""), which tapUrl would then open as a URL.
    private fun JSONObject.optTextOrNull(key: String): String? =
        if (isNull(key)) null else optString(key).ifEmpty { null }

    private fun JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        keys().forEach { key -> map[key] = get(key) }
        return map
    }
}

// MARK: - Event Analytics

data class SellwildEvent(
    val event: String,
    val action: String? = null,
    val label: String? = null,
    /**
     * Free-form passthrough bag that lands in BigQuery. The queue stamps
     * `platform` + `sdkVersion` here at flush time; any caller-supplied keys are
     * preserved.
     */
    val attributes: Map<String, Any?>? = null,
    val uid: String,
    val createdTime: Long = System.currentTimeMillis(),
)

/**
 * POSTs one events batch and returns the HTTP status. Throws on a network failure.
 * [SellwildEventQueue] owns what that means (nothing is retried, nothing is logged).
 */
internal fun interface SellwildEventSender {
    fun post(url: String, body: String): Int
}

/** The production sender: one HttpURLConnection POST per batch, on a kept-alive socket. */
internal object HttpEventSender : SellwildEventSender {
    override fun post(url: String, body: String): Int {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/json")
        // Persistent connection: keep the socket alive so HttpURLConnection's
        // pool can reuse it for the next flush instead of a fresh TCP+TLS
        // handshake per batch. events.sellwild.com is fronted by an ALB whose
        // cost scales with NewConnectionCount — one connection per POST was
        // ~1 new connection per request. Reuse drops that toward ~0.
        conn.setRequestProperty("Connection", "keep-alive")
        conn.connectTimeout = 10_000
        conn.readTimeout = 15_000
        conn.doOutput = true
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        // Fully drain + close the response stream. This is what actually
        // returns the socket to the keep-alive pool — reading only
        // `responseCode` leaves the body unread and the connection is dropped
        // (no reuse). Never call disconnect(): that evicts the pooled socket
        // and defeats the whole point.
        val code = conn.responseCode
        (if (code in 200..299) conn.inputStream else conn.errorStream)
            ?.use { it.readBytes() }
        return code
    }
}

/**
 * The events POST body: a JSON array of [batch], each element with the analytics
 * attributes bag stamped ONCE. The events pipeline reads `attributes.code` for
 * partner attribution (absent ⇒ the row lands as "Invalid") and `attributes.type`
 * for the ios/android discriminator (the events view does
 * JSON_EXTRACT(attributes,'type') → the `type` column); `sdkVersion` rides along
 * for an installed-base census. Caller-supplied keys are preserved, except that
 * these three are stamped over them.
 */
internal fun buildBatchJson(batch: List<SellwildEvent>, partnerCode: String?, sdkVersion: String): String =
    JSONArray().apply {
        batch.forEach { e ->
            put(JSONObject().apply {
                put("event", e.event)
                e.action?.let { put("action", it) }
                e.label?.let { put("label", it) }
                put("uid", e.uid)
                put("createdTime", e.createdTime)
                put(
                    "attributes",
                    JSONObject().apply {
                        e.attributes?.forEach { (k, v) -> put(k, v) }
                        put("type", "android")
                        put("sdkVersion", sdkVersion)
                        partnerCode?.takeIf { it.isNotEmpty() }?.let { put("code", it) }
                    },
                )
            })
        }
    }.toString()

class SellwildEventQueue internal constructor(
    uidProvider: () -> String,
    private val sender: SellwildEventSender,
    private val clock: () -> Long,
    private val dispatcher: CoroutineDispatcher,
) {

    constructor(context: Context) : this(
        uidProvider = prefsUid(context.getSharedPreferences("sellwild_sdk", Context.MODE_PRIVATE)),
        sender = HttpEventSender,
        clock = System::currentTimeMillis,
        dispatcher = Dispatchers.IO,
    )

    private val queue = mutableListOf<SellwildEvent>()

    /**
     * Analytics kill switch. Defaults on; [SellwildAdView] sets this from the
     * resolved remote config (EVENTS_ENABLED) so events can be stopped via CMS
     * without an app release. When off, [track] is a no-op.
     */
    @Volatile
    var enabled: Boolean = true

    /**
     * Partner attribution. Set from the resolved config (CODE / partnerCode) so
     * every event carries `attributes.code` — the events pipeline keys the
     * partner off that field. When absent, the server stamps the partner as
     * "Invalid", so this must be populated before any emit.
     */
    @Volatile
    var partnerCode: String? = null

    val uid: String by lazy(uidProvider)

    /**
     * POSTs that threw or were answered with a non-2xx status. The batch is dropped
     * (no retry), and the transport never reports itself through logFailure
     * (FAILURES.md 8.4): an outage must not feed more events into the queue.
     */
    internal val failedPosts = AtomicInteger()

    /**
     * Queues one event for the next [flush]. [attributes] ride in the event's attributes bag.
     * @JvmOverloads keeps the 3-argument Java signature this had before [attributes].
     */
    @JvmOverloads
    fun push(
        event: String,
        action: String? = null,
        label: String? = null,
        attributes: Map<String, Any?>? = null,
    ) {
        enqueue(newEvent(event, action, label, attributes))
    }

    private fun newEvent(event: String, action: String?, label: String?, attributes: Map<String, Any?>?) =
        SellwildEvent(event = event, action = action, label = label, attributes = attributes, uid = uid, createdTime = clock())

    private fun enqueue(e: SellwildEvent) {
        // track() pushes on the caller (main) thread while flush() drains on an
        // IO coroutine — guard the shared list so concurrent ad callbacks can't
        // trigger a ConcurrentModificationException / drop events.
        synchronized(queue) {
            queue.add(e)
        }
    }

    /** POSTs everything queued as one batch. Never throws and never calls logFailure. */
    suspend fun flush() {
        withContext(dispatcher) {
            val batch = synchronized(queue) {
                val snapshot = queue.toList()
                queue.clear()
                snapshot
            }
            if (batch.isEmpty()) return@withContext

            runCatching {
                val status = sender.post(EVENTS_URL, buildBatchJson(batch, partnerCode, SellwildSDK.SDK_VERSION))
                if (status !in 200..299) failedPosts.incrementAndGet()
            }.onFailure { failedPosts.incrementAndGet() }
        }
    }

    private val scope = CoroutineScope(dispatcher + SupervisorJob())

    /**
     * Fire-and-forget: queue one event and flush immediately. Mirrors iOS
     * `SellwildAPIClient.sendEvent` — call sites don't need their own scope.
     * Android does not batch: every call is its own POST. @JvmOverloads as on [push].
     */
    @JvmOverloads
    fun track(
        event: String,
        action: String? = null,
        label: String? = null,
        attributes: Map<String, Any?>? = null,
    ) {
        if (!enabled) return
        track(newEvent(event, action, label, attributes))
    }

    /** [track] for an event built elsewhere (logFailure), keeping its uid and createdTime. */
    internal fun track(e: SellwildEvent) {
        if (!enabled) return
        enqueue(e)
        scope.launch { flush() }
    }

    companion object {
        internal const val EVENTS_URL = "https://events.sellwild.com/events/queue"

        @Volatile private var instance: SellwildEventQueue? = null

        /**
         * Process-wide queue, keyed to the application context. Creating it also
         * attaches logFailure, which sends through this queue from then on.
         */
        fun shared(context: Context): SellwildEventQueue {
            instance?.let { return it }
            val created = synchronized(this) {
                instance?.let { return it }
                SellwildEventQueue(context.applicationContext).also { instance = it }
            }
            // Outside the lock: attaching may send failures held before any Context
            // existed (configure() has none), and sending calls uid, which reads prefs.
            SellwildFailures.attachQueue(created)
            return created
        }

        /** Forgets the process-wide queue. Tests only. */
        internal fun resetSharedForTests() {
            instance = null
        }

        private fun prefsUid(prefs: SharedPreferences): () -> String = {
            prefs.getString("_sw_uid", null) ?: UUID.randomUUID().toString().also { id ->
                prefs.edit().putString("_sw_uid", id).apply()
            }
        }
    }
}

// MARK: - Analytics kill switch

/**
 * Resolves the analytics kill switch from remote config. Events are enabled
 * unless the CMS explicitly disables them (EVENTS_ENABLED = false / "false" /
 * 0). An absent key leaves events ON so analytics are never silently dropped.
 * Remote JSON that does not parse also leaves them on, and is reported.
 */
object SellwildEvents {
    fun isEnabled(remoteJson: String?): Boolean {
        val obj = remoteJson?.let { json ->
            runCatching { JSONObject(json) }.getOrElse { e ->
                SellwildFailures.log(
                    code = SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE,
                    component = SellwildFailureComponent.REMOTE_CONFIG,
                    severity = SellwildFailureSeverity.WARN,
                    error = e,
                )
                null
            }
        } ?: return true
        if (!obj.has("EVENTS_ENABLED")) return true
        return when (val v = obj.opt("EVENTS_ENABLED")) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            is String -> v.trim().lowercase() !in setOf("false", "0", "no", "off")
            else -> true
        }
    }
}

// MARK: - Exceptions

class SellwildException(message: String, cause: Throwable? = null) : Exception(message, cause)
