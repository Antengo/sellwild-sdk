package com.sellwild.sdk.failures

import com.sellwild.sdk.support.ContractSchemas
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * The pure core reproduces every golden vector (FAILURES.md 12): the same event or null,
 * flushNow, reason and stateAfter. Kotlin strings hold lone UTF-16 surrogates, so the utf16
 * file runs too.
 */
@RunWith(Parameterized::class)
class FailuresGoldenVectorsTest(private val name: String, private val vector: JSONObject) {

    companion object {
        private val FILES = listOf("golden/log-failure.vectors.json", "golden/log-failure.utf16.vectors.json")

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun vectors(): List<Array<Any>> = FILES.flatMap { file ->
            val vectors = FixtureLoader.jsonObject(file).getJSONArray("vectors")
            (0 until vectors.length()).map { i ->
                val v = vectors.getJSONObject(i)
                arrayOf<Any>("${file.substringAfterLast('/')} ${v.getString("name")}", v)
            }
        }
    }

    @Test
    fun `reproduces the vector`() {
        val context = vector.getJSONObject("context")
        val expected = vector.getJSONObject("expected")

        val decision = FailuresCore.decideFailure(
            stateOf(vector.optJSONObject("stateBefore")),
            inputOf(vector.getJSONObject("input")),
            contextOf(context),
            context.value("uid") as String?,
            context.getLong("now"),
        )

        assertEquals("$name event", plain(expected.get("event")), decision.event?.toPlain())
        assertEquals("$name flushNow", expected.getBoolean("flushNow"), decision.flushNow)
        assertEquals("$name reason", expected.value("reason"), decision.reason)
        assertEquals("$name stateAfter", plain(expected.getJSONObject("stateAfter")), decision.state.toPlain())
        decision.event?.let { event ->
            assertEquals(
                "$name attributes follow the wire order",
                FailuresCore.ATTRIBUTE_KEYS.filter { it in event.attributes },
                event.attributes.keys.toList(),
            )
            // Every emitted event must also be a valid client-failure-event, as Android builds it.
            ContractSchemas.assertValid("client-failure-event", event.toJson())
        }
    }
}
