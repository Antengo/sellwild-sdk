package com.sellwild.sdk.support

import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement
import java.io.IOException
import java.net.InetAddress
import java.net.Proxy
import java.net.URL
import java.net.URLConnection
import java.net.URLStreamHandler
import java.net.URLStreamHandlerFactory
import java.util.function.Function

/**
 * Unit tests never touch the network (contract amendment A8).
 *
 * [install] claims the JVM-wide `URL.setURLStreamHandlerFactory` slot once, and from then on
 * every http/https connection in the test JVM fails with [NetworkBlockedException]. Nothing
 * can put a real handler back, because the JDK allows only one factory per JVM.
 * [NetworkBlockSessionListener] installs it when the JUnit Platform launcher starts, before
 * the first test class loads, so the block also covers tests that never mention it.
 *
 * Every blocked attempt is recorded, because production code usually swallows the IOException
 * (most SDK fetches sit inside `runCatching`). [NetworkBlockRule] fails a test that made one,
 * and [NetworkBlockAuditListener] fails the Gradle test task for any test that made one
 * without [NetworkBlockRule.expectAttempts], with or without the rule.
 *
 * A test that needs a response installs an [HttpStub]; the handler asks it before blocking.
 *
 * Robolectric loads test classes again in its sandbox class loader, so this object can exist
 * twice in one JVM. The shared state (installer, attempt log, expected flag, stub) therefore
 * lives in JVM-wide system properties, and [isBlocked] matches the exception by class name,
 * not by type.
 *
 * Only URL-based clients (HttpURLConnection, URL.openStream) pass through the factory. Raw
 * sockets do not; the SDK opens none.
 */
object NetworkBlock {
    private const val INSTALLED_KEY = "sellwild.test.networkBlock.installed"
    private const val ATTEMPTS_KEY = "sellwild.test.networkBlock.attempts"
    private const val EXPECTED_KEY = "sellwild.test.networkBlock.expected"
    // Not a string: a java.util.function.Function, the one type both class loaders share.
    private const val STUB_KEY = "sellwild.test.networkBlock.stub"
    private const val MAX_CAUSES = 32

    /**
     * Claims the JVM-wide URL handler factory. Idempotent and safe from any class loader;
     * [by] names the first installer for [installedBy].
     */
    fun install(by: String = "NetworkBlockRule") {
        synchronized(System.getProperties()) {
            if (System.getProperty(INSTALLED_KEY) != null) return
            try {
                URL.setURLStreamHandlerFactory(BlockingFactory)
            } catch (e: Error) {
                throw IllegalStateException(
                    "NetworkBlock could not claim URL.setURLStreamHandlerFactory: another " +
                        "factory is already installed in this JVM, so tests cannot guarantee " +
                        "they stay off the network.",
                    e,
                )
            }
            System.setProperty(INSTALLED_KEY, by)
        }
    }

    /** Who installed the block first in this JVM, or null if nothing has. */
    fun installedBy(): String? = System.getProperty(INSTALLED_KEY)

    /** URLs of the blocked connection attempts since the last [clearAttempts], oldest first. */
    fun attempts(): List<String> =
        System.getProperty(ATTEMPTS_KEY).orEmpty().lines().filter { it.isNotEmpty() }

    fun clearAttempts() {
        System.clearProperty(ATTEMPTS_KEY)
    }

    /** Marks the running test's attempts as expected, for [NetworkBlockAuditListener]. */
    fun expectAttempts() {
        System.setProperty(EXPECTED_KEY, "true")
    }

    /**
     * The attempts made since the last call, unless [expectAttempts] was called in that time.
     * Clears both, so each attempt is judged once.
     */
    fun takeUnexpectedAttempts(): List<String> =
        synchronized(System.getProperties()) {
            val made = attempts()
            val expected = System.getProperty(EXPECTED_KEY) != null
            clearAttempts()
            System.clearProperty(EXPECTED_KEY)
            if (expected) emptyList() else made
        }

    /** Removes an [HttpStub] a test left installed. True when there was one. */
    fun removeLeftoverStub(): Boolean =
        synchronized(System.getProperties()) { System.getProperties().remove(STUB_KEY) != null }

    internal fun setStub(opener: Function<URL, URLConnection?>) {
        synchronized(System.getProperties()) {
            check(System.getProperties()[STUB_KEY] == null) {
                "Another HttpStub is still installed; close it (HttpStub.install(...).use { }) first."
            }
            System.getProperties()[STUB_KEY] = opener
        }
    }

