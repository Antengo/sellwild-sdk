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
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures

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
     *
     * A field of the wrong type (for example lat sent as text) used to throw
     * from a ReadableMap getter and crash the host app. Now it is dropped and
     * reported, and the other fields are set, as on iOS.
     */
    @ReactMethod
    fun setGeo(geo: ReadableMap?) {
        val parsed = if (geo == null) {
            // JS sends {} to clear (commands.ts), so null comes only from a
            // caller outside the JS API. It clears geo, as before, and is
            // reported, as on iOS.
            RnGeo.Parsed(null, listOf(RnBridgeRules.geoNotObject("Null")))
        } else try {
            RnGeo.parse(geo)
        } catch (e: Exception) {
            // A map the bridge could not read at all. Geo is cleared, as iOS
            // clears it for a payload that is not an object.
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_GEO_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.WARN,
                error = e,
                message = "geo could not be read, so geo was cleared",
            )
            RnGeo.Parsed(null, emptyList())
        }
        if (parsed.problems.isNotEmpty()) {
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_GEO_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.WARN,
                message = parsed.problems.joinToString("; "),
            )
        }
        SellwildPrebidMobile.setGeo(parsed.geo)
    }

    /**
     * JS: `SellwildRNModule.setExternalUserIds([{ source, uids: [{ id, atype, ext? }] }])`.
     * Pass `[]` to clear. Mirrors [SellwildPrebidMobile.setExternalUserIds].
     */
    @ReactMethod
    fun setExternalUserIds(eids: ReadableArray?) {
        val parsed = try {
            toEids(eids)
        } catch (e: Exception) {
            // An entry or field of the wrong type (ReadableArray/ReadableMap
            // getters throw). It used to crash the host app; now no eids are set.
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_EIDS_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.WARN,
                error = e,
                message = "eids could not be read, so no eids were set",
            )
            return
        }
        parsed.problem?.let {
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_EIDS_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.WARN,
                message = it,
            )
        }
        SellwildPrebidMobile.setExternalUserIds(parsed.eids)
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
        // prewarm is optional (mounting a view bootstraps too), and JS always
        // sends a config: null has nothing to prewarm with.
        if (config == null) return
        val ctx = reactApplicationContext
        val cfg = try {
            SellwildBannerViewManager.configFromMap(config)
        } catch (e: Exception) {
            // A config field of the wrong type (ReadableMap getters throw). It
            // used to crash the host app; the first ad view bootstraps instead.
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_CONFIG_INVALID,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.WARN,
                error = e,
                message = "the prewarm config could not be read, so nothing was prewarmed",
            )
            return
        }
        UiThreadUtil.runOnUiThread { SellwildSDK.prewarm(ctx, cfg) }
    }

    private class ParsedEids(val eids: List<SellwildEid>, val problem: String?)

    // Skips, as before, an entry without source or uids and a uid without id,
    // and says what it skipped.
    private fun toEids(arr: ReadableArray?): ParsedEids {
        if (arr == null) return ParsedEids(emptyList(), null)
        val out = ArrayList<SellwildEid>()
        var skippedEntries = 0
        var skippedUids = 0
        for (i in 0 until arr.size()) {
            val eid = arr.getMap(i)
            val source = if (eid != null && eid.hasKey("source")) eid.getString("source") else null
            val uidsArr = if (eid != null && eid.hasKey("uids") && !eid.isNull("uids")) eid.getArray("uids") else null
            if (source == null || uidsArr == null) {
                skippedEntries++
                continue
            }
            val uids = ArrayList<SellwildEidUid>()
            for (j in 0 until uidsArr.size()) {
                val u = uidsArr.getMap(j)
                val id = if (u != null && u.hasKey("id")) u.getString("id") else null
                if (u == null || id == null) {
                    skippedUids++
                    continue
                }
                val atype = if (u.hasKey("atype")) u.getInt("atype") else 0
                @Suppress("UNCHECKED_CAST")
                val ext = if (u.hasKey("ext") && !u.isNull("ext"))
                    u.getMap("ext")?.toHashMap() as? Map<String, Any> else null
                uids.add(SellwildEidUid(id, atype, ext))
            }
            out.add(SellwildEid(source, uids))
        }
        return ParsedEids(out, RnBridgeRules.eidsProblem(skippedEntries, arr.size(), skippedUids))
    }
}
