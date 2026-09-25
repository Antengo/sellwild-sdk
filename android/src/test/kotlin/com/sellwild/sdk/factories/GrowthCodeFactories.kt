package com.sellwild.sdk.factories

import org.json.JSONArray
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

    /** A fresh build of the [variants] or [invalid] entry named [name]. */
    fun variant(name: String): Any = (variants + invalid).single { it.name == name }.build()

    override val variants = listOf(
        Variant("default") { base() },
        Variant("minimal") { contractArray("fixtures/eid-blob/valid/minimal.json") },
        Variant("empty") { JSONArray() },
    )

    override val invalid = listOf(
        Variant("missing-source") { base().apply { getJSONObject(0).remove("source") } },
        Variant("not-an-array") { base().getJSONObject(0) },
        // Every entry usable, but one uid has no id.
        Variant("uid-without-id") { base().apply { getJSONObject(0).getJSONArray("uids").put(JSONObject().put("atype", 1)) } },
        // JSON null where text belongs (a device's org.json reads it as the text "null"): the
        // first uid's id, the second entry's stype, and the source of an added entry.
        Variant("null-text-fields") {
            base().apply {
                getJSONObject(0).getJSONArray("uids").getJSONObject(0).put("id", JSONObject.NULL)
                getJSONObject(1).getJSONArray("uids").getJSONObject(1).put("stype", JSONObject.NULL)
                put(JSONObject().put("source", JSONObject.NULL).put("uids", JSONArray().put(JSONObject().put("id", "null-source-uid"))))
            }
        },
        // Empty text where text belongs: the same three fields as null-text-fields.
        Variant("empty-text-fields") {
            base().apply {
                getJSONObject(0).getJSONArray("uids").getJSONObject(0).put("id", "")
                getJSONObject(1).getJSONArray("uids").getJSONObject(1).put("stype", "")
                put(JSONObject().put("source", "").put("uids", JSONArray().put(JSONObject().put("id", "empty-source-uid"))))
            }
        },
        // The two good entries of the base, plus whole entries a parser must drop (one that is
        // not an object, one without uids, one without source), and no bad uid.
        Variant("bad-entries-only") {
            base().apply {
                put("not-an-object")
                put(JSONObject().put("source", "no-uids.example"))
                put(JSONObject().put("uids", base().getJSONObject(0).getJSONArray("uids")))
            }
        },
        // The two good entries of the base, plus every shape a parser must drop: uids that
        // are not objects or have no id, an entry that is not an object, one without uids,
        // one without source, and one whose every uid is bad.
        Variant("partly-invalid") {
            base().apply {
                getJSONObject(1).getJSONArray("uids").put(JSONObject().put("atype", 1)).put("not-an-object")
                put("not-an-object")
                put(JSONObject().put("source", "no-uids.example"))
                put(JSONObject().put("uids", base().getJSONObject(0).getJSONArray("uids")))
                put(JSONObject().put("source", "all-uids-bad.example").put("uids", JSONArray().put(JSONObject())))
            }
        },
    )
}
