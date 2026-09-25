package com.sellwild.sdk.factories

import com.sellwild.sdk.support.ContractSchemas
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONTokener
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * The in-process validator agrees with ajv (contracts/scripts/validate.mjs) on the shared
 * fixtures of every schema a factory covers: valid fixtures pass, and each invalid fixture
 * fails at the instance path `_expected-errors.json` names.
 */
class ContractFixturesAgreementTest {

    @get:Rule
    val network = NetworkBlockRule()

    private val schemas = ALL_FACTORIES.map { it.schema }.distinct()

    private fun errorsOf(schema: String, path: String): List<String> =
        ContractSchemas.errors(schema, JSONTokener(FixtureLoader.text(path)).nextValue().toString())

    @Test
    fun `valid fixtures pass`() {
        for (schema in schemas) {
            val files = FixtureLoader.list("fixtures/$schema/valid")
            assertTrue("$schema has valid fixtures", files.isNotEmpty())
            files.forEach { assertEquals(it, emptyList<String>(), errorsOf(schema, it)) }
        }
    }

    @Test
    fun `invalid fixtures fail where ajv says they fail`() {
        for (schema in schemas) {
            val expected = FixtureLoader.jsonObject("fixtures/$schema/invalid/_expected-errors.json").getJSONObject("errors")
            val files = FixtureLoader.list("fixtures/$schema/invalid").filterNot { it.endsWith("/_expected-errors.json") }
            assertEquals("$schema: every invalid fixture has an expected error", expected.keys().asSequence().toSet(), files.map { it.substringAfterLast('/') }.toSet())
            for (file in files) {
                val pointer = expected.getJSONObject(file.substringAfterLast('/')).getString("instancePath").ifEmpty { "/" }
                val errors = errorsOf(schema, file)
                assertTrue("$file should fail at $pointer, got $errors", errors.any { it.startsWith("$pointer: ") })
            }
        }
    }
}
