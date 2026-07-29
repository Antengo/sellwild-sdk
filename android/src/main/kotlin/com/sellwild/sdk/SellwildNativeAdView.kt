// SellwildNativeAdView.kt — renders a Prebid native ad into a default template
// and wires impression / click tracking.
//
// Native, unlike banner/outstream, is not auto-rendered by the fork: Prebid
// fetches demand and hands back a PrebidNativeAd of raw assets (title, body,
// icon, main image, CTA, sponsoredBy). We lay them out here and call
// registerViewList(...) so the fork fires the impression / click trackers
// against our views.
//
// Hosted inside SellwildAdView when NATIVE_ENABLED resolves on a PREBID_ONLY
// placement — it reuses the same ad slot. The layout is a standard template:
// icon + title + sponsoredBy on top, main media in the middle, body + CTA at
// the bottom. Built programmatically to avoid an XML dependency.

package com.sellwild.sdk

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.net.URL
import com.sellwild.prebid.NativeAdUnit
import com.sellwild.prebid.PrebidNativeAd
import com.sellwild.prebid.PrebidNativeAdEventListener
import com.sellwild.prebid.ResultCode

class SellwildNativeAdView(
    context: Context,
    private val config: SellwildConfig,
    private val zoneId: String,
    private val maxHeightDp: Int,
) : FrameLayout(context) {

    // Forwarded to the hosting SellwildAdView's listener.
    var onLoaded: (() -> Unit)? = null
    var onImpression: (() -> Unit)? = null
    var onClick: (() -> Unit)? = null
    var onFailed: ((String) -> Unit)? = null

    // Strong reference: the fork's native ad must outlive fetchDemand or its
    // trackers / click handling are torn down.
    private var nativeAd: PrebidNativeAd? = null
    private var nativeAdUnit: NativeAdUnit? = null

    private val iconView: ImageView
    private val titleView: TextView
    private val sponsoredView: TextView
    private val mediaView: ImageView
    private val bodyView: TextView
    private val ctaButton: Button

    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        val dp = resources.displayMetrics.density
        fun px(v: Int) = (v * dp).toInt()

        iconView = ImageView(context).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        titleView = TextView(context).apply {
            textSize = 15f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            maxLines = 2
        }
        sponsoredView = TextView(context).apply {
            textSize = 11f
            setTextColor(Color.GRAY)
        }
        mediaView = ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            setBackgroundColor(Color.parseColor("#EEEEEE"))
        }
        bodyView = TextView(context).apply {
            textSize = 13f
            maxLines = 3
        }
        ctaButton = Button(context).apply {
            isAllCaps = false
            setOnClickListener { onClick?.invoke() }
        }

        // Header: icon + (title / sponsored)
        val titleStack = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(titleView)
            addView(sponsoredView)
        }
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(iconView, LinearLayout.LayoutParams(px(40), px(40)).apply { rightMargin = px(8) })
            addView(titleStack, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }

        // Footer: body (grows) + CTA (hugs trailing)
        val footer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(bodyView, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { rightMargin = px(8) })
            addView(ctaButton, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        // Fixed-height root = the hard cap; the media (height 0 + weight 1)
        // absorbs the leftover space, while header/footer stay WRAP_CONTENT so
        // title / sponsoredBy / body / CTA are never squeezed out.
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(8), px(8), px(8), px(8))
            addView(header, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(mediaView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).apply { topMargin = px(8); bottomMargin = px(8) })
            addView(footer, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }
        addView(root, LayoutParams(LayoutParams.MATCH_PARENT, px(maxHeightDp)))
    }

    // MARK: Load

    /** Request native demand and, on a win, bind + register the assets. */
    fun load() {
        val unit = SellwildNative.makeRequest(zoneId)
        nativeAdUnit = unit
        // Pass a Bundle as the ad object so the fork writes the winning cache
        // id into `BUNDLE_KEY_CACHE_ID` (Util.saveCacheId Bundle path). We
        // then hand that id to `PrebidNativeAd.create(cacheId)`.
        val adBundle = Bundle()
        unit.fetchDemand(adBundle) { resultCode ->
            if (resultCode != ResultCode.SUCCESS) {
                if (config.debug) android.util.Log.d("SellwildNativeAdView", "[native] no fill — zone $zoneId, result $resultCode")
                onFailed?.invoke("Native demand request returned no fill ($resultCode).")
                return@fetchDemand
            }
            val cacheId = adBundle.getString(NativeAdUnit.BUNDLE_KEY_CACHE_ID)
            val ad = cacheId?.let { PrebidNativeAd.create(it) }
            if (ad == null) {
                onFailed?.invoke("Native demand won but no PrebidNativeAd could be created.")
                return@fetchDemand
            }
            mainHandler.post { bind(ad) }
        }
    }

    // MARK: Bind

    private fun bind(ad: PrebidNativeAd) {
        nativeAd = ad

        titleView.text = ad.title
        bodyView.text = ad.description
        sponsoredView.text = ad.sponsoredBy?.takeIf { it.isNotEmpty() }?.let { "Sponsored · $it" } ?: "Sponsored"
        ctaButton.text = ad.callToAction?.takeIf { it.isNotEmpty() } ?: "Learn more"

        loadImage(ad.iconUrl, iconView)
        loadImage(ad.imageUrl, mediaView)

        // Register for impression / click tracking. Shaded fork uses
        // `registerView(container, clickableViews, listener)`.
        ad.registerView(this, listOf(ctaButton, titleView, mediaView), object : PrebidNativeAdEventListener {
            override fun onAdClicked() { onClick?.invoke() }
            override fun onAdImpression() { onImpression?.invoke() }
            override fun onAdExpired() {
                if (config.debug) android.util.Log.d("SellwildNativeAdView", "[native] ad expired — zone $zoneId")
            }
        })

        onLoaded?.invoke()
    }

    // MARK: Image loading (dependency-free)

    private fun loadImage(urlString: String?, target: ImageView) {
        val url = urlString?.takeIf { it.isNotEmpty() } ?: return
        Thread {
            val bmp = runCatching {
                URL(url).openStream().use { BitmapFactory.decodeStream(it) }
            }.getOrNull() ?: return@Thread
            mainHandler.post { target.setImageBitmap(bmp) }
        }.start()
    }

    fun destroy() {
        // Native ad units are one-shot (no auto-refresh to stop); just release.
        nativeAd = null
        nativeAdUnit = null
    }
}
