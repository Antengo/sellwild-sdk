package com.sellwild.sdk

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.FixtureLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/**
 * The audio guard's remote toggle, the shim's contents and the result it returns. The
 * WebView side runs in SellwildAdAdaptersTest (Robolectric); the shim itself runs in the
 * page. Parity with iOS on the pure bits.
 */
class SellwildAdAudioGuardTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun enabled(value: Any?) = SellwildAdAudioGuard.isEnabled(AppConfigFactory.checked(mapOf("MOBILE_AD_MUTE_AUTOPLAY" to value)).toString())

    @Test
    fun `enabled by default`() {
        assertTrue(SellwildAdAudioGuard.isEnabled(null))
        assertTrue(enabled(null))
        assertTrue(SellwildAdAudioGuard.isEnabled(FixtureLoader.text("fixtures/app-config/valid/flags-mixed-types.json")))
    }

    @Test
    fun `disable via remote flag`() {
        assertFalse(enabled(false))
        assertFalse(enabled("off"))
        assertFalse(enabled(0))
        assertTrue(enabled(true))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `config that does not parse keeps the guard on and is reported`() {
        assertTrue(SellwildAdAudioGuard.isEnabled(FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")))

        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), sink.pushed.map { it.action })
    }

    @Test
    fun `mute script forces mute, observes media, and returns its error count`() {
        val js = SellwildAdAudioGuard.MUTE_SCRIPT
        assertTrue(js.contains("HTMLMediaElement"))
        assertTrue(js.contains("muted = true"))
        assertTrue(js.contains("MutationObserver"))
        assertTrue(js.contains("__swAudioGuard"))
        assertTrue(js.contains("video, audio"))
        assertTrue(js.contains("return errors;"))
    }

    @Test
    fun `no catch in the shim is empty`() {
        val catches = Regex("""catch\s*\(\s*\w+\s*\)\s*\{([^}]*)\}""").findAll(SellwildAdAudioGuard.MUTE_SCRIPT).map { it.groupValues[1].trim() }.toList()

        assertEquals(5, catches.size)
        assertEquals(List(5) { "fail();" }, catches)
    }

    @Test
    fun `the evaluate result is the shim's error count`() {
        assertEquals(2, SellwildAdAudioGuard.shimErrors("2"))
        assertEquals(0, SellwildAdAudioGuard.shimErrors("0"))
        assertEquals(0, SellwildAdAudioGuard.shimErrors("null"))
        assertEquals(0, SellwildAdAudioGuard.shimErrors(null))
    }
}
