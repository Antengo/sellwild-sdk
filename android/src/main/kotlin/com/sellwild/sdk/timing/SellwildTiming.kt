package com.sellwild.sdk.timing

import android.os.SystemClock
import com.sellwild.sdk.SellwildEvent
import com.sellwild.sdk.SellwildEventQueue
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures

/**
 * sdkTiming shell (contracts/FAILURES.md section 18.1): records how long a step took, sends
 * the sampled sdkTiming event through the events queue, and logs the step's `*.slow`
 * clientFailure when it is over its budget. Decisions live in [TimingCore]. Never throws.
 *
 * Measurements made before a queue is attached (configure() has no Context) are held, up to
 * [TimingCore.SESSION_TIMINGS], and decided when [attachQueue] runs.
 */
internal object SellwildTiming {
    private val lock = Any()
    private var state = TimingState()
    private var queue: SellwildEventQueue? = null
    private val pending = ArrayList<Pair<TimingInput, Long>>()
    private val claimed = HashSet<String>()

    /**
     * True the first time [key] is claimed in this process: `feed.firstListing` once, and
     * `ad.firstLoad:<zone>` once per zone.
     */
    fun claimOnce(key: String): Boolean = synchronized(lock) { claimed.add(key) }

    /** Raw TIMING_ENABLED, TIMING_SAMPLE_RATE and the remote config, set by configure(). */
    @Volatile
    var remote: org.json.JSONObject? = null

    /** Tests: where events go instead of the queue. */
    @Volatile
    var push: ((TimingEvent) -> Unit)? = null

    /** Epoch ms for createdTime, and a monotonic clock for durations. Tests replace them. */
    @Volatile
    var clock: () -> Long = System::currentTimeMillis

    @Volatile
    var monotonic: () -> Long = SystemClock::elapsedRealtime

    /** Errors inside record itself (counted, never reported). */
    @Volatile
    var internalErrors = 0
        private set

    /** Sends timings through [queue] from now on, the held ones first. */
    fun attachQueue(queue: SellwildEventQueue) {
        val held = synchronized(lock) {
            if (this.queue === queue) return
            this.queue = queue
            pending.toList().also { pending.clear() }
        }
        held.forEach { (input, now) -> decideAndSend(input, now) }
    }

    /**
     * Records [ms] for [step]. Logs `*.slow` when over the budget (not sampled by timing),
     * then sends the sdkTiming event if this session is sampled.
     */
    fun record(step: String, ms: Long, zoneId: String? = null) {
        runCatching {
            val remoteNow = remote
            val budget = TimingCore.budgetFor(step, remoteNow)
            if (budget != null && ms > budget) {
                SellwildFailures.log(
                    code = TimingCore.SLOW_CODES.getValue(step),
                    component = when (step) {
                        "config.fetch" -> SellwildFailureComponent.REMOTE_CONFIG
                        "listings.fetch" -> SellwildFailureComponent.LISTINGS
                        else -> SellwildFailureComponent.BANNER
                    },
                    severity = SellwildFailureSeverity.WARN,
                    message = "$step took $ms ms",
                    zoneId = zoneId,
                    context = mapOf("ms" to ms, "budgetMs" to budget),
                )
            }
            val input = TimingInput(step, ms, zoneId)
            val now = clock()
            val attached = synchronized(lock) {
                val ready = queue != null || push != null
                if (!ready && pending.size < TimingCore.SESSION_TIMINGS) pending += input to now
                ready
            }
            if (attached) decideAndSend(input, now)
        }.onFailure { internalErrors++ }
    }

    /** Starts a timer; calling the result records [step] once and returns the ms. */
    fun start(step: String, zoneId: String? = null): () -> Long {
        val started = monotonic()
        return {
            val ms = monotonic() - started
            record(step, ms, zoneId)
            ms
        }
    }

    private fun decideAndSend(input: TimingInput, now: Long) {
        runCatching {
            val failures = SellwildFailures.context
            val remoteNow = remote
            val target = queue
            val context = TimingContext(
                partnerCode = failures.partnerCode,
                client = failures.client,
                clientVersion = failures.clientVersion,
                appId = failures.appId,
                appVersion = failures.appVersion,
                os = failures.os,
                device = failures.device,
                eventsEnabled = failures.eventsEnabled,
                timingEnabled = remoteNow?.opt("TIMING_ENABLED")?.takeIf { it != org.json.JSONObject.NULL },
                timingSampleRate = remoteNow?.opt("TIMING_SAMPLE_RATE")?.takeIf { it != org.json.JSONObject.NULL },
            )
            val uid = target?.uid
            val event = synchronized(lock) {
                val decision = TimingCore.decideTiming(state, input, context, uid, now)
                state = decision.state
                decision.event
            } ?: return@runCatching
            val sink = push
            if (sink != null) {
                sink(event)
            } else {
                target?.track(
                    SellwildEvent(
                        event.event,
                        event.action,
                        event.label,
                        event.attributes,
                        event.uid,
                        event.createdTime
                    )
                )
            }
        }.onFailure { internalErrors++ }
    }

    /** Back to a fresh session. Tests only. */
    fun resetForTests() {
        synchronized(lock) {
            state = TimingState()
            queue = null
            pending.clear()
            claimed.clear()
        }
        remote = null
        push = null
        clock = System::currentTimeMillis
        monotonic = SystemClock::elapsedRealtime
        internalErrors = 0
    }
}
