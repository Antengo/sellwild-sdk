package com.sellwild.sdk.failures

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.math.BigInteger

/**
 * Pure-core cases the golden vectors do not reach: Kotlin number types from the two org.json
 * flavors (JVM BigDecimal, device Double), canonical-JSON escaping, UTF-8 sizes, null
 * arguments and the debug echo line.
 */
class FailuresCoreTest {

    private val now = 1_790_000_000_000L

    @Test
    fun `hostOf rejects what is not a URL with a host`() {
        assertNull(FailuresCore.hostOf(42))
        assertNull(FailuresCore.hostOf(null))
        assertNull(FailuresCore.hostOf("1a://host.example"))
        assertNull(FailuresCore.hostOf("://host.example"))
        assertNull(FailuresCore.hostOf("http://[::1"))
        assertEquals("host.example", FailuresCore.hostOf("//user@host.example:80"))
        assertEquals("a.b", FailuresCore.hostOf("https://a.b\u0000c/d"))
    }

    @Test
    fun `stack frames mask what a message masks and reduce paths to basenames`() {
        val stack = listOf(
            "Error: boom",
            "at load (file:///data/app/x/)",
            "at open (file:///data/app/main.js:1:2)",
            "at mail jane@example.com 2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11 10.0.0.1",
            "at q (lib/a.js?token=abc:3)",
            "at //cdn.example/b.js:4",
            "at dropped (sixth.js:6)",
        ).joinToString("\r\n")

        assertEquals(
            listOf(
                "at load (<url>)",
                "at open (main.js:1:2)",
                "at mail <email> <id> <ip>",
                "at q (a.js:3)",
                "at cdn.example",
            ).joinToString("\n"),
            FailuresCore.sanitizeStack(stack, "Error"),
        )
    }

    @Test
    fun `a cut drops the base with every kind of extender, and keeps it before a neighbour`() {
        val extenders = listOf(0x0301, 0x1ab0, 0x1dc0, 0x20d0, 0xfe0f, 0xfe20, 0x200d, 0x1f3fb, 0xe0020, 0xe0100)
        val neighbours = listOf(
            0x02ff, 0x0370, 0x1aaf, 0x1b00, 0x1dbf, 0x1e00, 0x20cf, 0x2100, 0xfdff, 0xfe10,
            0xfe1f, 0xfe30, 0x200c, 0x1f3fa, 0x1f400, 0xe001f, 0xe0080, 0xe00ff, 0xe01f0,
        )
        fun cut(cp: Int) = FailuresCore.truncateUnicode("abc" + String(Character.toChars(cp)) + "de", 4)

        extenders.forEach { assertEquals(Integer.toHexString(it), "ab\u2026", cut(it)) }
        neighbours.forEach { assertEquals(Integer.toHexString(it), "abc\u2026", cut(it)) }
    }

    @Test
    fun `a cut never splits a flag, even from the first code point`() {
        val flags = "\ud83c\uddfa\ud83c\uddf8\ud83c\uddec\ud83c\udde7"

        assertEquals(flags, FailuresCore.truncateUnicode(flags, 4))
        assertEquals("\ud83c\uddfa\ud83c\uddf8\u2026", FailuresCore.truncateUnicode(flags + "x", 4))
    }

    @Test
    fun `every space-like code point collapses, other invisibles stay`() {
        val spaces = listOf(0x7f, 0x85, 0x9f, 0x1680, 0x2000, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff, 0xa0)

        assertEquals(
            "x x x x x x x x x x x x x y",
            FailuresCore.cleanText(spaces.joinToString("") { "x" + String(Character.toChars(it)) } + "y"),
        )
        assertEquals("a\u200bb\u00a1c", FailuresCore.cleanText("a\u200bb\u00a1c"))
    }

    @Test
    fun `ASCII trim removes tab through carriage return and space only`() {
        assertEquals("a \b", FailuresCore.trimAscii("\u000b\u000c a \b"))
        assertEquals("x", FailuresCore.trimAscii("\t\n\r x \u000b"))
    }

    @Test
    fun `the authority ends at a path, query, fragment or a character a host cannot hold`() {
        assertEquals("a", FailuresCore.hostOf("https://a{b.c/"))
        assertEquals("a.b", FailuresCore.hostOf("https://a.b#frag"))
        assertEquals("a.b", FailuresCore.hostOf("https://a.b?q=1"))
        assertEquals("a~b.c", FailuresCore.hostOf("https://A~b.C|x"))
        assertEquals("09.a-b_c", FailuresCore.hostOf("https://09.a-b_c/"))
    }

