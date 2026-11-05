package com.sellwild.sdk.factories

import com.sellwild.sdk.SellwildEvent
import com.sellwild.sdk.SellwildSDK
import com.sellwild.sdk.buildBatchJson
import com.sellwild.sdk.failures.FailureContext
import com.sellwild.sdk.failures.FailureEvent
import com.sellwild.sdk.failures.FailureInput
import com.sellwild.sdk.failures.FailuresCore
import org.json.JSONArray
import org.json.JSONObject

/**
 * clientFailure events. Base: `fixtures/client-failure-event/valid/minimal.json`; [android]
 * builds the event with the real Android pure core instead of copying one.
 */
object ClientFailureEventFactory :
    JsonObjectFactory("client-failure-event", "fixtures/client-failure-event/valid/minimal.json") {

    private const val UID = "2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11"
    private const val NOW = 1_790_000_000_000L

    /** An event from FailuresCore.decideFailure with the Android context, the first of a session. */
    internal fun android(input: FailureInput = configHttp(), partnerCode: String = "weatherbug"): FailureEvent =
        FailuresCore.decideFailure(
            null,
            input,
            FailureContext(partnerCode = partnerCode, client = "android", clientVersion = SellwildSDK.SDK_VERSION),
            UID,
            NOW,
        ).event!!

    internal fun configHttp() = FailureInput(
        code = "config.fetch.http",
        component = "remoteConfig",
        message = "HTTP 403",
        httpStatus = 403,
        url = "https://widget.sellwild.com/app/weatherbug/weatherbug-main.json",
    )

    internal fun toJson(event: FailureEvent): JSONObject = JSONObject()
        .put("event", event.event)
        .put("action", event.action)
        .put("label", event.label)
        .put("attributes", JSONObject(event.attributes))
        .put("uid", event.uid)
        .put("createdTime", event.createdTime)

    override val variants = listOf(
        Variant("default") { build() },
        Variant("android-config-http") { toJson(android()) },
        Variant("android-with-error") {
            toJson(
                android(
                    FailureInput(
                        code = "listings.fetch.network",
                        component = "listings",
                        severity = "warn",
                        errName = "SocketTimeoutException",
                        errMessage = "timeout after 15000 ms",
                        stack = "com.sellwild.sdk.SellwildAPIClient.fetchListings(SellwildAPI.kt:121)",
                        zoneId = "43",
                    ),
                ),
            )
        },
        Variant("all-16-attributes") { contractObject("fixtures/client-failure-event/valid/all-16-attributes.json") },
    )

    override val invalid = listOf(
        Variant("extra-attribute") { build().apply { getJSONObject("attributes").put("title", "2021 Lexus") } },
        Variant("legacy-snake-code") { build(mapOf("action" to "config_fetch_failed")) },
        Variant("queue-stamped-not-allowed") {
            // The bare event must not carry the queue stamps; only the wire form (events-batch) does.
            build().apply { getJSONObject("attributes").put("type", "android") }
        },
    )
}

/**
 * The events POST body. Base: `fixtures/events-batch/valid/android-render.json`. [android]
 * builds the body with the queue's real buildBatchJson.
 */
object EventsBatchFactory : ContractFactory {
    override val schema = "events-batch"

    fun base(): JSONArray = contractArray("fixtures/events-batch/valid/android-render.json")

    /** The body SellwildEventQueue posts for [events]. */
    fun android(vararg events: SellwildEvent, partnerCode: String? = "weatherbug"): JSONArray =
        JSONArray(buildBatchJson(events.toList(), partnerCode, SellwildSDK.SDK_VERSION))

    fun adError(): SellwildEvent =
        SellwildEvent(event = "adError", action = "No ad to show.", label = "43", uid = "u-1", createdTime = 1_790_000_000_000L)

    internal fun clientFailure(event: FailureEvent = ClientFailureEventFactory.android()): SellwildEvent = SellwildEvent(
        event = event.event,
        action = event.action,
        label = event.label,
        attributes = event.attributes,
        uid = event.uid,
        createdTime = event.createdTime,
    )

    override val variants = listOf(
        Variant("default") { base() },
        Variant("android-ad-error") { android(adError()) },
        Variant("android-client-failure") { android(adError(), clientFailure()) },
        Variant("android-no-partner") { android(adError(), partnerCode = null) },
    )

    override val invalid = listOf(
        Variant("empty") { JSONArray() },
        Variant("client-failure-extra-attribute") {
            val failure = ClientFailureEventFactory.android()
            android(clientFailure(failure.copy(attributes = failure.attributes + ("amount" to "1"))))
        },
    )
}
