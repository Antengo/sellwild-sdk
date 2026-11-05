package com.sellwild.sdk.support

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.net.URL

/**
 * Reads the shared cross-platform contracts (`sellwild-sdk/contracts`: schemas, fixtures,
 * samples, golden vectors) from the unit-test classpath. android/build.gradle.kts adds
 * `../contracts` as a test resource dir, so a path here is relative to `contracts/`, e.g.
 * `fixtures/app-config/valid/minimal.json`.
 *
 * Mock factories start from these files instead of inlining payload literals.
 */
object FixtureLoader {
    /** True when [path] is on the test classpath. */
    fun exists(path: String): Boolean = resource(path) != null

    /** The UTF-8 text of [path]. Throws [FileNotFoundException] naming the path if absent. */
    fun text(path: String): String =
        (resource(path) ?: throw missing(path)).openStream().use { it.readBytes().toString(Charsets.UTF_8) }

    fun jsonObject(path: String): JSONObject = JSONObject(text(path))

    fun jsonArray(path: String): JSONArray = JSONArray(text(path))

    /**
     * Paths of the files directly inside [dir] (not subdirectories), sorted, in the same
     * form [text] takes. Empty when the dir is not on the classpath.
     */
    fun list(dir: String): List<String> {
        val prefix = normalize(dir).trimEnd('/')
        val names = sortedSetOf<String>()
        for (url in loader().getResources(prefix)) {
            when (url.protocol) {
                "file" -> File(url.toURI()).listFiles()
                    ?.filter { it.isFile }
                    ?.forEach { names += it.name }
                // AGP puts unit-test resources in a directory, never a jar.
                else -> throw IllegalStateException("Cannot list contract dir $prefix from $url")
            }
        }
        return names.map { "$prefix/$it" }
    }

    private fun resource(path: String): URL? = loader().getResource(normalize(path))

    // Null only for bootstrap classes, never for test code.
    private fun loader(): ClassLoader = FixtureLoader::class.java.classLoader!!

    private fun normalize(path: String): String {
        val clean = path.trim().trimStart('/')
        require(clean.isNotEmpty()) { "Contract path is empty" }
        require(clean.split('/').none { it == ".." }) { "Contract path must stay inside contracts/: $path" }
        return clean
    }

    private fun missing(path: String) = FileNotFoundException(
        "Contract file not on the unit-test classpath: $path. android/build.gradle.kts adds " +
            "../contracts (sellwild-sdk/contracts) as a test resource dir; check the file exists there.",
    )
}
