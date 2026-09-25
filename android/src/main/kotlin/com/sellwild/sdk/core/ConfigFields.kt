package com.sellwild.sdk.core

import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONArray
import org.json.JSONObject

/**
 * The CDN keys SellwildSDK.apply maps, with the type it reads each as, and the check for
 * values apply had to drop or coerce (config.field.invalid).
 */
internal object ConfigFields {

    enum class Kind {
        /** optString: text, or a number written as text. An array or object is dropped. */
        TEXT,

        /** optInt/optDouble: a number, or text that parses as one. Anything else reads as 0. */
        NUMBER,

        /** optBoolean: a boolean, or the text true/false in any case. Anything else reads as false. */
        BOOL,

        /** optJSONArray: a list. Anything else is dropped. */
        TEXT_LIST,

        /** A list, or text Android ignores (known drift, not a failure: IAB_CATS). */
        TEXT_LIST_OR_TEXT,
    }

    /** Every key apply reads, in the order it reads them. */
    val KINDS: Map<String, Kind> = linkedMapOf(
        "CODE" to Kind.TEXT,
        "SLUG" to Kind.TEXT,
        "NAME" to Kind.TEXT,
        "LISTINGS" to Kind.TEXT,
        "TITLE" to Kind.TEXT,
        "PARTNER_URL" to Kind.TEXT,
        "COL1" to Kind.TEXT,
        "BH_TAG" to Kind.TEXT,
        "LINK_TEXT" to Kind.TEXT,
        "BUY_NOW_TEXT" to Kind.TEXT,
        "TITLE_COLOR" to Kind.TEXT,
        "LINK_COLOR" to Kind.TEXT,
        "FONT_COLOR" to Kind.TEXT,
        "PRICE_COLOR" to Kind.TEXT,
        "PRICE_FONT_COLOR" to Kind.TEXT,
        "MARGIN_BOTTOM" to Kind.NUMBER,
        "COLORS" to Kind.TEXT_LIST,
        "OVERLAY_TITLE" to Kind.BOOL,
        "WATERMARK" to Kind.BOOL,
        "WATERMARK_TITLE" to Kind.TEXT,
        "BANNER_ZID" to Kind.TEXT,
        "BOTTOM_BANNER_ZID" to Kind.TEXT,
        "MOBILE_BANNER_ZID_ANDROID" to Kind.TEXT,
        "MOBILE_ZID_ALL_ANDROID" to Kind.TEXT,
        "MOBILE_BANNER_ZID" to Kind.TEXT,
        "MOBILE_ZID_ANDROID" to Kind.TEXT_LIST,
        "MOBILE_ZID" to Kind.TEXT_LIST,
        "HIDE_BANNER_TOP" to Kind.BOOL,
        "HIDE_BANNER_BOTTOM" to Kind.BOOL,
        "GAM" to Kind.TEXT,
        "DISABLE_GPT" to Kind.BOOL,
        "AD_DISABLE_DISPLAY" to Kind.BOOL,
        "AD_REFRESH_MAX" to Kind.NUMBER,
        "AD_REFRESH_MAX_MOBILE" to Kind.NUMBER,
        "AD_REFRESH_INTERVAL" to Kind.NUMBER,
        "MAX_FAILED_AUCTIONS" to Kind.NUMBER,
        "GPP_ENABLED" to Kind.BOOL,
        "TCF_VERSION" to Kind.NUMBER,
        "IAB_CATS" to Kind.TEXT_LIST_OR_TEXT,
        "ENABLE_INTERSTITIAL" to Kind.BOOL,
        "ENABLE_FULLSCREEN_VIDEO" to Kind.BOOL,
        "INTERSTITIALS_PER_SESSION" to Kind.NUMBER,
        "VIDEO_TAKEOVERS_PER_SESSION" to Kind.NUMBER,
        "APP_BUNDLE_ID_ANDROID" to Kind.TEXT,
        "APP_BUNDLE_ID" to Kind.TEXT,
        "APP_STORE_URL_ANDROID" to Kind.TEXT,
        "APP_STORE_URL" to Kind.TEXT,
        "BOLTIVE" to Kind.BOOL,
        "BOLTIVE_CLIENT_ID" to Kind.TEXT,
        "LOTAME" to Kind.BOOL,
        "DEBUG" to Kind.BOOL,
        "PBS_DEBUG" to Kind.BOOL,
    )

    /**
     * The mapped keys whose value apply dropped or coerced to a default because its type is
     * wrong, in [KINDS] order. Absent, JSON null and '' (how the CMS writes unset) are not
     * wrong. Every value app-config.schema.json allows passes, so only off-schema configs
     * report anything.
     */
    fun invalidKeys(raw: JSONObject): List<String> =
        KINDS.filter { (key, kind) -> isInvalid(RemoteValues.optAny(raw, key), kind) }.keys.toList()

    /** One config.field.invalid issue naming every invalid key, or none. */
    fun issues(raw: JSONObject): List<Issue> {
        val keys = invalidKeys(raw)
        if (keys.isEmpty()) return emptyList()
        return listOf(
            Issue(
                SellwildFailureCode.CONFIG_FIELD_INVALID,
                SellwildFailureComponent.REMOTE_CONFIG,
                SellwildFailureSeverity.WARN,
                message = "ignored or coerced: ${keys.joinToString(", ")}",
            ),
        )
    }

    private fun isInvalid(v: Any?, kind: Kind): Boolean {
        if (v == null || v == "") return false
        return when (kind) {
            Kind.TEXT -> v is JSONArray || v is JSONObject
            Kind.NUMBER -> v !is Number && (v !is String || v.toDoubleOrNull() == null)
            Kind.BOOL -> v !is Boolean && (v !is String || !(v.equals("true", true) || v.equals("false", true)))
            Kind.TEXT_LIST -> v !is JSONArray
            Kind.TEXT_LIST_OR_TEXT -> v !is JSONArray && v !is String
        }
    }
}