    internal fun clearStub(opener: Function<URL, URLConnection?>) {
        synchronized(System.getProperties()) {
            if (System.getProperties()[STUB_KEY] === opener) System.getProperties().remove(STUB_KEY)
        }
    }

    /** The installed [HttpStub]'s connection for [url], or null to block it. */
    internal fun stubbed(url: URL): URLConnection? {
        @Suppress("UNCHECKED_CAST")
        val opener = System.getProperties()[STUB_KEY] as? Function<URL, URLConnection?> ?: return null
        return opener.apply(url)
    }

    /** True when [t], or a cause of it, is the block's failure. Works across class loaders. */
    fun isBlocked(t: Throwable?): Boolean =
        generateSequence(t) { it.cause }.take(MAX_CAUSES).any { it.javaClass.name == NetworkBlockedException::class.java.name }

    /** The blocking handler for http/https; null lets the JDK handle every other protocol. */
    private fun handlerFor(protocol: String): URLStreamHandler? =
        when (protocol.lowercase()) {
            "http" -> BlockingUrlHandler(80)
            "https" -> BlockingUrlHandler(443)
            else -> null
        }

    internal fun record(url: URL) {
        synchronized(System.getProperties()) {
            val previous = System.getProperty(ATTEMPTS_KEY).orEmpty()
            val entry = url.toExternalForm().replace('\n', ' ')
            System.setProperty(ATTEMPTS_KEY, if (previous.isEmpty()) entry else "$previous\n$entry")
        }
    }

    private object BlockingFactory : URLStreamHandlerFactory {
        override fun createURLStreamHandler(protocol: String): URLStreamHandler? = handlerFor(protocol)
    }
}

/**
 * Serves a connection from the installed [HttpStub], else fails it with
 * [NetworkBlockedException] and records it. Parsing, ports and equality behave like the JDK
 * handler, minus DNS.
 */
private class BlockingUrlHandler(private val port: Int) : URLStreamHandler() {
    override fun openConnection(u: URL): URLConnection = NetworkBlock.stubbed(u) ?: throw block(u)

    override fun openConnection(u: URL, p: Proxy?): URLConnection = openConnection(u)

    override fun getDefaultPort(): Int = port

    // URL.equals/hashCode would otherwise resolve the host, which is a DNS lookup.
    override fun getHostAddress(u: URL): InetAddress? = null

    override fun hostsEqual(u1: URL, u2: URL): Boolean =
        u1.host.orEmpty().equals(u2.host.orEmpty(), ignoreCase = true)

    private fun block(u: URL): NetworkBlockedException {
        NetworkBlock.record(u)
        return NetworkBlockedException(u)
    }
}

/**
 * Thrown when a unit test opens an http/https connection. It is an IOException so the SDK's
 * own network-failure paths run exactly as they would offline.
 */
class NetworkBlockedException(url: URL) : IOException(
    "Network is blocked in unit tests (contract A8): ${url.toExternalForm()}. " +
        "Inject a fake sender or HTTP seam instead of opening a real connection.",
)

/**
 * Installs [NetworkBlock] and fails any test that tried to open a connection, listing the
 * URLs. A test that exercises the blocked path on purpose calls [expectAttempts] first and
 * then asserts on [attempts].
 *
 * ```
 * @get:Rule val network = NetworkBlockRule()
 * ```
 */
class NetworkBlockRule : TestRule {
    @Volatile private var attemptsExpected = false

    /** Blocked attempts made so far in the running test. */
    val attempts: List<String> get() = NetworkBlock.attempts()

    /** Lets the running test make blocked attempts without failing, here and in [NetworkBlockAuditListener]. */
    fun expectAttempts() {
        attemptsExpected = true
        NetworkBlock.expectAttempts()
    }

    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            NetworkBlock.install()
            NetworkBlock.clearAttempts()
            attemptsExpected = false
            try {
                base.evaluate()
            } catch (t: Throwable) {
                unexpectedAttempts(description)?.let(t::addSuppressed)
                throw t
            }
            unexpectedAttempts(description)?.let { throw it }
        }
    }

    private fun unexpectedAttempts(description: Description): AssertionError? {
        val made = NetworkBlock.attempts()
        if (attemptsExpected || made.isEmpty()) return null
        return AssertionError(
            "${description.displayName} tried to open ${made.size} network connection(s). " +
                "Unit tests must not touch the network (contract A8); inject a fake instead:\n" +
                made.joinToString("\n") { "  $it" },
        )
    }
}
