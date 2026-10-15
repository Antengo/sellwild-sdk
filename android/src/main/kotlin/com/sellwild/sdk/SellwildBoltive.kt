// SellwildBoltive.kt — Boltive ad-quality monitoring for rendered banners.
//
// Boltive watches the creative WebView inside a rendered banner and blanks a
// creative it flags as malicious/offensive, then calls us back. It runs AFTER
// render (it does not filter bids before the auction), so every render we
// skip is unmonitored. The policy below decides which renders get a monitor.
//
// Remote config (all default OFF / unlimited):
//   MOBILE_BOLTIVE_ENABLED          bool — master switch (default false)
//   MOBILE_BOLTIVE_ENABLED_ANDROID  bool or "on"/"off" — platform override; off
//                                   is a hard kill, on turns it on everywhere on
//                                   Android. Blank (the CMS select's default) = unset
//   MOBILE_BOLTIVE_ENABLED_BY_ZONE  {zoneId: bool} — per-zone opt-in when the
//                                   global switch is off
//   MOBILE_BOLTIVE_CLIENT_ID        string — Boltive client id; empty ⇒ off
//   MOBILE_BOLTIVE_SAMPLE_RATE      0–1 — share of renders monitored (default 1)
//   MOBILE_BOLTIVE_MAX_PER_SESSION  int — monitored renders per app process
//                                   (0/absent = unlimited)
//   MOBILE_BOLTIVE_MAX_PER_SLOT     int — monitored renders per ad view
//                                   (0/absent = unlimited)
//
// On a block, SellwildAdView hides the paid creative, shows the house backdrop,
// emits `adBlocked`, and re-auctions if the refresh cap has budget.

package com.sellwild.sdk

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import com.boltive.api.AdNetwork
import com.boltive.api.AdViewConfiguration
import com.boltive.api.BoltiveConfiguration
import com.boltive.api.BoltiveListener
import com.boltive.api.BoltiveMonitor
import com.boltive.api.BoltiveTagDetails
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger
import kotlin.random.Random

internal object SellwildBoltive {

    /** Resolved settings for one placement. `null` from [policy] means off. */
    data class Policy(
        val clientId: String,
        val sampleRate: Double,
        val maxPerSession: Int,
        val maxPerSlot: Int,
    )

    /** Which ad server rendered the creative; maps to Boltive's ad network. */
    enum class Network { GAM, PREBID }

    /** Monitored renders this app process. */
    val sessionCount = AtomicInteger(0)

    /** Whether Boltive is enabled for this placement. See the file header. */
    fun isEnabled(remoteJson: String?, zoneId: String?): Boolean {
        val obj = parse(remoteJson) ?: return false
        val platform = obj.opt("MOBILE_BOLTIVE_ENABLED_ANDROID")
        if (platform != null && platform != JSONObject.NULL && !(platform is String && platform.isBlank())) {
            return truthy(platform)
        }
        if (truthy(obj.opt("MOBILE_BOLTIVE_ENABLED"))) return true
        if (zoneId != null) {
            val byZone = obj.optJSONObject("MOBILE_BOLTIVE_ENABLED_BY_ZONE")
            if (byZone != null && byZone.has(zoneId)) return truthy(byZone.opt(zoneId))
        }
        return false
    }

    /** The monitoring policy for this placement, or null when Boltive is off
     *  (disabled, or no client id). */
    fun policy(remoteJson: String?, zoneId: String?): Policy? {
        if (!isEnabled(remoteJson, zoneId)) return null
        val obj = parse(remoteJson) ?: return null
        val clientId = obj.optString("MOBILE_BOLTIVE_CLIENT_ID", "").trim()
        if (clientId.isEmpty()) return null
        val rate = number(obj.opt("MOBILE_BOLTIVE_SAMPLE_RATE")) ?: 1.0
        return Policy(
            clientId = clientId,
            sampleRate = rate.coerceIn(0.0, 1.0),
            maxPerSession = (number(obj.opt("MOBILE_BOLTIVE_MAX_PER_SESSION")) ?: 0.0).toInt().coerceAtLeast(0),
            maxPerSlot = (number(obj.opt("MOBILE_BOLTIVE_MAX_PER_SLOT")) ?: 0.0).toInt().coerceAtLeast(0),
        )
    }

