package com.sellwild.sdk.failures

// Pure core of logFailure: a Kotlin port of contracts/reference/log-failure.mjs
// (contracts/FAILURES.md sections 5-7). No I/O, clock or globals: SellwildFailures
// reads the flags, uid and clock, calls [FailuresCore.decideFailure] and pushes.
//
// Every platform must reproduce contracts/golden/log-failure.vectors.json and the
// utf16 file exactly, so this file follows the reference function by function.
// Inputs are `Any?` because the reference takes untyped JSON and the vectors pass
// wrong types on purpose (a numeric code, a boolean sample rate).
//
// Units: string lengths are Unicode code points, sizes are UTF-8 bytes, times are
// epoch milliseconds.

/** What the shell hands the gate. Missing and null are the same for every field. */
internal data class FailureInput(
    val code: Any? = null,
    val component: Any? = null,
    val severity: Any? = null,
    val errName: Any? = null,
    val errMessage: Any? = null,
    val message: Any? = null,
    val stack: Any? = null,
    val httpStatus: Any? = null,
    val url: Any? = null,
    val zoneId: Any? = null,
    /** Call-site context: a Map (or JSONObject) of strings and finite numbers, sent as `ctx.<key>`. */
    val context: Any? = null,
)

/**
 * The context fields the gate reads. The flags are the raw remote values (a
 * boolean, number, string, JSON object ...); the core coerces them.
 */
internal data class FailureContext(
    val partnerCode: Any? = null,
    val client: Any? = null,
    val clientVersion: Any? = null,
    val wrapper: Any? = null,
    val release: Any? = null,
    val appId: Any? = null,
    val appVersion: Any? = null,
    val os: Any? = null,
    val device: Any? = null,
    val slug: Any? = null,
    val eventsEnabled: Any? = null,
    val failuresEnabled: Any? = null,
    val failuresSampleRate: Any? = null,
)

/** One dedupe entry. */
internal data class FailureKey(
    val key: String,
    val lastEmitAt: Long,
    val suppressed: Int,
    val emits: Int,
)

/** Gate state for one session. [keys] run from least to most recently used. */
internal data class FailureState(
    val sessionCount: Int = 0,
    val keys: List<FailureKey> = emptyList(),
)

/** One clientFailure event. [attributes] keeps the wire order of [FailuresCore.ATTRIBUTE_KEYS]. */
internal data class FailureEvent(
    val action: String,
    val label: String,
    val attributes: Map<String, String>,
    val uid: String,
    val createdTime: Long,
) {
    val event: String get() = FailuresCore.EVENT_NAME
}

/** [event] is null when dropped, and [reason] names the gate that dropped it. */
internal data class FailureDecision(
    val state: FailureState,
    val event: FailureEvent?,
    val flushNow: Boolean,
    val reason: String?,
)

internal object FailuresCore {
    const val CONTRACT_VERSION = "2"
    const val EVENT_NAME = "clientFailure"
    const val INVALID_CODE = "client.code.invalid"
    const val UNKNOWN = "unknown"

    val COMPONENTS = listOf(
        "configure", "remoteConfig", "listings", "localized", "feed", "banner", "native",
        "video", "house", "bridge", "webview", "widget", "shorts", "tv", "flipcard",
        "growthcode", "geo", "storage", "sdk",
    )
    val SEVERITIES = listOf("fatal", "error", "warn")
    val WRAPPERS = listOf("react-native", "flutter")

    /**
     * Wire order of attribute keys. This is also the allowlist: nothing else is sent,
     * except the call-site context keys `ctx.<key>` ([CTX_KEY_RE]), which follow these
     * in key order.
     */
    val ATTRIBUTE_KEYS = listOf(
        "code", "client", "clientVersion", "severity", "fv", "errName", "msg", "stack",
        "httpStatus", "host", "zoneId", "wrapper", "release",
        "appId", "appVersion", "os", "device", "slug",
        "seq", "repeat", "capped",
    )

    /** Call-site context keys, sent as `ctx.<key>`. */
    val CTX_KEY_RE = Regex("[a-z][a-zA-Z0-9_]{0,31}")
    const val CTX_PREFIX = "ctx."

