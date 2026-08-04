// SellwildHouseAdView.kt — renders the house-ad backdrop.
//
// Two content modes, driven by SellwildHouseAd.resolve precedence:
//   - image:   a CMS-configured house creative (fit into the slot).
//   - listing: a Sellwild listing card (full-bleed photo + title/price overlay),
//              used when no image is configured. Supplied by the feed; only
//              meaningful for the MREC slot (a 320x50 banner is too small).
//
// The view sits BEHIND the paid creative in SellwildAdView and is only ever
// seen when that creative is absent. A tap opens the creative's click URL (or
// the listing's tap URL) via the owning ad view.

package com.sellwild.sdk

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal class SellwildHouseAdView(context: Context) : FrameLayout(context) {

    /** Invoked when the house ad is tapped; the owner routes it to the URL. */
    var onTap: (() -> Unit)? = null

    private val imageView: ImageView
    private val overlay: LinearLayout
    private val titleView: TextView
    private val priceView: TextView

    init {
        layoutParams = LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        isClickable = true
        isFocusable = true
        setOnClickListener { onTap?.invoke() }

        imageView = ImageView(context).apply {
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        addView(imageView)

        // Bottom scrim + title/price, shown only in listing mode.
        titleView = TextView(context).apply {
            textSize = 14f
            maxLines = 2
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
        }
        priceView = TextView(context).apply {
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
        }
        val pad = dp(10)
        overlay = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.BOTTOM
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.TRANSPARENT, Color.parseColor("#A6000000")),
            )
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            visibility = GONE
            addView(titleView)
            addView(priceView)
        }
        addView(overlay)
    }

    /** Render a CMS house image (fit into the slot; creatives are slot-sized). */
    fun showImage(creative: SellwildHouseAd.Creative) {
        overlay.visibility = GONE
        imageView.scaleType = ImageView.ScaleType.FIT_CENTER
        imageView.setBackgroundColor(Color.TRANSPARENT)
        SellwildHouseAd.loadImage(context, creative.imageUrl) { bmp -> bmp?.let { imageView.setImageBitmap(it) } }
    }

    /** Render a Sellwild listing as the house ad (full-bleed photo + overlay). */
    fun showListing(listing: SellwildListing, config: SellwildConfig) {
        overlay.visibility = VISIBLE
        imageView.scaleType = ImageView.ScaleType.CENTER_CROP
        imageView.setBackgroundColor(Color.parseColor("#EEEEEE"))
        titleView.text = listing.title
        priceView.text = formatPrice(listing.currency, listing.price)
        listing.photos.firstOrNull()?.url?.let { url ->
            SellwildHouseAd.loadImage(context, url) { bmp -> bmp?.let { imageView.setImageBitmap(it) } }
        }
    }

    private fun dp(value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()

    private fun formatPrice(currency: String?, price: String?): String {
        val value = price?.toDoubleOrNull() ?: return ""
        val sym = when (currency?.uppercase()) {
            "EUR" -> "€"
            "GBP" -> "£"
            else -> "$"
        }
        return if (value % 1.0 == 0.0) "$sym${value.toInt()}" else "$sym${"%.2f".format(value)}"
    }
}