    /** Whether this render gets a monitor. Caps are checked before the sample
     *  roll; [roll] is in [0, 1). */
    fun shouldMonitor(policy: Policy, slotCount: Int, sessionCount: Int, roll: Double): Boolean {
        if (policy.maxPerSlot > 0 && slotCount >= policy.maxPerSlot) return false
        if (policy.maxPerSession > 0 && sessionCount >= policy.maxPerSession) return false
        return roll < policy.sampleRate
    }

    private fun parse(remoteJson: String?): JSONObject? =
        remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun truthy(v: Any?): Boolean = when (v) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v.lowercase() in setOf("1", "true", "yes", "on")
        else -> false
    }

    private fun number(v: Any?): Double? = when (v) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }
}

/**
 * Per-ad-view Boltive monitor. Created once per [SellwildAdView]; holds at most
 * one live [BoltiveMonitor]. Each monitored render gets a fresh monitor and the
 * previous one is terminated first: a monitor's timer keeps polling the
 * creative WebView it captured, which a refresh destroys. A render that isn't
 * monitored terminates it too, so a sampled-out render costs nothing. Main
 * thread only.
 */
internal class SellwildBoltiveController {

    /** Details Boltive attaches to a block report. */
    data class Tag(
        val adUnitId: String,
        val advertiserId: String? = null,
        val creativeId: String? = null,
        val campaignId: String? = null,
        val sspRefreshCode: String? = null,
    )

    /** Monitored renders for this ad view. */
    var slotCount = 0
        private set

    private var monitor: BoltiveMonitor? = null

    /** Monitors created by this controller (for tests). */
    internal var monitorsCreated = 0
        private set
    private val main = Handler(Looper.getMainLooper())

    /**
     * Decide whether to monitor this render and, if so, capture [bannerView].
     * [onBlocked] runs on the main thread with the view that was blocked.
     * Returns whether a monitor was attached.
     */
    fun renderDidSucceed(
        bannerView: View,
        widthDp: Int,
        heightDp: Int,
        network: SellwildBoltive.Network,
        remoteJson: String?,
        zoneId: String?,
        tag: Tag,
        debug: Boolean = false,
        roll: Double = Random.nextDouble(),
        onBlocked: (View) -> Unit,
    ): Boolean {
        val policy = SellwildBoltive.policy(remoteJson, zoneId)
        if (policy == null ||
            !SellwildBoltive.shouldMonitor(policy, slotCount, SellwildBoltive.sessionCount.get(), roll)
        ) {
            stop()
            return false
        }
        // End the previous render's monitor before capturing the new creative.
        stop()
        val adNetwork = if (network == SellwildBoltive.Network.GAM) AdNetwork.GAM else AdNetwork.custom("Prebid")
        val m = BoltiveMonitor(BoltiveConfiguration(policy.clientId, adNetwork))
        monitor = m
        monitorsCreated++
        val details = BoltiveTagDetails(tag.adUnitId).apply {
            tag.advertiserId?.let { advertiserId = it }
            tag.creativeId?.let { creativeId = it }
            tag.campaignId?.let { campaignId = it }
            tag.sspRefreshCode?.let { sspRefreshCode = it }
        }
        val blocked = java.lang.ref.WeakReference(bannerView)
        val captured = runCatching {
            m.capture(bannerView, AdViewConfiguration(widthDp, heightDp, details), object : BoltiveListener {
                override fun onAdBlocked() {
                    main.post { blocked.get()?.let(onBlocked) }
                }
            })
        }
        if (captured.isFailure) {
            Log.w(TAG, "Boltive capture failed: ${captured.exceptionOrNull()?.message}")
            stop()
            return false
        }
        slotCount++
        val session = SellwildBoltive.sessionCount.incrementAndGet()
        if (debug) Log.d(TAG, "monitoring render — zone ${zoneId.orEmpty()}, $network, slot #$slotCount, session #$session")
        return true
    }

    /** Terminate the live monitor (if any). */
    fun stop() {
        monitor?.let { runCatching { it.terminate() } }
        monitor = null
    }

    private companion object {
        const val TAG = "SellwildBoltive"
    }
}
