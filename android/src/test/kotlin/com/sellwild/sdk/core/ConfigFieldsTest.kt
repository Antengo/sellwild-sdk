package com.sellwild.sdk.core

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/** Which mapped config values SellwildSDK.apply has to drop or coerce (config.field.invalid). */
class ConfigFieldsTest {

    private fun configs(): List<String> =
        FixtureLoader.list("fixtures/app-config/valid") + FixtureLoader.list("samples/app-config").filter { it.endsWith(".json") }

    @Test
    fun `every config the schema allows passes, including the real samples`() {
        val checked = configs().map { path -> path to ConfigFields.invalidKeys(FixtureLoader.jsonObject(path)) }

        assertEquals(checked.map { it.first to emptyList<String>() }, checked)
        assertEquals(true, checked.size >= 37)
        assertEquals(emptyList<String>(), ConfigFields.invalidKeys(AppConfigFactory.everyMappedKey()))
    }

    @Test
    fun `unset values are not invalid`() {
        val unset = AppConfigFactory.checked(mapOf("MOBILE_BANNER_ZID" to "", "LISTINGS" to ""))
        val nulls = AppConfigFactory.offSchema(mapOf("COLORS" to "", "AD_REFRESH_MAX" to JSONObject.NULL, "DEBUG" to JSONObject.NULL))

        assertEquals(emptyList<String>(), ConfigFields.invalidKeys(unset))
        assertEquals(emptyList<String>(), ConfigFields.invalidKeys(nulls))
    }

    @Test
    fun `text read as a number or boolean, and numbers written as text, are fine`() {
        val coercible = AppConfigFactory.offSchema(
            mapOf("AD_REFRESH_MAX" to "5", "DEBUG" to "TRUE", "GPP_ENABLED" to "false", "IAB_CATS" to "IAB15"),
        )

        assertEquals(emptyList<String>(), ConfigFields.invalidKeys(coercible))
    }

    @Test
    fun `values of the wrong type are named in the order apply reads them`() {
        val raw = AppConfigFactory.offSchema(
            mapOf(
                "TITLE" to JSONObject().put("text", "x"),
                "MOBILE_BANNER_ZID" to jsonArrayOf(),
                "MOBILE_ZID" to "fixture-mobile-300x250",
                "AD_REFRESH_MAX" to "five",
                "MAX_FAILED_AUCTIONS" to true,
                "IAB_CATS" to 15,
                "DEBUG" to 1,
                "PBS_DEBUG" to "yes",
            ),
        )

        assertEquals(
            listOf("TITLE", "MOBILE_BANNER_ZID", "MOBILE_ZID", "AD_REFRESH_MAX", "MAX_FAILED_AUCTIONS", "IAB_CATS", "DEBUG", "PBS_DEBUG"),
            ConfigFields.invalidKeys(raw),
        )
        val issue = ConfigFields.issues(raw).single()
        assertEquals(SellwildFailureCode.CONFIG_FIELD_INVALID, issue.code)
        assertEquals("remoteConfig", issue.component)
        assertEquals("warn", issue.severity)
        assertEquals(
            "ignored or coerced: TITLE, MOBILE_BANNER_ZID, MOBILE_ZID, AD_REFRESH_MAX, MAX_FAILED_AUCTIONS, IAB_CATS, DEBUG, PBS_DEBUG",
            issue.message,
        )
    }

    @Test
    fun `a valid config has no issue`() {
        assertEquals(emptyList<Issue>(), ConfigFields.issues(AppConfigFactory.checked()))
    }

    @Test
    fun `every key apply reads is listed, and the every-mapped-key factory sets each one`() {
        assertEquals(52, ConfigFields.KINDS.size)
        assertEquals(ConfigFields.Kind.TEXT_LIST_OR_TEXT, ConfigFields.KINDS["IAB_CATS"])
        val set = AppConfigFactory.everyMappedKey().keys().asSequence().toSet()
        assertEquals(emptyList<String>(), ConfigFields.KINDS.keys.filterNot { it in set })
    }
}
