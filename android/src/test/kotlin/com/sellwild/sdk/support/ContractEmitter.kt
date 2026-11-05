package com.sellwild.sdk.support

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File

/**
 * Writes mock-factory output for the cross-platform schema gate. Each call writes
 * `<outDir>/<schema>.<variant>.json`; `node contracts/scripts/validate.mjs --out android`
 * (run by scripts/coverage/android.sh) then checks it against
 * `contracts/schemas/<schema>.schema.json`.
 *
 * The default [outDir] is `sellwild-sdk/contracts/out/android`, or `$SELLWILD_CONTRACT_OUT/android`
 * when that is set (as validate.mjs reads it), passed in by android/build.gradle.kts as the
 * `sellwild.contracts.outDir` system property.
 */
object ContractEmitter {
    const val OUT_DIR_PROPERTY = "sellwild.contracts.outDir"
    const val OUT_ROOT_ENV = "SELLWILD_CONTRACT_OUT"

    private val SCHEMA_NAME = Regex("^[a-z0-9]+(-[a-z0-9]+)*$")
    private val VARIANT_NAME = Regex("^[A-Za-z0-9]+([-_][A-Za-z0-9]+)*$")

    /** The Gradle-configured dir, else [defaultOutDir] for this JVM (e.g. a run from the IDE). */
    fun outDir(): File =
        System.getProperty(OUT_DIR_PROPERTY)?.takeIf { it.isNotBlank() }?.let(::File)
            ?: defaultOutDir(System.getenv(OUT_ROOT_ENV), System.getProperty("user.dir") ?: ".")

    /**
     * `<outRoot>/android` when [outRoot] ($SELLWILD_CONTRACT_OUT) is set, else
     * `../contracts/out/android`. Relative paths resolve from [moduleDir], as Gradle's `file()`
     * does in android/build.gradle.kts.
     */
    fun defaultOutDir(outRoot: String?, moduleDir: String): File {
        val root = outRoot?.takeIf { it.isNotBlank() }?.let(::File) ?: File("../contracts/out")
        return File(if (root.isAbsolute) root else File(moduleDir, root.path), "android").normalize()
    }

    fun emit(schema: String, variant: String, json: JSONObject, outDir: File = outDir()): File =
        write(schema, variant, json.toString(2), outDir)

    fun emit(schema: String, variant: String, json: JSONArray, outDir: File = outDir()): File =
        write(schema, variant, json.toString(2), outDir)

    /** Emits already-serialized JSON, e.g. a wire body built by SDK code. It must parse. */
    fun emitText(schema: String, variant: String, json: String, outDir: File = outDir()): File {
        val parsed = JSONTokener(json).nextValue()
        require(parsed is JSONObject || parsed is JSONArray) {
            "$schema.$variant: expected a JSON object or array, got ${parsed?.javaClass?.simpleName}"
        }
        return write(schema, variant, json, outDir)
    }

    private fun write(schema: String, variant: String, text: String, outDir: File): File {
        require(SCHEMA_NAME.matches(schema)) {
            "Schema name '$schema' must be kebab-case, matching contracts/schemas/<name>.schema.json"
        }
        require(VARIANT_NAME.matches(variant)) {
            "Variant name '$variant' may use letters, digits, '-' and '_' only (no dots or slashes)"
        }
        outDir.mkdirs()
        val file = File(outDir, "$schema.$variant.json")
        file.writeText(text + "\n", Charsets.UTF_8)
        return file
    }
}
