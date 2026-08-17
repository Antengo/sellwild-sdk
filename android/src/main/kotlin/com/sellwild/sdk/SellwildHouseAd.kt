// SellwildHouseAd.kt — client-side house-ad backfill.
//
// When a paid creative is absent — a no-fill, or the transient blank while a
// PREBID_ONLY slot tears down one creative and renders the next on refresh —
// the ad slot would otherwise flash empty. House ads fill that gap with our own
// inventory, entirely client-side (no GAM house line items, which don't exist
// on the PREBID_ONLY path anyway).
//
// The mechanism is a BACKDROP: a house view sits *behind* the paid creative and
// shows through only when the slot is empty. When a real creative renders on
// top it covers the house ad, so the slot auto-reverts to the paid ad with no
// explicit "blank detected" event (there isn't one for the refresh gap).
//
// Content precedence, resolved per placement from remote config (no release):
//   1. CMS house image  — MOBILE_HOUSE_AD_IMAGE / MOBILE_HOUSE_AD_URL, with optional
//      per-size (MOBILE_HOUSE_AD_BY_SIZE) and per-zone (MOBILE_HOUSE_AD_BY_ZONE) overrides.
//   2. A Sellwild listing — supplied by the feed when no image is configured
//      (MREC only; a 320x50 banner is too small for a card).
//   3. Nothing — the slot stays empty, today's behavior.
//
// Master switch: MOBILE_HOUSE_AD_ENABLED (default true) kills all backfill, image and
// listing alike, so ops can revert to the plain-blank behavior remotely.
//
// Images are cached locally — in-memory plus an on-disk copy in the app cache
// directory — so a house image is fetched from the network at most once per
// device, not once per empty slot. This is a deliberate request-saving measure.

package com.sellwild.sdk

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import org.json.JSONObject
import java.io.File

internal object SellwildHouseAd {

    /** A resolved house-ad creative: an image to render and an optional tap URL. */
    data class Creative(val imageUrl: String, val clickUrl: String?)

