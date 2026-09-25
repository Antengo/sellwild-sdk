package com.sellwild.sdk.support

import org.junit.platform.engine.TestExecutionResult
import org.junit.platform.engine.support.descriptor.ClassSource
import org.junit.platform.engine.support.descriptor.MethodSource
import org.junit.platform.launcher.TestExecutionListener
import org.junit.platform.launcher.TestIdentifier
import org.junit.platform.launcher.TestPlan
import java.io.File

/**
 * Makes the network block loud for every test, not only those with [NetworkBlockRule]
 * (contract A8). SDK code swallows the blocked IOException, so without this a test that forgot
 * the rule would pass after trying the network.
 *
 * Around each test and container it takes [NetworkBlock.takeUnexpectedAttempts] and appends
 * each one to [report] as `<where>: <url>`. Attempts seen when a test starts were made outside
 * any test: in class setup, or by a background job (a fire-and-forget flush) of the test
 * before. It also removes and reports an [HttpStub] left installed.
 *
 * android/build.gradle.kts passes [REPORT_PROPERTY] and fails the test task when the report
 * is not empty; a JUnit listener cannot fail a test itself. Without the property (e.g. a run
 * from the IDE) nothing is written and only [NetworkBlockRule] checks. Registered in
 * `src/test/resources/META-INF/services/org.junit.platform.launcher.TestExecutionListener`.
 */
class NetworkBlockAuditListener(
    private val report: File? = System.getProperty(REPORT_PROPERTY)?.takeIf { it.isNotBlank() }?.let(::File),
) : TestExecutionListener {

    override fun executionStarted(testIdentifier: TestIdentifier) {
        checkpoint("outside any test, before ${label(testIdentifier)} started")
    }

    override fun executionFinished(testIdentifier: TestIdentifier, testExecutionResult: TestExecutionResult) {
        checkpoint(label(testIdentifier))
    }

    override fun testPlanExecutionFinished(testPlan: TestPlan) {
        checkpoint("outside any test, after the last one finished")
    }

    private fun checkpoint(where: String) {
        val lines = NetworkBlock.takeUnexpectedAttempts().map { "$where: $it" }.toMutableList()
        if (NetworkBlock.removeLeftoverStub()) lines += "$where: left an HttpStub installed (close it with use { })"
        if (lines.isEmpty() || report == null) return
        report.parentFile?.mkdirs()
        report.appendText(lines.joinToString("\n", postfix = "\n"), Charsets.UTF_8)
    }

    private fun label(id: TestIdentifier): String =
        when (val source = id.source.orElse(null)) {
            is MethodSource -> "${source.className}#${source.methodName}"
            is ClassSource -> source.className
            else -> id.displayName
        }

    companion object {
        const val REPORT_PROPERTY = "sellwild.test.networkBlock.report"
    }
}
