package com.sellwild.sdk.factories

import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONArray
import org.json.JSONObject

/**
 * One named output of a factory. [build] returns a JSONObject or a JSONArray, matching the
 * factory's schema (or deliberately not, for [ContractFactory.invalid]).
 */
class Variant(val name: String, val build: () -> Any)

/**
 * A mock factory for one shape in `sellwild-sdk/contracts/schemas`. Factories start from a
 * contracts file (a hand-made fixture or a real captured sample), never from an inline
 * payload, and apply overrides. FactoriesContractTest validates every [variants] entry
 * against `contracts/schemas/<schema>.schema.json` in-process (networknt), checks every
 * [invalid] entry fails it, and emits the valid ones to `contracts/out/android` for
 * `validate.mjs --out android`.
 */
interface ContractFactory {
    /** The schema file name without `.schema.json`. */
    val schema: String

    /** Outputs that must match [schema]. The first is the default. */
    val variants: List<Variant>

    /** Outputs that must not match [schema]. */
    val invalid: List<Variant>
}

/** A factory whose shape is a JSON object, built from [basePath] (relative to contracts/). */
abstract class JsonObjectFactory(final override val schema: String, private val basePath: String) : ContractFactory {

    /** A fresh copy of the base file. */
    fun base(): JSONObject = FixtureLoader.jsonObject(basePath)

    /**
     * The base with [overrides] applied at the top level. [JSONObject.NULL] sets JSON null;
     * a Kotlin null removes the key.
     */
    fun build(overrides: Map<String, Any?> = emptyMap()): JSONObject = base().apply {
        overrides.forEach { (key, value) -> if (value == null) remove(key) else put(key, value) }
    }
}

/** A deep copy of a contracts file, for variants that are a fixture or sample as is. */
internal fun contractObject(path: String): JSONObject = FixtureLoader.jsonObject(path)

internal fun contractArray(path: String): JSONArray = FixtureLoader.jsonArray(path)

/** [items] as a JSON array. */
internal fun jsonArrayOf(vararg items: Any): JSONArray = JSONArray().apply { items.forEach { put(it) } }