    /**
     * Whether house-ad backfill is enabled for this app. Defaults to `true`; set
     * `MOBILE_HOUSE_AD_ENABLED: false` in the CDN config to disable all backfill (image
     * and listing) and restore the plain-blank behavior.
     */
    fun isEnabled(remoteJson: String?): Boolean {
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return true
        val v = obj.optAny("MOBILE_HOUSE_AD_ENABLED") ?: return true
        return when (v) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            is String -> v.lowercase() !in setOf("0", "false", "no", "off")
            else -> true
        }
    }

    /**
     * Resolve the house image creative for a placement, most specific first:
     *   1. MOBILE_HOUSE_AD_BY_ZONE[zoneId]      — { "image": ..., "url": ... }
     *   2. MOBILE_HOUSE_AD_BY_SIZE["<w>x<h>"]   — { "image": ..., "url": ... }
     *   3. MOBILE_HOUSE_AD_IMAGE + MOBILE_HOUSE_AD_URL — the app-wide default
     *
     * The image field (top-level `MOBILE_HOUSE_AD_IMAGE` or the `image` inside a
     * by-zone / by-size object) accepts **either a single URL string or an array
     * of URL strings**. For an array, one URL is chosen at random on each call —
     * i.e. each no-fill — so backfill rotates. The chosen image is lazily fetched
     * by [loadImage] and cached (memory + disk) per URL the first time selected.
     * The click URL (`MOBILE_HOUSE_AD_URL` / `url`) is paired the same way: a
     * single string is shared across all images, or an array pairs one click URL
     * per image by index.
     *
     * Returns null when disabled or no image is configured (the caller then
     * falls back to a listing, or leaves the slot empty).
     */
    fun resolve(remoteJson: String?, zoneId: String?, widthDp: Int, heightDp: Int): Creative? {
        if (!isEnabled(remoteJson)) return null
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null

        if (zoneId != null) {
            obj.optJSONObject("MOBILE_HOUSE_AD_BY_ZONE")?.optJSONObject(zoneId)?.let { creative(it)?.let { c -> return c } }
        }
        val sizeKey = "${widthDp}x${heightDp}"
        obj.optJSONObject("MOBILE_HOUSE_AD_BY_SIZE")?.optJSONObject(sizeKey)?.let { creative(it)?.let { c -> return c } }

        pickCreative(obj.opt("MOBILE_HOUSE_AD_IMAGE"), obj.opt("MOBILE_HOUSE_AD_URL"))?.let { return it }
        return null
    }

    private fun creative(obj: JSONObject): Creative? =
        pickCreative(obj.opt("image"), obj.opt("url"))

    /**
     * Pick a house creative — an image and its paired click URL — from `image`
     * and `url` values that are each either a single URL string or a JSON array
     * of URL strings. One index is chosen at random per call (per no-fill), so an
     * array of images rotates. The click URL pairs by the image's **original**
     * index when `url` is an array (one per image); a single `url` string is
     * shared across all images; a missing/blank paired entry yields no click.
     * Returns null when there's no usable image.
     */
    private fun pickCreative(imageValue: Any?, urlValue: Any?): Creative? {
        // Non-empty images with their original index for URL pairing.
        val images: List<Pair<Int, String>> = when (imageValue) {
            is org.json.JSONArray ->
                (0 until imageValue.length()).mapNotNull { i ->
                    nonEmpty(imageValue.optString(i))?.let { i to it }
                }
            is String -> nonEmpty(imageValue)?.let { listOf(0 to it) } ?: emptyList()
            else -> emptyList()
        }
        val picked = images.randomOrNull() ?: return null
        // Click URL: array → paired by the image's original index; string → shared.
        val click: String? = when (urlValue) {
            is org.json.JSONArray ->
                if (picked.first < urlValue.length()) nonEmpty(urlValue.optString(picked.first)) else null
            is String -> nonEmpty(urlValue)
            else -> null
        }
        return Creative(picked.second, click)
    }

    private fun nonEmpty(s: String?): String? = s?.trim()?.takeIf { it.isNotEmpty() }

    // ── Local image cache (memory + disk) ────────────────────────────────────

    private val memory = LruCache<String, Bitmap>(8)

    private fun diskFile(context: Context, url: String): File {
        val dir = File(context.cacheDir, "sellwild_house").apply { mkdirs() }
        // Stable (launch-independent) filename: djb2 hashed to hex.
        var hash = 5381L
        for (b in url.toByteArray()) hash = hash * 33 + b
        return File(dir, java.lang.Long.toHexString(hash))
    }

    /**
     * Load a house image: memory cache → disk cache → network (populating both).
     * [callback] is always invoked on the main thread; null on failure.
     */
    fun loadImage(context: Context, url: String, callback: (Bitmap?) -> Unit) {
        memory.get(url)?.let { callback(it); return }
        val appContext = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        Thread {
            val bitmap = runCatching {
                // data: URI — listing photos from the static cache can be inline
                // base64 (the feed's own cell decodes these too). Decode inline,
                // size-capped; memory-cache only, no disk churn. Without this, a
                // data: photo fails SellwildSafeUrl.imageUrl's http/https check
                // below and the slot shows a grey placeholder.
                if (url.startsWith("data:")) {
                    val comma = url.indexOf(',')
                    if (comma < 0) return@runCatching null
                    val bytes = android.util.Base64.decode(url.substring(comma + 1), android.util.Base64.DEFAULT)
                    if (bytes.size > SellwildSafeUrl.MAX_IMAGE_BYTES) return@runCatching null
                    return@runCatching BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }
                val disk = diskFile(appContext, url)
                if (disk.exists()) {
                    BitmapFactory.decodeFile(disk.absolutePath)
                } else {
                    // http/https only (reject file:// — URL is remote config) + cap.
                    val safe = SellwildSafeUrl.imageUrl(url) ?: return@runCatching null
                    val bytes = safe.openStream().use { it.readBytes() }
                    if (bytes.size > SellwildSafeUrl.MAX_IMAGE_BYTES) return@runCatching null
                    disk.writeBytes(bytes)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }
            }.getOrNull()
            if (bitmap != null) memory.put(url, bitmap)
            main.post { callback(bitmap) }
        }.start()
    }

    private fun JSONObject.optAny(key: String): Any? =
        if (has(key) && !isNull(key)) get(key) else null

    // ── Listing fallback selection ───────────────────────────────────────────

    /**
     * Whether a listing carries a usable (non-blank) primary photo URL. A
     * photoless listing renders as a grey placeholder, so the feed prefers to
     * skip it when picking a house-backfill listing.
     */
    fun hasUsablePhoto(listing: SellwildListing): Boolean =
        !listing.primaryPhotoUrl.isNullOrBlank()

    /**
     * Pick a listing to house-backfill an MREC slot, rotating by [row] so
     * adjacent slots don't repeat. Prefers listings that actually have a photo
     * (rotating within that subset); falls back to plain rotation over all
     * listings only when none have a usable photo. Null when empty.
     */
    fun pickListing(listings: List<SellwildListing>, row: Int): SellwildListing? {
        if (listings.isEmpty()) return null
        val withPhoto = listings.filter { hasUsablePhoto(it) }
        val pool = if (withPhoto.isEmpty()) listings else withPhoto
        return pool[((row % pool.size) + pool.size) % pool.size]
    }
}
