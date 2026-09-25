package com.sellwild.sdk.failures

import android.content.Context
import com.sellwild.sdk.SellwildEvent
import com.sellwild.sdk.SellwildEventQueue
import com.sellwild.sdk.SellwildSDK
import java.util.concurrent.atomic.AtomicInteger

/**
 * What logFailure reads on every call (FAILURES.md 3.2). Change it with
 * [SellwildFailures.setContext].
 *
 * @property partnerCode set by [SellwildSDK.configure] before its fetch, so config
 *   failures carry the partner.
 * @property debug the SDK debug flag (config.debug). It turns on the debug echo and
 *   [SellwildLog].
 * @property eventsEnabled the raw remote EVENTS_ENABLED value (Boolean, Number, String,
 *   JSON object ...); the pure core coerces it. Null means unset, which means on.
 * @property failuresEnabled the raw remote FAILURES_ENABLED value. Null means on.
 * @property failuresSampleRate the raw remote FAILURES_SAMPLE_RATE value. Null means 1.
 * @property failuresEnabledOverride a local switch that wins over [failuresEnabled].
 * @property wrapper `react-native` or `flutter` when the SDK is hosted by a wrapper.
 */
data class SellwildFailureContext(
    val partnerCode: String? = null,
    val client: String = "android",
    val clientVersion: String = SellwildSDK.SDK_VERSION,
    val debug: Boolean = false,
    val eventsEnabled: Any? = null,
    val failuresEnabled: Any? = null,
    val failuresSampleRate: Any? = null,
    val failuresEnabledOverride: Boolean? = null,
    val wrapper: String? = null,
)

/** Where logFailure sends what it emits: the events queue, or a fake in tests. */
internal interface FailureSink {
    /**
     * The queue uid. Sampling and the wire use the same one (FAILURES.md 8.3). Read once,
     * when the sink is bound.
     */
    val uid: String

    fun push(event: FailureEvent, flushNow: Boolean)
}

/**
 * Sends through [SellwildEventQueue.track], which POSTs every event at once, so
 * `flushNow` needs nothing more on Android (FAILURES.md 8.1).
 */
internal data class QueueFailureSink(val queue: SellwildEventQueue) : FailureSink {
    override val uid: String get() = queue.uid

    override fun push(event: FailureEvent, flushNow: Boolean) {
        queue.track(
            SellwildEvent(
                event = event.event,
                action = event.action,
                label = event.label,
                attributes = event.attributes,
                uid = event.uid,
                createdTime = event.createdTime,
            ),
        )
    }
}

/**
 * logFailure for Android (FAILURES.md 3.4): the thin impure shell around
 * [FailuresCore]. Every failure path in the SDK catches its error and calls [log] with
 * a [SellwildFailureCode]; nothing prints a failure.
 *
 * The shell reads the context, uid and clock, asks the pure gate, and pushes the event
 * into the existing events queue. It never throws, never blocks on the network, and
 * never reports a failure of its own, because that would recurse: those are counted
 * instead (the one catch that does not call [log]).
 *
 * [SellwildSDK.configure] has no Context, so the queue may not exist yet when a config
 * failure happens. Until a queue is attached ([attach], the first
 * [SellwildEventQueue.shared], or the first listings fetch) calls are held, up to one
 * session's worth, and decided when it arrives, with the context and time of the call
 * and the queue's uid. The events kill switch loaded since then also applies: see [bind].
 */
object SellwildFailures {
    private val lock = Any()

    // Set while log() runs on this thread, so a nested call from inside it (a sink or
    // printer that reports) returns at once. Per thread rather than one global flag:
    // a failure logged at the same moment on another thread is still reported.
    private val inLog = ThreadLocal<Boolean>()

    @Volatile
    private var settings = SellwildFailureContext()
    private var state = FailureState()
    private var bound: Bound? = null
    private val pending = ArrayList<Pending>()
    private val internalErrors = AtomicInteger()

    /** Epoch milliseconds. Tests replace it. */
    @Volatile
    internal var clock: () -> Long = System::currentTimeMillis

    private class Pending(val input: FailureInput, val context: FailureContext, val now: Long)

    /** The attached sink and its uid, read once when it was bound. */
    private class Bound(val sink: FailureSink, val uid: String)

    private class Send(val sink: FailureSink, val event: FailureEvent, val flushNow: Boolean)

