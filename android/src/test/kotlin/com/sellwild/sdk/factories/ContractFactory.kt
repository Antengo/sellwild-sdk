package com.sellwild.sdk.factories

import com.sellwild.sdk.support.ContractSchemas
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

    /** A fresh build of the [variants] or [invalid] entry named [name]. */
    fun variant(name: String): JSONObject = (variants + invalid).single { it.name == name }.build() as JSONObject

    /**
     * The base with [overrides] applied at the top level. [JSONObject.NULL] sets JSON null;
     * a Kotlin null removes the key.
     */
    fun build(overrides: Map<String, Any?> = emptyMap()): JSONObject = base().apply {
        overrides.forEach { (key, value) -> if (value == null) remove(key) else put(key, value) }
    }

    /**
     * [build] with [overrides], checked against the schema now: a payload a test shapes
     * itself is still one the contract allows. Fails the test when it is not.
     */
    fun checked(overrides: Map<String, Any?> = emptyMap()): JSONObject =
        build(overrides).also { ContractSchemas.assertValid(schema, it) }

    /**
     * [build] with [overrides] that must NOT match the schema: the off-contract input a
     * robustness test feeds the SDK (JSON null where text belongs, a wrong type). Fails the
     * test when the payload turns out to be valid, so it keeps testing what it says.
     */
    fun offSchema(overrides: Map<String, Any?>): JSONObject = build(overrides).also {
        if (ContractSchemas.errors(schema, it).isEmpty()) throw AssertionError("$schema: expected an off-schema payload, got a valid one: $it")
    }
}

/** A deep copy of a contracts file, for variants that are a fixture or sample as is. */
internal fun contractObject(path: String): JSONObject = FixtureLoader.jsonObject(path)

internal fun contractArray(path: String): JSONArray = FixtureLoader.jsonArray(path)

/** [items] as a JSON array. */
internal fun jsonArrayOf(vararg items: Any): JSONArray = JSONArray().apply { items.forEach { put(it) } }

/** Every Android factory, for FactoriesContractTest. */
val ALL_FACTORIES: List<ContractFactory> = listOf(
    AppConfigFactory,
    ListingFactory,
    ListingsResponseFactory,
    LocalizedListingsConfigFactory,
    LocalizedListingsResponseFactory,
    ClientFailureEventFactory,
    EventsBatchFactory,
    GrowthCodeSyncResponseFactory,
    EidBlobFactory,
)
