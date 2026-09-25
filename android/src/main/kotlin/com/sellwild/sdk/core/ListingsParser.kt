package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.SellwildListingsResponse
import com.sellwild.sdk.SellwildPhoto
import com.sellwild.sdk.SellwildUser
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Parses a listings cache body (`result.rs`, or `rs` at the top level). The primary feed
 * and the per-state localized caches share the shape.
 */
internal object ListingsParser {

    /**
     * @throws JSONException when [json] is not a JSON object, or an `rs` item or a photo is
     *   not an object. One bad item fails the whole body, as it always has.
     */
    fun parse(json: String): SellwildListingsResponse {
        val root = JSONObject(json)
        val result = root.optJSONObject("result") ?: root
        val rs = result.optJSONArray("rs") ?: JSONArray()
        val configJson = result.optJSONObject("config")
        val config = if (configJson != null) toMap(configJson) else emptyMap()
        val versionId = result.optString("widgetCacheVersionId").ifEmpty { null }
        val listings = (0 until rs.length()).map { i -> parseListing(rs.getJSONObject(i)) }
        return SellwildListingsResponse(listings, config, versionId)
    }

    fun parseListing(json: JSONObject): SellwildListing {
        val photosArray = json.optJSONArray("photos") ?: JSONArray()
        val photos = (0 until photosArray.length()).map { i ->
            val p = photosArray.getJSONObject(i)
            SellwildPhoto(
                url = p.optString("url"),
                thumbUrl = p.optString("thumbUrl"),
                background = p.optString("background").ifEmpty { null },
            )
        }
        val user = json.optJSONObject("user")?.let {
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
            remoteUrl = optTextOrNull(json, "remote_url"),
        )
    }

    /**
     * Text at [key], or null when it is absent, JSON null or empty. The cache sends
     * `"remote_url": null` on some items, and a device's org.json returns the text "null"
     * from optString for JSON null (the JVM org.json of plain unit tests returns ""), which
     * tapUrl would then open as a URL.
     */
    fun optTextOrNull(json: JSONObject, key: String): String? =
        if (json.isNull(key)) null else json.optString(key).ifEmpty { null }

    private fun toMap(json: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        json.keys().forEach { key -> map[key] = json.get(key) }
        return map
    }
}
