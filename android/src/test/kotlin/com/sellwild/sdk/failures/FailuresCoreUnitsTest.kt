package com.sellwild.sdk.failures

import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The single-function tables in the golden files (`units`): each helper of the pure core
 * gives the reference's answer for every row.
 */
class FailuresCoreUnitsTest {

    private val units: List<JSONObject> = listOf(
        "golden/log-failure.vectors.json",
        "golden/log-failure.utf16.vectors.json",
    ).map { FixtureLoader.jsonObject(it).getJSONObject("units") }

    private fun rows(table: String): List<JSONObject> = units.flatMap { u ->
        val rows = u.optJSONArray(table) ?: JSONArray()
        (0 until rows.length()).map { rows.getJSONObject(it) }
    }

    private fun check(table: String, expectedOf: (Any?) -> Any? = ::plain, fn: (Any?) -> Any?) {
        val rows = rows(table)
        assertTrue("$table has rows", rows.isNotEmpty())
        for (row in rows) {
            val input = row.value("input")
            assertEquals("$table($input)", expectedOf(row.opt("expected")), plain(fn(input)))
        }
    }

    @Test
    fun fnv1a32() = check("fnv1a32") { FailuresCore.fnv1a32(it as String) }

    @Test
    fun truncateUnicode() = check("truncateUnicode") {
        val args = it as JSONArray
        FailuresCore.truncateUnicode(args.getString(0), args.getInt(1))
    }

    @Test
    fun hostOf() = check("hostOf") { FailuresCore.hostOf(it) }

    @Test
    fun sanitizeMessage() = check("sanitizeMessage") { FailuresCore.sanitizeMessage(it) }

    @Test
    fun coerceFlag() = check("coerceFlag") { FailuresCore.coerceFlag(it) }

    @Test
    fun coerceRate() = check("coerceRate", { (it as Number).toDouble() }) { FailuresCore.coerceRate(it) }

    @Test
    fun normalizeCode() = check("normalizeCode") { FailuresCore.normalizeCode(it) }

    @Test
    fun normalizeHttpStatus() = check("normalizeHttpStatus") { FailuresCore.normalizeHttpStatus(it) }
}
