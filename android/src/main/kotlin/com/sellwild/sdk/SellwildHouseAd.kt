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
import android.util.Base64
import android.util.LruCache
import com.sellwild.sdk.core.HouseImages
import com.sellwild.sdk.core.RemoteValues
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URL
import kotlin.random.Random

internal object SellwildHouseAd {

    /** A resolved house-ad creative: an image to render and an optional tap URL. */
    data class Creative(val imageUrl: String, val clickUrl: String?)

    /**
     * Whether house-ad backfill is enabled for this app. Defaults to `true`; set
     * `MOBILE_HOUSE_AD_ENABLED: false` in the CDN config to disable all backfill (image
     * and listing) and restore the plain-blank behavior.
     */
    fun isEnabled(remoteJson: String?): Boolean = isEnabled(remoteObject(remoteJson))

    private fun isEnabled(obj: JSONObject?): Boolean =
        RemoteValues.isNotOff(RemoteValues.optAny(obj, "MOBILE_HOUSE_AD_ENABLED"))

    /**
     * Resolve the house image creative for a placement, most specific first:
     *   1. MOBILE_HOUSE_AD_BY_ZONE[zoneId]      — { "image": ..., "url": ... }
     *   2. MOBILE_HOUSE_AD_BY_SIZE["<w>x<h>"]   — { "image": ..., "url": ... }
     *   3. MOBILE_HOUSE_AD_IMAGE + MOBILE_HOUSE_AD_URL — the app-wide default
     *
     * The image field (top-level `MOBILE_HOUSE_AD_IMAGE` or the `image` inside a
     * by-zone / by-size object) accepts **either a single URL string or an array
     * of URL strings**. For an array, one URL is chosen with [random] on each call —
     * i.e. each no-fill — so backfill rotates. The chosen image is lazily fetched
     * by [loadImage] and cached (memory + disk) per URL the first time selected.
     * The click URL (`MOBILE_HOUSE_AD_URL` / `url`) is paired the same way: a
     * single string is shared across all images, or an array pairs one click URL
     * per image by index.
     *
     * Returns null when disabled or no image is configured (the caller then
     * falls back to a listing, or leaves the slot empty).
     */
    fun resolve(
        remoteJson: String?,
        zoneId: String?,
        widthDp: Int,
        heightDp: Int,
        random: Random = Random.Default,
    ): Creative? = candidates(remoteObject(remoteJson), zoneId, widthDp, heightDp).randomOrNull(random)

    /**
     * Every creative [resolve] picks from, pure: the first of BY_ZONE[zoneId],
     * BY_SIZE["<w>x<h>"] and IMAGE/URL that has a usable image, in index order. Empty
     * when disabled or when nothing is configured.
     */
    internal fun candidates(obj: JSONObject?, zoneId: String?, widthDp: Int, heightDp: Int): List<Creative> {
        if (obj == null || !isEnabled(obj)) return emptyList()
        val byZone = zoneId?.let { obj.optJSONObject("MOBILE_HOUSE_AD_BY_ZONE")?.optJSONObject(it) }
        val bySize = obj.optJSONObject("MOBILE_HOUSE_AD_BY_SIZE")?.optJSONObject("${widthDp}x$heightDp")
        return listOfNotNull(byZone, bySize)
            .map { creatives(it.opt("image"), it.opt("url")) }
            .firstOrNull { it.isNotEmpty() }
            ?: creatives(obj.opt("MOBILE_HOUSE_AD_IMAGE"), obj.opt("MOBILE_HOUSE_AD_URL"))
    }

    /**
     * The creatives from `image` and `url` values that are each a single URL string or
     * a JSON array of them. The click URL pairs by the image's **original** index when
     * `url` is an array (one per image); a single `url` string is shared across all
     * images; a missing/blank paired entry yields no click.
     */
    private fun creatives(imageValue: Any?, urlValue: Any?): List<Creative> {
        // Non-empty images with their original index for URL pairing.
        val images: List<Pair<Int, String>> = when (imageValue) {
            is JSONArray -> (0 until imageValue.length()).mapNotNull { i -> nonEmpty(imageValue.optString(i))?.let { i to it } }
            is String -> listOfNotNull(nonEmpty(imageValue)?.let { 0 to it })
            else -> emptyList()
        }
        return images.map { (index, image) ->
            val click = when (urlValue) {
                is JSONArray -> if (index < urlValue.length()) nonEmpty(urlValue.optString(index)) else null
                is String -> nonEmpty(urlValue)
                else -> null
            }
            Creative(image, click)
        }
    }

    private fun nonEmpty(s: String): String? {
        val trimmed = s.trim()
        return if (trimmed.isEmpty()) null else trimmed
    }

    // ── Local image cache (memory + disk) ────────────────────────────────────

    private val memory = LruCache<String, Bitmap>(8)

    private val newThread: (Runnable) -> Unit = { Thread(it).start() }
    private val openStream: (URL) -> ByteArray = { url -> url.openStream().use { it.readBytes() } }
    private val bitmapFactory: (ByteArray) -> Bitmap? = { bytes -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }

    /** Runs each image load off the main thread. Tests run it inline. */
    @Volatile
    internal var runner: (Runnable) -> Unit = newThread

    /** Reads a remote image. Tests replace it to fail on purpose. */
    @Volatile
    internal var download: (URL) -> ByteArray = openStream

