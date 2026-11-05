package com.sellwild.sdk.core

/**
 * A value the SDK could not use as given. Pure code returns it next to its result, and
 * the calling shell reports it through logFailure as [code] (FAILURES.md 1, 9: log once,
 * where the failure is observed).
 *
 * @property severity a SellwildFailureSeverity constant.
 * @property message short and PII-free: key names, config values, counts; never listing
 *   text or user data.
 */
internal data class Issue(
    val code: String,
    val component: String,
    val severity: String,
    val message: String? = null,
    val error: Throwable? = null,
    val zoneId: String? = null,
)

/** A pure function's result plus the [Issue]s it found on the way. */
internal data class Resolved<out T>(val value: T, val issues: List<Issue> = emptyList())
