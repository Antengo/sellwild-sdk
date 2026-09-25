package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildUser
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import java.util.Locale

/** Pure text for listing cards and native ads. */
internal object Format {

    /**
     * A listing price: "$12" for a whole number, "$12.50" otherwise; € for EUR, £ for GBP, $ for
     * anything else. Empty when [price] is not a number. Two decimals use [locale], as the views
     * always did with the default locale. Locale.getDefault(Locale.Category) is API 24+, and
     * minSdk is 23, so this takes the plain default.
     */
    fun price(currency: String?, price: String?, locale: Locale = Locale.getDefault()): String {
        val value = price?.toDoubleOrNull() ?: return ""
        val sym = when (currency?.uppercase()) {
            "EUR" -> "€"
            "GBP" -> "£"
            else -> "$"
        }
        return if (value % 1.0 == 0.0) "$sym${value.toInt()}" else "$sym${String.format(locale, "%.2f", value)}"
    }

    /** The card's seller line: "JANE D.  |  sellwild.com", or just "sellwild.com" with no user. */
    fun seller(user: SellwildUser?): String {
        if (user == null) return "sellwild.com"
        val first = if (user.firstName.isNotBlank()) user.firstName.uppercase() else "SELLER"
        val name = if (user.lastName.isNotBlank()) "$first ${user.lastName.uppercase().first()}." else first
        return "$name  |  sellwild.com"
    }

    /** The native ad's sponsor line. */
    fun sponsored(sponsoredBy: String?): String = if (sponsoredBy.isNullOrEmpty()) "Sponsored" else "Sponsored · $sponsoredBy"

    /** The native ad's call to action. */
    fun callToAction(text: String?): String = if (text.isNullOrEmpty()) "Learn more" else text
}

/** The feed's resolved colors (ARGB). */
internal data class FeedColors(
    /** The feed background and pull-to-refresh spinner: PRICE_COLOR. */
    val background: Int,
    /** The header title: TITLE_COLOR. */
    val title: Int,
    /** The header's "Powered by Sellwild": LINK_COLOR. */
    val poweredBy: Int,
    /** Listing card prices: LINK_COLOR. */
    val price: Int,
)

/** The feed's colors from the CMS color strings, each with its fallback. */
internal object FeedTheme {
    const val BACKGROUND = 0xFF0A1F3D.toInt()
    const val TITLE = 0xFFFFFFFF.toInt()
    const val POWERED_BY = 0xFF9CA3AF.toInt()
    const val PRICE = 0xFF2563EB.toInt()

    /**
     * [parse] is the platform color parser (Color.parseColor), which throws
     * IllegalArgumentException for text that is not a color. An empty value takes its fallback
     * quietly (unset); one that does not parse takes it too and is reported as
     * config.color.invalid, once per field.
     */
    fun resolve(priceColor: String?, titleColor: String?, linkColor: String?, parse: (String) -> Int): Resolved<FeedColors> {
        val issues = mutableListOf<Issue>()

        fun color(field: String, value: String?): Int? {
            if (value.isNullOrEmpty()) return null
            return try {
                parse(value)
            } catch (e: IllegalArgumentException) {
                issues += Issue(
                    SellwildFailureCode.CONFIG_COLOR_INVALID,
                    SellwildFailureComponent.REMOTE_CONFIG,
                    SellwildFailureSeverity.ERROR,
                    message = "$field is not a color: $value",
                    error = e,
                )
                null
            }
        }

        val price = color("PRICE_COLOR", priceColor)
        val title = color("TITLE_COLOR", titleColor)
        val link = color("LINK_COLOR", linkColor)
        val colors = FeedColors(
            background = price ?: BACKGROUND,
            title = title ?: TITLE,
            poweredBy = link ?: POWERED_BY,
            price = link ?: PRICE,
        )
        return Resolved(colors, issues)
    }
}
