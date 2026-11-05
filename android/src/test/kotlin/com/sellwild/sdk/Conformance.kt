package com.sellwild.sdk

import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import java.math.BigDecimal

/**
 * contracts/README.md "Conformance" for Android: each case of an expectations file must give
 * the expected value for every field Android is held to, or differ in exactly the fields that
 * expectations/drift/android.json names for that case (FAILURES.md 14.2). A named field that
 * matches fails too, so the entry goes in the change that fixes the drift.
 */
internal class Conformance(val name: String) {
    private val doc = FixtureLoader.jsonObject("expectations/$name.expected.json")
    private val drift = FixtureLoader.jsonObject("expectations/drift/android.json")
        .getJSONObject("expectations").getJSONObject(name)

    /** The expectation cases: file path to expected values. */
    val cases: List<Pair<String, JSONObject>> = doc.getJSONArray("cases").let { cases ->
        (0 until cases.length()).map { cases.getJSONObject(it) }.map { it.getString("file") to it.getJSONObject("expected") }
    }

    /** The fields whose `platforms` include android. */
    val fields: List<String> = doc.getJSONObject("fields").let { fields ->
        fields.keys().asSequence().filter { f ->
            val platforms = fields.getJSONObject(f).getJSONArray("platforms")
            (0 until platforms.length()).any { platforms.getString(it) == "android" }
        }.toList()
    }

    /** The zone ids app-config cases resolve per zone. */
    val zones: List<String> = doc.optJSONArray("zones")?.let { z -> (0 until z.length()).map { z.getString(it) } } ?: emptyList()

    /** Fields the drift text for [file] names: "field:" anywhere, or the text starts with it. */
    fun driftFields(file: String): List<String> {
        val text = drift.optString(file, "")
        if (text.isEmpty()) return emptyList()
        return doc.getJSONObject("fields").keys().asSequence().filter { text.contains("$it:") || text.startsWith(it) }.toList()
    }

    /**
     * Checks [actual] (plain Kotlin values: maps, lists, strings, numbers, booleans, null)
     * against [expected] for every Android field. [views] narrows an expected value to what
     * Android is held to (for example the android entry of a per-OS map).
     */
    fun check(file: String, expected: JSONObject, actual: Map<String, Any?>, views: Map<String, (Any?) -> Any?> = emptyMap()) {
        val named = driftFields(file)
        for (field in fields) {
            val raw = plain(expected.opt(field))
            val view = views[field]
            val want = norm(if (view != null) view(raw) else raw)
            val got = norm(actual.getValue(field))
            if (field in named) {
                assertNotEquals("$file $field is listed as known drift, so it must differ", want, got)
            } else {
                assertEquals("$file $field", want, got)
            }
        }
    }

    companion object {
        /** org.json values as plain Kotlin; JSON null is null. */
        fun plain(v: Any?): Any? = when (v) {
            null, JSONObject.NULL -> null
            is JSONObject -> v.keys().asSequence().associateWith { plain(v.get(it)) }
            is JSONArray -> (0 until v.length()).map { plain(v.get(it)) }
            else -> v
        }

        /** Numbers as BigDecimal without trailing zeros, so 1, 1L and 1.0 compare equal. */
        fun norm(v: Any?): Any? = when (v) {
            is Map<*, *> -> v.entries.associate { (k, x) -> k to norm(x) }
            is List<*> -> v.map(::norm)
            is Number -> BigDecimal(v.toString()).stripTrailingZeros()
            else -> v
        }
    }
}
