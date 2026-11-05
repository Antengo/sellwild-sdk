package com.sellwild.sdk.support

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.platform.engine.TestDescriptor
import org.junit.platform.engine.TestExecutionResult
import org.junit.platform.engine.UniqueId
import org.junit.platform.engine.support.descriptor.AbstractTestDescriptor
import org.junit.platform.engine.support.descriptor.MethodSource
import org.junit.platform.launcher.TestExecutionListener
import org.junit.platform.launcher.TestIdentifier
import org.junit.rules.TemporaryFolder
import java.io.File
import java.net.URL
import java.util.ServiceLoader

/**
 * [NetworkBlockAuditListener] reports network attempts from tests that did not expect them,
 * with or without [NetworkBlockRule]. Each test drives a second listener by hand with probe
 * test identifiers and its own report file; the outer rule expects attempts, and the probe
 * listener consumes them before the real listener sees them.
 */
class NetworkBlockAuditListenerTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val tmp = TemporaryFolder()

    @Test
    fun `reports a connection from a test without the rule`() {
        network.expectAttempts()
        val report = File(tmp.root, "audit/testDebugUnitTest.txt")
        val audit = NetworkBlockAuditListener(report)

        audit.executionStarted(PROBE)
        runCatching { URL("https://network-block.invalid/no-rule").openConnection() }
        audit.executionFinished(PROBE, TestExecutionResult.successful())

        assertEquals(listOf("com.example.ProbeTest#probe: https://network-block.invalid/no-rule"), report.readLines())
        assertTrue(NetworkBlock.attempts().isEmpty())
    }

    @Test
    fun `ignores connections the test expected`() {
        network.expectAttempts()
        val report = File(tmp.root, "audit.txt")
        val audit = NetworkBlockAuditListener(report)

        audit.executionStarted(PROBE)
        NetworkBlockRule().expectAttempts()
        runCatching { URL("https://network-block.invalid/expected").openConnection() }
        audit.executionFinished(PROBE, TestExecutionResult.successful())

        assertFalse(report.exists())
    }

    @Test
    fun `the expected flag ends with the test that set it`() {
        network.expectAttempts()
        val report = File(tmp.root, "audit.txt")
        val audit = NetworkBlockAuditListener(report)

        audit.executionStarted(PROBE)
        NetworkBlock.expectAttempts()
        audit.executionFinished(PROBE, TestExecutionResult.successful())
        audit.executionStarted(NEXT)
        runCatching { URL("https://network-block.invalid/next").openConnection() }
        audit.executionFinished(NEXT, TestExecutionResult.successful())

        assertEquals(listOf("com.example.ProbeTest#next: https://network-block.invalid/next"), report.readLines())
    }

    @Test
    fun `attempts between tests are reported when the next one starts`() {
        network.expectAttempts()
        val report = File(tmp.root, "audit.txt")
        val audit = NetworkBlockAuditListener(report)

        audit.executionStarted(PROBE)
        audit.executionFinished(PROBE, TestExecutionResult.successful())
        // e.g. a fire-and-forget flush that outlived its test
        runCatching { URL("https://network-block.invalid/late").openConnection() }
        audit.executionStarted(NEXT)
        audit.executionFinished(NEXT, TestExecutionResult.successful())

        assertEquals(
            listOf("outside any test, before com.example.ProbeTest#next started: https://network-block.invalid/late"),
            report.readLines(),
        )
    }

    @Test
    fun `a leftover HttpStub is removed and reported`() {
        val report = File(tmp.root, "audit.txt")
        val audit = NetworkBlockAuditListener(report)

        audit.executionStarted(PROBE)
        HttpStub.install { StubResponse() }
        audit.executionFinished(PROBE, TestExecutionResult.successful())

        assertEquals(listOf("com.example.ProbeTest#probe: left an HttpStub installed (close it with use { })"), report.readLines())
        assertFalse(NetworkBlock.removeLeftoverStub())
    }

    @Test
    fun `the JUnit Platform loads the listener`() {
        val listeners = ServiceLoader.load(TestExecutionListener::class.java, javaClass.classLoader).toList()

        assertEquals(1, listeners.count { it is NetworkBlockAuditListener })
    }

    @Test
    fun `the Gradle test task sets the report file`() {
        val configured = System.getProperty(NetworkBlockAuditListener.REPORT_PROPERTY)

        assertNotNull("android/build.gradle.kts passes ${NetworkBlockAuditListener.REPORT_PROPERTY}", configured)
        assertTrue(configured!!, Regex(".*/build/network-block/test\\w+UnitTest\\.txt").matches(configured))
    }

    private class Probe(method: String) : AbstractTestDescriptor(
        UniqueId.forEngine("probe").append("method", method),
        method,
        MethodSource.from("com.example.ProbeTest", method),
    ) {
        override fun getType() = TestDescriptor.Type.TEST
    }

    private companion object {
        val PROBE: TestIdentifier = TestIdentifier.from(Probe("probe"))
        val NEXT: TestIdentifier = TestIdentifier.from(Probe("next"))
    }
}
