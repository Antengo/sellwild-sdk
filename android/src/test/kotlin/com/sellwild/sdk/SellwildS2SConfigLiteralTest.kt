package com.sellwild.sdk

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * More of origin's JS-literal reader (c55efa0): comments, raw line breaks in text, `undefined`,
 * numbers with exponents, timeouts as text, and fields of the wrong type.
 */
class SellwildS2SConfigLiteralTest {

    @Test
    fun `comments are dropped and undefined is null`() {
        val text = "// S2S settings\n{ /* the account */ accountId: 'acct', endpoint: undefined, " +
            "url: 'https://u.example/a', timeout: '1200' }"

        assertEquals(SellwildS2SConfig("acct", "https://u.example/a", 1200), SellwildS2SConfig.parse(text))
    }

    @Test
    fun `line breaks and tabs in text are escaped`() {
        assertEquals("{ \"a\": \"x\\ny\\r\\tz\" }", SellwildS2SConfig.jsLiteralToJson("{ a: 'x\ny\r\tz' }"))
    }

    @Test
    fun `a number with an exponent is copied, not read as a key`() {
        assertEquals(SellwildS2SConfig("a", null, 1200), SellwildS2SConfig.parse("{ accountId: 'a', timeout: 1.2e3 }"))
    }

    @Test
    fun `wrong-typed or empty fields are ignored`() {
        val wrong = JSONObject()
            .put("accountId", 5)
            .put("endpoint", JSONObject().put("p1Consent", ""))
            .put("timeout", -1)
        assertNull(SellwildS2SConfig.parse(wrong))
        val partial = JSONObject()
            .put("endpoint", JSONObject().put("noP1Consent", "https://n.example/a"))
            .put("timeout", "x")
        assertEquals(SellwildS2SConfig(null, "https://n.example/a", null), SellwildS2SConfig.parse(partial))
    }

    private fun json(text: String) = SellwildS2SConfig.jsLiteralToJson(text)

    @Test
    fun `escapes inside text carry over, and an escaped single quote becomes a plain one`() {
        assertEquals("""{"a": "q\"x", "b": "it's"}""", json("""{a: "q\"x", b: 'it\'s'}"""))
        assertEquals("""{"a": "say \"hi\""}""", json("""{a: 'say "hi"'}"""))
    }

    @Test
    fun `unterminated text and comments end at the end of the input`() {
        assertEquals("\"abc\"", json("'abc"))
        assertEquals("\"a\\\"", json("'a\\"))
        assertEquals("{}", json("{}/* open"))
        assertEquals("{}", json("{}// trailing"))
    }

    @Test
    fun `a slash that starts no comment is copied`() {
        assertEquals("1/2", json("1/2"))
        assertEquals("[/]", json("[/]"))
        assertEquals("/", json("/"))
    }

    @Test
    fun `only a comma before a closing bracket is dropped`() {
        assertEquals("[1]", json("[1,]"))
        assertEquals("{\"a\": 1 }", json("{a: 1, }"))
        assertEquals("[1,2]", json("[1,2]"))
        assertEquals("[1,", json("[1,"))
    }

    @Test
    fun `numbers keep exponent signs, and a sign elsewhere ends the number`() {
        assertEquals("[1e-3, 2E+4]", json("[1e-3, 2E+4]"))
        assertEquals("1-2", json("1-2"))
    }

    @Test
    fun `a bare word is a key only before a colon`() {
        assertEquals("true", json("true"))
        assertEquals("[null, false]", json("[undefined, false]"))
        assertEquals("{\"\$a_1\" : 1}", json("{\$a_1 : 1}"))
    }
}
