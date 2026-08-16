// SellwildHouseAdView.kt — renders the house-ad backdrop.
//
// Two content modes, driven by SellwildHouseAd.resolve precedence:
//   - image:   a CMS-configured house creative (fit, full-bleed into the slot;
//              creatives are designed to the slot).
//   - listing: a Sellwild listing rendered as a compact card that mirrors the
//              feed's real listing card — white card, photo on top, title + price
//              below. Used when no image is configured. Supplied by the feed;
//              only meaningful for the MREC slot (a 320x50 banner is too small).
//
// The view sits BEHIND the paid creative in SellwildAdView and is shown only
// when that creative is absent (no-fill). SellwildAdView hides it on paid fill,
// so a transparent or undersized creative can't let it bleed through. A tap
// opens the creative's click URL (or the listing's tap URL) via the owner.

package com.sellwild.sdk

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal class SellwildHouseAdView(context: Context) : FrameLayout(context) {

    /** Invoked when the house ad is tapped; the owner routes it to the URL. */
    var onTap: (() -> Unit)? = null

    private val imageView: ImageView
    private val textArea: LinearLayout
    private val titleView: TextView
    private val priceView: TextView
    private val card: LinearLayout

    // The image URL currently being loaded. Guards against a reused view (the
    // owning SellwildAdView is pooled in feed rows) applying a stale async image
    // after the content was swapped — the feed's own cell guards the same way.
    private var pendingImageUrl: String? = null

    init {
        layoutParams = LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        isClickable = true
        isFocusable = true
        setOnClickListener { onTap?.invoke() }

        imageView = ImageView(context)

        titleView = TextView(context).apply {
            textSize = 15f
            maxLines = 2
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.rgb(18, 23, 38))          // ListingCardCell title
        }
        priceView = TextView(context).apply {
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.rgb(38, 99, 235))         // ListingCardCell price/link blue
        }
        val padH = dp(12)
        textArea = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padH, dp(8), padH, dp(12))
            addView(titleView)
            addView(priceView)
            visibility = GONE
        }

        // Vertical card: photo on top (fills the space above), text below. In
        // image mode the text area is GONE so the photo fills the whole slot.
        card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            addView(
                imageView,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
            )
            addView(
                textArea,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        addView(card)
    }

    /** Render a CMS house image (fit into the slot; creatives are slot-sized). */
    fun showImage(creative: SellwildHouseAd.Creative) {
        textArea.visibility = GONE
        card.setBackgroundColor(Color.TRANSPARENT)
        imageView.scaleType = ImageView.ScaleType.FIT_CENTER
        imageView.setBackgroundColor(Color.TRANSPARENT)
        loadImage(creative.imageUrl)
    }

    /** Render a Sellwild listing as a compact card (photo on top, title + price
     *  below on a white card) so it reads like the feed's listing cards. */
    fun showListing(listing: SellwildListing, config: SellwildConfig) {
        textArea.visibility = VISIBLE
        card.setBackgroundColor(Color.WHITE)
        imageView.scaleType = ImageView.ScaleType.CENTER_CROP
        imageView.setBackgroundColor(Color.parseColor("#EEEEEE"))
        titleView.text = listing.title
        priceView.text = formatPrice(listing.currency, listing.price)
        loadImage(listing.primaryPhotoUrl)
    }

    /** Load [url] into the image view, ignoring a result that arrives after the
     *  content was swapped (reused view). Clears any prior image first. */
    private fun loadImage(url: String?) {
        pendingImageUrl = url
        imageView.setImageDrawable(null)
        if (url.isNullOrEmpty()) return
        SellwildHouseAd.loadImage(context, url) { bmp ->
            if (pendingImageUrl == url) bmp?.let { imageView.setImageBitmap(it) }
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
