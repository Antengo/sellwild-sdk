package com.sellwild.sdk.timing

import com.sellwild.sdk.failures.FailuresCore

// sdkTiming pure core: a Kotlin port of contracts/reference/sdk-timing.mjs
// (contracts/FAILURES.md section 18.1). Reproduces contracts/golden/sdk-timing.vectors.json.

/** One measurement. */
internal data class TimingInput(val step: Any? = null, val ms: Any? = null, val zoneId: Any? = null)

/** What the core reads: the report context and the raw remote values. */
internal data class TimingContext(
    val partnerCode: Any? = null,
    val client: Any? = null,
    val clientVersion: Any? = null,
    val appId: Any? = null,
    val appVersion: Any? = null,
    val os: Any? = null,
    val device: Any? = null,
    val net: Any? = null,
    val eventsEnabled: Any? = null,
    val timingEnabled: Any? = null,
    val timingSampleRate: Any? = null,
)

internal data class TimingState(val sessionCount: Int = 0)

/** One sdkTiming event; [attributes] keeps the wire order of [TimingCore.ATTRIBUTE_KEYS]. */
internal data class TimingEvent(
    val action: String,
    val attributes: Map<String, String>,
    val uid: String,
    val createdTime: Long,
) {
    val event: String get() = TimingCore.EVENT
    val label: String get() = TimingCore.LABEL
}

internal data class TimingDecision(val state: TimingState, val event: TimingEvent?, val reason: String?)

internal object TimingCore {
    const val EVENT = "sdkTiming"
    const val LABEL = "timing"
    const val VERSION = "1"

    val STEPS = listOf("config.fetch", "listings.fetch", "listings.decode", "feed.firstListing", "ad.firstLoad")
    val ATTRIBUTE_KEYS = listOf(
        "code", "client", "clientVersion", "tv", "step", "ms", "zoneId",
        "appId", "appVersion", "os", "device", "net", "seq",
    )

    const val DEFAULT_RATE = 0.1
    const val SESSION_TIMINGS = 50
    const val MAX_MS = 600_000.0
    const val FIELD_MAX = 64
    const val ZONE_ID_MAX = 32

    private const val CONFIG_BUDGET_MS = 3000L
    private const val LISTINGS_BUDGET_MS = 4000L
    private const val AD_BUDGET_MS = 6000L
    private const val TWO_TO_32 = 4294967296.0

    val BUDGETS = mapOf(
        "config.fetch" to CONFIG_BUDGET_MS,
        "listings.fetch" to LISTINGS_BUDGET_MS,
        "ad.firstLoad" to AD_BUDGET_MS,
    )
    val BUDGET_KEYS = mapOf(
        "config.fetch" to "TIMING_BUDGET_CONFIG_MS",
        "listings.fetch" to "TIMING_BUDGET_LISTINGS_MS",
        "ad.firstLoad" to "TIMING_BUDGET_AD_MS",
    )
    val SLOW_CODES = mapOf(
        "config.fetch" to "config.fetch.slow",
        "listings.fetch" to "listings.fetch.slow",
        "ad.firstLoad" to "ad.load.slow",
    )

    private val MS_RE = Regex("\\+?[0-9]+")
    private val RATE_RE = Regex("\\+?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)")

    /** A positive whole number of ms from a remote value, else null. */
    fun parseBudgetMs(v: Any?): Long? {
        val n: Double? = when (v) {
            is Number -> v.toDouble().takeIf { it.isFinite() }?.let { Math.floor(it) }
            is String -> FailuresCore.trimAscii(v).takeIf { MS_RE.matches(it) }?.toDoubleOrNull()
            else -> null
        }
        return n?.takeIf { it >= 1 }?.toLong()
    }

    /** The budget of [step]: the remote override ([remote] is a Map or JSONObject), else the default. */
    fun budgetFor(step: Any?, remote: Any?): Long? {
        val default = BUDGETS[step] ?: return null
        val key = BUDGET_KEYS.getValue(step as String)
        val raw = when (remote) {
            is Map<*, *> -> remote[key]
            is org.json.JSONObject -> remote.opt(key)
            else -> null
        }
        return parseBudgetMs(raw) ?: default
    }

