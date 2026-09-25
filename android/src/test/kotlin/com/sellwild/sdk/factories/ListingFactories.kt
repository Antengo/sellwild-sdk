package com.sellwild.sdk.factories

import org.json.JSONArray
import org.json.JSONObject

/** One listing (`result.rs[i]`). Base: a real Sellwild cache item, `fixtures/listing/valid/sellwild-cache-item.json`. */
object ListingFactory : JsonObjectFactory("listing", "fixtures/listing/valid/sellwild-cache-item.json") {

    /** A dataSourceId 31 listing whose `remote_url` is JSON null, as some real cache items are. */
    fun remoteUrlNull(): JSONObject = build(mapOf("remote_url" to JSONObject.NULL))

    override val variants = listOf(
        Variant("default") { build() },
        Variant("remote-url-null") { remoteUrlNull() },
        Variant("bargainhunter") { contractObject("fixtures/listing/valid/bargainhunter-item.json") },
        Variant("no-remote-url") { build(mapOf("remote_url" to null, "dataSourceId" to null)) },
        Variant("data-uri-photos") { contractObject("fixtures/listing/valid/data-uri-photos.json") },
        Variant("rpc-item") { contractObject("fixtures/listing/valid/rpc-item.json") },
        Variant("localized-item") { contractObject("fixtures/listing/valid/localized-item-text-shippable.json") },
        // Every optional text field set, so a parser test sees each one mapped.
        Variant("every-field") {
            build(
                mapOf(
                    "text" to "Low miles, one owner.",
                    "url" to "https://sellwild.com/product/105140231",
                    "categoryId" to "7",
                    "currency" to "USD",
                    "strikePrice" to "21000",
                    "createdDate" to "2026-09-01T12:00:00Z",
                    "has_photo" to true,
                    "photos" to JSONArray().put(
                        JSONObject()
                            .put("url", "https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231.jpg")
                            .put("thumbUrl", "https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231_thumb.jpg")
                            .put("background", "#ffffff"),
                    ),
                ),
            )
        },
        Variant("no-price-empty-remote-url") { build(mapOf("price" to null, "remote_url" to "")) },
    )

    override val invalid = listOf(
        Variant("title-number") { build(mapOf("title" to 7)) },
        Variant("no-photos") { build(mapOf("photos" to null)) },
    )
}

/** The listings cache (`GET cache.sellwild.com/listings-*`). Base: `fixtures/listings-response/valid/empty-rs.json`. */
object ListingsResponseFactory : JsonObjectFactory("listings-response", "fixtures/listings-response/valid/empty-rs.json") {

    /** The base with `result.rs` set to [items]. */
    fun withItems(vararg items: JSONObject): JSONObject = build().apply {
        getJSONObject("result").put("rs", JSONArray().apply { items.forEach { put(it) } })
    }

    override val variants = listOf(
        Variant("default") { withItems(ListingFactory.build()) },
        Variant("null-remote-url") { withItems(ListingFactory.remoteUrlNull(), ListingFactory.build()) },
        Variant("empty") { build() },
        Variant("sample-weatherbug") { contractObject("samples/listings-response/listings-img-data-sm-avif-weatherbug.json") },
    )

    override val invalid = listOf(
        Variant("result-null") { build(mapOf("result" to JSONObject.NULL)) },
        Variant("item-missing-title") { withItems(ListingFactory.build(mapOf("title" to null))) },
    )
}

/** LOCALIZED_LISTINGS inside the app config. Base: `fixtures/localized-listings-config/valid/full.json`. */
object LocalizedListingsConfigFactory :
    JsonObjectFactory("localized-listings-config", "fixtures/localized-listings-config/valid/full.json") {

    override val variants = listOf(
        Variant("default") { build() },
        Variant("disabled") { contractObject("fixtures/localized-listings-config/valid/disabled-only.json") },
        Variant("minimal") { contractObject("fixtures/localized-listings-config/valid/minimal.json") },
        Variant("no-force-state") { build(mapOf("forceState" to null, "frequency" to "10")) },
    )

    override val invalid = listOf(
        Variant("enabled-text") { build(mapOf("enabled" to "yes")) },
        Variant("template-without-state") { build(mapOf("urlTemplate" to "sports.json")) },
    )
}

/**
 * The per-state listings cache (`GET {baseUrl}{urlTemplate}`). Base:
 * `fixtures/localized-listings-response/valid/one-item.json`.
 */
object LocalizedListingsResponseFactory :
    JsonObjectFactory("localized-listings-response", "fixtures/localized-listings-response/valid/one-item.json") {

    override val variants = listOf(
        Variant("default") { build() },
        Variant("empty") { contractObject("fixtures/localized-listings-response/valid/minimal.json") },
        Variant("sample-al") { contractObject("samples/localized-listings-response/sports-img-data-sm-webp-al.json") },
    )

    override val invalid = listOf(
        Variant("missing-state") { build().apply { getJSONObject("result").remove("state") } },
        Variant("state-lower-case") { build().apply { getJSONObject("result").put("state", "al") } },
    )
}
