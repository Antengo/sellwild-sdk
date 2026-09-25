package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildUser
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/** Card and native text (Format) and the feed's colors (FeedTheme), pure. */
class FormatTest {

    @Test
    fun `a whole price has no decimals, others two, in the currency's symbol`() {
        assertEquals("$19315", Format.price(null, "19315", Locale.US))
        assertEquals("$12.50", Format.price("usd", "12.5", Locale.US))
        assertEquals("€7", Format.price("EUR", "7.0", Locale.US))
        assertEquals("£3.25", Format.price("gbp", "3.25", Locale.US))
        assertEquals("$4", Format.price("CAD", "4", Locale.US))
        assertEquals("$12,50", Format.price(null, "12.5", Locale.GERMANY))
        assertEquals("", Format.price("USD", "call", Locale.US))
        assertEquals("", Format.price("USD", null, Locale.US))
    }

    @Test
    fun `the default locale formats decimals when none is given`() {
        // Plain Locale.setDefault: the SDK reads Locale.getDefault(), since the
        // category overload is API 24+ and minSdk is 23.
        val before = Locale.getDefault()
        Locale.setDefault(Locale.GERMANY)
        try {
            assertEquals("$1,50", Format.price(null, "1.5"))
        } finally {
            Locale.setDefault(before)
        }
    }

    private fun user(first: String, last: String): SellwildUser {
        val listing = ListingsParser.parseListing(
            ListingFactory.checked(mapOf("user" to JSONObject().put("id", "1").put("firstName", first).put("lastName", last))),
        )
        return checkNotNull(listing.user)
    }

    @Test
    fun `the seller line is the upper-case first name and last initial, with fallbacks`() {
        assertEquals("LOTLINX A.  |  sellwild.com", Format.seller(user("Lotlinx", "a")))
        assertEquals("SELLER A.  |  sellwild.com", Format.seller(user(" ", "Ames")))
        assertEquals("JANE  |  sellwild.com", Format.seller(user("Jane", "")))
        assertEquals("sellwild.com", Format.seller(null))
    }

    @Test
    fun `the native sponsor line and call to action have fallbacks`() {
        assertEquals("Sponsored · Acme", Format.sponsored("Acme"))
        assertEquals("Sponsored", Format.sponsored(""))
        assertEquals("Sponsored", Format.sponsored(null))
        assertEquals("Shop now", Format.callToAction("Shop now"))
        assertEquals("Learn more", Format.callToAction(""))
        assertEquals("Learn more", Format.callToAction(null))
    }

    // ── FeedTheme ────────────────────────────────────────────────────────────

    // A stand-in for Color.parseColor: #RRGGBB only.
    private val parse: (String) -> Int = { text ->
        require(Regex("#[0-9a-fA-F]{6}").matches(text)) { "Unknown color" }
        (0xFF000000 or text.substring(1).toLong(16)).toInt()
    }

    @Test
    fun `each CMS color is parsed, and LINK_COLOR colors both the powered-by line and prices`() {
        val resolved = FeedTheme.resolve("#112233", "#445566", "#778899", parse)

        assertEquals(FeedColors(0xFF112233.toInt(), 0xFF445566.toInt(), 0xFF778899.toInt(), 0xFF778899.toInt()), resolved.value)
        assertEquals(emptyList<Issue>(), resolved.issues)
    }

    @Test
    fun `unset colors fall back quietly`() {
        val resolved = FeedTheme.resolve("", null, "", parse)

        assertEquals(FeedColors(FeedTheme.BACKGROUND, FeedTheme.TITLE, FeedTheme.POWERED_BY, FeedTheme.PRICE), resolved.value)
        assertEquals(emptyList<Issue>(), resolved.issues)
    }

    @Test
    fun `a color that does not parse falls back and is reported once per field`() {
        val resolved = FeedTheme.resolve("teal-ish", "#445566", "#12", parse)

        assertEquals(FeedColors(FeedTheme.BACKGROUND, 0xFF445566.toInt(), FeedTheme.POWERED_BY, FeedTheme.PRICE), resolved.value)
        assertEquals(
            listOf(
                Issue(SellwildFailureCode.CONFIG_COLOR_INVALID, SellwildFailureComponent.REMOTE_CONFIG, SellwildFailureSeverity.ERROR, message = "PRICE_COLOR is not a color: teal-ish"),
                Issue(SellwildFailureCode.CONFIG_COLOR_INVALID, SellwildFailureComponent.REMOTE_CONFIG, SellwildFailureSeverity.ERROR, message = "LINK_COLOR is not a color: #12"),
            ),
            resolved.issues,
        )
    }
}
