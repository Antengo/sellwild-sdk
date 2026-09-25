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
}
