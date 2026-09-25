package com.sellwild.sample

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat

/** Sellwild Sample: native listings and native ads. The SDK ships no WebView surface (origin 9ff579f). */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Debug builds only: the ad creatives' WebViews are then open to chrome://inspect
        // and to UI tests (Maestro). Never in a release build.
        if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true)
        // Dark status bar icons on the light screens (Android 15+ draws edge to edge).
        WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = true
        setContent { SampleApp() }
    }
}