    /** Decodes image bytes; null when they are not an image. Tests replace it. */
    @Volatile
    internal var decode: (ByteArray) -> Bitmap? = bitmapFactory

    /** Restores the seams above and empties the memory cache. Tests only. */
    internal fun resetForTests() {
        runner = newThread
        download = openStream
        decode = bitmapFactory
        memory.evictAll()
    }

    // Stable (launch-independent) filename: djb2 hashed to hex.
    private fun diskFile(cacheDir: File, url: String): File {
        val dir = File(cacheDir, "sellwild_house").apply { mkdirs() }
        return File(dir, java.lang.Long.toHexString(HouseImages.djb2(url)))
    }

    /**
     * Load a house image: memory cache → disk cache → network (populating both).
     * [callback] is always invoked on the main thread; null on failure, which is
     * reported once (house.image.invalid, house.image.network, storage.write.exception).
     */
    fun loadImage(context: Context, url: String, callback: (Bitmap?) -> Unit) {
        memory.get(url)?.let { callback(it); return }
        val cacheDir = context.applicationContext.cacheDir
        val main = Handler(Looper.getMainLooper())
        runner(
            Runnable {
                val bitmap = load(cacheDir, url)
                if (bitmap != null) memory.put(url, bitmap)
                main.post { callback(bitmap) }
            },
        )
    }

    /** One image by [HouseImages.source]; null (and reported) when it cannot be had. */
    internal fun load(cacheDir: File, url: String): Bitmap? = when (val source = HouseImages.source(url)) {
        is HouseImages.Source.Refused -> invalid(source.reason, url = source.url)
        // data: URI — listing photos from the static cache can be inline base64 (the
        // feed's own cell decodes these too). Decoded inline, size-capped; memory-cache
        // only, no disk churn.
        is HouseImages.Source.Inline -> decodeInline(source.base64)
        is HouseImages.Source.Remote -> loadRemote(diskFile(cacheDir, url), url, source.url)
    }

    private fun decodeInline(base64: String): Bitmap? {
        val bytes = try {
            Base64.decode(base64, Base64.DEFAULT)
        } catch (e: IllegalArgumentException) {
            return invalid("data URI is not base64", error = e)
        }
        if (bytes.size > SellwildSafeUrl.MAX_IMAGE_BYTES) return invalid(TOO_LARGE)
        return decodeOrReport(bytes, url = null)
    }

    private fun loadRemote(disk: File, key: String, url: URL): Bitmap? {
        if (disk.exists()) {
            val cached = runCatching { disk.readBytes() }.getOrElse { e -> return invalid("cached image could not be read", error = e) }
            return decodeOrReport(cached, url = key)
        }
        val bytes = runCatching { download(url) }.getOrElse { e ->
            SellwildFailures.log(
                code = SellwildFailureCode.HOUSE_IMAGE_NETWORK,
                component = SellwildFailureComponent.HOUSE,
                severity = SellwildFailureSeverity.WARN,
                error = e,
                url = key,
            )
            return null
        }
        if (bytes.size > SellwildSafeUrl.MAX_IMAGE_BYTES) return invalid(TOO_LARGE, url = key)
        // The disk copy saves the next download. Writing it failing drops the image, as
        // it always has.
        runCatching { disk.writeBytes(bytes) }.onFailure { e ->
            SellwildFailures.log(
                code = SellwildFailureCode.STORAGE_WRITE_EXCEPTION,
                component = SellwildFailureComponent.HOUSE,
                severity = SellwildFailureSeverity.WARN,
                error = e,
            )
            return null
        }
        return decodeOrReport(bytes, url = key)
    }

    private fun decodeOrReport(bytes: ByteArray, url: String?): Bitmap? {
        val bitmap = runCatching { decode(bytes) }.getOrElse { e -> return invalid(NOT_DECODED, url = url, error = e) }
        return bitmap ?: invalid(NOT_DECODED, url = url)
    }

    // Reports house.image.invalid and gives the load's null result.
    private fun invalid(message: String, url: String? = null, error: Throwable? = null): Bitmap? {
        SellwildFailures.log(
            code = SellwildFailureCode.HOUSE_IMAGE_INVALID,
            component = SellwildFailureComponent.HOUSE,
            severity = SellwildFailureSeverity.WARN,
            error = error,
            message = message,
            url = url,
        )
        return null
    }

    private const val TOO_LARGE = "image over 8 MiB"
    private const val NOT_DECODED = "image could not be decoded"

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
     * listings only when none have a usable photo. [excludeIds] — the ids of
     * listings already rendered as a normal row elsewhere in the same feed —
     * are skipped so a house backfill never duplicates one, falling back to a
     * duplicate only if every candidate in the pool is already shown. Null
     * when empty.
     */
    fun pickListing(
        listings: List<SellwildListing>,
        row: Int,
        excludeIds: Set<String> = emptySet(),
    ): SellwildListing? {
        if (listings.isEmpty()) return null
        val withPhoto = listings.filter { hasUsablePhoto(it) }
        val pool = if (withPhoto.isEmpty()) listings else withPhoto
        val notShown = pool.filterNot { it.id in excludeIds }
        val finalPool = notShown.ifEmpty { pool }
        return finalPool[((row % finalPool.size) + finalPool.size) % finalPool.size]
    }
}
