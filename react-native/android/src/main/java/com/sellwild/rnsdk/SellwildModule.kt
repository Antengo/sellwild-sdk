package com.sellwild.rnsdk

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.UiThreadUtil
import com.sellwild.sdk.SellwildEid
import com.sellwild.sdk.SellwildEidUid
import com.sellwild.sdk.SellwildPrebidMobile
import com.sellwild.sdk.SellwildSDK

/**
 * React Native method module for the native Sellwild SDK's runtime setters.
 *
 * The RN ad surface is otherwise view-manager-only (config flows as a prop);
 * this module is the one callable bridge for imperative, session-scoped calls
 * like [setGeo]. Registered in [SellwildSdkPackage.createNativeModules]. The
 * module name ("SellwildRNModule") matches the iOS `@objc(SellwildRNModule)` so
 * JS resolves one `NativeModules.SellwildRNModule` on both platforms.
 */
class SellwildModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "SellwildRNModule"

    /**
     * JS: `SellwildRNModule.setGeo({ state: "NY", zip: "10001", ... })`.
     * Pass an empty object to clear. Mirrors [SellwildPrebidMobile.setGeo] —
     * updates the Prebid auction geo AND the shared SellwildGeoStore.
     */
    @ReactMethod
    fun setGeo(geo: ReadableMap?) {
        SellwildPrebidMobile.setGeo(RnGeo.readableMapToGeo(geo))
    }

    /**
     * JS: `SellwildRNModule.setExternalUserIds([{ source, uids: [{ id, atype, ext? }] }])`.
     * Pass `[]` to clear. Mirrors [SellwildPrebidMobile.setExternalUserIds].
     */
    @ReactMethod
    fun setExternalUserIds(eids: ReadableArray?) {
        SellwildPrebidMobile.setExternalUserIds(toEids(eids))
    }

    /**
     * JS: `SellwildRNModule.prewarm(nativeConfig)`. Pre-initializes the native ad
     * stack (Prebid + ad server SDK) before the first ad view mounts, so the
     * first impression doesn't incur cold-start init latency. Mirrors the native
     * Android-only [SellwildSDK.prewarm]; idempotent. Runs on the main thread —
     * the ad-SDK inits expect it. Reuses the banner manager's config mapping so
     * the payload shape matches `<SellwildBanner config=...>`.
     */
    @ReactMethod
    fun prewarm(config: ReadableMap?) {
        if (config == null) return
        val ctx = reactApplicationContext
        val cfg = SellwildBannerViewManager.configFromMap(config)
        UiThreadUtil.runOnUiThread { SellwildSDK.prewarm(ctx, cfg) }
    }

    private fun toEids(arr: ReadableArray?): List<SellwildEid> {
        if (arr == null) return emptyList()
        val out = ArrayList<SellwildEid>()
        for (i in 0 until arr.size()) {
            val eid = arr.getMap(i) ?: continue
            val source = if (eid.hasKey("source")) eid.getString("source") else null
            val uidsArr = if (eid.hasKey("uids") && !eid.isNull("uids")) eid.getArray("uids") else null
            if (source == null || uidsArr == null) continue
            val uids = ArrayList<SellwildEidUid>()
            for (j in 0 until uidsArr.size()) {
                val u = uidsArr.getMap(j) ?: continue
                val id = (if (u.hasKey("id")) u.getString("id") else null) ?: continue
                val atype = if (u.hasKey("atype")) u.getInt("atype") else 0
                @Suppress("UNCHECKED_CAST")
                val ext = if (u.hasKey("ext") && !u.isNull("ext"))
                    u.getMap("ext")?.toHashMap() as? Map<String, Any> else null
                uids.add(SellwildEidUid(id, atype, ext))
            }
            out.add(SellwildEid(source, uids))
        }
        return out
    }
}
