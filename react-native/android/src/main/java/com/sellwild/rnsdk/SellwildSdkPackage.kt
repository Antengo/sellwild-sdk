package com.sellwild.rnsdk

import android.view.View
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ReactShadowNode
import com.facebook.react.uimanager.ViewManager
import com.sellwild.sdk.failures.SellwildFailures

class SellwildSdkPackage : ReactPackage {
    init {
        // Mark every failure the native SDK reports as coming from React Native
        // (`wrapper: react-native`, contracts/FAILURES.md 3.1). The host builds
        // this package at startup, before any bridge class runs SDK code. The
        // native SDK logs its own failures; the bridge never logs them again.
        SellwildFailures.setWrapper("react-native")
    }

    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> =
        listOf(SellwildModule(reactContext))

    override fun createViewManagers(
        reactContext: ReactApplicationContext,
    ): List<ViewManager<out View, out ReactShadowNode<*>>> = listOf(
        SellwildBannerViewManager(),
        SellwildFeedViewManager(),
    )
}
