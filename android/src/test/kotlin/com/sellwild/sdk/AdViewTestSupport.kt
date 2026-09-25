package com.sellwild.sdk

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.AdSize as PrebidAdSize
import com.sellwild.prebid.configuration.AdUnitConfiguration
import com.sellwild.prebid.rendering.bidding.data.bid.BidResponse
import com.sellwild.prebid.api.rendering.BannerView
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import java.time.Duration

/** Every SellwildAdView.Listener callback, in order, as short text. */
internal class AdEvents : SellwildAdView.Listener {
    val calls = mutableListOf<String>()

    override fun onAdLoaded(adView: SellwildAdView) {
        calls += "loaded"
    }

    override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
        calls += "impression:$zoneId"
    }

    override fun onAdClicked(adView: SellwildAdView) {
        calls += "clicked"
    }

    override fun onAdFailed(adView: SellwildAdView, message: String) {
        calls += "failed:$message"
    }

    override fun onAdResize(adView: SellwildAdView, width: Int, height: Int) {
        calls += "resize:${width}x$height"
    }

    override fun onHouseAdImpression(adView: SellwildAdView, zoneId: String) {
        calls += "house:$zoneId"
    }
}

/** Runs the main looper for [ms] of fake time: posted and delayed work runs. */
internal fun idleFor(ms: Long) {
    shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
}

internal fun idle() {
    shadowOf(Looper.getMainLooper()).idle()
}

internal fun ViewGroup.childrenList(): List<View> = (0 until childCount).map(::getChildAt)

internal fun SellwildAdView.gam(): AdManagerAdView = childrenList().filterIsInstance<AdManagerAdView>().single()

internal fun SellwildAdView.prebid(): BannerView = childrenList().filterIsInstance<BannerView>().single()

internal fun SellwildAdView.native(): SellwildNativeAdView = childrenList().filterIsInstance<SellwildNativeAdView>().single()

internal fun SellwildAdView.house(): SellwildHouseAdView? = childrenList().filterIsInstance<SellwildHouseAdView>().singleOrNull()

/** A visible activity to attach views to (and to start Custom Tabs from). */
internal fun newActivity(): Activity = Robolectric.buildActivity(Activity::class.java).setup().get()

/** Puts [view] in [activity]'s window, in a parent of [width]x[height] px, so it is attached. */
internal fun attach(activity: Activity, view: View, width: Int = 1080, height: Int = 900, lp: ViewGroup.LayoutParams? = null): FrameLayout {
    val parent = FrameLayout(activity)
    parent.addView(view, lp ?: FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    activity.setContentView(parent, ViewGroup.LayoutParams(width, height))
    idle()
    return parent
}

/** A context whose startActivity always fails, as on a device with no browser. */
internal class NoBrowserContext(base: Context) : ContextWrapper(base) {
    override fun startActivity(intent: Intent?) = throw ActivityNotFoundException("No Activity found to handle Intent")

    override fun startActivity(intent: Intent?, options: Bundle?) = throw ActivityNotFoundException("No Activity found to handle Intent")
}

/** A context whose startActivity throws [error], an Error rather than an exception. */
internal class ErrorOnStartContext(base: Context, private val error: Error) : ContextWrapper(base) {
    override fun startActivity(intent: Intent?) = throw error

    override fun startActivity(intent: Intent?, options: Bundle?) = throw error
}

/**
 * A Prebid rendering banner as a test controls it: the winning bid, the won creative size, and
 * whether stopRefresh() was called.
 */
internal class FakeBanner(
    context: Context,
    private val response: BidResponse? = null,
    private val wonWidth: Int = 0,
    private val wonHeight: Int = 0,
) : BannerView(context, "43", PrebidAdSize(300, 250)) {
    var stopped = 0

    override fun getBidResponse(): BidResponse? = response

    override fun getCreativeWidth(): Int = wonWidth

    override fun getCreativeHeight(): Int = wonHeight

    override fun stopRefresh() {
        stopped++
        super.stopRefresh()
    }
}

/** A winning bid whose isVideo() is [video], or throws [error]. */
internal class FakeBid(private val video: Boolean = false, private val error: Throwable? = null) :
    BidResponse("{}", AdUnitConfiguration()) {
    override fun isVideo(): Boolean {
        error?.let { throw it }
        return video
    }
}

/** The imp ext JSON Prebid will send ([impOrtbConfig]): its bidders and GPID. */
internal fun impExt(impOrtbConfig: String?): Pair<Set<String>, String?> {
    val ext = org.json.JSONObject(checkNotNull(impOrtbConfig) { "no imp ext" }).getJSONObject("ext")
    val bidders = ext.optJSONObject("prebid")?.optJSONObject("bidder")?.keys()?.asSequence()?.toSet().orEmpty()
    return bidders to ext.optString("gpid").ifEmpty { null }
}

/** A 1x1 bitmap, as a decoded image. */
internal fun pixel(): Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
