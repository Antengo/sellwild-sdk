package com.sellwild.sdk.guards

import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureSeverity

/** One ApplicationExitInfo, as the pure decision reads it. */
internal data class ExitRecord(
    val reason: Int,
    val timestamp: Long,
    val description: String?,
    val trace: String?,
)

/** One clientFailure the exits produce. */
internal data class ExitReport(
    val code: String,
    val severity: String,
    val message: String,
    val stack: String?,
)

/**
 * Which past process exits to report (contracts/FAILURES.md 18.2). Pure: the shell
 * ([SellwildGuards]) reads ApplicationExitInfo and the last timestamp seen, and stores
 * [Decision.lastSeen].
 */
internal object ExitReasons {
    // ApplicationExitInfo.REASON_* (API 30), copied so this stays pure and testable.
    const val REASON_LOW_MEMORY = 3
    const val REASON_CRASH = 4
    const val REASON_CRASH_NATIVE = 5
    const val REASON_ANR = 6

    private const val SDK_PACKAGE = "com.sellwild"
    private const val MAX_FRAMES = 30

    data class Decision(val reports: List<ExitReport>, val lastSeen: Long?)

    /**
     * The reports for [records] newer than [lastSeen], oldest first, and the newest timestamp
     * seen. With no [lastSeen] (the first launch with this SDK) nothing is reported: older exits
     * happened before the SDK could have caused them.
     */
    fun decide(records: List<ExitRecord>, lastSeen: Long?): Decision {
        val newest = (records.map { it.timestamp } + listOfNotNull(lastSeen)).maxOrNull()
        if (lastSeen == null) return Decision(emptyList(), newest)
        val reports = records.filter { it.timestamp > lastSeen }.sortedBy { it.timestamp }.mapNotNull(::report)
        return Decision(reports, newest)
    }

    private fun report(record: ExitRecord): ExitReport? {
        val text = listOfNotNull(record.description, record.trace).joinToString("\n")
        val ours = text.contains(SDK_PACKAGE)
        val detail = record.description?.takeIf { it.isNotBlank() }
        return when (record.reason) {
            REASON_LOW_MEMORY -> ExitReport(
                SellwildFailureCode.SDK_MEMORY_KILLED,
                SellwildFailureSeverity.ERROR,
                "killed for low memory",
                null,
            )
            REASON_CRASH, REASON_CRASH_NATIVE -> if (!ours) {
                null
            } else {
                ExitReport(
                    SellwildFailureCode.SDK_CRASH_EXCEPTION,
                    SellwildFailureSeverity.FATAL,
                    listOfNotNull(
                        if (record.reason == REASON_CRASH) "crash" else "native crash",
                        detail
                    ).joinToString(": "),
                    sdkFrames(record.trace),
                )
            }
            REASON_ANR -> if (!ours) {
                null
            } else {
                ExitReport(
                    SellwildFailureCode.SDK_HANG_TIMEOUT,
                    SellwildFailureSeverity.ERROR,
                    listOfNotNull("ANR", detail).joinToString(": "),
                    sdkFrames(record.trace),
                )
            }
            else -> null
        }
    }

    /**
     * The frames of the first thread in [trace] that holds a Sellwild frame (an ANR dump lists
     * the main thread first), `at ` dropped, at most 30. Null when there is none.
     */
    @Suppress("ReturnCount") // one guard per missing piece
    fun sdkFrames(trace: String?): String? {
        val threads = trace?.split(Regex("\n\\s*\n")) ?: return null
        val thread = threads.firstOrNull { it.contains(SDK_PACKAGE) } ?: return null
        val frames = thread.lines().map { it.trim() }.filter { it.startsWith("at ") }.map { it.removePrefix("at ") }
        return frames.take(MAX_FRAMES).joinToString("\n").ifEmpty { null }
    }
}
