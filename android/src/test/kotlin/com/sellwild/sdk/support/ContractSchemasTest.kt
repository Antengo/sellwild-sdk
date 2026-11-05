package com.sellwild.sdk.support

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * [SchemaSet] validates JSON against JSON Schema 2020-12 offline. The self-test schemas in
 * src/test/resources/support-selftest/schemas use an https `$id` and a relative `$ref`, the
 * same shape as contracts/schemas; the network rule proves nothing was fetched.
 */
class ContractSchemasTest {

    @get:Rule
    val network = NetworkBlockRule()

    private val selftest = SchemaSet("support-selftest/schemas")

    @Test
    fun `valid document has no errors`() {
        val json = JSONObject("""{"name":"feed","createdAt":"2026-09-23T12:00:00Z","item":{"id":"abc"}}""")

        assertEquals(emptyList<String>(), selftest.errors("selftest-root", json))
        selftest.assertValid("selftest-root", json)
    }

    @Test
    fun `referenced schema is resolved from the classpath`() {
        val errors = selftest.errors("selftest-root", """{"name":"feed","item":{"id":"ABC"}}""")

        assertEquals(1, errors.size)
        assertTrue(errors[0], errors[0].startsWith("/item/id: "))
    }

    @Test
    fun `required, type and additionalProperties are enforced`() {
        val errors = selftest.errors("selftest-root", """{"name":7,"extra":true}""")

        assertEquals(errors.toString(), 3, errors.size)
        assertTrue(errors.toString(), errors.any { it.startsWith("/: ") && it.contains("'item'") })
        assertTrue(errors.toString(), errors.any { it.startsWith("/: ") && it.contains("'extra'") })
        assertTrue(errors.toString(), errors.any { it.startsWith("/name: ") && it.contains("string expected") })
    }

    @Test
    fun `formats are asserted like ajv-formats`() {
        val errors = selftest.errors("selftest-root", """{"name":"feed","createdAt":"yesterday","item":{"id":"a"}}""")

        assertEquals(1, errors.size)
        assertTrue(errors[0], errors[0].startsWith("/createdAt: ") && errors[0].contains("date-time"))
    }

    @Test
    fun `assertValid lists every error`() {
        val failure = assertThrows(AssertionError::class.java) {
            selftest.assertValid("selftest-root", """{"item":{}}""")
        }

        assertTrue(failure.message!!.startsWith("Not valid against selftest-root.schema.json:"))
        assertTrue(failure.message!!.contains("name"))
        assertTrue(failure.message!!.contains("id"))
    }

    @Test
    fun `unknown schema name fails clearly`() {
        val failure = assertThrows(AssertionError::class.java) { selftest.schema("nope") }

        assertTrue(failure.message!!.contains("support-selftest/schemas/nope.schema.json"))
    }

    @Test
    fun `every shared contract schema compiles offline and its id matches its file`() {
        val files = FixtureLoader.list("schemas").filter { it.endsWith(".schema.json") }

        for (file in files) {
            // $ref IRIs resolve by their last segment, so an $id must end in the file name.
            val id = FixtureLoader.jsonObject(file).optString("\$id")
            if (id.isNotEmpty()) assertEquals(file, file.substringAfterLast('/'), id.substringAfterLast('/'))
            ContractSchemas.schema(file.removePrefix("schemas/").removeSuffix(".schema.json"))
        }
        assertTrue(network.attempts.isEmpty())
    }
}
