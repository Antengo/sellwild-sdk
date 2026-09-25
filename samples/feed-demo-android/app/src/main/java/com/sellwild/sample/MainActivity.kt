package com.sellwild.sample

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat

/** Sellwild Sample: native listings and native ads first. The WebView widget is only on the Legacy tab. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Debug builds only: the WebViews' DOM is then open to chrome://inspect and to
        // UI tests (Maestro). Never in a release build.
        if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true)
        // Dark status bar icons on the light screens (Android 15+ draws edge to edge).
        WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = true
        setContent { SampleApp() }
    }
}