    const val CODE_MAX = 64
    const val ERR_NAME_MAX = 64
    const val MSG_MAX = 200
    const val MSG_BUDGET = 80
    const val MSG_KEY = 64
    const val STACK_MAX = 4000
    const val STACK_FRAMES = 30
    const val FRAME_INPUT = 500
    const val ZONE_ID_MAX = 32
    const val HOST_MAX = 253
    const val PARTNER_CODE_MAX = 64
    const val CLIENT_VERSION_MAX = 32
    const val RELEASE_MAX = 64
    const val APP_FIELD_MAX = 64
    const val CTX_KEYS = 8
    const val CTX_VALUE_MAX = 200
    const val CTX_INPUT = 1000
    const val EVENT_BYTES = 8192
    const val DEDUPE_WINDOW_MS = 60_000L
    const val LRU_SIZE = 50
    const val PER_KEY_EMITS = 3
    const val SESSION_EMITS = 20

    private val CODE_RE = Regex("[a-z][a-z0-9]*\\.[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*")
    private val CODE_CHARS_RE = Regex("[a-z0-9_.]+")
    private val SCHEME_RE = Regex("[A-Za-z][A-Za-z0-9+.-]*")
    private val IPV4_RE = Regex("[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}")
    private val HTTP_STATUS_RE = Regex("[0-9]{3}")
    private val RATE_RE = Regex("\\+?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)")
    private const val HOST_PUNCT = ".-_~%!$&'*+,;=:@[]"
    private const val ELLIPSIS = "…"
    private val FALSE_WORDS = setOf("false", "0", "no", "off")

    // One left-to-right pass; the first alternative that matches at a position wins
    // and replaced text is never scanned again. ASCII classes only, no flags, so
    // java.util.regex matches exactly what the JS reference matches.
    private const val URL_ALT = "([A-Za-z][A-Za-z0-9+.-]*://[^ \"'<>()]*)"
    private const val PROTO_REL_ALT = "(//[A-Za-z0-9-]+\\.[^ \"'<>()]*)"
    private const val EMAIL_ALT = "([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,})"
    private const val UUID_ALT =
        "([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"
    private const val IPV4_ALT = "([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})"
    private const val DIGITS_ALT = "([0-9]{6,})"
    private const val PATH_ALT = "([^ ():]*/)"
    private const val QUERY_ALT = "(\\?[^ :()]*)"

    val MESSAGE_PATTERN = listOf(URL_ALT, PROTO_REL_ALT, EMAIL_ALT, UUID_ALT, IPV4_ALT, DIGITS_ALT).joinToString("|")
    val FRAME_PATTERN = listOf(
        URL_ALT,
        PROTO_REL_ALT,
        EMAIL_ALT,
        UUID_ALT,
        IPV4_ALT,
        PATH_ALT,
        QUERY_ALT
    ).joinToString("|")
    private val MESSAGE_RE = Regex(MESSAGE_PATTERN)
    private val FRAME_RE = Regex(FRAME_PATTERN)
    private val LINE_COL_RE = Regex("(:[0-9]+){1,2}$")
    private val PATH_PII_RE = Regex(listOf(EMAIL_ALT, UUID_ALT, IPV4_ALT).joinToString("|"))

    /** Hosts whose stack URLs are kept whole, so their frames can be source-mapped. */
    val OUR_DOMAINS = listOf("sellwild.com", "sellwild.org")

    // ── Code points ──────────────────────────────────────────────────────────

