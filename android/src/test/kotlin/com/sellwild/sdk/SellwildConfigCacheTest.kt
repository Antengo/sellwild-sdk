package com.sellwild.sdk

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Unit tests for the last-good remote config cache ([SellwildConfigCache]) and
 * the "fetched body or cached body" decision behind `SellwildSDK.configure`
 * ([SellwildSDK.resolveConfig]). Pure JVM: the cache takes its directory as a
 * parameter, so these point it at a temp dir — no network, no Context.
 */
class SellwildConfigCacheTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val body =
        """{"CODE":"acme","SLUG":"acme-main","AD_STACK":"prebid",""" +
            """"MOBILE_ZID":["101","102"],"MOBILE_BANNER_ZID":"201"}"""

    private val otherBody =
        """{"CODE":"acme","SLUG":"acme-main","AD_STACK":"prebid",""" +
            """"MOBILE_ZID":["301"],"MOBILE_BANNER_ZID":"401"}"""

    /** A cache dir that does not exist yet — it must be created on demand. */
    private fun cacheDir(): File = File(tmp.root, "sellwild")

    // ── SellwildConfigCache ──────────────────────────────────────────────────

    @Test
    fun `write then read round trips the raw body`() {
        val dir = cacheDir()
        assertFalse(dir.exists())

        assertTrue(SellwildConfigCache.write(dir, "acme", "acme-main", body))

        assertTrue(dir.isDirectory)
        assertEquals(body, SellwildConfigCache.read(dir, "acme", "acme-main"))
        // Temp file was renamed into place — nothing else is left behind.
        assertEquals(
            listOf(SellwildConfigCache.fileName("acme", "acme-main")),
            dir.list()?.toList(),
        )
    }

    @Test
    fun `read returns null when nothing was cached`() {
        // Directory missing entirely.
        assertNull(SellwildConfigCache.read(cacheDir(), "acme", "acme-main"))

        // Directory present, different key.
        val dir = cacheDir()
        SellwildConfigCache.write(dir, "acme", "acme-main", body)
        assertNull(SellwildConfigCache.read(dir, "acme", "acme-other"))
        assertNull(SellwildConfigCache.read(dir, "other", "acme-main"))
    }

    @Test
    fun `write replaces the previous body`() {
        val dir = cacheDir()
        SellwildConfigCache.write(dir, "acme", "acme-main", body)

        assertTrue(SellwildConfigCache.write(dir, "acme", "acme-main", otherBody))

        assertEquals(otherBody, SellwildConfigCache.read(dir, "acme", "acme-main"))
        assertEquals(1, dir.list()?.size)
    }

    @Test
    fun `write and read swallow io errors`() {
        // The "directory" is a regular file, so nothing can be created in it.
        val notADir = tmp.newFile("not-a-dir")

        assertFalse(SellwildConfigCache.write(notADir, "acme", "acme-main", body))
        assertNull(SellwildConfigCache.read(notADir, "acme", "acme-main"))
    }

    @Test
    fun `sanitize replaces everything outside the safe set`() {
        assertEquals("acme-main_1", SellwildConfigCache.sanitize("acme-main_1"))
        assertEquals("ac_me___x_y", SellwildConfigCache.sanitize("ac/me..\\x y"))
        assertEquals(64, SellwildConfigCache.sanitize("x".repeat(200)).length)
    }

    @Test
    fun `fileName is a plain file name inside the cache dir`() {
        val safe = Regex("config-[A-Za-z0-9_-]+\\.json")

        assertTrue(safe.matches(SellwildConfigCache.fileName("acme", "acme-main")))
        assertTrue(
            SellwildConfigCache.fileName("acme", "acme-main").startsWith("config-acme-acme-main-")
        )

        val hostile = SellwildConfigCache.fileName("../../etc", "a b/c.json")
        assertTrue(hostile, safe.matches(hostile))
        val dir = cacheDir()
        assertEquals(dir, File(dir, hostile).parentFile)
    }

    @Test
    fun `fileName keeps keys that sanitize alike apart`() {
        assertNotEquals(
            SellwildConfigCache.fileName("a-b", "c"),
            SellwildConfigCache.fileName("a", "b-c"),
        )
        assertNotEquals(
            SellwildConfigCache.fileName("a/b", "c"),
            SellwildConfigCache.fileName("a_b", "c"),
        )
        // Stable for the same key.
        assertEquals(
            SellwildConfigCache.fileName("acme", "acme-main"),
            SellwildConfigCache.fileName("acme", "acme-main"),
        )
    }

    // ── SellwildSDK.resolveConfig ────────────────────────────────────────────

    @Test
    fun `resolveConfig applies a fresh body and caches it`() {
        val dir = cacheDir()

        val config = SellwildSDK.resolveConfig("acme", "acme-main", body, dir)

        assertEquals(body, config.remoteJson)
        assertEquals("acme-main", config.slug)
        assertEquals(listOf("101", "102"), config.mobileZids)
        assertEquals("201", config.mobileBannerZid)
        assertEquals(body, SellwildConfigCache.read(dir, "acme", "acme-main"))
    }

    @Test
    fun `resolveConfig falls back to the cached body when the fetch failed`() {
        val dir = cacheDir()
        val fresh = SellwildSDK.resolveConfig("acme", "acme-main", body, dir)

        // fetchedBody == null: network error, timeout or non-2xx.
        val offline = SellwildSDK.resolveConfig("acme", "acme-main", null, dir)

        // Applied exactly as the fresh one was.
        assertEquals(fresh, offline)
        assertEquals(body, offline.remoteJson)
        assertEquals(listOf("101", "102"), offline.mobileZids)
        assertEquals(
            SellwildAdStack.PREBID_ONLY,
            SellwildAdStack.resolve(offline.remoteJson, "101"),
        )
    }

    @Test
    fun `resolveConfig returns defaults when the fetch failed and nothing is cached`() {
        val config = SellwildSDK.resolveConfig("acme", "acme-main", null, cacheDir())

        assertEquals(SellwildConfig(partnerCode = "acme"), config)
        assertNull(config.remoteJson)
        assertTrue(config.mobileZids.isEmpty())
        // Unknown stack → no GAM request.
        assertEquals(
            SellwildAdStack.PREBID_ONLY,
            SellwildAdStack.resolve(config.remoteJson, null),
        )
    }

    @Test
    fun `resolveConfig does not use another slug's cache`() {
        val dir = cacheDir()
        SellwildSDK.resolveConfig("acme", "acme-main", body, dir)

        val config = SellwildSDK.resolveConfig("acme", "acme-other", null, dir)

        assertEquals(SellwildConfig(partnerCode = "acme"), config)
    }

    @Test
    fun `resolveConfig treats a body that is not a JSON object as a failed fetch`() {
        val dir = cacheDir()
        SellwildSDK.resolveConfig("acme", "acme-main", body, dir)

        for (bad in listOf("<html>502</html>", "[]", "")) {
            val config = SellwildSDK.resolveConfig("acme", "acme-main", bad, dir)
            assertEquals("body=$bad", body, config.remoteJson)
        }
        // The bad bodies never overwrote the last good one.
        assertEquals(body, SellwildConfigCache.read(dir, "acme", "acme-main"))

        // …and with no cache they yield defaults.
        val none = SellwildSDK.resolveConfig("acme", "acme-main", "<html>", File(tmp.root, "empty"))
        assertEquals(SellwildConfig(partnerCode = "acme"), none)
    }

    @Test
    fun `resolveConfig replaces the cache with a newer fresh body`() {
        val dir = cacheDir()
        SellwildSDK.resolveConfig("acme", "acme-main", body, dir)
        SellwildSDK.resolveConfig("acme", "acme-main", otherBody, dir)

        val offline = SellwildSDK.resolveConfig("acme", "acme-main", null, dir)

        assertEquals(otherBody, offline.remoteJson)
        assertEquals(listOf("301"), offline.mobileZids)
    }

    @Test
    fun `resolveConfig ignores a corrupt cache file`() {
        val dir = cacheDir()
        SellwildConfigCache.write(dir, "acme", "acme-main", "{not json")

        val config = SellwildSDK.resolveConfig("acme", "acme-main", null, dir)

        assertEquals(SellwildConfig(partnerCode = "acme"), config)
    }

    @Test
    fun `resolveConfig works without a cache dir`() {
        // No application Context → caching is skipped, nothing throws.
        val fresh = SellwildSDK.resolveConfig("acme", "acme-main", body, null)
        assertEquals(body, fresh.remoteJson)

        val offline = SellwildSDK.resolveConfig("acme", "acme-main", null, null)
        assertEquals(SellwildConfig(partnerCode = "acme"), offline)
    }

    @Test
    fun `resolveConfig still applies the fresh body when the cache is unwritable`() {
        val notADir = tmp.newFile("not-a-dir")

        val config = SellwildSDK.resolveConfig("acme", "acme-main", body, notADir)

        assertEquals(body, config.remoteJson)
    }
}
