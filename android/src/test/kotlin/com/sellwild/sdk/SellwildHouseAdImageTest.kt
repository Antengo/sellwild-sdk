package com.sellwild.sdk

import android.content.Context
import android.graphics.Bitmap
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.core.HouseImages
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/**
 * SellwildHouseAd.loadImage: memory, disk, network and inline data: images, each failure
 * reported once (house.image.invalid, house.image.network, storage.write.exception). Loads run
 * inline ([SellwildHouseAd.runner]) except where a test proves the default thread;
 * [HttpStub] answers downloads in-process.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildHouseAdImageTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val results = CopyOnWriteArrayList<Bitmap?>()
    private lateinit var events: CapturedEvents

    private val photoUrl: String = ListingFactory.build().getJSONArray("photos").getJSONObject(0).getString("url")
    private val dataPhoto: String = ListingFactory.variant("data-uri-photos").getJSONArray("photos").getJSONObject(0).getString("url")
    private val cacheDir get() = File(context.cacheDir, "sellwild_house")

    @Before
    fun setUp() {
        SellwildHouseAd.resetForTests()
        SellwildHouseAd.runner = { it.run() }
        cacheDir.deleteRecursively()
        events = CapturedEvents().install()
    }

    @After
    fun tearDown() {
        SellwildHouseAd.resetForTests()
        cacheDir.deleteRecursively()
    }

    /** Loads [url] and delivers the main-thread callback. */
    private fun load(url: String): Bitmap? {
        results.clear()
        SellwildHouseAd.loadImage(context, url) { results += it }
        shadowOf(Looper.getMainLooper()).idle()
        return results.single()
    }

    private fun diskFile(url: String) = File(cacheDir, java.lang.Long.toHexString(HouseImages.djb2(url)))

    @Test
    fun `a data URI decodes inline, lands in the memory cache only, and reports nothing`() {
        val bitmap = load(dataPhoto)

        assertNotNull(bitmap)
        SellwildHouseAd.runner = { throw AssertionError("a memory hit must not load") }
        SellwildHouseAd.loadImage(context, dataPhoto) { results += it }
        assertSame("delivered at once from memory", bitmap, results.last())
        assertFalse(cacheDir.exists() && cacheDir.list()!!.isNotEmpty())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a data URI without a comma is house image invalid, with no host`() {
        assertNull(load("data:image/png;base64"))

        val attributes = events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID)
        assertEquals("data URI without a comma", attributes.getString("msg"))
        assertFalse(attributes.has("host"))
        assertEquals("house", events.single(SellwildFailureCode.HOUSE_IMAGE_INVALID).getString("label"))
    }

    @Test
    fun `a data URI that is not base64 is house image invalid`() {
        assertNull(load(dataPhoto.substringBefore(',') + ",A"))

        val attributes = events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID)
        assertEquals("data URI is not base64: bad base-64", attributes.getString("msg"))
        assertEquals("IllegalArgumentException", attributes.getString("errName"))
    }

    @Test
    fun `a data URI over 8 MiB is house image invalid`() {
        val tooLarge = dataPhoto.substringBefore(',') + "," + "A".repeat((SellwildSafeUrl.MAX_IMAGE_BYTES / 3 + 1) * 4)

        assertNull(load(tooLarge))

        assertEquals("image over 8 MiB", events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID).getString("msg"))
    }

    @Test
    fun `a data URI of exactly 8 MiB is decoded`() {
        val max = SellwildSafeUrl.MAX_IMAGE_BYTES
        // Base64: each "AAAA" is 3 zero bytes; the tail pads the last 1 or 2.
        val tail = listOf("", "AA==", "AAA=")[max % 3]
        val exact = dataPhoto.substringBefore(',') + "," + "A".repeat(max / 3 * 4) + tail
        val decoded = CopyOnWriteArrayList<Int>()
        SellwildHouseAd.decode = { bytes -> decoded += bytes.size; Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888) }

        assertNotNull(load(exact))

        assertEquals(listOf(max), decoded)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a remote image downloads once, then comes from the disk cache`() {
        val bytes = HttpStub.install { StubResponse(200, "image-bytes") }.use { stub ->
            assertNotNull(load(photoUrl))
            assertEquals(1, stub.requests.size)
            SellwildHouseAd.resetForTests()
            SellwildHouseAd.runner = { it.run() }
            assertNotNull("from disk, with no request", load(photoUrl))
            assertEquals(1, stub.requests.size)
            diskFile(photoUrl).readText()
        }

        assertEquals("image-bytes", bytes)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a URL that is not http(s) is refused as house image invalid`() {
        assertNull(load("file:///sdcard/secret.png"))

        val attributes = events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID)
        assertEquals("not an http(s) URL", attributes.getString("msg"))
        assertFalse(attributes.has("host"))
    }

    @Test
    fun `a download that fails is house image network, with the host`() {
        network.expectAttempts()

        assertNull(load(photoUrl))

        assertEquals(listOf(photoUrl), network.attempts)
        val attributes = events.attributes(SellwildFailureCode.HOUSE_IMAGE_NETWORK)
        assertEquals("NetworkBlockedException", attributes.getString("errName"))
        assertEquals("antengo-listings.s3.us-west-2.amazonaws.com", attributes.getString("host"))
        assertFalse(diskFile(photoUrl).exists())
    }

    @Test
    fun `a download of exactly 8 MiB is cached on disk and decoded`() {
        val max = SellwildSafeUrl.MAX_IMAGE_BYTES
        val decoded = CopyOnWriteArrayList<Int>()
        SellwildHouseAd.download = { ByteArray(max) }
        SellwildHouseAd.decode = { bytes -> decoded += bytes.size; Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888) }

        assertNotNull(load(photoUrl))

        assertEquals(listOf(max), decoded)
        assertEquals(max.toLong(), diskFile(photoUrl).length())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a download over 8 MiB is house image invalid, and nothing is cached`() {
        SellwildHouseAd.download = { ByteArray(SellwildSafeUrl.MAX_IMAGE_BYTES + 1) }

        assertNull(load(photoUrl))

        assertEquals("image over 8 MiB", events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID).getString("msg"))
        assertFalse(diskFile(photoUrl).exists())
    }

    @Test
    fun `a disk cache that cannot be written is storage write exception, and the image is dropped`() {
        SellwildHouseAd.download = { "image-bytes".toByteArray() }
        cacheDir.parentFile!!.mkdirs()
        cacheDir.writeText("a file where the cache dir belongs")

        assertNull(load(photoUrl))

        val event = events.single(SellwildFailureCode.STORAGE_WRITE_EXCEPTION)
        assertEquals("house", event.getString("label"))
        assertEquals("FileNotFoundException", event.getJSONObject("attributes").getString("errName"))
    }

    @Test
    fun `bytes that are not an image are house image invalid`() {
        SellwildHouseAd.download = { "not-an-image".toByteArray() }
        SellwildHouseAd.decode = { null }

        assertNull(load(photoUrl))

        val attributes = events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID)
        assertEquals("image could not be decoded", attributes.getString("msg"))
        assertEquals("antengo-listings.s3.us-west-2.amazonaws.com", attributes.getString("host"))
    }

    @Test
    fun `a disk cache entry that is not an image is house image invalid, with the host, and no download`() {
        assertTrue(diskFile(photoUrl).parentFile!!.mkdirs())
        diskFile(photoUrl).writeText("not-an-image")
        SellwildHouseAd.download = { throw AssertionError("a cached image must not be downloaded") }
        SellwildHouseAd.decode = { null }

        assertNull(load(photoUrl))

        val attributes = events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID)
        assertEquals("image could not be decoded", attributes.getString("msg"))
        assertEquals("antengo-listings.s3.us-west-2.amazonaws.com", attributes.getString("host"))
    }

    @Test
    fun `a decoder that throws is house image invalid with the error`() {
        SellwildHouseAd.decode = { throw IllegalStateException("decoder") }

        assertNull(load(dataPhoto))

        assertEquals("IllegalStateException", events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID).getString("errName"))
    }

    @Test
    fun `a disk cache entry that cannot be read is house image invalid`() {
        assertTrue(diskFile(photoUrl).mkdirs())

        assertNull(load(photoUrl))

        val attributes = events.attributes(SellwildFailureCode.HOUSE_IMAGE_INVALID)
        assertTrue(attributes.getString("msg").startsWith("cached image could not be read: "))
        assertEquals("FileNotFoundException", attributes.getString("errName"))
    }

    @Test
    fun `by default each load runs on its own thread and calls back on the main thread`() {
        SellwildHouseAd.resetForTests()
        val mainThread = Looper.getMainLooper().thread
        val threads = CopyOnWriteArrayList<Thread>()

        SellwildHouseAd.loadImage(context, dataPhoto) { results += it; threads += Thread.currentThread() }
        val deadline = System.currentTimeMillis() + 10_000
        while (results.isEmpty() && System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(5)
        }

        assertNotNull(results.single())
        assertSame(mainThread, threads.single())
    }
}
