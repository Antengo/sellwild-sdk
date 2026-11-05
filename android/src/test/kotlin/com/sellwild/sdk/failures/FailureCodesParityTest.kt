package com.sellwild.sdk.failures

import com.sellwild.sdk.support.FixtureLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Modifier

/**
 * The Android registry mirror equals the codes in contracts/failure-codes.json whose
 * `clients` include `android` (FAILURES.md 4.2), and the component and severity constants
 * equal the contract's enums.
 */
class FailureCodesParityTest {

    private fun registry(): List<Pair<String, List<String>>> {
        val codes = FixtureLoader.jsonArray("failure-codes.json")
        return (0 until codes.length()).map { i ->
            val c = codes.getJSONObject(i)
            val clients = c.getJSONArray("clients")
            c.getString("code") to (0 until clients.length()).map { clients.getString(it) }
        }
    }

    /** `const val` String fields of [type], name to value. */
    private fun constants(type: Class<*>): Map<String, String> =
        type.declaredFields
            .filter { Modifier.isStatic(it.modifiers) && Modifier.isFinal(it.modifiers) && it.type == String::class.java }
            .associate { it.name to it.get(null) as String }

    @Test
    fun `ALL equals the android codes in the registry, in code order`() {
        val android = registry().filter { "android" in it.second }.map { it.first }

        assertEquals(android.sorted(), SellwildFailureCode.ALL)
    }

    @Test
    fun `every constant is in ALL, named after its code`() {
        val constants = constants(SellwildFailureCode::class.java)

        assertEquals(SellwildFailureCode.ALL.toSet(), constants.values.toSet())
        assertEquals(SellwildFailureCode.ALL.size, constants.size)
        constants.forEach { (name, code) -> assertEquals(code.uppercase().replace('.', '_'), name) }
    }

    @Test
    fun `every mirrored code passes the pure core format check`() {
        SellwildFailureCode.ALL.forEach { assertEquals(it, FailuresCore.normalizeCode(it)) }
    }

    @Test
    fun `component constants are contract components`() {
        val components = constants(SellwildFailureComponent::class.java).values

        assertTrue(components.isNotEmpty())
        components.forEach { assertEquals(it, FailuresCore.normalizeComponent(it)) }
    }

    @Test
    fun `severity constants are the contract severities`() {
        assertEquals(
            FailuresCore.SEVERITIES.toSet(),
            constants(SellwildFailureSeverity::class.java).values.toSet(),
        )
    }
}
