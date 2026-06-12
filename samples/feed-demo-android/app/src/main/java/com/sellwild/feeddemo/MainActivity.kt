package com.sellwild.feeddemo

import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildFeed
import com.sellwild.sdk.SellwildSDK

private const val TAG = "FeedDemo"

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    FeedScreen()
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun FeedScreen() {
    var config by remember { mutableStateOf<SellwildConfig?>(null) }
    val ctx = androidx.compose.ui.platform.LocalContext.current

    LaunchedEffect(Unit) {
        // configure() pulls weatherbug's CDN payload. The CDN currently ships
        // no COL1 / zone IDs, so we inject a demo schedule + theme via
        // overrides so the feed has something to render end-to-end.
        config = SellwildSDK.configure(
            partnerCode = "weatherbug",
            slug = "weatherbug-weatherbug",
        ) { c ->
            c.copy(
                col1 = "BLGLGLGLGLG",
                title = "Marketplace",
                partnerUrl = "https://www.weatherbug.com",
                titleColor = "#FFFFFF",
                linkColor = "#60A5FA",
                priceColor = "#0A1F3D",
                mobileBannerZid = c.mobileBannerZid?.takeIf { it.isNotEmpty() } ?: "demo-banner",
                mobileZids = c.mobileZids.ifEmpty { listOf("demo-mrec-1", "demo-mrec-2", "demo-mrec-3") },
                appBundleId = "com.sellwild.feeddemo",
                appStoreUrl = "https://play.google.com/store/apps/details?id=com.sellwild.feeddemo",
                debug = true,
            )
        }
        Log.d(TAG, "Config ready: partner=${config?.partnerCode} col1=${config?.col1} listingsUrl=${config?.effectiveListingsUrl}")
    }

    val ready = config
    if (ready != null) {
        SellwildFeed(
            config = ready,
            onListingTap = { listing ->
                Log.d(TAG, "Listing tapped: ${listing.title} url=${listing.url}")
                Toast.makeText(ctx, "Tapped: ${listing.title}", Toast.LENGTH_SHORT).show()
                false // let the SDK open Custom Tabs
            },
            onAdImpression = { zoneId -> Log.d(TAG, "Ad impression zoneId=$zoneId") },
            onAdClicked = { zoneId -> Log.d(TAG, "Ad clicked zoneId=$zoneId") },
            onLoad = { Log.d(TAG, "Feed loaded") },
            onError = { msg -> Log.w(TAG, "Feed error: $msg") },
        )
    }
}