    /** Whether [ms] is over the budget of [step]. */
    @Suppress("ReturnCount") // guard clauses, as the reference reads
    fun isSlow(step: Any?, ms: Any?, remote: Any?): Boolean {
        val budget = budgetFor(step, remote) ?: return false
        val value = (ms as? Number)?.toDouble() ?: return false
        return value.isFinite() && value > budget
    }

    /** TIMING_SAMPLE_RATE clamped to [0, 1]; unset or anything else → 0.1. */
    fun timingRate(v: Any?): Double {
        val n: Double? = when (v) {
            is Number -> v.toDouble().takeIf { it.isFinite() }
            is String -> FailuresCore.trimAscii(v).takeIf { RATE_RE.matches(it) }?.toDouble()
            else -> null
        }
        return n?.coerceIn(0.0, 1.0) ?: DEFAULT_RATE
    }

    /** fnv1a32(uid + ":timing") / 2^32 < rate. */
    fun isTimingSampled(uid: String?, rate: Double): Boolean = when {
        rate >= 1 -> true
        rate <= 0 -> false
        else -> FailuresCore.fnv1a32(uid.orEmpty() + ":timing") / TWO_TO_32 < rate
    }

    private fun cleanBounded(v: Any?, max: Int): String? {
        if (v !is String) return null
        val t = FailuresCore.cleanText(v)
        return if (t.isEmpty()) null else FailuresCore.truncateUnicode(t, max)
    }

    /** The whole decision as a pure function (FAILURES.md 18.1), gate by gate as the reference reads. */
    @Suppress("ReturnCount", "CyclomaticComplexMethod", "ComplexCondition")
    fun decideTiming(
        state: TimingState?,
        input: TimingInput?,
        context: TimingContext?,
        uid: String?,
        now: Long
    ): TimingDecision {
        val st = state ?: TimingState()
        val ctx = context ?: TimingContext()
        val inp = input ?: TimingInput()
        fun drop(reason: String) = TimingDecision(st, null, reason)

        if (!FailuresCore.coerceFlag(ctx.eventsEnabled, true)) return drop("events_disabled")
        if (!FailuresCore.coerceFlag(ctx.timingEnabled, true)) return drop("timing_disabled")
        val step = inp.step as? String
        if (step == null || step !in STEPS) return drop("invalid_step")
        val ms = (inp.ms as? Number)?.toDouble()
        if (ms == null || !ms.isFinite() || ms < 0 || ms > MAX_MS) return drop("invalid_ms")
        if (!isTimingSampled(uid, timingRate(ctx.timingSampleRate))) return drop("sampled_out")
        if (st.sessionCount >= SESSION_TIMINGS) return drop("session_capped")

        val seq = st.sessionCount + 1
        val a = mapOf(
            "code" to (cleanBounded(ctx.partnerCode, FIELD_MAX) ?: "unknown"),
            "client" to (cleanBounded(ctx.client, FIELD_MAX) ?: "unknown"),
            "clientVersion" to (cleanBounded(ctx.clientVersion, FIELD_MAX) ?: "unknown"),
            "tv" to VERSION,
            "step" to step,
            "ms" to Math.round(ms).toString(),
            "zoneId" to cleanBounded(inp.zoneId, ZONE_ID_MAX),
            "appId" to cleanBounded(ctx.appId, FIELD_MAX),
            "appVersion" to cleanBounded(ctx.appVersion, FIELD_MAX),
            "os" to cleanBounded(ctx.os, FIELD_MAX),
            "device" to cleanBounded(ctx.device, FIELD_MAX),
            "net" to cleanBounded(ctx.net, FIELD_MAX),
            "seq" to seq.toString(),
        )
        val attributes = LinkedHashMap<String, String>()
        for (k in ATTRIBUTE_KEYS) a[k]?.let { attributes[k] = it }
        return TimingDecision(TimingState(seq), TimingEvent(step, attributes, uid.orEmpty(), now), null)
    }
}
