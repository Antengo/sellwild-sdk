package com.sellwild.sdk.factories

/**
 * Messages the widget page posts to SellwildWidgetView's JS bridge. Base:
 * `fixtures/bridge-message/valid/widget-loaded.json`.
 */
object BridgeMessageFactory : JsonObjectFactory("bridge-message", "fixtures/bridge-message/valid/widget-loaded.json") {

    override val variants = listOf(
        Variant("default") { build() },
        Variant("ad-impression") { build(mapOf("type" to "AD_IMPRESSION", "zoneId" to "43")) },
        Variant("error") { contractObject("fixtures/bridge-message/valid/error.json") },
        Variant("listing-click") { contractObject("fixtures/bridge-message/valid/listing-click-url.json") },
        Variant("listing-click-stub") { contractObject("fixtures/bridge-message/valid/listing-click-stub.json") },
        // The listing object is free-form: every field the Android bridge maps, photos included.
        Variant("listing-click-photos") { listingClickWith(photos = org.json.JSONArray().put(org.json.JSONObject().put("url", PHOTO).put("thumbUrl", THUMB))) },
        // A photo that is not an object: valid for the schema (the listing is free-form), not for the bridge.
        Variant("listing-click-bad-photo") { listingClickWith(photos = org.json.JSONArray().put(1)) },
        Variant("ad-impression-number-zone") { contractObject("fixtures/bridge-message/valid/ad-impression-number-zone.json") },
    )

    private const val PHOTO = "https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231.jpg"
    private const val THUMB = "https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231_thumb.jpg"

    private fun listingClickWith(photos: org.json.JSONArray) =
        contractObject("fixtures/bridge-message/valid/listing-click-stub.json").apply {
            getJSONObject("listing").put("photos", photos).put("price", "19315").put("currency", "USD").put("url", "https://sellwild.com/listing/105140231")
        }

    override val invalid = listOf(
        Variant("unknown-type") { build(mapOf("type" to "NOPE")) },
        Variant("extra-field") { build(mapOf("extra" to true)) },
    )
}

/** Every Android factory, for FactoriesContractTest. */
val ALL_FACTORIES: List<ContractFactory> = listOf(
    AppConfigFactory,
    ListingFactory,
    ListingsResponseFactory,
    LocalizedListingsConfigFactory,
    LocalizedListingsResponseFactory,
    ClientFailureEventFactory,
    EventsBatchFactory,
    GrowthCodeSyncResponseFactory,
    EidBlobFactory,
    BridgeMessageFactory,
)
