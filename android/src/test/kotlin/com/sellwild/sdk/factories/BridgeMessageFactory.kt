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
    )

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
