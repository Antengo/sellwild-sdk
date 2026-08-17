package com.sellwild.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the best-effort ad audio guard — the remote-config gate and
 * the mute-shim contents. (WebView traversal + the actual muting need Android
 * framework / a live creative, so they're covered by instrumentation / on-device
 * and by the iOS `SellwildAdAudioGuardTests`.) Parity with iOS on the pure bits.
 */
class SellwildAdAudioGuardTest {

    @Test
    fun `enabled by default`() {
        assertTrue(SellwildAdAudioGuard.isEnabled(null))
        assertTrue(SellwildAdAudioGuard.isEnabled("""{"CODE":"weatherbug"}"""))
    }

    @Test
    fun `disable via remote flag`() {
        assertFalse(SellwildAdAudioGuard.isEnabled("""{"MOBILE_AD_MUTE_AUTOPLAY":false}"""))
        assertFalse(SellwildAdAudioGuard.isEnabled("""{"MOBILE_AD_MUTE_AUTOPLAY":"off"}"""))
        assertFalse(SellwildAdAudioGuard.isEnabled("""{"MOBILE_AD_MUTE_AUTOPLAY":0}"""))
        assertTrue(SellwildAdAudioGuard.isEnabled("""{"MOBILE_AD_MUTE_AUTOPLAY":true}"""))
    }

    @Test
    fun `mute script forces mute and observes media`() {
        val js = SellwildAdAudioGuard.MUTE_SCRIPT
        assertTrue(js.contains("HTMLMediaElement"))
        assertTrue(js.contains("muted = true"))
        assertTrue(js.contains("MutationObserver"))
        assertTrue(js.contains("__swAudioGuard"))
        assertTrue(js.contains("video, audio"))
    }
}
