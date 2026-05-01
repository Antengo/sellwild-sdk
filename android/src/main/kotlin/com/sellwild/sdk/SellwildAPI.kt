package com.sellwild.sdk

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

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
) {
    val displayPrice: String?
        get() {
            val value = price?.toDoubleOrNull() ?: return null
            return if (value > 0) String.format("%.0f", value) else null
        }

    val primaryPhotoUrl: String?
        get() = photos.firstOrNull()?.url
}

data class SellwildListingsResponse(
    val listings: List<SellwildListing>,
    val config: Map<String, Any>,
    val widgetCacheVersionId: String?,
)

// MARK: - API Client

class SellwildAPIClient(private val context: Context) {

    private val listingCache = java.util.concurrent.ConcurrentHashMap<String, SellwildListingsResponse>()

    suspend fun fetchListings(config: SellwildConfig): Result<SellwildListingsResponse> =
        withContext(Dispatchers.IO) {
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

                val body = connection.inputStream.bufferedReader().readText()
                val response = parseListingsResponse(body)
                listingCache[listingsUrl] = response
                response
            }
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
        )
    }

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
    val uid: String,
    val createdTime: Long = System.currentTimeMillis(),
)

class SellwildEventQueue(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("sellwild_sdk", Context.MODE_PRIVATE)
    private val eventsUrl = "https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/events/queue"
    private val queue = mutableListOf<SellwildEvent>()

    val uid: String by lazy {
        prefs.getString("_sw_uid", null) ?: UUID.randomUUID().toString().also { id ->
            prefs.edit().putString("_sw_uid", id).apply()
        }
    }

    fun push(event: String, action: String? = null, label: String? = null) {
        queue.add(SellwildEvent(event = event, action = action, label = label, uid = uid))
    }

    suspend fun flush() = withContext(Dispatchers.IO) {
        val batch = queue.toList()
        queue.clear()
        if (batch.isEmpty()) return@withContext

        runCatching {
            val json = JSONArray().apply {
                batch.forEach { e ->
                    put(JSONObject().apply {
                        put("event", e.event)
                        e.action?.let { put("action", it) }
                        e.label?.let { put("label", it) }
                        put("uid", e.uid)
                        put("createdTime", e.createdTime)
                    })
                }
            }

            val conn = URL(eventsUrl).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            OutputStreamWriter(conn.outputStream).use { it.write(json.toString()) }
            conn.responseCode // trigger send
        }
    }
}

// MARK: - Exceptions

class SellwildException(message: String, cause: Throwable? = null) : Exception(message, cause)