    @Test
    fun `a hostless URL in a frame keeps only its file name, and emptied frames are dropped`() {
        val stack = "at f (file:///data/main.js?v=1:2:3)\nat g (file:///a/b.js#x)\na/b/\nat h (x.js:1)"

        assertEquals("at f (main.js)\nat g (b.js)\nat h (x.js:1)", FailuresCore.sanitizeStack(stack, null))
    }

    @Test
    fun `stack is null when nothing is left`() {
        assertNull(FailuresCore.sanitizeStack(7, "Error"))
        assertNull(FailuresCore.sanitizeStack("Error", "Error"))
        assertNull(FailuresCore.sanitizeStack(" \n\r\n ", null))
        assertEquals("Error: x", FailuresCore.sanitizeStack("Error: x", null))
        assertEquals("Error: x", FailuresCore.sanitizeStack("Error: x", ""))
    }

    @Test
    fun `http status accepts every integral Kotlin and org json number type`() {
        assertEquals("503", FailuresCore.normalizeHttpStatus(503L))
        assertEquals("503", FailuresCore.normalizeHttpStatus(BigDecimal("503.0")))
        assertEquals("503", FailuresCore.normalizeHttpStatus(BigInteger.valueOf(503)))
        assertEquals("503", FailuresCore.normalizeHttpStatus(503.0f))
        assertNull(FailuresCore.normalizeHttpStatus(Double.NaN))
        assertNull(FailuresCore.normalizeHttpStatus(Double.POSITIVE_INFINITY))
        assertNull(FailuresCore.normalizeHttpStatus(99))
        assertNull(FailuresCore.normalizeHttpStatus(true))
    }

    @Test
    fun `zone ids are safe integers or text`() {
        assertEquals("43", FailuresCore.normalizeZoneId(BigDecimal("43")))
        assertEquals("-5", FailuresCore.normalizeZoneId(-5))
        assertEquals("0", FailuresCore.normalizeZoneId(-0.0))
        assertEquals("9007199254740991", FailuresCore.normalizeZoneId(9007199254740991L))
        assertNull(FailuresCore.normalizeZoneId(9007199254740993L))
        assertNull(FailuresCore.normalizeZoneId(Long.MAX_VALUE))
        assertNull(FailuresCore.normalizeZoneId(" \t "))
        assertNull(FailuresCore.normalizeZoneId(true))
        assertNull(FailuresCore.normalizeZoneId(null))
    }

    @Test
    fun `flags and rates coerce every number type`() {
        assertTrue(FailuresCore.coerceFlag(Double.NaN))
        assertFalse(FailuresCore.coerceFlag(BigDecimal("0.0")))
        assertFalse(FailuresCore.coerceFlag(-0.0))
        assertTrue(FailuresCore.coerceFlag(0.5))
        assertFalse(FailuresCore.coerceFlag(null, false))
        assertTrue(FailuresCore.coerceFlag(JSONObject(), true))
        assertFalse(FailuresCore.coerceFlag(JSONArray(), false))

        assertEquals(1.0, FailuresCore.coerceRate(Double.NaN), 0.0)
        assertEquals(1.0, FailuresCore.coerceRate(Double.NEGATIVE_INFINITY), 0.0)
        assertEquals(0.25, FailuresCore.coerceRate(BigDecimal("0.25")), 0.0)
        assertEquals(0.0, FailuresCore.coerceRate(-0.0), 0.0)
        assertEquals(0.5, FailuresCore.coerceRate("\t+.5\n"), 0.0)
        assertEquals(1.0, FailuresCore.coerceRate("9".repeat(400)), 0.0)
        assertEquals(1.0, FailuresCore.coerceRate(false), 0.0)
    }

    @Test
    fun `sampling treats a missing uid as empty`() {
        assertEquals(FailuresCore.isSampled("", 0.2), FailuresCore.isSampled(null, 0.2))
        assertTrue(FailuresCore.isSampled(null, 1.0))
        assertFalse(FailuresCore.isSampled("anything", 0.0))
    }

