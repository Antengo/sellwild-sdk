package com.sellwild.sdk.factories

import org.json.JSONObject

/** The GrowthCode sync response. Base: `fixtures/growthcode-sync-response/valid/full.json`. */
object GrowthCodeSyncResponseFactory :
    JsonObjectFactory("growthcode-sync-response", "fixtures/growthcode-sync-response/valid/full.json") {

    /** `gc_id` and `eb` as JSON null, which a device's org.json reads as the text "null". */
    fun nullIds(): JSONObject = build(mapOf("gc_id" to JSONObject.NULL, "eb" to JSONObject.NULL))

    override val variants = listOf(
        Variant("default") { build() },
        Variant("null-ids") { nullIds() },
        Variant("empty") { contractObject("fixtures/growthcode-sync-response/valid/empty.json") },
    )

    override val invalid = listOf(
        Variant("gc-id-number") { build(mapOf("gc_id" to 42)) },
        Variant("idi-text") { build(mapOf("idi" to "true")) },
    )
}

/** The eids blob GrowthCode returns in `eb` (a JSON array). Base: `fixtures/eid-blob/valid/full.json`. */
object EidBlobFactory : ContractFactory {
    override val schema = "eid-blob"

    fun base() = contractArray("fixtures/eid-blob/valid/full.json")

    override val variants = listOf(
        Variant("default") { base() },
        Variant("minimal") { contractArray("fixtures/eid-blob/valid/minimal.json") },
    )

    override val invalid = listOf(
        Variant("missing-source") { base().apply { getJSONObject(0).remove("source") } },
        Variant("not-an-array") { base().getJSONObject(0) },
    )
}
