package com.sellwild.rnsdk

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.sellwild.sdk.SellwildPrebidMobile

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
}