    @Test
    fun `canonical JSON escapes only quotes, backslash and control characters`() {
        val event = FailureEvent(
            action = "a.b.c",
            label = "feed",
            attributes = linkedMapOf("seq" to "1", "code" to "p/q"),
            uid = "\"\\\b\u000c\n\r\t\u0001/é",
            createdTime = now,
        )

        assertEquals(
            "{\"event\":\"clientFailure\",\"action\":\"a.b.c\",\"label\":\"feed\"," +
                "\"attributes\":{\"code\":\"p/q\",\"seq\":\"1\"}," +
                "\"uid\":\"\\\"\\\\\\b\\f\\n\\r\\t\\u0001/é\",\"createdTime\":1790000000000}",
            FailuresCore.canonicalJson(event),
        )
    }

    @Test
    fun `UTF-8 sizes count lone surrogates as U+FFFD`() {
        assertEquals(1, FailuresCore.utf8Length("a"))
        assertEquals(2, FailuresCore.utf8Length("é"))
        assertEquals(3, FailuresCore.utf8Length("…"))
        assertEquals(4, FailuresCore.utf8Length("\ud83d\ude00"))
        assertEquals(3, FailuresCore.utf8Length("\ud800"))
        assertEquals(3, FailuresCore.utf8Length("\udc00"))
        assertEquals(FailuresCore.fnv1a32("\ufffd"), FailuresCore.fnv1a32("\ud800"))
    }

    @Test
    fun `code points keep pairs whole and lone surrogates single`() {
        assertEquals(listOf(0x61, 0x1f600, 0xd83d), FailuresCore.codePoints("a\ud83d\ude00\ud83d").toList())
        assertEquals(listOf(0xdc00, 0x62), FailuresCore.codePoints("\udc00b").toList())
    }

    @Test
    fun `cleanText gives empty text for non-strings`() {
        assertEquals("", FailuresCore.cleanText(null))
        assertEquals("", FailuresCore.cleanText(12))
        assertEquals("a b", FailuresCore.cleanText("\u00a0a\u2028\u3000b\ufeff"))
    }

    @Test
    fun `null state, input and context decide with defaults`() {
        val d = FailuresCore.decideFailure(null, null, null, null, now)

        val event = d.event!!
        assertEquals(FailuresCore.INVALID_CODE, event.action)
        assertEquals(FailuresCore.UNKNOWN, event.label)
        assertEquals("", event.uid)
        assertEquals("unknown", event.attributes["code"])
        assertEquals("unknown", event.attributes["client"])
        assertEquals("unknown", event.attributes["clientVersion"])
        assertEquals(FailureState(1, listOf(FailureKey("client.code.invalid|unknown||", now, 0, 1))), d.state)
        assertTrue(d.flushNow)
    }

    @Test
    fun `a non-string or empty client becomes unknown, a known wrapper passes`() {
        val input = FailureInput(code = "config.fetch.http", component = "remoteConfig")

        val numeric = FailuresCore.decideFailure(null, input, FailureContext(client = 3, wrapper = "flutter"), "u", now)
        val empty = FailuresCore.decideFailure(null, input, FailureContext(client = "", wrapper = 1), "u", now)

        assertEquals("unknown", numeric.event!!.attributes["client"])
        assertEquals("flutter", numeric.event!!.attributes["wrapper"])
        assertEquals("unknown", empty.event!!.attributes["client"])
        assertNull(empty.event!!.attributes["wrapper"])
    }

    @Test
    fun `the echo line carries the normalized fields and the sanitized message`() {
        val input = FailureInput(
            code = "config.fetch.http",
            component = "remoteConfig",
            severity = "warn",
            message = "HTTP 403 for jane@example.com",
            errMessage = "Access Denied",
        )

        assertEquals(
            "[Sellwild] failure config.fetch.http remoteConfig warn sent HTTP 403 for <email>: Access Denied",
            FailuresCore.echoLine(input, null),
        )
        assertEquals(
            "[Sellwild] failure client.code.invalid unknown error sampled_out",
            FailuresCore.echoLine(FailureInput(code = "Bad"), "sampled_out"),
        )
    }

    @Test
    fun `the echo message is cut like the event message`() {
        val line = FailuresCore.echoLine(FailureInput(code = "a.b.c", message = "x".repeat(300)), "held")

        assertEquals("[Sellwild] failure a.b.c unknown error held " + "x".repeat(199) + "\u2026", line)
    }
}
