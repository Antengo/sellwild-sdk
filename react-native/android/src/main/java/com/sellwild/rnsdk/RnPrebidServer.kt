package com.sellwild.rnsdk

import com.facebook.react.bridge.ReadableMap
import com.sellwild.sdk.PrebidServerConfig

/**
 * Marshals a bridged JS `prebidServer` object (React `ReadableMap`) into the
 * native [PrebidServerConfig]. Lives in the RN module because `ReadableMap` is a
 * React type. Mirrors the iOS bridge (`configFromMap`) so an RN partner's custom
 * Prebid Server (accountId / endpoint / bidders / timeout) routes to the same
 * auction endpoint on both platforms. Returns null when `accountId`/`endpoint`
 * are absent, so `bootstrap()` falls back to `S2S_CONFIG` / the hosted default.
 */
internal object RnPrebidServer {
    fun fromMap(map: ReadableMap?): PrebidServerConfig? {
        if (map == null) return null
        fun str(k: String) = if (map.hasKey(k) && !map.isNull(k)) map.getString(k) else null
        val accountId = str("accountId") ?: return null
        val endpoint = str("endpoint") ?: return null
        val bidders = if (map.hasKey("bidders") && !map.isNull("bidders")) {
            map.getArray("bidders")?.let { arr ->
                (0 until arr.size()).mapNotNull { arr.getString(it) }
            } ?: emptyList()
        } else {
            emptyList()
        }
        val timeout = if (map.hasKey("timeout") && !map.isNull("timeout")) map.getInt("timeout") else 1500
        return PrebidServerConfig(
            accountId = accountId,
            endpoint = endpoint,
            bidders = bidders,
            timeout = timeout,
            syncEndpoint = str("syncEndpoint"),
        )
    }
}
