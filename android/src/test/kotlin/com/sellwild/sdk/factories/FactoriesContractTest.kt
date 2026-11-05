package com.sellwild.sdk.factories

import com.sellwild.sdk.support.ContractEmitter
import com.sellwild.sdk.support.ContractSchemas
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File

/**
 * Every factory variant matches its schema in-process (networknt, JSON Schema 2020-12) and is
 * emitted to contracts/out/android, where `validate.mjs --out android` checks it again with
 * ajv. Every invalid variant must fail the same schema.
 */
@RunWith(Parameterized::class)
class FactoriesContractTest(
    private val label: String,
    private val factory: ContractFactory,
    private val variant: Variant,
    private val valid: Boolean,
) {

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> = ALL_FACTORIES.flatMap { f ->
            f.variants.map { arrayOf("${f.schema} ${it.name}", f, it, true) } +
                f.invalid.map { arrayOf("${f.schema} ${it.name} (invalid)", f, it, false) }
        }
    }

    @get:Rule
    val network = NetworkBlockRule()

    private fun errors(json: Any): List<String> = when (json) {
        is JSONObject -> ContractSchemas.errors(factory.schema, json)
        is JSONArray -> ContractSchemas.errors(factory.schema, json)
        else -> throw AssertionError("$label built ${json.javaClass.name}, not JSON")
    }

    @Test
    fun `matches its schema, or fails it when invalid`() {
        val json = variant.build()

        val errors = errors(json)

        if (valid) {
            assertEquals("$label errors", emptyList<String>(), errors)
            val file = when (json) {
                is JSONObject -> ContractEmitter.emit(factory.schema, "factory-${variant.name}", json)
                else -> ContractEmitter.emit(factory.schema, "factory-${variant.name}", json as JSONArray)
            }
            assertEquals(File(ContractEmitter.outDir(), "${factory.schema}.factory-${variant.name}.json"), file)
        } else {
            assertFalse("$label must not match ${factory.schema}", errors.isEmpty())
        }
    }

    @Test
    fun `builds a fresh copy each time`() {
        val first = variant.build()
        when (first) {
            is JSONObject -> first.put("mutated-by-test", true)
            is JSONArray -> first.put("mutated-by-test")
        }

        val second = variant.build().toString()

        assertTrue("$label shares state between builds", !second.contains("mutated-by-test"))
    }
}
