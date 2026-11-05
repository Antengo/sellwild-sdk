// A ReadableMap / ReadableArray over plain Kotlin values that behaves like
// React Native's ReadableNativeMap: JS numbers are Doubles, and a getter for
// another type throws UnexpectedNativeTypeException. For native-checks/run.sh.
package com.sellwild.rnsdk

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType

class UnexpectedNativeTypeException(msg: String) : RuntimeException(msg)

private fun typeOf(v: Any?): ReadableType = when (v) {
    null -> ReadableType.Null
    is Boolean -> ReadableType.Boolean
    is Double -> ReadableType.Number
    is String -> ReadableType.String
    is Map<*, *> -> ReadableType.Map
    is List<*> -> ReadableType.Array
    else -> error("not a bridged value: ${v::class}")
}

private inline fun <reified T> cast(key: Any, v: Any?): T? {
    if (v == null) return null
    if (v !is T) throw UnexpectedNativeTypeException("Value for $key cannot be cast from ${typeOf(v)} to ${T::class.simpleName}")
    return v
}

class FakeMap(private val values: Map<String, Any?>) : ReadableMap {
    override fun hasKey(name: String) = values.containsKey(name)
    override fun isNull(name: String) = values[name] == null
    override fun getBoolean(name: String): Boolean = cast<Boolean>(name, values[name]) ?: throw NullPointerException(name)
    override fun getDouble(name: String): Double = cast<Double>(name, values[name]) ?: throw NullPointerException(name)
    override fun getInt(name: String): Int = getDouble(name).toInt()
    override fun getString(name: String): String? = cast<String>(name, values[name])
    override fun getArray(name: String): ReadableArray? = cast<List<*>>(name, values[name])?.let { FakeArray(it) }

    @Suppress("UNCHECKED_CAST")
    override fun getMap(name: String): ReadableMap? = cast<Map<*, *>>(name, values[name])?.let { FakeMap(it as Map<String, Any?>) }
    override fun getType(name: String): ReadableType = typeOf(values[name])
    override fun toHashMap(): java.util.HashMap<String, Any> = java.util.HashMap(values.filterValues { it != null }.mapValues { it.value!! })
}

class FakeArray(private val values: List<Any?>) : ReadableArray {
    override fun size() = values.size
    override fun isNull(index: Int) = values[index] == null
    override fun getInt(index: Int): Int = (cast<Double>(index, values[index]) ?: throw NullPointerException("$index")).toInt()
    override fun getString(index: Int): String? = cast<String>(index, values[index])

    @Suppress("UNCHECKED_CAST")
    override fun getMap(index: Int): ReadableMap? = cast<Map<*, *>>(index, values[index])?.let { FakeMap(it as Map<String, Any?>) }
    override fun getType(index: Int): ReadableType = typeOf(values[index])
}

/** A bridged map React Native could not read at all: every call throws. */
class BrokenMap : ReadableMap {
    private fun no(): Nothing = throw IllegalStateException("the bridged map is gone")
    override fun hasKey(name: String): Boolean = no()
    override fun isNull(name: String): Boolean = no()
    override fun getBoolean(name: String): Boolean = no()
    override fun getDouble(name: String): Double = no()
    override fun getInt(name: String): Int = no()
    override fun getString(name: String): String? = no()
    override fun getArray(name: String): ReadableArray? = no()
    override fun getMap(name: String): ReadableMap? = no()
    override fun getType(name: String): ReadableType = no()
    override fun toHashMap(): java.util.HashMap<String, Any> = no()
}