    /** The context logFailure reads now. */
    val context: SellwildFailureContext get() = settings

    /**
     * Reports one failure. Call it from the catch (or failure branch) that handles it,
     * once, at the lowest layer that sees it (FAILURES.md 9).
     *
     * @param code a [SellwildFailureCode] constant.
     * @param component a [SellwildFailureComponent] constant.
     * @param severity a [SellwildFailureSeverity] constant; `error` when null.
     * @param error the caught error: its class name, message and first frames are sent,
     *   sanitized.
     * @param message a short, PII-free description. Never listing text, user data or URLs
     *   with query strings.
     * @param url only its host is sent.
     */
    @JvmStatic
    fun log(
        code: String,
        component: String,
        severity: String? = null,
        error: Throwable? = null,
        message: String? = null,
        httpStatus: Int? = null,
        url: String? = null,
        zoneId: String? = null,
    ) {
        if (inLog.get() == true) return
        inLog.set(true)
        try {
            runCatching {
                record(toInput(code, component, severity, error, message, httpStatus, url, zoneId))
            }.onFailure(::internalError)
        } finally {
            inLog.set(false)
        }
    }

    /**
     * Updates the context atomically: `setContext { it.copy(partnerCode = "weatherbug") }`.
     * Also turns [SellwildLog] on or off with [SellwildFailureContext.debug].
     */
    @JvmStatic
    fun setContext(update: (SellwildFailureContext) -> SellwildFailureContext) {
        runCatching {
            val next = synchronized(lock) { update(settings).also { settings = it } }
            SellwildLog.enabled = next.debug
        }.onFailure(::internalError)
    }

    /** Called by a wrapper's native bridge (`react-native`, `flutter`) so failures carry it. */
    @JvmStatic
    fun setWrapper(wrapper: String) {
        setContext { it.copy(wrapper = wrapper) }
    }

    /**
     * Sends failures through the process-wide events queue from now on, including any
     * held before a Context existed. [SellwildSDK.prewarm] and every
     * [com.sellwild.sdk.SellwildAPIClient] fetch call it, and creating the queue
     * ([SellwildEventQueue.shared]) attaches it too; calling it again is harmless.
     */
    @JvmStatic
    fun attach(context: Context) {
        runCatching { attachQueue(SellwildEventQueue.shared(context)) }.onFailure(::internalError)
    }

    internal fun attachQueue(queue: SellwildEventQueue) {
        bind(QueueFailureSink(queue))
    }

    /**
     * Sets where events go and decides every held call. A null sink holds calls again.
     *
     * The sink's uid is read once, here, before anything changes and outside the lock (the
     * queue's uid reads SharedPreferences), and every later call reuses it. If reading it
     * fails, nothing is bound and the held calls wait for the next attach.
     *
     * EVENTS_ENABLED is a send-time switch: the queue checks it when an event goes out, and
     * a queue this attach just created has not read the config yet. So when the value loaded
     * since the calls were held is off, they are dropped (FAILURES.md 10.1), even though
     * each call's own context had it on.
     */
    internal fun bind(next: FailureSink?) {
        runCatching {
            val target = next?.let { Bound(it, it.uid) }
            val sends = synchronized(lock) {
                if (bound?.sink == next) return@synchronized emptyList()
                bound = target
                if (target == null) return@synchronized emptyList()
                val held = pending.toList()
                pending.clear()
                if (!FailuresCore.coerceFlag(settings.eventsEnabled)) return@synchronized emptyList()
                held.mapNotNull { decide(target, it.input, it.context, it.now) }
            }
            sends.forEach { send ->
                runCatching { send.sink.push(send.event, send.flushNow) }.onFailure(::internalError)
            }
        }.onFailure(::internalError)
    }

    /** Clears state, context, sink, held calls and counters. Tests only. */
    @JvmStatic
    fun resetForTests() {
        synchronized(lock) {
            settings = SellwildFailureContext()
            state = FailureState()
            bound = null
            pending.clear()
        }
        internalErrors.set(0)
        clock = System::currentTimeMillis
        inLog.remove()
        SellwildLog.resetForTests()
    }

    /** Errors inside logFailure itself since the last [resetForTests]. */
    internal val internalErrorCount: Int get() = internalErrors.get()

    internal val pendingCount: Int get() = synchronized(lock) { pending.size }

    internal val gateState: FailureState get() = synchronized(lock) { state }

