package com.sellwild.sdk.support

import com.fasterxml.jackson.databind.ObjectMapper
import com.networknt.schema.JsonSchema
import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SchemaLocation
import com.networknt.schema.SchemaValidatorsConfig
import com.networknt.schema.SpecVersion
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * Validates JSON against the shared JSON Schemas (draft 2020-12) on the unit-test classpath,
 * fully offline. [ContractSchemas] reads `contracts/schemas/<name>.schema.json`.
 *
 * A schema's `$id` and `$ref` IRIs (e.g. `https://contracts.sellwild.com/listing.schema.json`)
 * resolve to `<root>/<last path segment>` on the classpath, never over the network. The
 * JSON Schema meta-schemas come from the validator's own jar. Formats are asserted, as ajv +
 * ajv-formats do in contracts/scripts/validate.mjs.
 */
open class SchemaSet(root: String) {
    private val root = root.trim('/')
    private val schemas = ConcurrentHashMap<String, JsonSchema>()
    private val mapper = ObjectMapper()

    private val factory: JsonSchemaFactory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012) {
        it.schemaMappers { mappers -> mappers.mappings(::isContractIri, ::toClasspath) }
    }
    private val config: SchemaValidatorsConfig =
        SchemaValidatorsConfig.builder().formatAssertionsEnabled(true).build()

    /** Loads and compiles `<root>/<name>.schema.json`. Throws if it is missing or malformed. */
    fun schema(name: String): JsonSchema = schemas.getOrPut(name) {
        val path = "$root/$name.schema.json"
        if (!FixtureLoader.exists(path)) throw AssertionError("No schema '$name' on the test classpath ($path)")
        factory.getSchema(SchemaLocation.of("classpath:$path"), config).also { it.initializeValidators() }
    }

    /**
     * Validation errors for [json] (JSON text), as "<JSON pointer>: <error>", the pointer
     * style ajv uses ("/" is the root). Empty means valid.
     */
    fun errors(name: String, json: String): List<String> =
        schema(name).validate(mapper.readTree(json))
            .map { "${it.instanceLocation.toString().ifEmpty { "/" }}: ${it.error}" }
            .sorted()

    fun errors(name: String, json: JSONObject): List<String> = errors(name, json.toString())

    fun errors(name: String, json: JSONArray): List<String> = errors(name, json.toString())

    /** Fails with every validation error when [json] does not match schema [name]. */
    fun assertValid(name: String, json: String) {
        val errors = errors(name, json)
        if (errors.isNotEmpty()) {
            throw AssertionError("Not valid against $name.schema.json:\n" + errors.joinToString("\n") { "  $it" })
        }
    }

    fun assertValid(name: String, json: JSONObject) = assertValid(name, json.toString())

    fun assertValid(name: String, json: JSONArray) = assertValid(name, json.toString())

    private fun isContractIri(iri: String): Boolean =
        (iri.startsWith("https://") || iri.startsWith("http://")) &&
            !iri.substringAfter("://").startsWith("json-schema.org/") &&
            lastSegment(iri).isNotEmpty()

    private fun toClasspath(iri: String): String = "classpath:$root/${lastSegment(iri)}"

    private fun lastSegment(iri: String): String =
        iri.substringBefore('#').substringBefore('?').substringAfterLast('/')
}

/** The shared schemas in `sellwild-sdk/contracts/schemas`. */
object ContractSchemas : SchemaSet("schemas")
