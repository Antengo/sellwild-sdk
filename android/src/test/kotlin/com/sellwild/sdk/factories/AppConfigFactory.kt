package com.sellwild.sdk.factories

import org.json.JSONObject

/**
 * The CDN app config (`GET widget.sellwild.com/app/{partner}/{slug}.json`), the payload
 * SellwildSDK.configure parses. Base: `fixtures/app-config/valid/minimal.json`.
 */
object AppConfigFactory : JsonObjectFactory("app-config", "fixtures/app-config/valid/minimal.json") {

    /** The remote kill switches and sample rate, as raw values (Boolean, Number or String). */
    fun withFailureFlags(failuresEnabled: Any?, sampleRate: Any?, eventsEnabled: Any? = null): JSONObject =
        build(
            mapOf(
                "EVENTS_ENABLED" to eventsEnabled,
                "FAILURES_ENABLED" to failuresEnabled,
                "FAILURES_SAMPLE_RATE" to sampleRate,
            ),
        )

    override val variants = listOf(
        Variant("default") { build() },
        Variant("sample-weatherbug") { contractObject("samples/app-config/weatherbug_weatherbug-weatherbug.json") },
        Variant("failures-off") { withFailureFlags(false, 0.25, eventsEnabled = true) },
        Variant("failures-text") { withFailureFlags("off", "0.5", eventsEnabled = "yes") },
        Variant("per-os-zids") {
            build(mapOf("MOBILE_ZID" to jsonArrayOf("shared-1"), "MOBILE_ZID_ANDROID" to jsonArrayOf("android-1")))
        },
    )

    override val invalid = listOf(
        Variant("missing-code") { build(mapOf("CODE" to null)) },
        Variant("sample-rate-object") { build(mapOf("FAILURES_SAMPLE_RATE" to JSONObject().put("rate", 0.5))) },
    )
}
