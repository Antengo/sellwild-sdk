package com.sellwild.rnsdk

import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.sellwild.sdk.PrebidServerConfig

/**
 * Marshals a bridged JS `prebidServer` object (React `ReadableMap`) into the
 * native [PrebidServerConfig]. Lives in the RN module because `ReadableMap` is a
 * React type. Mirrors the iOS bridge (`configFromMap`) so an RN partner's custom
 * Prebid Server (accountId / endpoint / bidders / timeout) routes to the same
 * auction endpoint on both platforms. The config is null when `accountId` or
 * `endpoint` is not text, so `bootstrap()` falls back to `S2S_CONFIG` / the
 * hosted default.
 */
internal object RnPrebidServer {
    /**
     * The custom Prebid Server to use (null: the default one), and why a
     * `prebidServer` that was sent could not be used. The caller reports the
     * problem with the rest of its config (`bridge.config.invalid`), in one
     * report, as the iOS bridge does.
     */
    class Parsed(val config: PrebidServerConfig?, val problem: String?)

    /**
     * Reads `prebidServer` from a config map. Absent or null: the default
     * Prebid Server, by design, and no problem. A value that is not an
     * object, or an object without accountId and endpoint text: the default,
     * and a problem, with the same text as iOS. Any other field of the wrong
     * type still throws, and the caller reports the whole config.
     */
    fun fromConfig(config: ReadableMap): Parsed {
        if (!config.hasKey("prebidServer")) return Parsed(null, null)
        val type = config.getType("prebidServer")
        if (type == ReadableType.Null) return Parsed(null, null)
        if (type != ReadableType.Map) return Parsed(null, RnBridgeRules.prebidServerNotObject(type.name))
        // getType said Map, so getMap returns one.
        val map = config.getMap("prebidServer")!!
        fun text(k: String) = if (map.hasKey(k) && map.getType(k) == ReadableType.String) map.getString(k) else null
        val accountId = text("accountId")
        val endpoint = text("endpoint")
        if (accountId == null || endpoint == null) {
            return Parsed(null, RnBridgeRules.prebidServerProblem(hasAccountId = accountId != null, hasEndpoint = endpoint != null))
        }
        val bidders = if (map.hasKey("bidders") && !map.isNull("bidders")) {
            map.getArray("bidders")?.let { arr ->
                (0 until arr.size()).mapNotNull { arr.getString(it) }
            } ?: emptyList()
        } else {
            emptyList()
        }
        val timeout = if (map.hasKey("timeout") && !map.isNull("timeout")) map.getInt("timeout") else 1500
        val syncEndpoint = if (map.hasKey("syncEndpoint") && !map.isNull("syncEndpoint")) map.getString("syncEndpoint") else null
        return Parsed(
            PrebidServerConfig(
                accountId = accountId,
                endpoint = endpoint,
                bidders = bidders,
                timeout = timeout,
                syncEndpoint = syncEndpoint,
            ),
            null,
        )
    }
}
