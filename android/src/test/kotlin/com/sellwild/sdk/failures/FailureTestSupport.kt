package com.sellwild.sdk.failures

import com.sellwild.sdk.SellwildEventQueue
import org.json.JSONArray
import org.json.JSONObject
import org.junit.rules.ExternalResource
import java.math.BigDecimal
import java.math.BigInteger
import java.util.concurrent.CopyOnWriteArrayList

/** The uid most golden vectors use. */
internal const val VECTOR_UID = "8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11"

/** Records what logFailure pushes. [onPush] runs first, so a test can make the sink misbehave. */
internal class FakeFailureSink(override val uid: String = VECTOR_UID) : FailureSink {
    val pushed = CopyOnWriteArrayList<FailureEvent>()
    val flushes = CopyOnWriteArrayList<Boolean>()
    var onPush: ((FailureEvent) -> Unit)? = null

    override fun push(event: FailureEvent, flushNow: Boolean) {
        onPush?.invoke(event)
        pushed += event
        flushes += flushNow
    }
}

/**
 * Resets logFailure, its debug logger and the process-wide events queue around each test,
 * because all three are process singletons. [lines] collects everything [SellwildLog] prints.
 */
class FailuresRule : ExternalResource() {
    val lines = CopyOnWriteArrayList<String>()

    override fun before() {
        reset()
        SellwildLog.printer = { lines += it }
    }

    override fun after() = reset()

    private fun reset() {
        SellwildFailures.resetForTests()
        SellwildEventQueue.resetSharedForTests()
    }
}

/** org.json values as plain Kotlin: maps, lists, strings, booleans, Long or Double; JSON null is null. */
internal fun plain(v: Any?): Any? = when (v) {
    null, JSONObject.NULL -> null
    is JSONObject -> v.keys().asSequence().associateWith { plain(v.get(it)) }
    is JSONArray -> (0 until v.length()).map { plain(v.get(it)) }
    is Int, is Long, is Short, is Byte, is BigInteger -> (v as Number).toLong()
    is BigDecimal -> if (v.stripTrailingZeros().scale() <= 0) v.toLong() else v.toDouble()
    is Number -> v.toDouble()
    else -> v
}

/** A JSON value as the pure core takes it: JSON null (and a missing key) is null. */
internal fun JSONObject.value(key: String): Any? = opt(key)?.takeIf { it != JSONObject.NULL }

internal fun FailureEvent.toPlain(): Map<String, Any?> = mapOf(
    "event" to event,
    "action" to action,
    "label" to label,
    "attributes" to attributes,
    "uid" to uid,
    "createdTime" to createdTime,
)

internal fun FailureEvent.toJson(): JSONObject = JSONObject()
    .put("event", event)
    .put("action", action)
    .put("label", label)
    .put("attributes", JSONObject(attributes))
    .put("uid", uid)
    .put("createdTime", createdTime)

internal fun FailureState.toPlain(): Map<String, Any?> = mapOf(
    "sessionCount" to sessionCount.toLong(),
    "keys" to keys.map {
        mapOf(
            "key" to it.key,
            "lastEmitAt" to it.lastEmitAt,
            "suppressed" to it.suppressed.toLong(),
            "emits" to it.emits.toLong(),
        )
    },
)

internal fun stateOf(json: JSONObject?): FailureState {
    if (json == null) return FailureState()
    val keys = json.optJSONArray("keys") ?: JSONArray()
    return FailureState(
        sessionCount = json.optInt("sessionCount"),
        keys = (0 until keys.length()).map { i ->
            val k = keys.getJSONObject(i)
            FailureKey(k.getString("key"), k.optLong("lastEmitAt"), k.optInt("suppressed"), k.optInt("emits"))
        },
    )
}

internal fun inputOf(json: JSONObject) = FailureInput(
    code = json.value("code"),
    component = json.value("component"),
    severity = json.value("severity"),
    errName = json.value("errName"),
    errMessage = json.value("errMessage"),
    message = json.value("message"),
    stack = json.value("stack"),
    httpStatus = json.value("httpStatus"),
    url = json.value("url"),
    zoneId = json.value("zoneId"),
)

internal fun contextOf(json: JSONObject) = FailureContext(
    partnerCode = json.value("partnerCode"),
    client = json.value("client"),
    clientVersion = json.value("clientVersion"),
    wrapper = json.value("wrapper"),
    release = json.value("release"),
    eventsEnabled = json.value("eventsEnabled"),
    failuresEnabled = json.value("failuresEnabled"),
    failuresSampleRate = json.value("failuresSampleRate"),
)
