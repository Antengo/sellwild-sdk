package com.sellwild.sdk

import java.io.File

/**
 * Last-known-good remote config, persisted so a failed config fetch (offline,
 * timeout, non-2xx, bad JSON) can fall back to the previous payload instead of
 * bare defaults — defaults carry no ad zones, so the feed would show no ads.
 *
 * One file per `partnerCode` + `slug` holding the raw CDN body verbatim. There
 * is no TTL: a stale config beats none. Every function takes the cache
 * directory as a parameter (production passes [directory] of the app's private
 * files dir; JVM tests pass a temp dir), swallows all I/O errors and never
 * throws.
 */
internal object SellwildConfigCache {

    private const val DIR_NAME = "sellwild"
    private const val MAX_PART_LENGTH = 64

    /** The cache directory under the app's private files dir. Not created here. */
    fun directory(filesDir: File): File = File(filesDir, DIR_NAME)

    /**
     * Make [value] safe as a filename component: anything outside
     * `[A-Za-z0-9_-]` becomes `_` (so no path separators or dots survive), and
     * the result is length-capped.
     */
    fun sanitize(value: String): String =
        value.replace(Regex("[^A-Za-z0-9_-]"), "_").take(MAX_PART_LENGTH)

    /**
     * `config-<partner>-<slug>-<hash>.json`. The readable parts are sanitized;
     * the trailing hash of the RAW key keeps two keys that sanitize to the same
     * text (`a-b` + `c` vs `a` + `b-c`, or `a/b` vs `a_b`) in separate files, so
     * one partner's config is never served for another.
     */
    fun fileName(partnerCode: String, slug: String): String {
        // String.hashCode is specified by the language, so it is stable across
        // launches and devices.
        val hash = Integer.toHexString("$partnerCode/$slug".hashCode())
        return "config-${sanitize(partnerCode)}-${sanitize(slug)}-$hash.json"
    }

    /** The cached body for this key, or null when absent, blank or unreadable. */
    fun read(dir: File, partnerCode: String, slug: String): String? =
        runCatching {
            val file = File(dir, fileName(partnerCode, slug))
            if (file.isFile) file.readText().takeIf { it.isNotBlank() } else null
        }.getOrNull()

    /**
     * Persist [body] for this key, creating [dir] on demand. Written to a temp
     * file and renamed into place so a reader never sees a half-written file.
     * Returns true when the body was stored.
     */
    fun write(dir: File, partnerCode: String, slug: String, body: String): Boolean =
        runCatching {
            if (!dir.isDirectory) dir.mkdirs()
            val target = File(dir, fileName(partnerCode, slug))
            // Throws (→ false) when the directory could not be created.
            val tmp = File.createTempFile("config-", ".tmp", dir)
            val stored = runCatching {
                tmp.writeText(body)
                tmp.renameTo(target)
            }.getOrDefault(false)
            if (!stored) tmp.delete()
            stored
        }.getOrDefault(false)
}
