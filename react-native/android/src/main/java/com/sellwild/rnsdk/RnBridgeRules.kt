package com.sellwild.rnsdk

/**
 * The decisions the React Native bridge makes about what JS sent: which props
 * and config values it cannot use, and why. Plain Kotlin, with no Android and
 * no React types, so it can be checked without an RN host app. The view
 * managers and [SellwildModule] act on the answers and log each problem with
 * `SellwildFailures.log` (contracts/FAILURES.md). The problem text names the
 * field and its type, never the value.
 */
internal object RnBridgeRules {

    /**
     * The size labels React Native JS accepts: the keys of AD_DIMENSIONS in
     * react-native/src/bannerSizing.ts. JS reports any other label itself
     * (`ad.size.invalid`), so the bridge reports only a label from this set
     * that the native SDK has no size for. react-native/test/nativeGlue.test.ts
     * keeps this list equal to the JS one.
     */
    val JS_AD_SIZE_LABELS: Set<String> = setOf("300x250", "320x50", "728x90", "160x600", "300x600", "1x1")

    /**
     * Why the banner props cannot set up an ad (`bridge.props.invalid`), or
     * null when they can. Also null for a missing size or a label JS does not
     * accept: JS already reported that one as `ad.size.invalid`, and a failure
     * is logged once.
     */
    fun bannerPropsProblem(
        hasConfig: Boolean,
        size: String?,
        zoneId: String?,
        nativeSupports: (String) -> Boolean,
    ): String? {
        if (!hasConfig) return "the config prop is missing"
        if (zoneId == null) return "the zoneId prop is missing"
        if (size == null || nativeSupports(size)) return null
        return if (size in JS_AD_SIZE_LABELS) "size $size has no native ad size" else null
    }

    /** A config value of another type than [want] was dropped (`bridge.config.invalid`). */
    fun wrongType(key: String, readableType: String, want: String): String =
        "$key is ${kind(readableType)}, not $want, so it was dropped"

    /** A list config value with [bad] of [total] entries that are not text was dropped. */
    fun notTextEntries(key: String, bad: Int, total: Int): String =
        "$key has $bad of $total entries that are not text, so it was dropped"

    /**
     * Why a `prebidServer` config value cannot be used, so the default Prebid
     * Server is used instead (`bridge.config.invalid`), or null when it is
     * complete.
     */
    fun prebidServerProblem(hasAccountId: Boolean, hasEndpoint: Boolean): String? {
        val missing = listOfNotNull("accountId".takeUnless { hasAccountId }, "endpoint".takeUnless { hasEndpoint })
        return if (missing.isEmpty()) null
        else "prebidServer has no ${missing.joinToString(" or ")} text, so the default Prebid Server is used"
    }

    /** A `prebidServer` config value that is not an object: the default Prebid Server is used (`bridge.config.invalid`). */
    fun prebidServerNotObject(readableType: String): String =
        "prebidServer is ${kind(readableType)}, not an object, so the default Prebid Server is used"

    /**
     * The geo fields the bridge reads, and the ReadableType name each one
     * needs: the fields of `SellwildGeo`.
     */
    val GEO_FIELD_TYPES: Map<String, String> = linkedMapOf(
        "country" to "String",
        "state" to "String",
        "city" to "String",
        "zip" to "String",
        "metro" to "String",
        "lat" to "Number",
        "lon" to "Number",
        "type" to "Number",
    )

    /**
     * The geo fields JS sent with a type the bridge cannot read, each mapped
     * to why it was dropped (`bridge.geo.invalid` from setGeo). [typeOf]
     * gives the ReadableType name of a field, or null when it is absent. An
     * absent or null field is not a problem: it is unset.
     */
    fun geoWrongTyped(typeOf: (String) -> String?): Map<String, String> =
        GEO_FIELD_TYPES.mapNotNull { (key, want) ->
            val type = typeOf(key)
            if (type == null || type == "Null" || type == want) null
            else key to wrongType("geo.$key", type, if (want == "Number") "a number" else "text")
        }.toMap()

    /**
     * setGeo got a value that is not an object, so geo is cleared
     * (`bridge.geo.invalid`). The same text as iOS (SellwildRNBridgeRules.geoMap).
     */
    fun geoNotObject(readableType: String): String =
        "geo is ${kind(readableType)}, not an object, so geo was cleared"

    /**
     * What setExternalUserIds dropped (`bridge.eids.invalid`), or null when it
     * dropped nothing.
     */
    fun eidsProblem(skippedEntries: Int, total: Int, skippedUids: Int): String? =
        if (skippedEntries == 0 && skippedUids == 0) null
        else "skipped $skippedEntries of $total eids without source or a uids list, and $skippedUids uids without id"

    /** A short name for a bridged value's ReadableType name, for problem text. */
    fun kind(readableType: String): String = when (readableType) {
        "Null" -> "null"
        "Boolean" -> "a boolean"
        "Number" -> "a number"
        "String" -> "text"
        "Map" -> "an object"
        "Array" -> "a list"
        else -> readableType
    }
}

/**
 * The last problem reported for one view, so a re-render with the same bad
 * props does not report it again (`bridge.props.invalid`, logged once).
 */
internal class ReportOnce {
    private var last: String? = null

    /**
     * [problem] when it should be reported now, because it is not the last
     * one reported; null otherwise. A null [problem] (the props are fine
     * again) forgets the last one, so the same problem coming back is
     * reported again.
     */
    fun take(problem: String?): String? {
        if (problem == last) return null
        last = problem
        return problem
    }
}
