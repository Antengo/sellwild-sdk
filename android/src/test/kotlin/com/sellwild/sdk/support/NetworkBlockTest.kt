package com.sellwild.sdk.support

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.Description
import org.junit.runners.model.Statement
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Proves the unit-test network block (contract A8): every http/https connection fails with
 * a clear error, other protocols still work, and [NetworkBlockRule] fails a test that tried
 * the network even when the code under test swallowed the exception.
 *
 * Probe hosts use the reserved `.invalid` TLD, so nothing could resolve even if the block broke.
 */
class NetworkBlockTest {

    @get:Rule
    val network = NetworkBlockRule()

    // ── Blocking ─────────────────────────────────────────────────────────────

    @Test
    fun `https connection fails before any socket opens`() {
        network.expectAttempts()
        val url = URL("https://network-block.invalid/app/weatherbug/app.json")

        val e = assertThrows(NetworkBlockedException::class.java) { url.openConnection() as HttpURLConnection }

        assertTrue(e.message!!.contains("https://network-block.invalid/app/weatherbug/app.json"))
        assertTrue(e.message!!.contains("Network is blocked in unit tests"))
        assertEquals(listOf("https://network-block.invalid/app/weatherbug/app.json"), network.attempts)
    }

    @Test
    fun `http connection and openStream fail too`() {
        network.expectAttempts()

        assertThrows(NetworkBlockedException::class.java) { URL("http://network-block.invalid/a").openConnection() }
        assertThrows(NetworkBlockedException::class.java) { URL("http://network-block.invalid/b").openStream() }

        assertEquals(
            listOf("http://network-block.invalid/a", "http://network-block.invalid/b"),
            network.attempts,
        )
    }

    @Test
    fun `loopback is blocked as well`() {
        network.expectAttempts()

        assertThrows(NetworkBlockedException::class.java) { URL("http://127.0.0.1:1/events").openConnection() }
    }

    @Test
    fun `blocked error is an IOException so SDK offline paths run`() {
        network.expectAttempts()

        val e = assertThrows(IOException::class.java) { URL("https://network-block.invalid/").openConnection() }

        assertTrue(NetworkBlock.isBlocked(e))
        assertTrue(NetworkBlock.isBlocked(RuntimeException("wrapped", e)))
        assertFalse(NetworkBlock.isBlocked(IOException("real outage")))
        assertFalse(NetworkBlock.isBlocked(null))
    }

    @Test
    fun `file URLs still open`() {
        val resource = NetworkBlockTest::class.java.classLoader!!.getResource("support-selftest/fixture.json")!!

        val text = resource.openStream().use { it.readBytes().toString(Charsets.UTF_8) }

        assertTrue(text.contains("support-selftest"))
        assertTrue(network.attempts.isEmpty())
    }

    @Test
    fun `URLs keep their default ports and case-insensitive hosts`() {
        assertEquals(443, URL("https://network-block.invalid/").defaultPort)
        assertEquals(80, URL("http://network-block.invalid/").defaultPort)
        assertEquals(URL("https://NETWORK-BLOCK.invalid/x"), URL("https://network-block.invalid/x"))
    }

    @Test
    fun `install claims the JVM-wide factory slot once`() {
        network.expectAttempts()
        NetworkBlock.install()
        NetworkBlock.install()

        // The slot is taken, so no other code can put a real http handler back.
        val taken = assertThrows(Error::class.java) { URL.setURLStreamHandlerFactory { null } }
        assertEquals("factory already defined", taken.message)
        assertThrows(NetworkBlockedException::class.java) { URL("https://network-block.invalid/").openConnection() }
    }

    @Test
    fun `launcher session installed the block before the first test`() {
        // Proves the block is JVM-wide for tests without the rule: the JUnit Platform
        // session listener got there before any NetworkBlockRule did.
        assertEquals(NetworkBlockSessionListener.INSTALLER, NetworkBlock.installedBy())
    }

    // ── NetworkBlockRule ─────────────────────────────────────────────────────

    @Test
    fun `rule fails a test that swallowed a blocked connection`() {
        network.expectAttempts()
        val swallowing = statement {
            runCatching { URL("https://network-block.invalid/swallowed").openConnection() }
        }

        val failure = assertThrows(AssertionError::class.java) {
            NetworkBlockRule().apply(swallowing, DESCRIPTION).evaluate()
        }

        assertTrue(failure.message!!.contains("probe(NetworkBlockTest) tried to open 1 network connection(s)"))
        assertTrue(failure.message!!.contains("https://network-block.invalid/swallowed"))
    }

    @Test
    fun `rule passes a test that stayed offline`() {
        var ran = false

        NetworkBlockRule().apply(statement { ran = true }, DESCRIPTION).evaluate()

        assertTrue(ran)
    }

    @Test
    fun `rule allows attempts after expectAttempts`() {
        network.expectAttempts()
        val rule = NetworkBlockRule()
        val expecting = statement {
            rule.expectAttempts()
            runCatching { URL("https://network-block.invalid/expected").openConnection() }
        }

        rule.apply(expecting, DESCRIPTION).evaluate()

        assertEquals(listOf("https://network-block.invalid/expected"), rule.attempts)
    }

    @Test
    fun `rule keeps the test's own failure and attaches the attempts`() {
        network.expectAttempts()
        val failing = statement {
            runCatching { URL("https://network-block.invalid/then-fail").openConnection() }
            throw IllegalStateException("test failed on its own")
        }

        val failure = assertThrows(IllegalStateException::class.java) {
            NetworkBlockRule().apply(failing, DESCRIPTION).evaluate()
        }

        assertEquals("test failed on its own", failure.message)
        assertEquals(1, failure.suppressed.size)
        assertTrue(failure.suppressed[0].message!!.contains("https://network-block.invalid/then-fail"))
    }

    @Test
    fun `rule clears attempts left by an earlier test`() {
        network.expectAttempts()
        runCatching { URL("https://network-block.invalid/earlier").openConnection() }
        val rule = NetworkBlockRule()

        rule.apply(statement {}, DESCRIPTION).evaluate()

        assertTrue(rule.attempts.isEmpty())
    }

    private fun statement(body: () -> Unit) = object : Statement() {
        override fun evaluate() = body()
    }

    private companion object {
        val DESCRIPTION: Description = Description.createTestDescription("NetworkBlockTest", "probe")
    }
}