    /** The code points of [s]. A lone surrogate stays one unit (String.codePoints() needs API 24). */
    fun codePoints(s: String): IntArray {
        val out = IntArray(s.length)
        var n = 0
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate()) {
                out[n++] = Character.toCodePoint(c, s[i + 1])
                i += 2
            } else {
                out[n++] = c.code
                i++
            }
        }
        return out.copyOf(n)
    }

    private fun fromCodePoints(cps: IntArray, count: Int): String {
        val sb = StringBuilder(count)
        for (i in 0 until count) sb.appendCodePoint(cps[i])
        return sb.toString()
    }

    private fun isLoneSurrogate(cp: Int) = cp in 0xd800..0xdfff

    // Code points that attach to the one before them. A cut never separates them
    // from their base: the base is dropped with them.
    private fun isExtender(cp: Int) =
        cp in 0x0300..0x036f || cp in 0x1ab0..0x1aff || cp in 0x1dc0..0x1dff ||
            cp in 0x20d0..0x20ff || cp in 0xfe00..0xfe0f || cp in 0xfe20..0xfe2f ||
            cp == 0x200d || cp in 0x1f3fb..0x1f3ff || cp in 0xe0020..0xe007f || cp in 0xe0100..0xe01ef

    private fun isRegionalIndicator(cp: Int) = cp in 0x1f1e6..0x1f1ff

    /**
     * Cut [s] to at most [max] code points. When a cut happens the result ends in
     * "…", which counts toward [max]. Never splits a surrogate pair, never leaves a
     * combining mark, variation selector, skin tone, tag or ZWJ without its base,
     * and never splits a regional-indicator (flag) pair.
     */
    fun truncateUnicode(s: String, max: Int): String {
        val cps = codePoints(s)
        if (cps.size <= max) return s
        var k = max - 1
        while (k > 0 && (isExtender(cps[k]) || cps[k - 1] == 0x200d)) k--
        if (k > 0 && isRegionalIndicator(cps[k])) {
            var run = 0
            var i = k - 1
            while (i >= 0 && isRegionalIndicator(cps[i])) {
                run++
                i--
            }
            if (run % 2 == 1) k--
        }
        return fromCodePoints(cps, k) + ELLIPSIS
    }

    private fun firstCodePoints(s: String, n: Int): String {
        val cps = codePoints(s)
        return if (cps.size <= n) s else fromCodePoints(cps, n)
    }

    // ── Text cleanup ─────────────────────────────────────────────────────────

    // Space-like code points that become U+0020 before collapsing.
    private fun isSpaceLike(cp: Int) =
        cp <= 0x1f || cp in 0x7f..0x9f || cp == 0x20 || cp == 0xa0 || cp == 0x1680 ||
            cp in 0x2000..0x200a || cp == 0x2028 || cp == 0x2029 || cp == 0x202f ||
            cp == 0x205f || cp == 0x3000 || cp == 0xfeff

    /**
     * Lone surrogates become U+FFFD, control and space-like code points become one
     * space, runs of spaces collapse, and the ends are trimmed. Non-strings give "".
     */
    fun cleanText(v: Any?): String {
        if (v !is String) return ""
        val sb = StringBuilder(v.length)
        var pendingSpace = false
        for (cp in codePoints(v)) {
            if (isSpaceLike(cp)) {
                pendingSpace = sb.isNotEmpty()
                continue
            }
            if (pendingSpace) sb.append(' ')
            pendingSpace = false
            sb.appendCodePoint(if (isLoneSurrogate(cp)) 0xfffd else cp)
        }
        return sb.toString()
    }

    private fun asciiLower(s: String): String {
        val chars = CharArray(s.length) { i -> s[i].let { c -> if (c in 'A'..'Z') c + 32 else c } }
        return String(chars)
    }

    private fun isAsciiSpace(c: Char) = c == ' ' || c in '\t'..'\r'

    /** Trim U+0009–U+000D and U+0020 only (identical on every platform). */
    fun trimAscii(s: String): String {
        var a = 0
        var b = s.length
        while (a < b && isAsciiSpace(s[a])) a++
        while (b > a && isAsciiSpace(s[b - 1])) b--
        return s.substring(a, b)
    }

    // ── Host extraction ──────────────────────────────────────────────────────

    private fun isAuthorityChar(cp: Int): Boolean {
        if (cp >= 0x80) return true
        val c = cp.toChar()
        return c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || HOST_PUNCT.indexOf(c) >= 0
    }

    /**
     * Hostname of an absolute (`scheme://`) or protocol-relative (`//`) URL, lower
     * case, without userinfo, port or trailing dots. IP literals become "<ip>".
     * Null when there is no host.
     */
    fun hostOf(url: Any?): String? {
        if (url !is String) return null
        val s = trimAscii(url)
        val i = s.indexOf("://")
        val rest = when {
            i > 0 && SCHEME_RE.matches(s.substring(0, i)) -> s.substring(i + 3)
            s.startsWith("//") -> s.substring(2)
            else -> return null
        }
        val auth = StringBuilder()
        for (cp in codePoints(rest)) {
            if (cp == '/'.code || cp == '?'.code || cp == '#'.code || !isAuthorityChar(cp)) break
            auth.appendCodePoint(cp)
        }
        var a = auth.toString()
        val at = a.lastIndexOf('@')
        if (at >= 0) a = a.substring(at + 1)
        if (a.startsWith("[")) return if (a.contains(']')) "<ip>" else null
        val colon = a.indexOf(':')
        if (colon >= 0) a = a.substring(0, colon)
        val host = asciiLower(a.trimEnd('.'))
        if (host.isEmpty()) return null
        if (IPV4_RE.matches(host)) return "<ip>"
        return host
    }

    // ── Message and stack sanitizing ─────────────────────────────────────────

    /**
     * PII-safe message: cleanText, then URLs → host (or "<url>"), emails →
     * "<email>", UUIDs → "<id>", IPv4 → "<ip>", 6+ digit runs → "<n>".
     * Not truncated here.
     */
    fun sanitizeMessage(v: Any?): String =
        MESSAGE_RE.replace(cleanText(v)) { m ->
            val g = m.groups
            when {
                g[1] != null || g[2] != null -> hostOf(m.value) ?: "<url>"
                g[3] != null -> "<email>"
                g[4] != null -> "<id>"
                g[5] != null -> "<ip>"
                else -> "<n>"
            }
        }

    private fun basenameOfUrl(u: String): String {
        val cut = u.indexOfFirst { it == '?' || it == '#' }
        val path = if (cut >= 0) u.substring(0, cut) else u
        return path.substring(path.lastIndexOf('/') + 1)
    }

    /** True for sellwild.com, sellwild.org and any subdomain of either. */
    fun isOurHost(host: String): Boolean = OUR_DOMAINS.any { host == it || host.endsWith(".$it") }

    /**
     * A stack URL on one of our hosts (FAILURES.md 7.4): the scheme (lower case)
     * or "//", the host from hostOf, the path, then the trailing ":line" or
     * ":line:col". Userinfo, port, query and fragment are removed; emails, UUIDs
     * and IPv4s in the path are masked.
     */
    private fun keepOurUrl(m: String, host: String): String {
        val prefix = if (m.startsWith("//")) "//" else asciiLower(m.substring(0, m.indexOf("://"))) + "://"
        val rest = m.substring(prefix.length)
        var authLen = 0
        for (cp in codePoints(rest)) {
            if (cp == '/'.code || cp == '?'.code || cp == '#'.code || !isAuthorityChar(cp)) break
            authLen += Character.charCount(cp)
        }
        val after = rest.substring(authLen)
        val lcMatch = LINE_COL_RE.find(after)
        val lc = if (lcMatch == null) "" else lcMatch.value
        val path = after.substring(0, after.length - lc.length).substringBefore('?').substringBefore('#')
        val masked = PATH_PII_RE.replace(path) { p ->
            when {
                p.groups[1] != null -> "<email>"
                p.groups[2] != null -> "<id>"
                else -> "<ip>"
            }
        }
        return prefix + host + masked + lc
    }

    private fun frameUrl(m: String): String {
        val host = hostOf(m) ?: return basenameOfUrl(m).ifEmpty { "<url>" }
        return if (isOurHost(host)) keepOurUrl(m, host) else host
    }

    private fun sanitizeFrame(line: String): String =
        FRAME_RE.replace(cleanText(line)) { m ->
            val g = m.groups
            when {
                g[1] != null || g[2] != null -> frameUrl(m.value)
                g[3] != null -> "<email>"
                g[4] != null -> "<id>"
                g[5] != null -> "<ip>"
                else -> ""
            }
        }

    /**
     * First 30 frames of a stack, one per line: the engine header line
     * ([errName] or `errName: …`) is dropped, each frame is cut to its first 500
     * UTF-16 units, URLs on our hosts keep their path and line:col (no query),
     * other URLs become hosts, directories and query strings are removed,
     * emails/UUIDs/IPs are masked. Max 4000 code points.
     * Null when nothing is left.
     */
    fun sanitizeStack(stack: Any?, errName: String?): String? {
        if (stack !is String) return null
        var lines = stack.split('\n').map { trimAscii(it.replace("\r", "")) }.filter { it.isNotEmpty() }
        if (!errName.isNullOrEmpty() && lines.isNotEmpty() &&
            (lines[0] == errName || lines[0].startsWith("$errName:"))
        ) {
            lines = lines.drop(1)
        }
        val frames = lines.take(
            STACK_FRAMES
        ).map { sanitizeFrame(capInput(it, FRAME_INPUT)) }.filter { it.isNotEmpty() }
        if (frames.isEmpty()) return null
        return truncateUnicode(frames.joinToString("\n"), STACK_MAX)
    }

    // ── Field normalizers ────────────────────────────────────────────────────

    /** A code that fails the registry format becomes "client.code.invalid". */
    fun normalizeCode(code: Any?): String {
        if (code !is String || code.length > CODE_MAX) return INVALID_CODE
        if (!CODE_CHARS_RE.matches(code) || !CODE_RE.matches(code)) return INVALID_CODE
        return code
    }

    /** Exact match against the component enum, else "unknown". */
    fun normalizeComponent(component: Any?): String =
        if (component is String && component in COMPONENTS) component else UNKNOWN

    /** Exact match against fatal | error | warn, else "error". */
    fun normalizeSeverity(severity: Any?): String =
        if (severity is String && severity in SEVERITIES) severity else "error"

    // A JSON number as JS sees it: a double.
    private fun integralOrNull(n: Number): Double? {
        val d = n.toDouble()
        return if (d.isFinite() && d == Math.floor(d)) d else null
    }

    /** HTTP status as exactly three digits, else null. */
    fun normalizeHttpStatus(v: Any?): String? = when (v) {
        is Number -> integralOrNull(v)?.takeIf { it in 100.0..999.0 }?.toLong()?.toString()
        is String -> trimAscii(v).takeIf { HTTP_STATUS_RE.matches(it) }
        else -> null
    }

    /** Integer numbers or strings; cleaned and cut to 32 code points. */
    fun normalizeZoneId(v: Any?): String? {
        val s = when (v) {
            is Number -> integralOrNull(v)?.takeIf { Math.abs(it) <= MAX_SAFE_INTEGER }?.toLong()?.toString()
            is String -> v
            else -> null
        } ?: return null
        val t = cleanText(s)
        return if (t.isEmpty()) null else truncateUnicode(t, ZONE_ID_MAX)
    }

    private const val MAX_SAFE_INTEGER = 9007199254740991.0
    private const val CTX_DECIMAL_LIMIT = 1e15

    /**
     * The file name at the end of a URL's path, without its query or fragment, e.g.
     * `listings-weatherbug.json`: call-site context that names the resource without
     * sending the URL. Empty when the path ends in `/`.
     */
    fun urlFileName(url: String): String {
        val path = url.split('?', '#', limit = 2)[0]
        return path.substring(path.lastIndexOf('/') + 1)
    }

    /** The first [max] UTF-16 units of [s] (FAILURES.md 3.3 item 4). */
    fun capInput(s: String, max: Int): String = if (s.length > max) s.substring(0, max) else s

    /** Up to 6 decimals, trailing zeros and a bare point removed; "-0" → "0" (JS toFixed(6)). */
    fun formatDecimal(v: Double): String {
        val s = java.math.BigDecimal(v).setScale(6, java.math.RoundingMode.HALF_UP).toPlainString()
            .trimEnd('0').trimEnd('.')
        return if (s == "-0") "0" else s
    }

    /**
     * A call-site context value as text: a string is cut to 1000 UTF-16 units and
     * sanitized like msg; a safe integer is written in decimal; another finite
     * number with |v| < 1e15 is written with up to 6 decimals. Cut to 200 code
     * points. Anything else, or empty, → null.
     */
    fun normalizeCtxValue(v: Any?): String? {
        val s = when (v) {
            is String -> sanitizeMessage(capInput(v, CTX_INPUT))
            is Number -> {
                val d = v.toDouble()
                when {
                    !d.isFinite() -> null
                    d == Math.floor(d) && Math.abs(d) <= MAX_SAFE_INTEGER -> d.toLong().toString()
                    Math.abs(d) < CTX_DECIMAL_LIMIT -> formatDecimal(d)
                    else -> null
                }
            }
            else -> null
        }
        return if (s.isNullOrEmpty()) null else truncateUnicode(s, CTX_VALUE_MAX)
    }

    /**
     * The call-site context as attributes: String keys matching [CTX_KEY_RE] whose
     * value normalizes to text, sorted by key, the first 8 kept, each as `ctx.<key>`.
     * Anything but a Map or a JSONObject → none.
     */
    fun normalizeCtx(context: Any?): List<Pair<String, String>> {
        val entries: Map<*, *> = when (context) {
            is Map<*, *> -> context
            is org.json.JSONObject -> context.keys().asSequence().associateWith { context.opt(it) }
            else -> return emptyList()
        }
        return entries.keys.filterIsInstance<String>().filter { CTX_KEY_RE.matches(it) }.sorted()
            .mapNotNull { k ->
                normalizeCtxValue(
                    entries[k]?.takeIf { it != org.json.JSONObject.NULL }
                )?.let { k to it }
            }
            .take(CTX_KEYS)
            .map { (k, v) -> "$CTX_PREFIX$k" to v }
    }

    private fun cleanBounded(v: Any?, max: Int): String? {
        if (v !is String) return null
        val t = cleanText(v)
        return if (t.isEmpty()) null else truncateUnicode(t, max)
    }

    // ── Flags and sampling ───────────────────────────────────────────────────

    /**
     * Kill-switch coercion: boolean as is; number → value != 0; string → not one
     * of false/0/no/off after ASCII trim and ASCII lower case; anything else
     * (null, absent, JSON object, array) → [dflt].
     */
    fun coerceFlag(v: Any?, dflt: Boolean = true): Boolean = when (v) {
        is Boolean -> v
        is Number -> v.toDouble() != 0.0
        is String -> asciiLower(trimAscii(v)) !in FALSE_WORDS
        else -> dflt
    }

    /**
     * FAILURES_SAMPLE_RATE: a finite number, or a plain decimal string, clamped to
     * [0, 1]. Anything else (null, "", NaN, "50%", booleans, objects) → 1.
     */
    fun coerceRate(v: Any?): Double {
        val n = when (v) {
            is Number -> v.toDouble().takeIf { it.isFinite() }
            is String -> trimAscii(v).takeIf { RATE_RE.matches(it) }?.toDouble()
            else -> null
        } ?: return 1.0
        return when {
            n <= 0.0 -> 0.0
            n >= 1.0 -> 1.0
            else -> n
        }
    }

    // UTF-8 bytes of [s], lone surrogates as U+FFFD (as TextEncoder does; Java's
    // encoder writes '?' instead).
    private inline fun forEachUtf8Byte(s: String, f: (Int) -> Unit) {
        for (raw in codePoints(s)) {
            val cp = if (isLoneSurrogate(raw)) 0xfffd else raw
            when {
                cp < 0x80 -> f(cp)
                cp < 0x800 -> {
                    f(0xc0 or (cp shr 6))
                    f(0x80 or (cp and 0x3f))
                }
                cp < 0x10000 -> {
                    f(0xe0 or (cp shr 12))
                    f(0x80 or ((cp shr 6) and 0x3f))
                    f(0x80 or (cp and 0x3f))
                }
                else -> {
                    f(0xf0 or (cp shr 18))
                    f(0x80 or ((cp shr 12) and 0x3f))
                    f(0x80 or ((cp shr 6) and 0x3f))
                    f(0x80 or (cp and 0x3f))
                }
            }
        }
    }

    fun utf8Length(s: String): Int {
        var n = 0
        forEachUtf8Byte(s) { n++ }
        return n
    }

    /** FNV-1a 32-bit over the UTF-8 bytes of [s], as an unsigned value. */
    fun fnv1a32(s: String): Long {
        var h = 0x811c9dc5.toInt()
        forEachUtf8Byte(s) { b -> h = (h xor b) * 0x01000193 }
        return h.toLong() and 0xffffffffL
    }

    /** Session sampling: fnv1a32(uid + ":failures") / 2^32 < rate. */
    fun isSampled(uid: String?, rate: Double): Boolean {
        if (rate >= 1.0) return true
        if (rate <= 0.0) return false
        return fnv1a32(uid.orEmpty() + ":failures").toDouble() / 4294967296.0 < rate
    }

    // ── Dedupe ───────────────────────────────────────────────────────────────

    /** action|label|errName|first 64 code points of the sanitized (uncut) message. */
    fun dedupeKey(action: String, label: String, errName: String?, msgFull: String): String =
        listOf(action, label, errName.orEmpty(), firstCodePoints(msgFull, MSG_KEY)).joinToString("|")

    // ── Event building ───────────────────────────────────────────────────────

    private fun jsonString(s: String, out: StringBuilder) {
        out.append('"')
        for (ch in s) {
            when {
                ch == '"' -> out.append("\\\"")
                ch == '\\' -> out.append("\\\\")
                ch == '\b' -> out.append("\\b")
                ch == '\u000c' -> out.append("\\f")
                ch == '\n' -> out.append("\\n")
                ch == '\r' -> out.append("\\r")
                ch == '\t' -> out.append("\\t")
                ch.code < 0x20 -> out.append("\\u").append(ch.code.toString(16).padStart(4, '0'))
                else -> out.append(ch)
            }
        }
        out.append('"')
    }

    /**
     * Canonical JSON of the event (fixed key order, no whitespace, minimal
     * escaping, "/" and non-ASCII left literal). Its UTF-8 length is the size the
     * 8192-byte budget is measured against. Never the platform JSON encoder.
     */
    fun canonicalJson(event: FailureEvent): String {
        val out = StringBuilder()
        out.append("{\"event\":")
        jsonString(event.event, out)
        out.append(",\"action\":")
        jsonString(event.action, out)
        out.append(",\"label\":")
        jsonString(event.label, out)
        out.append(",\"attributes\":{")
        var first = true
        val ctxKeys = event.attributes.keys.filter { it.startsWith(CTX_PREFIX) }.sorted()
        for (k in ATTRIBUTE_KEYS + ctxKeys) {
            val v = event.attributes[k] ?: continue
            if (!first) out.append(',')
            first = false
            jsonString(k, out)
            out.append(':')
            jsonString(v, out)
        }
        out.append("},\"uid\":")
        jsonString(event.uid, out)
        out.append(",\"createdTime\":").append(event.createdTime).append('}')
        return out.toString()
    }

    fun eventByteSize(event: FailureEvent): Int = utf8Length(canonicalJson(event))

    /** Normalized fields [buildFailureEvent] turns into attributes. */
    // one field per attribute the event can carry
    @Suppress("LongParameterList")
    class Fields(
        val action: String,
        val label: String,
        val severity: String,
        val errName: String?,
        val msg: String?,
        val stack: String?,
        val httpStatus: String?,
        val host: String?,
        val zoneId: String?,
        val seq: Int,
        val ctx: List<Pair<String, String>> = emptyList(),
        val repeat: Int,
        val capped: Boolean,
    )

    /**
     * Build the wire event from normalized fields and apply the size budget:
     * over 8192 bytes → drop every ctx.* key; still over → drop stack; still over →
     * cut msg to 80; still over → drop msg; still over → send as is.
     */
    fun buildFailureEvent(fields: Fields, ctx: FailureContext, uid: String?, now: Long): FailureEvent {
        val a = mapOf(
            "code" to (cleanBounded(ctx.partnerCode, PARTNER_CODE_MAX) ?: UNKNOWN),
            "client" to ((ctx.client as? String)?.takeIf { it.isNotEmpty() } ?: UNKNOWN),
            "clientVersion" to (cleanBounded(ctx.clientVersion, CLIENT_VERSION_MAX) ?: UNKNOWN),
            "severity" to fields.severity,
            "fv" to CONTRACT_VERSION,
            "errName" to fields.errName,
            "msg" to fields.msg,
            "stack" to fields.stack,
            "httpStatus" to fields.httpStatus,
            "host" to fields.host,
            "zoneId" to fields.zoneId,
            "wrapper" to (ctx.wrapper as? String)?.takeIf { it in WRAPPERS },
            "release" to cleanBounded(ctx.release, RELEASE_MAX),
            "appId" to cleanBounded(ctx.appId, APP_FIELD_MAX),
            "appVersion" to cleanBounded(ctx.appVersion, APP_FIELD_MAX),
            "os" to cleanBounded(ctx.os, APP_FIELD_MAX),
            "device" to cleanBounded(ctx.device, APP_FIELD_MAX),
            "slug" to cleanBounded(ctx.slug, APP_FIELD_MAX),
            "seq" to fields.seq.toString(),
            "repeat" to fields.repeat.toString(),
            "capped" to (if (fields.capped) "1" else null),
        )
        val attributes = LinkedHashMap<String, String>()
        for (k in ATTRIBUTE_KEYS) a[k]?.let { attributes[k] = it }
        for ((k, v) in fields.ctx) attributes[k] = v
        // The event reads [attributes] live, so each step re-measures what is left.
        val event = FailureEvent(fields.action, fields.label, attributes, uid.orEmpty(), now)
        if (eventByteSize(event) > EVENT_BYTES) attributes.keys.removeAll { it.startsWith(CTX_PREFIX) }
        if (eventByteSize(event) > EVENT_BYTES) attributes.remove("stack")
        val msg = attributes["msg"]
        if (msg != null && eventByteSize(event) > EVENT_BYTES) {
            attributes["msg"] = truncateUnicode(msg, MSG_BUDGET)
            if (eventByteSize(event) > EVENT_BYTES) attributes.remove("msg")
        }
        return event
    }

    // ── The gate ─────────────────────────────────────────────────────────────

    private fun touch(keys: List<FailureKey>, entry: FailureKey): List<FailureKey> =
        keys.filter { it.key != entry.key } + entry

    // The full sanitized message before the 200 cut: message and error message,
    // joined with ": ", the error left out when it equals the message.
    private fun messageFull(input: FailureInput): String {
        val fromMessage = if (input.message is String) sanitizeMessage(input.message) else ""
        val fromError = if (input.errMessage is String) sanitizeMessage(input.errMessage) else ""
        val parts = mutableListOf(fromMessage)
        if (fromError != fromMessage) parts += fromError
        return parts.filter { it.isNotEmpty() }.joinToString(": ")
    }

    /**
     * The whole decision as a pure function (FAILURES.md 5.2). Returns the next
     * state and the event, or null with the gate that dropped it.
     */
    fun decideFailure(
        state: FailureState?,
        input: FailureInput?,
        context: FailureContext?,
        uid: String?,
        now: Long,
    ): FailureDecision {
        val st = state ?: FailureState()
        val ctx = context ?: FailureContext()
        val inp = input ?: FailureInput()
        fun drop(reason: String, next: FailureState = st) = FailureDecision(next, null, false, reason)

        if (!coerceFlag(ctx.eventsEnabled, true)) return drop("events_disabled")
        if (!coerceFlag(ctx.failuresEnabled, true)) return drop("failures_disabled")

        val action = normalizeCode(inp.code)
        val label = normalizeComponent(inp.component)
        val severity = normalizeSeverity(inp.severity)

        if (severity != "fatal" && !isSampled(uid, coerceRate(ctx.failuresSampleRate))) {
            return drop("sampled_out")
        }
        if (st.sessionCount >= SESSION_EMITS) return drop("session_capped")

        val errName = cleanBounded(inp.errName, ERR_NAME_MAX)
        val msgFull = messageFull(inp)

        val key = dedupeKey(action, label, errName, msgFull)
        val existing = st.keys.firstOrNull { it.key == key }
        if (existing != null) {
            if (existing.emits >= PER_KEY_EMITS) {
                return drop("key_capped", st.copy(keys = touch(st.keys, existing)))
            }
            if (now - existing.lastEmitAt < DEDUPE_WINDOW_MS) {
                val bumped = existing.copy(suppressed = existing.suppressed + 1)
                return drop("deduped", st.copy(keys = touch(st.keys, bumped)))
            }
        }

        val seq = st.sessionCount + 1
        val repeat = (existing?.suppressed ?: 0) + 1
        val entry = FailureKey(key, now, 0, (existing?.emits ?: 0) + 1)
        var keys = touch(st.keys, entry)
        if (keys.size > LRU_SIZE) keys = keys.drop(keys.size - LRU_SIZE)

        val host = hostOf(inp.url)
        val event = buildFailureEvent(
            Fields(
                action = action,
                label = label,
                severity = severity,
                errName = errName,
                msg = if (msgFull.isEmpty()) null else truncateUnicode(msgFull, MSG_MAX),
                stack = sanitizeStack(inp.stack, errName),
                httpStatus = normalizeHttpStatus(inp.httpStatus),
                host = host?.let { truncateUnicode(it, HOST_MAX) },
                zoneId = normalizeZoneId(inp.zoneId),
                seq = seq,
                repeat = repeat,
                capped = seq == SESSION_EMITS,
                ctx = normalizeCtx(inp.context),
            ),
            ctx,
            uid,
            now,
        )
        return FailureDecision(FailureState(seq, keys), event, seq == 1 || severity == "fatal", null)
    }

    /**
     * The debug echo line (FAILURES.md section 2):
     * `[Sellwild] failure <action> <label> <severity> <reason or "sent"> <msg>`.
     * [msg] is the sanitized message, never the raw input; it and its space are
     * left out when there is none.
     */
    fun echoLine(input: FailureInput, outcome: String?): String {
        val msgFull = messageFull(input)
        val head = "[Sellwild] failure ${normalizeCode(input.code)} ${normalizeComponent(input.component)} " +
            "${normalizeSeverity(input.severity)} ${outcome ?: "sent"}"
        return if (msgFull.isEmpty()) head else "$head ${truncateUnicode(msgFull, MSG_MAX)}"
    }
}