    private fun record(input: FailureInput) {
        val current = settings
        val context = current.toCore()
        val now = clock()
        var outcome: String? = null
        val send = synchronized(lock) {
            val target = bound
            if (target == null) {
                if (pending.size < FailuresCore.SESSION_EMITS) {
                    pending += Pending(input, context, now)
                    outcome = HELD
                } else {
                    outcome = HELD_FULL
                }
                null
            } else {
                val decision = FailuresCore.decideFailure(state, input, context, target.uid, now)
                state = decision.state
                outcome = decision.reason
                decision.event?.let { Send(target.sink, it, decision.flushNow) }
            }
        }
        // Send before the echo, so a printer that throws cannot cost the event.
        send?.let { it.sink.push(it.event, it.flushNow) }
        if (current.debug) SellwildLog.debug(FailuresCore.echoLine(input, outcome))
    }

    // Caller holds [lock].
    private fun decide(target: Bound, input: FailureInput, context: FailureContext, now: Long): Send? {
        val decision = FailuresCore.decideFailure(state, input, context, target.uid, now)
        state = decision.state
        return decision.event?.let { Send(target.sink, it, decision.flushNow) }
    }

    private fun internalError(t: Throwable) {
        internalErrors.incrementAndGet()
        // The one catch that does not report (FAILURES.md 3.4): reporting would recurse.
        // A printer that throws while echoing it is counted too, and not echoed again.
        if (settings.debug) {
            runCatching { SellwildLog.debug("[Sellwild] failure internal ${t.javaClass.name}") }
                .onFailure { internalErrors.incrementAndGet() }
        }
    }

    private fun SellwildFailureContext.toCore() = FailureContext(
        partnerCode = partnerCode,
        client = client,
        clientVersion = clientVersion,
        wrapper = wrapper,
        eventsEnabled = eventsEnabled,
        failuresEnabled = failuresEnabledOverride ?: failuresEnabled,
        failuresSampleRate = failuresSampleRate,
    )

    /** Echo outcome while no queue is attached: the call is held (see the class doc). */
    internal const val HELD = "held"

    /** Echo outcome when the hold is full: the call is dropped. */
    internal const val HELD_FULL = "held_full"

    internal fun toInput(
        code: String,
        component: String,
        severity: String?,
        error: Throwable?,
        message: String?,
        httpStatus: Int?,
        url: String?,
        zoneId: String?,
    ) = FailureInput(
        code = code,
        component = component,
        severity = severity,
        errName = error?.let { it.javaClass.simpleName },
        errMessage = capInput(error?.message, MESSAGE_INPUT_MAX),
        message = capInput(message, MESSAGE_INPUT_MAX),
        stack = capInput(error?.let(::stackOf), STACK_INPUT_MAX),
        httpStatus = httpStatus,
        url = url,
        zoneId = zoneId,
    )

    /**
     * Input cap (FAILURES.md 3.3 item 4): the most UTF-16 units of message and error message
     * handed to the pure core. Its sanitizer patterns backtrack superlinearly on long runs of
     * letters and digits, and log must never block. Only 200 code points are ever sent, so
     * the cut changes nothing but pathological input.
     */
    internal const val MESSAGE_INPUT_MAX = 1000

    /** Input cap for the stack text (5 frames of at most 800 code points are ever sent). */
    internal const val STACK_INPUT_MAX = 2000

    /**
     * The first [max] UTF-16 units of [text]. A surrogate pair the cut splits leaves a lone
     * high surrogate, which the core's cleanText turns into U+FFFD, as on every platform.
     */
    internal fun capInput(text: String?, max: Int): String? =
        if (text != null && text.length > max) text.substring(0, max) else text

    /**
     * The first frames of [error], one `Class.method(File.kt:line)` per line, with no
     * header line (FAILURES.md 3.3). Built by hand: the JDK's StackTraceElement.toString
     * adds module and loader prefixes that ART does not.
     */
    internal fun stackOf(error: Throwable): String =
        error.stackTrace.take(FailuresCore.STACK_FRAMES).joinToString("\n") { e ->
            val where = when {
                e.fileName == null -> "Unknown Source"
                e.lineNumber >= 0 -> "${e.fileName}:${e.lineNumber}"
                else -> e.fileName
            }
            "${e.className}.${e.methodName}($where)"
        }
}
